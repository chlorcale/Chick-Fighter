# -*- coding: utf-8 -*-
"""Tách giao thông (xe máy, vỏ lãi) và người đứng khỏi bản đồ thế giới → dữ liệu cho hệ thống giao thông / người đi bộ
chạy lúc chơi (build_world_map.py gọi). Không vẽ gì lên bản đồ: các layer giao thông bị loại khỏi world_layers.json.

Kết quả (game/art/world_map/):
    traffic.json        {"version", "frame_ms", "vehicles", "routes", "spawns", "docks", "bridges", "notes"} – xem write_traffic()
    traffic_atlas.png   một trang ảnh: khung xe/thuyền (đủ hai hướng), bóng, vệt sóng, bọt nước
    water.png           L8 đủ cỡ bản đồ: 1 = nước thuyền người chơi chạy được (nhập dạng Image)
    roads.png           L8 đủ cỡ bản đồ: 1 = mặt đường xe chạy được (nhập dạng Image)
    people.json         người đứng trên bản đồ (NEW_NPC + NV_*) – ứng viên người đi bộ, kèm vai trò đoán theo tên
    people_atlas.png    ảnh các khung của những người đó
Toạ độ: pixel bản đồ 5120×2160. Vùng ảnh: [x, y, w, h] trong atlas tương ứng.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
from statistics import median

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image
from scipy import ndimage

# ------------------------------------------------------------------ layer giao thông

## Nhóm (thư mục cuối của layer) chỉ chứa xe/thuyền chạy vòng + bóng/vệt sóng của chúng.
TRAFFIC_GROUPS = {"NEW_TRAFFIC", "NEW_TRAFFIC_SONG", "Xe_Thuyen_Bong_Song", "2_Xe_DuongLang", "6_Xe_DuongDua"}
## Vỏ lãi của bản đồ cũ nằm chung nhóm 4_TrenSong với ghe đậu/bến/đò → liệt kê tên.
OLD_BOAT_LAYERS = {"song_vo_lai_1_boc_dau", "song_vo_lai_1_bot_nuoc", "song_vo_lai_1_mui_dap_nuoc", "song_vo_lai_2",
                   "song_vo_lai_2_bot_nuoc"}
## Gợn nước của đò ngang bản đồ nằm trong Xe_Thuyen_Bong_Song nhưng không phải giao thông (World ẩn cùng đò).
KEEP = {"song_do_ngang_gon"}
## Node bản đồ World ẩn lúc chạy (đò ngang của bản đồ – World có đò riêng): không tính là vật cản trên nước.
RUNTIME_HIDDEN = {"song_do_ngang", "song_do_ngang_gon"}
OLD_BIKES = {"A_xe_may_con_tay_do": "road_village_north", "A_xe_may_cho_ga": "road_village_north",
             "C_xe_may_cho_dua": "road_village_coconut", "C_xe_may_con_tay_den": "road_village_coconut"}
## Xe NPC của trò đua bí mật (game/world/race/race_riders.gd) – tên node cũ giữ làm khoá tay lái.
RACE_RIDERS = set(OLD_BIKES)
OLD_BOATS = {
    "song_vo_lai_1_boc_dau": {"shadow": "song_vo_lai_1_bong", "wake": "song_vo_lai_1_vet_song",
                              "foam": ["song_vo_lai_1_bot_nuoc"], "splash": "song_vo_lai_1_mui_dap_nuoc"},
    "song_vo_lai_2": {"shadow": "song_vo_lai_2_bong", "wake": "song_vo_lai_2_vet_song", "foam": ["song_vo_lai_2_bot_nuoc"]},
}
NEW_BIKE_RE = re.compile(r"^N_xe_may_(T1|T2|T3|xom_chai)(?:_(tay|dong))?_(\d+)$")
NEW_BOAT_RE = re.compile(r"^N_vo_lai_song_(chinh|nam)_(tay|dong)_(\d+)$")
ROUTE_BASE = {"T1": "road_T1", "T2": "road_T2", "T3": "road_T3", "xom_chai": "road_xom_chai",
              "chinh": "river_main", "nam": "river_south"}
## Cầu bắc qua đường thuỷ: cao (thuyền chui qua được) / thấp (chặn thuyền người chơi).
HIGH_BRIDGES = ["N_cau_be_tong_song_chinh", "N_cau_pho_chinh_kenh_xang", "N_cau_T3_kenh_xang", "N_cau_T3_rach_vuon",
                "N_cau_pho_chinh_rach_nho", "N_cau_T3_rach_nho", "N_cau_S8_rach_nho", "D_cau_xi_mang_mat"]
LOW_BRIDGES = ["N_cau_go_qua_song", "N_cau_khi_song_nam", "N_cau_khi_rach_nho", "N_cau_ao_sen", "N_cau_ao_x1",
               "N_cau_ban_nha_may", "N_cau_van_muong__01", "N_cau_van_muong__02", "N_cau_van_muong__03",
               "N_cau_van_muong__04"]
## Bến/cầu tàu chìa ra nước (chặn thuyền, chỗ lên xuống thuyền).
PIERS = ["N_ben_do_bac", "N_ben_do_nam", "N_cho_cau_go_cap_ghe_1", "N_cho_cau_go_cap_ghe_2", "N_ben_kenh_xang_S8",
         "N_ben_hem_H10b", "N_ben_hem_H2", "N_ben_do_song_nam_bac", "N_ben_do_song_nam_nam", "N_ben_tau_du_lich",
         "N_ben_tau_du_lich_loi", "A_cau_van_ben_ghe", "A_cau_van_noi_dai", "C_cau_tau_ben_do", "D_cau_tau_ghe_du_lich",
         "C_ca_tra_cau_van"]
## Cầu/bến của bản đồ cũ không có layer riêng (đã có trong OPEN_RECTS cũ): cầu khỉ tre, cầu ván bến đò, cầu cá tra.
OLD_LOW_RECTS = [(626, 770, 90, 36), (448, 262, 24, 129), (448, 469, 24, 52), (18, 728, 110, 13)]
## Mặt đường cho xe (roads.png): đường bê tông/đất + đường làng cũ + cầu bê tông.
ROAD_LAYERS = ["N_duong_be_tong", "N_duong_dat", "duong_lang_noi_dai_B", "duong_dua_be_tong", "duong_doc_F",
               "duong_dat_ra_ruong", "D_cau_xi_mang_mat", "N_cau_pho_chinh_kenh_xang", "N_cau_T3_kenh_xang",
               "N_cau_T3_rach_vuon", "N_cau_pho_chinh_rach_nho", "N_cau_T3_rach_nho", "N_cau_S8_rach_nho",
               "N_cau_be_tong_song_chinh"]
WATER_LAYERS = ["N_song_kenh_nen", "song_rach_nen"]
## Bến cho thuyền người chơi: id → (layer bến, ghi chú). Điểm đứng/điểm nước tính tự động trên layer.
DOCKS = [
    ("dock_village_ferry", "A_cau_van_ben_ghe", "Cầu ván bến ghe xóm cũ (bờ bắc sông làng, cạnh bến đò ngang)"),
    ("dock_floating_market", "N_cho_cau_go_cap_ghe_1", "Cầu gỗ cập ghe ở kè chợ nổi (bờ nam sông chính)"),
    ("dock_floating_market_east", "N_cho_cau_go_cap_ghe_2", "Cầu gỗ cập ghe phía đông kè chợ nổi"),
    ("dock_tour_pier", "N_ben_tau_du_lich", "Bến tàu du lịch (bờ bắc sông chính, đối diện chợ nổi)"),
    ("dock_main_ferry_south", "N_ben_do_nam", "Bến đò bờ nam sông chính (x≈1727)"),
    ("dock_south_river", "N_ben_hem_H10b", "Bến hẻm H10b (bờ bắc sông phía nam)"),
    ("dock_south_ferry", "N_ben_do_song_nam_bac", "Bến đò sông phía nam, bờ bắc"),
    ("dock_east_south_river", "N_ben_hem_H2", "Bến hẻm H2 (bờ bắc sông phía nam, phía đông – gần Sân gà Olympia)"),
]
BOAT_CLEAR = 6       # thuyền người chơi cách bờ/vật ít nhất (px) khi chọn điểm nước của bến
RDP_TOL = 2.0
NPC_EXCLUDE = re.compile(r"^(N_ga__|N_vit__|N_ga_dau_|NV_cho_|NV_meo_)")


def log(*a):
    try:
        print(*a, flush=True)
    except UnicodeEncodeError:
        print(*(str(v).encode("ascii", "replace").decode() for v in a), flush=True)


def is_traffic(row):
    if row["name"] in KEEP:
        return False
    if row["name"] in OLD_BOAT_LAYERS:
        return True
    return row["gp"].split("/")[-1] in TRAFFIC_GROUPS


# ------------------------------------------------------------------ ảnh: cắt mép, mốc chạm đất

def _arr(L, row, u):
    return np.asarray(L.image(row, u)).copy()


def _find_crop(small, big):
    """small là ảnh cắt (khung con) của big? → (dx, dy) hoặc None."""
    h, w = small.shape[:2]
    H, W = big.shape[:2]
    if h > H or w > W or (h == H and w == W):
        return None
    win = sliding_window_view(big, (h, w, 4))[:, :, 0]
    eq = (win == small).all(axis=(2, 3, 4))
    ys, xs = np.nonzero(eq)
    if len(ys) == 0:
        return None
    return int(xs[0]), int(ys[0])


def classify_images(L, row):
    """Ảnh duy nhất của layer → {u: ("full", u, 0, 0) | ("crop", u_cha, dx, dy)}. Ảnh bị cắt ở mép bản đồ / chỗ khuất
    là khung con y hệt của một ảnh đầy đủ (Aseprite không giữ phần ngoài khung) → tìm lại vị trí thật."""
    us = sorted({fr[0] for fr in row["frames"] if fr is not None})
    arrs = {u: _arr(L, row, u) for u in us}
    order = sorted(us, key=lambda u: -(arrs[u].shape[0] * arrs[u].shape[1]))
    full, out = [], {}
    for u in order:
        hit = None
        for f in full:
            m = _find_crop(arrs[u], arrs[f])
            if m is not None:
                hit = ("crop", f, m[0], m[1])
                break
        if hit is None:
            full.append(u)
            out[u] = ("full", u, 0, 0)
        else:
            out[u] = hit
    return out, arrs


def hull_anchor(arr, kind, direction, hull_len):
    """Mốc chạm đất/mặt nước dưới tâm xe (toạ độ trong ảnh).
    Xe máy: x giữa khoảng cột có ≥ 4 điểm đặc (bỏ chi tiết mảnh), y = hàng đặc thấp nhất (đáy bánh xe).
    Thuyền: mũi thuyền luôn là điểm đặc xa nhất theo hướng chạy (phía sau là máy, cần lái dài, bọt/tia nước) →
    thân thuyền = hull_len px tính từ mũi; x = giữa thân, y = đáy thân ở cột giữa thân (mặt nước dưới tâm thuyền)."""
    a = arr[..., 3] > 0
    if kind == "boat":
        cols = np.nonzero(a.any(axis=0))[0]
        if direction == "east":
            c1 = int(cols.max())
            c0 = max(c1 - hull_len + 1, 0)
        else:
            c0 = int(cols.min())
            c1 = min(c0 + hull_len - 1, a.shape[1] - 1)
        # thuyền bốc đầu nghiêng: lấy đáy thân ở giữa thân (không lấy đuôi chìm sâu nhất)
        mid = (c0 + c1) // 2
        rows = np.nonzero(a[:, max(mid - 3, 0):mid + 4].any(axis=1))[0]
        return (c0 + c1) / 2.0, float(rows.max())
    else:
        cols = np.nonzero(a.sum(axis=0) >= 4)[0]
        if len(cols) == 0:
            cols = np.nonzero(a.any(axis=0))[0]
        c0, c1 = int(cols.min()), int(cols.max())
    rows = np.nonzero(a[:, c0:c1 + 1].any(axis=1))[0]
    return (c0 + c1) / 2.0, float(rows.max())


def boat_hull_len(L, by_name):
    """Chiều dài thân vỏ lãi (mũi → máy) đo trên song_vo_lai_2 (ảnh không có bọt): khoảng cột có ≥ 6 điểm đặc."""
    row = by_name.get("song_vo_lai_2")
    if row is None:
        return 150
    fr = next(fr for fr in row["frames"] if fr is not None)
    a = np.asarray(L.image(row, fr[0]))[..., 3] > 0
    cols = np.nonzero(a.sum(axis=0) >= 6)[0]  # cần lái dài chỉ 4–5 điểm/cột
    return int(cols.max() - cols.min() + 1)


def _hash(arr):
    return hashlib.md5(arr.tobytes() + bytes(str(arr.shape), "ascii")).hexdigest()


# ------------------------------------------------------------------ đường đi

def rdp(points, tol):
    if len(points) < 3:
        return list(points)
    pts = np.asarray(points, float)
    keep = np.zeros(len(pts), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        ab = b - a
        n = math.hypot(*ab)
        seg = pts[i + 1:j]
        if n < 1e-9:
            d = np.hypot(*(seg - a).T)
        else:
            d = np.abs(ab[0] * (seg[:, 1] - a[1]) - ab[1] * (seg[:, 0] - a[0])) / n
        k = int(np.argmax(d))
        if d[k] > tol:
            m = i + 1 + k
            keep[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return [points[i] for i in range(len(points)) if keep[i]]


def arc_lengths(points):
    s = [0.0]
    for a, b in zip(points, points[1:]):
        s.append(s[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    return s


def project_s(points, p):
    """Độ dài cung (px) của điểm gần p nhất trên đường gấp khúc."""
    best, best_s = 1e18, 0.0
    s = 0.0
    for a, b in zip(points, points[1:]):
        ab = (b[0] - a[0], b[1] - a[1])
        n2 = ab[0] ** 2 + ab[1] ** 2
        t = 0.0 if n2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / n2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
        d = (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2
        if d < best:
            best, best_s = d, s + math.sqrt(n2) * t
        s += math.sqrt(n2)
    return best_s, math.sqrt(best)


def seg_dist(points, p):
    return project_s(points, p)[1]


# ------------------------------------------------------------------ atlas một trang

class Atlas:
    def __init__(self, width=2048):
        self.width = width
        self.items = []
        self.by_hash = {}

    def add(self, arr):
        key = _hash(arr)
        if key in self.by_hash:
            return self.by_hash[key]
        ref = [0, 0, int(arr.shape[1]), int(arr.shape[0])]
        self.items.append((arr, ref))
        self.by_hash[key] = ref
        return ref

    def pack(self, path):
        order = sorted(range(len(self.items)), key=lambda i: (-self.items[i][0].shape[0], -self.items[i][0].shape[1]))
        x = y = row_h = 0
        for i in order:
            arr, ref = self.items[i]
            h, w = arr.shape[:2]
            if x + w > self.width:
                x, y, row_h = 0, y + row_h + 1, 0
            ref[0], ref[1] = x, y
            x += w + 1
            row_h = max(row_h, h)
        H = y + row_h
        W = max((ref[0] + ref[2] for _, ref in self.items), default=1)
        page = np.zeros((max(H, 1), max(W, 1), 4), np.uint8)
        for arr, ref in self.items:
            page[ref[1]:ref[1] + ref[3], ref[0]:ref[0] + ref[2]] = arr
        Image.fromarray(page, "RGBA").save(path, optimize=True)
        return page.shape[1], page.shape[0]


# ------------------------------------------------------------------ phân tích một layer xe/thuyền

class Track:
    """Một layer xe/thuyền: ảnh đầy đủ, vị trí thật từng frame, mốc chạm đất, hướng, tốc độ, đường đi."""

    def __init__(self, L, row, kind, frame_ms, hull_len=150):
        self.row = row
        self.name = row["name"]
        self.kind = kind
        info, arrs = classify_images(L, row)
        self.info, self.arrs = info, arrs
        self.full = [u for u, v in info.items() if v[0] == "full"]
        self.pose = []      # mỗi frame: (u_đầy_đủ, x_thật, y_thật) | None
        for fr in row["frames"]:
            if fr is None:
                self.pose.append(None)
                continue
            kind_, parent, dx, dy = info[fr[0]]
            self.pose.append((parent, fr[1] - dx, fr[2] - dy))
        # hướng + tốc độ theo góc trên-trái thật (ảnh đã bù phần bị cắt)
        tl = [None if p is None else (p[1], p[2]) for p in self.pose]
        steps = []
        for i in range(len(tl)):
            a, b = tl[i], tl[(i + 1) % len(tl)]
            if a is not None and b is not None:
                steps.append((b[0] - a[0], b[1] - a[1]))
        mags = [math.hypot(*s) for s in steps]
        step = median(mags)
        # bỏ bước "nhảy về đầu" (dài gấp nhiều lần bước thường)
        good = [s for s, m in zip(steps, mags) if m < step * 3 + 2]
        self.dx_sign = 1 if sum(s[0] for s in good) > 0 else -1
        self.direction = "east" if self.dx_sign > 0 else "west"
        self.speed = round(median(math.hypot(*s) for s in good) * 1000.0 / frame_ms, 1)
        # mốc chạm đất: ảnh cùng cỡ (bánh xe quay) → một mốc chung (không rung); khác cỡ (thuyền bốc đầu, tia nước
        # cao thấp) → mốc riêng từng ảnh
        anchors = {u: hull_anchor(arrs[u], kind, self.direction, hull_len) for u in self.full}
        same = len({arrs[u].shape for u in self.full}) == 1
        if same:
            m = (median(a[0] for a in anchors.values()), median(a[1] for a in anchors.values()))
            anchors = {u: m for u in anchors}
        self.anchors = anchors
        pts = [None if p is None else (p[1] + anchors[p[0]][0], p[2] + anchors[p[0]][1]) for p in self.pose]
        self.points_by_frame = pts
        # thứ tự thời gian: bắt đầu ngay sau bước nhảy lớn nhất (hoặc sau đoạn khuất)
        n = len(pts)
        start = 0
        worst = -1.0
        for i in range(n):
            a, b = pts[i - 1], pts[i]
            if b is None:
                continue
            gap = 1e9 if a is None else math.hypot(b[0] - a[0], b[1] - a[1])
            if gap > step * 3 + 2 and gap > worst:
                worst, start = gap, i
        self.start_frame = start
        raw_path = [pts[(start + k) % n] for k in range(n) if pts[(start + k) % n] is not None]
        if kind == "boat" and len(raw_path) > 7:
            # thuyền nhấp nhô ±1–3 px theo khung (mốc riêng từng ảnh) → làm trơn trung bình trượt 7 điểm (giữ hai đầu)
            sm = []
            for i in range(len(raw_path)):
                lo, hi = max(0, i - 3), min(len(raw_path), i + 4)
                k = min(i - lo, hi - 1 - i)
                win = raw_path[i - k:i + k + 1]
                sm.append((sum(p[0] for p in win) / len(win), sum(p[1] for p in win) / len(win)))
            raw_path = sm
        self.path = [(round(p[0], 1), round(p[1], 1)) for p in raw_path]
        # khung hoạt ảnh: ảnh đầy đủ theo thứ tự xuất hiện + nhịp đổi khung
        order, runs, last, run = [], [], None, 0
        for k in range(n):
            p = self.pose[(start + k) % n]
            u = None if p is None else p[0]
            if u is not None and u not in order:
                order.append(u)
            if u == last:
                run += 1
            else:
                if last is not None and run:
                    runs.append(run)
                last, run = u, 1
        self.order = order
        self.frame_ms = int(round(median(runs) if runs else 1)) * frame_ms

    def full_arrays(self):
        return [self.arrs[u] for u in self.order]


def attach_offset(main, att):
    """Độ lệch (median) góc trên-trái ảnh phụ (bóng/vệt sóng/bọt) so với mốc chạm đất của xe, xét các frame cả hai
    cùng hiện. → ((dx, dy), [ảnh đầy đủ theo thứ tự], nhịp ms) hoặc None."""
    dxs, dys = [], []
    for p, q in zip(main.points_by_frame, att.pose):
        if p is None or q is None:
            continue
        dxs.append(q[1] - p[0])
        dys.append(q[2] - p[1])
    if not dxs:
        return None
    return (round(median(dxs)), round(median(dys))), att.full_arrays(), att.frame_ms


# ------------------------------------------------------------------ chính

def build(rows, by_name, L, out_dir, frame_ms, foot, reach, blocked, raw, import_as_image):
    W, H = L.W, L.H
    os.makedirs(out_dir, exist_ok=True)
    hull_len = boat_hull_len(L, by_name)
    # ---- các layer xe/thuyền chính + phần đính kèm
    specs = []
    for row in rows:
        name = row["name"]
        if not is_traffic(row) or row["top"] != "03_Object" or name.endswith("_bot_nuoc") or name.endswith("_mui_dap_nuoc"):
            continue
        m = NEW_BIKE_RE.match(name)
        b = NEW_BOAT_RE.match(name)
        if m:
            specs.append({"row": row, "kind": "bike", "base": ROUTE_BASE[m.group(1)], "seg": int(m.group(3)),
                          "shadow": name + "_bong", "wake": None, "foam": []})
        elif b:
            specs.append({"row": row, "kind": "boat", "base": ROUTE_BASE[b.group(1)], "seg": int(b.group(3)),
                          "shadow": None, "wake": name + "_bong", "foam": []})
        elif name in OLD_BIKES:
            specs.append({"row": row, "kind": "bike", "base": OLD_BIKES[name], "seg": 1, "shadow": name + "_bong",
                          "wake": None, "foam": []})
        elif name in OLD_BOATS:
            o = OLD_BOATS[name]
            specs.append({"row": row, "kind": "boat", "base": "river_village", "seg": 1, "shadow": o["shadow"],
                          "wake": o["wake"], "foam": o["foam"], "splash": o.get("splash")})
        else:
            log("  CẢNH BÁO giao thông: layer lạ %s" % name)
    tracks = {}
    for s in specs:
        t = Track(L, s["row"], s["kind"], frame_ms, hull_len)
        tracks[t.name] = t
        s["track"] = t
    att_tracks = {}

    def att(name):
        if name is None or name not in by_name:
            return None
        if name not in att_tracks:
            att_tracks[name] = Track(L, by_name[name], "att", frame_ms)
        return att_tracks[name]

    atlas = Atlas()
    # ---- gộp kiểu xe (dedupe theo bộ ảnh quay về hướng đông)
    looks = {}
    for s in specs:
        t = s["track"]
        arrs = t.full_arrays()
        canon = arrs if t.direction == "east" else [a[:, ::-1] for a in arrs]
        key = (t.kind, tuple(sorted(_hash(np.ascontiguousarray(a)) for a in canon)))
        looks.setdefault(key, []).append(s)
    vehicles = []
    look_of = {}
    counters = {}
    for key, group in sorted(looks.items(), key=lambda kv: (kv[0][0], kv[1][0]["row"]["idx"])):
        kind = key[0]
        counters[kind] = counters.get(kind, 0) + 1
        first = group[0]["track"]
        vid = "%s_%02d" % (kind, counters[kind])
        by_dir = {}
        for s in group:
            by_dir.setdefault(s["track"].direction, s["track"])
        frames, anchors, mirrored = {}, {}, None
        for d in ("east", "west"):
            t = by_dir.get(d)
            if t is not None:
                arrs = t.full_arrays()
                anchors[d] = [list(t.anchors[u]) for u in t.order]
                frames[d] = [atlas.add(np.ascontiguousarray(a)) for a in arrs]
        for d, o in (("east", "west"), ("west", "east")):
            if d not in frames:
                t = by_dir[o]
                arrs = [np.ascontiguousarray(a[:, ::-1]) for a in t.full_arrays()]
                anchors[d] = [[t.arrs[u].shape[1] - 1 - t.anchors[u][0], t.anchors[u][1]] for u in t.order]
                frames[d] = [atlas.add(a) for a in arrs]
                mirrored = d
        src = by_dir.get("east") or by_dir.get("west")
        size = [int(src.arrs[src.order[0]].shape[1]), int(src.arrs[src.order[0]].shape[0])]
        fa = {d: [[round(a[0], 1), round(a[1], 1)] for a in anchors[d]] for d in anchors}
        entry = {"id": vid, "kind": kind, "frames": frames, "frame_ms": src.frame_ms if len(src.order) > 1 else frame_ms,
                 "anchor": fa["east"][0], "anchor_west": fa["west"][0],
                 "frame_anchors": fa if any(a != fa[d][0] for d in fa for a in fa[d]) else None,
                 "size": size, "speed_px_s": round(median(s["track"].speed for s in group), 1),
                 "source_layers": [s["row"]["name"] for s in group], "mirrored": mirrored,
                 "shadow": None, "shadow_offset": None, "wake": None, "wake_offset": None, "wake_ms": None}
        # bóng / vệt sóng / bọt: lấy theo layer đầu tiên có (độ lệch tính theo mốc của hướng nguồn; hướng kia lật gương)

        def attach(field, names):
            for s in group:
                for nm in names(s):
                    a = att(nm)
                    if a is None:
                        continue
                    got = attach_offset(s["track"], a)
                    if got is None:
                        continue
                    (ox, oy), arrs, ms = got
                    d = s["track"].direction
                    out = {}
                    for dd in ("east", "west"):
                        if dd == d:
                            out[dd] = ([atlas.add(np.ascontiguousarray(x)) for x in arrs], [ox, oy])
                        else:
                            w = arrs[0].shape[1]
                            out[dd] = ([atlas.add(np.ascontiguousarray(x[:, ::-1])) for x in arrs], [-ox - w + 1, oy])
                    return out, ms
            return None

        sh = attach("shadow", lambda s: [s.get("shadow")])
        if sh is not None:
            (out, ms) = sh
            entry["shadow"] = {d: out[d][0][0] for d in out}
            entry["shadow_offset"] = {d: out[d][1] for d in out}
        wk = attach("wake", lambda s: [s.get("wake")])
        if wk is not None:
            (out, ms) = wk
            entry["wake"] = {d: out[d][0] for d in out}
            entry["wake_offset"] = {d: out[d][1] for d in out}
            entry["wake_ms"] = ms
        fm = attach("foam", lambda s: s.get("foam") or [])
        if fm is not None:
            (out, ms) = fm
            entry["foam"] = {d: out[d][0] for d in out}
            entry["foam_offset"] = {d: out[d][1] for d in out}
            entry["foam_ms"] = ms
        vehicles.append(entry)
        for s in group:
            look_of[s["row"]["name"]] = vid
    # ---- đường đi: nối các đoạn cùng đường + cùng chiều theo thứ tự chạy
    groups = {}
    for s in specs:
        t = s["track"]
        rid = "%s_%s" % (s["base"], t.direction)
        groups.setdefault(rid, []).append(s)
    routes = []
    route_pts = {}
    for rid, segs in sorted(groups.items()):
        sgn = segs[0]["track"].dx_sign
        segs.sort(key=lambda s: sgn * s["track"].path[0][0])
        pts = []
        joins = []
        for s in segs:
            p = list(s["track"].path)
            if pts:
                last = pts[-1]
                while p and sgn * (p[0][0] - last[0]) <= 0:
                    p.pop(0)
                if p:
                    joins.append({"at": [round(last[0]), round(last[1])], "gap_px": round(math.hypot(p[0][0] - last[0], p[0][1] - last[1]), 1)})
            pts.extend(p)
        simp = rdp(pts, RDP_TOL)
        simp = [[round(x, 1), round(y, 1)] for x, y in simp]
        route_pts[rid] = simp
        kind = segs[0]["kind"]
        ends = []
        for which, p in (("start", simp[0]), ("end", simp[-1])):
            edge = None
            if p[0] < 60:
                edge = "W"
            elif p[0] > W - 60:
                edge = "E"
            ends.append({"at": which, "pos": p, "map_edge": edge})
        routes.append({"id": rid, "kind": kind, "points": simp, "loop": False, "lane_offset": 0.0,
                       "length_px": round(arc_lengths(simp)[-1], 1), "ends": ends, "joins": joins,
                       "source_layers": [s["row"]["name"] for s in segs], "next": None, "prev": None, "notes": []})
    by_id = {r["id"]: r for r in routes}
    # nối tiếp: cuối đường A gần đầu đường B (cùng loại, cùng chiều) → A.next = B
    for a in routes:
        for b in routes:
            if a is b or a["kind"] != b["kind"] or a["id"].rsplit("_", 1)[1] != b["id"].rsplit("_", 1)[1]:
                continue
            pa, pb = a["points"][-1], b["points"][0]
            if math.hypot(pa[0] - pb[0], pa[1] - pb[1]) <= 90:
                a["next"], b["prev"] = b["id"], a["id"]
    # làn: lệch vuông góc so với đường giữa của cặp hai chiều cùng đường (+ = bên phải hướng chạy)
    for r in routes:
        base, d = r["id"].rsplit("_", 1)
        other = by_id.get(base + "_" + ("west" if d == "east" else "east"))
        if other is None:
            r["notes"].append("một chiều (nguồn chỉ có xe chạy %s)" % ("sang đông" if d == "east" else "sang tây"))
            continue
        offs = []
        pts = r["points"]
        dense = densify(pts, 16)
        for i in range(len(dense) - 1):
            p, q = dense[i], dense[i + 1]
            dx, dy = q[0] - p[0], q[1] - p[1]
            n = math.hypot(dx, dy)
            if n < 1e-6:
                continue
            nx, ny = -dy / n, dx / n
            s_, dist = project_s(other["points"], p)
            if dist > 120:
                continue
            o = point_at(other["points"], s_)
            offs.append(((p[0] - o[0]) * nx + (p[1] - o[1]) * ny) / 2.0)
        if offs:
            r["lane_offset"] = round(median(offs), 1)
    for r in routes:
        if r["id"].startswith("river_main"):
            r["notes"].append("đầu phía tây dừng ở cầu bê tông sông chính (x≈3600): vỏ lãi trong tranh chui dưới cầu rồi khuất; "
                              "sông vẫn thông qua chợ nổi về xóm cũ (xem water.png) nhưng tranh không có xe chạy đoạn đó")
        if r["id"].startswith("river_village"):
            r["notes"].append("vỏ lãi của bản đồ cũ: chạy trong khúc sông làng x<1460 (bản đồ cũ 1280 px); "
                              "đầu phía đông ở giữa bản đồ mới (trước cầu gỗ x≈1390) → mờ dần/quay đầu ở đó")
        if r["id"].startswith("road_village"):
            r["notes"].append("xe của bản đồ cũ: đầu phía đông ở x≈1300 (mép bản đồ cũ) – nối với đường mới qua next/prev")
        if r["id"].startswith("river_south"):
            r["notes"].append("chui dưới cầu khỉ sông phía nam (x≈2986) như trong tranh; thuyền người chơi không qua được")
        for e in r["ends"]:
            if e["map_edge"]:
                r["notes"].append("%s ra khỏi mép %s bản đồ → xe biến mất/xuất hiện lại ở đó" % (
                    "đầu" if e["at"] == "start" else "cuối", "tây" if e["map_edge"] == "W" else "đông"))
    # ---- xe xuất phát: mỗi layer nguồn = một xe trên đường, vị trí (độ dài cung) ở frame 0 của bản đồ
    spawns = []
    for s in specs:
        t = s["track"]
        rid = "%s_%s" % (s["base"], t.direction)
        pts = route_pts[rid]
        p0 = t.points_by_frame[0]
        first_visible = t.start_frame
        if p0 is None:
            p0 = t.points_by_frame[first_visible]
        s0, _ = project_s(pts, p0)
        visible = sum(1 for p in t.points_by_frame if p is not None)
        sp = {"route": rid, "vehicle": look_of[t.name], "source_layer": t.name, "phase_px": round(s0, 1),
              "visible_at_frame0": t.points_by_frame[0] is not None, "speed_px_s": t.speed,
              "period_s": round(len(t.points_by_frame) * frame_ms / 1000.0, 2),
              "visible_s": round(visible * frame_ms / 1000.0, 2),
              "segment": [round(project_s(pts, t.path[0])[0], 1), round(project_s(pts, t.path[-1])[0], 1)]}
        if t.name in RACE_RIDERS:
            sp["race_rider"] = t.name
        spawns.append(sp)
    # ---- mặt nước / mặt đường
    water = np.zeros((H, W), bool)
    for name in WATER_LAYERS:
        if name in by_name:
            water |= L.mask(by_name[name])
    # nước = phần layer nước bị chặn đi bộ (bỏ mép bãi/bờ vẽ đè), cộng phần nước dưới cầu cao (mặt cầu đi bộ được nên
    # va chạm mở – thuyền vẫn chui qua)
    high = np.zeros((H, W), bool)
    for name in HIGH_BRIDGES:
        if name in by_name:
            high |= ndimage.binary_fill_holes(L.mask(by_name[name]))
    water &= raw | high
    obstacles = np.zeros((H, W), bool)
    for row in rows:
        if row["top"] != "03_Object" or is_traffic(row) or row["name"] in HIGH_BRIDGES or row["name"] in RUNTIME_HIDDEN:
            continue
        if row["frames"][0] is None:
            continue
        obstacles |= L.mask(row)
    # vật thể chỉ chặn thuyền ở "chân" (16 hàng dưới cùng của từng mảnh liền): ghe đậu/nhà sàn/cọc chặn, còn tán cây
    # dừa/bần vươn ra kênh (cùng mảnh với gốc trên bờ) thì thuyền chạy bên dưới được
    lab_o, n_o = ndimage.label(obstacles, structure=np.ones((3, 3), bool))
    footprint = np.zeros_like(obstacles)
    for k, sl in enumerate(ndimage.find_objects(lab_o), start=1):
        if sl is None:
            continue
        y1 = sl[0].stop
        y0 = max(sl[0].start, y1 - 16)
        sub = lab_o[y0:y1, sl[1]] == k
        footprint[y0:y1, sl[1]] |= sub
    obstacles = footprint
    low = np.zeros((H, W), bool)
    for name in LOW_BRIDGES + PIERS:
        if name in by_name:
            low |= ndimage.binary_fill_holes(L.mask(by_name[name]))
    for x, y, w, h in OLD_LOW_RECTS:
        low[y:y + h, x:x + w] = True
    nav_water = water & ~ndimage.binary_dilation(obstacles | low, iterations=1)
    nav_water = ndimage.binary_erosion(nav_water, iterations=2, border_value=1)
    lab, n = ndimage.label(nav_water)
    # chỉ giữ mặt nước thông với các đường vỏ lãi chạy (sông chính, sông phía nam, sông làng và kênh nối) – bỏ ao kín,
    # mương ruộng, rạch bị cầu thấp chặn hai đầu
    keep = np.zeros(n + 1, bool)
    near = np.zeros((H, W), bool)
    for r in routes:
        if r["kind"] != "boat":
            continue
        for x, y in densify(r["points"], 8):
            xi, yi = int(round(x)), int(round(y))
            if 0 <= xi < W and 0 <= yi < H:
                near[max(yi - 6, 0):yi + 7, max(xi - 6, 0):xi + 7] = True
    for k in np.unique(lab[near & nav_water]):
        keep[k] = k > 0
    nav_water = keep[lab]
    roads = np.zeros((H, W), bool)
    for name in ROAD_LAYERS:
        if name in by_name:
            roads |= L.mask(by_name[name])
    roads[200:244, 0:640] = True  # khúc đường làng bản đồ cũ (nằm trong co_nen, không có layer riêng)
    for fname, m in (("water.png", nav_water), ("roads.png", roads)):
        path = os.path.join(out_dir, fname)
        Image.fromarray(m.astype(np.uint8), "L").save(path, optimize=True)
        import_as_image(path)
    # ---- cầu (để hệ thống giao thông biết thuyền chui qua/không)
    bridges = []
    for name, high in [(n_, True) for n_ in HIGH_BRIDGES] + [(n_, False) for n_ in LOW_BRIDGES]:
        row = by_name.get(name)
        if row is None or row["frames"][0] is None:
            continue
        m = L.mask(row)
        ys, xs = np.nonzero(m)
        if not len(xs) or not (m & ndimage.binary_dilation(water, iterations=3)).any():
            continue
        bridges.append({"id": name, "rect": [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)],
                        "player_boat_passes": high})
    # ---- bến thuyền
    docks = []
    deep = ndimage.binary_erosion(nav_water, iterations=BOAT_CLEAR, border_value=1)
    dist, (iy, ix) = ndimage.distance_transform_edt(~deep, return_indices=True)
    land = foot & reach
    for _did, layer, _note in DOCKS:
        if layer in by_name:
            land &= ~ndimage.binary_dilation(L.mask(by_name[layer]), iterations=2)
    land_dist = ndimage.distance_transform_edt(~land)
    for did, layer, note in DOCKS:
        row = by_name.get(layer)
        if row is None:
            log("  CẢNH BÁO bến: không có layer %s" % layer)
            continue
        pier = ndimage.binary_fill_holes(L.mask(row)) if layer not in ("A_cau_van_ben_ghe",) else L.mask(row)
        cand = pier & foot & reach
        if not cand.any():
            # bến hẹp hơn khung chân: lấy điểm đứng được gần bến nhất
            grown = ndimage.binary_dilation(pier, iterations=8)
            cand = grown & foot & reach
        if not cand.any():
            log("  CẢNH BÁO bến %s: không có chỗ đứng" % did)
            continue
        ys, xs = np.nonzero(cand)
        d = dist[ys, xs]
        # ưu tiên đầu bến (xa bờ đất nhất) trong số điểm có nước sâu trong vòng 20 px
        near = d <= max(20.0, float(d.min()))
        far = land_dist[ys, xs]
        k = int(np.argmax(np.where(near, far, -1.0)))
        px_, py_ = int(xs[k]), int(ys[k])
        qx, qy = int(ix[py_, px_]), int(iy[py_, px_])
        vx, vy = qx - px_, qy - py_
        facing = ("E" if vx > 0 else "W") if abs(vx) >= abs(vy) else ("S" if vy > 0 else "N")
        docks.append({"id": did, "pos": [px_, py_], "water_pos": [qx, qy], "facing": facing,
                      "dist_px": round(float(d[k]), 1), "layer": layer, "note": note})
    page = os.path.join(out_dir, "traffic_atlas.png")
    aw, ah = atlas.pack(page)
    data = {"version": 1, "frame_ms": frame_ms, "atlas": "traffic_atlas.png", "atlas_size": [aw, ah],
            "vehicles": vehicles, "routes": routes, "spawns": spawns, "docks": docks, "bridges": bridges,
            "notes": [
                "Toạ độ pixel bản đồ 5120×2160; vùng ảnh [x, y, w, h] trong traffic_atlas.png.",
                "Vẽ xe: góc trên-trái khung = điểm trên đường − anchor (hướng east) / − anchor_west (hướng west).",
                "Bóng/vệt sóng/bọt: góc trên-trái = điểm trên đường + *_offset[hướng]; khung đổi theo *_ms.",
                "Đường: points theo thứ tự chạy; lane_offset = lệch (px) khỏi đường giữa của cặp hai chiều, + = bên phải.",
                "spawns: mỗi layer nguồn là một xe, phase_px = vị trí (độ dài cung) ở frame 0 bản đồ, chạy speed_px_s;",
                "    segment = đoạn [s_đầu, s_cuối] của đường mà layer nguồn vẽ (mỗi layer chạy một đoạn rồi quay lại sau period_s).",
                "mirrored: hướng được tạo bằng lật gương (tranh chỉ vẽ một hướng).",
                "water.png / roads.png: L8 0/1 đủ cỡ bản đồ (nhập dạng Image).",
            ]}
    with open(os.path.join(out_dir, "traffic.json"), "w", encoding="utf8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    log("traffic: %d kiểu xe (%s), %d đường, %d xe, %d bến, %d cầu, atlas %dx%d, nước=%d px, đường=%d px" % (
        len(vehicles), ", ".join("%s×%d" % (v["id"], len(v["source_layers"])) for v in vehicles), len(routes), len(spawns),
        len(docks), len(bridges), aw, ah, int(nav_water.sum()), int(roads.sum())))
    return data, nav_water, roads


def densify(points, step):
    out = []
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) // step))
        for k in range(n):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    out.append(tuple(points[-1]))
    return out


def point_at(points, s):
    acc = 0.0
    for a, b in zip(points, points[1:]):
        n = math.hypot(b[0] - a[0], b[1] - a[1])
        if acc + n >= s and n > 0:
            t = (s - acc) / n
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        acc += n
    return tuple(points[-1])


# ================================================================== người đứng (ứng viên người đi bộ)

ROLE_RULES = [
    ("vendor", ("ban_", "ganh_hang", "tho_hot_toc", "tho_lot_dua", "chu_quan", "chu_vuon", "ben_cho")),
    ("spectator", ("khan_gia",)),
    ("arena_staff", ("trong_tai", "su_ke", "chu_ga", "mc_", "goc_", "rapper_mc")),
    ("student", ("hoc_sinh",)),
    ("teacher", ("giao_vien",)),
    ("guard", ("bao_ve",)),
    ("kid", ("da_bong",)),
    ("worker", ("cong_nhan", "nong_dan", "cao_lua", "khieng", "tho_")),
    ("customer", ("khach_mua", "khach_vao_san", "khach_olympia", "an_sang")),
    ("shopper", ("di_cho",)),
    ("passerby", ("qua_cau", "qua_do", "pho_bac", "goi_dien", "ao_ngua", "dam_trang", "vest_ca_vat")),
    ("elder", ("ong_", "ba_", "danh_co")),
    ("resident", ("dan_",)),
]
## Người gắn với cốt truyện / điểm tương tác / vai cố định → giữ đứng yên.
STORY_NPCS = {"N_npc_ba_Lan_ban_com", "N_npc_chu_quan_vong", "N_npc_danh_co_tuong", "N_npc_ong_cau_ca_ao_sen",
              "N_npc_chu_vuon_kieng", "NV_co_ban_ve_so", "NV_rapper_mc_dau_truong", "NV_ba_lo_canh_cong_dau_truong",
              "NV_xam_tay_nhay_o_quan", "NV_ao_ngua_o_san_dinh", "NV_ong_cau_ca", "N_npc_mc_olympia"}
KEEP_ROLES = {"vendor", "spectator", "arena_staff", "customer", "guard", "teacher"}
WALK_ROLES = {"shopper", "passerby", "resident", "student"}


def _role(name):
    low = name.lower()
    for role, keys in ROLE_RULES:
        if any(k in low for k in keys):
            return role
    return "resident"


def build_people(rows, L, out_dir, hidden, frame_ms):
    atlas = Atlas(1024)
    people = []
    for row in rows:
        name = row["name"]
        is_npc = (row["gp"].endswith("NEW_NPC") and "_npc_" in name) or (name.startswith("NV_") and not name.endswith("_bong"))
        if not is_npc or NPC_EXCLUDE.match(name) or row["top"] != "03_Object":
            continue
        frames = [fr for fr in row["frames"] if fr is not None]
        if not frames:
            continue
        us, positions = [], set()
        for fr in frames:
            if fr[0] not in us:
                us.append(fr[0])
            positions.add((fr[1], fr[2]))
        arrs = [np.asarray(L.image(row, u)).copy() for u in us]
        regions = [atlas.add(np.ascontiguousarray(a)) for a in arrs]
        fr0 = frames[0]
        w, h = arrs[0].shape[1], arrs[0].shape[0]
        xs = [p[0] for p in positions]
        walks = len(positions) > 3 and (max(xs) - min(xs)) > 8
        role = _role(name)
        keep_static = name in STORY_NPCS or role in KEEP_ROLES or name in hidden
        people.append({
            "id": name, "pos": [fr0[1] + w // 2, fr0[2] + h - 1], "topleft": [fr0[1], fr0[2]], "size": [w, h],
            "regions": regions, "frame_count": len(us), "facing": "down",
            "role": role, "source_walks": walks,
            "walk_frames": "yes (đi qua lại trong tranh, %d khung)" % len(us) if walks else "no (đứng nhún 2 khung)",
            "walker_candidate": (not keep_static) and role in WALK_ROLES, "keep_static": keep_static,
            "hidden_in_map": name in hidden,
        })
    atlas.pack(os.path.join(out_dir, "people_atlas.png"))
    data = {"version": 1, "atlas": "people_atlas.png", "frame_ms": frame_ms, "people": people,
            "notes": ["pos = điểm chân (giữa mép dưới) ở frame 0; topleft/size = khung ảnh ở frame 0.",
                      "facing chỉ là đoán (đa số vẽ nhìn thẳng xuống) – role đoán theo tên layer.",
                      "keep_static: người bán, khán giả, nhân viên sới, khách đứng mua, NPC cốt truyện – để yên trên bản đồ.",
                      "walker_candidate: người đi chợ/đi đường/dân xóm/học sinh có thể thành người đi bộ "
                      "(cần ẩn node bản đồ cùng tên khi thay bằng người chạy lúc chơi)."]}
    with open(os.path.join(out_dir, "people.json"), "w", encoding="utf8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    roles = {}
    for p in people:
        roles[p["role"]] = roles.get(p["role"], 0) + 1
    log("people: %d người (%d có thể đi bộ, %d đi lại sẵn trong tranh), vai: %s" % (
        len(people), sum(p["walker_candidate"] for p in people), sum(p["source_walks"] for p in people), roles))
    return data
