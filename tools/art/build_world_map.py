# -*- coding: utf-8 -*-
"""Dựng bản đồ thế giới mở rộng (5120×2160, 96 frame × 80 ms) cho MapView – độc lập với build_assets.py.

Chạy (từ thư mục gốc dự án, cần Python 3.12 + Pillow + numpy + scipy):
    python -I tools/art/build_world_map.py --export-dir <thư_mục_tạm>                 # xuất bằng Aseprite rồi dựng
    python -I tools/art/build_world_map.py --skip-export --export-dir <thư_mục_đã_xuất> # chỉ dựng lại
    thêm --audit-dir <thư_mục> để ghi ảnh kiểm tra va chạm/đi bộ (mặc định <export-dir>/audit)
Sau đó: godot --headless --path . --import

Nguồn: D:/GameArt/Chick_Fighter_World_Map_Expanded.aseprite (CHỈ ĐỌC – script lua không bao giờ lưu sprite).
Bước xuất: tools/art/export_world_layers.lua. Nội dung vẽ thêm (chợ đông, sạp riêng, bảng chỉ đường, người đi chợ) và
tích hợp tranh của chủ dự án (xe khô gà Lão Gà Khô, Sân gà Liên tỉnh, Sân gà Olympia): tools/art/world_map_extras.py.
Giao thông (xe máy, vỏ lãi + bóng/vệt sóng) bị loại khỏi bản đồ → traffic.json (tools/art/world_map_traffic.py).

Kết quả (ghi đè, chỉ trong game/art/world_map/ – KHÔNG đụng game/art/map/ vì build_arena.py còn đọc atlas cũ):
    world_atlas_*.png    trang atlas ≤ 4096×4096
    world_layers.json    manifest v3 (xem đầu game/world/map_view.gd)
    collision.png        mặt nạ va chạm 5120×2160 (L8, 255 = chặn), nhập dạng Image (không lên GPU)
    nav.png              lưới 4 px (1280×540, L8): bit0 đi bộ được, bit1 xe máy được, bit2 mặt đường
    minimap.png          ảnh thu nhỏ 1/4 (1280×540) cho bản đồ phím M
    shoppers.png         người đi chợ (market_crowd.gd)
    world_map_info.json  điểm cửa/biển chỉ đường/chỗ đứng của nội dung thêm (tham khảo cho world.gd)
    traffic.json + traffic_atlas.png   xe/thuyền chạy lúc chơi: kiểu xe, đường đi, xe xuất phát, bến thuyền, cầu
    water.png / roads.png  mặt nạ 0/1 đủ cỡ bản đồ: nước thuyền chạy được / mặt đường xe chạy được (Image)
    people.json + people_atlas.png     người đứng trên bản đồ (ứng viên người đi bộ)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # không để lại __pycache__ của module phụ
sys.path.insert(0, HERE)
import world_map_extras  # noqa: E402
import world_map_traffic  # noqa: E402
import world_map_fixes  # noqa: E402

ROOT_DEFAULT = os.path.abspath(os.path.join(HERE, "..", ".."))
ART_DEFAULT = "D:/GameArt/Chick_Fighter_World_Map_Expanded.aseprite"
ASEPRITE_DEFAULT = "D:/aseprite/build/bin/aseprite.exe"
OUT_REL = os.path.join("game", "art", "world_map")

ATLAS_W = 4096
ATLAS_MAX_H = 4096
TILE = 512
MIN_TILE = 128
SPLIT_MIN = 200            # layer động below/above có khung hợp > 200×200 → tách theo thành phần liên thông
NAV_CELL = 4
FOOT_HALF = 5              # = WorldPlayer.FOOT_HALF_WIDTH
FOOT_H = 5                 # = WorldPlayer.FOOT_HEIGHT
BIKE_EXTRA = 3
GROUP_ROLE = {"00_Ground": "below", "01_Water": "below", "02_Decor_Duoi": "below",
              "03_Object": "object", "04_Above": "above"}

## Tên node mà code/công cụ khác tra theo tên (MapView API, race, arena, minigame, world.gd): luôn là node có tên.
REQUIRED_NAMES = [
    "A_cau_van_ben_ghe", "A_cau_van_noi_dai", "A_ghe_nhua_01", "A_quan_tap_hoa_tuong", "B_cay_da_01_goc",
    "B_cay_da_01_tan", "B_chuoi_01", "B_co_dau_truong_01",
    "B_co_hoi_dinh", "B_cot_co_dinh", "B_cot_dien_01", "B_den_long_01", "B_den_long_02", "B_dinh_bac_tam_cap",
    "B_dinh_tuong_cot", "B_dua_01_tan", "B_dua_01_than", "B_dua_03_tan", "B_dua_03_than", "B_dua_04_tan",
    "B_dua_04_than", "B_dua_05_tan", "B_dua_05_than", "B_dua_nuoc_02", "B_ga_nha_01", "B_ga_nha_02",
    "B_khoi_nhang", "B_nha_vuon_1_tuong", "C_ca_tra_cau_van", "C_ca_tra_con_01", "C_cau_tau_ben_do",
    "C_chuoi_02", "C_cot_dien_01", "C_dua_04_tan", "C_dua_04_than", "C_dua_nuoc_01", "C_khoi_bep",
    "C_nha_la_tuong", "D_dua_02_tan", "D_dua_02_than", "E_vit_01",
    "F_co_to_quoc", "F_day_co_hoi_01", "F_day_co_hoi_02", "NV_ao_ngua_o_san_dinh",
    "NV_ba_lo_canh_cong_dau_truong", "NV_cho_vang", "NV_co_ban_ve_so", "NV_dam_trang_o_nha_vuon",
    "NV_khan_gia_1", "NV_khan_gia_2", "NV_khan_gia_3", "NV_khan_gia_4", "NV_non_den_jean_goi_dien",
    "NV_ong_cau_ca", "NV_rapper_mc_dau_truong", "NV_vest_ca_vat_do_o_san_den", "NV_xam_tay_nhay_o_quan",
    "NV_meo_tam_the", "N_lao_ga_kho_xe_kho_ga_la_chanh", "song_do_ngang", "song_do_ngang_gon",
    "N_san_lien_tinh_khan_dai", "N_san_olympia_khan_dai",
]
## Không được còn trong bản đồ (giao thông đã tách sang traffic.json; nội dung tự vẽ cũ đã thay bằng tranh của chủ dự án).
FORBIDDEN_NAMES = ["A_xe_may_con_tay_do", "A_xe_may_cho_ga", "C_xe_may_cho_dua", "C_xe_may_con_tay_den",
                   "song_vo_lai_1_boc_dau", "song_vo_lai_2", "X_lao_ga_kho", "X_lao_ga_kho_mia_trai",
                   "X_lao_ga_kho_mia_phai", "X_soi_lien_tinh", "X_nha_thi_dau_olympic"]

# ------------------------------------------------------------------ bảng sửa lỗi tích hợp (không sửa file .aseprite)

## Đổi vai trò một layer (below/object/above). Trống: chưa thấy layer nào xếp sai nhóm.
ROLE_OVERRIDE: dict[str, str] = {}
## Gốc Y-sort cố định (toạ độ y bản đồ) cho node object: mặt sàn/cầu để người đi trên được vẽ đè lên.
## Cầu/bến của khu mới đều nằm ở 02_Decor_Duoi (vẽ dưới nhân vật) nên không cần; cầu ván bản đồ cũ do
## World.set_node_sort_y đặt lúc chạy. Tán cây/mái che (above) che người chơi → MapView.set_focus làm trong.
SORT_Y: dict[str, float] = {}
## Vật chạy vòng của bản đồ cũ biến mất ở mép phải cũ (x≈1280–1500) giữa bản đồ mới → mờ dần trong 80 px.
## Tự tính trong fade_for(); bảng này chỉ để liệt kê/báo cáo.
FADE_REPORT: list[str] = []

## Mở lối (bỏ chặn) theo hình dạng (alpha, đã lấp lỗ) của layer: cầu ván, cầu khỉ, bến/cầu tàu mà layer
## 05_Collision của file art tô đặc như nước. Cầu bê tông trên đường đã được mở sẵn trong file art.
OPEN_LAYERS = [
    "N_cau_go_qua_song",            # cầu gỗ qua sông chính (x≈1400)
    "N_ben_do_bac", "N_ben_do_nam",  # bến đò (cầu tàu) hai bờ sông chính (x≈1727)
    "N_cho_cau_go_cap_ghe_1", "N_cho_cau_go_cap_ghe_2",  # cầu gỗ cập ghe ở kè chợ
    "N_cau_ban_nha_may", "N_ben_kenh_xang_S8",
    "N_cau_van_muong__01", "N_cau_van_muong__02", "N_cau_van_muong__03", "N_cau_van_muong__04",
    "N_cau_khi_rach_nho", "N_cau_ao_sen", "N_ben_hem_H10b", "N_ben_hem_H2",
    "N_cau_khi_song_nam",           # cầu khỉ qua sông phía nam (x≈2986)
    "N_ben_do_song_nam_bac", "N_ben_do_song_nam_nam",
    "N_ben_tau_du_lich", "N_ben_tau_du_lich_loi", "N_cho_bac_xuong_song__01",
]
## Ô chặn bổ sung (x, y, w, h). Phần bản đồ cũ: chuyển nguyên từ World.EXTRA_BLOCKERS cũ (layer va chạm của
## bản đồ cũ thiếu nhà/hàng rào/NPC bờ bắc – vẫn thiếu trong file mới, đã so pixel: giống hệt collision.png cũ).
EXTRA_BLOCKERS = [
    (0, 0, 1280, 14), (228, 14, 1052, 26), (28, 10, 196, 100), (2, 170, 110, 16), (150, 170, 108, 16),
    (35, 128, 47, 24), (232, 70, 46, 42), (310, 40, 176, 86), (328, 142, 44, 32), (412, 146, 40, 28),
    (456, 168, 30, 26), (394, 178, 20, 14), (545, 165, 30, 25), (300, 236, 26, 16), (208, 256, 28, 16),
    (130, 250, 30, 14), (672, 30, 276, 130), (822, 160, 30, 20), (760, 170, 62, 34), (862, 182, 26, 12),
    (902, 182, 26, 12), (985, 140, 30, 20), (1033, 40, 239, 90), (1138, 130, 24, 22), (1040, 182, 176, 18),
    (910, 246, 92, 16), (1040, 246, 90, 16), (908, 246, 10, 112), (1122, 246, 10, 112), (908, 344, 224, 14),
    (922, 328, 60, 18), (1062, 328, 60, 18), (1052, 286, 28, 18), (954, 262, 26, 18),
    # Mới: hàng bụi trên cùng bản đồ cũ chặn tới x=1280; tiếp tục mép trên của bản đồ mới.
    (1280, 0, 3840, 6),
]
## Ô mở lối (x, y, w, h): bản đồ cũ (World.OPEN_RECTS cũ) – cầu bê tông, cầu khỉ tre, cầu ván bến đò, cầu cá tra.
OPEN_RECTS = [
    (632, 558, 92, 44), (626, 770, 90, 36), (448, 262, 24, 129), (448, 469, 24, 52), (18, 728, 110, 13),
    # Cầu khỉ qua sông phía nam (N_cau_khi_song_nam): layer chỉ là cây tre 4–12 px, bị tán cây + NPC qua cầu
    # đè va chạm → mở một lối 16 px từ bờ bắc tới đường đất bờ nam (lối duy nhất sang xóm chài phía nam).
    (2980, 1866, 16, 172),
]


def log(*a):
    try:
        print(*a, flush=True)
    except UnicodeEncodeError:
        print(*(str(v).encode("ascii", "replace").decode() for v in a), flush=True)


# ------------------------------------------------------------------ xuất từ Aseprite

def export(aseprite, art, out):
    for sub in ("", "coll", "guide"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for sub in ("", "coll", "guide"):
        d = os.path.join(out, sub)
        for name in os.listdir(d):
            if name.endswith(".png") or name.endswith(".tsv") or name == "size.txt":
                os.remove(os.path.join(d, name))
    lua = os.path.join(HERE, "export_world_layers.lua")
    t = time.time()
    subprocess.run([aseprite, "-b", art, "--script-param", "out=" + out.replace("\\", "/"), "--script", lua], check=True)
    log("export: %.1fs" % (time.time() - t))


def read_rows(src):
    rows = []
    with open(os.path.join(src, "manifest.tsv"), encoding="utf8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            idx, top, gp, name, n, frames = line.split("\t")
            parsed = []
            for token in frames.split(" "):
                parsed.append(None if token == "-1" else tuple(int(v) for v in token.split(":")))
            rows.append({"idx": int(idx), "top": top, "gp": gp, "name": name, "n": int(n), "frames": parsed})
    with open(os.path.join(src, "size.txt")) as f:
        w, h, count, ms = (int(v) for v in f.read().split())
    return rows, (w, h, count, ms)


# ------------------------------------------------------------------ atlas

class Packer:
    """Gom mọi ảnh rồi xếp kệ (cao giảm dần) vào các trang ≤ ATLAS_W×ATLAS_MAX_H. Ảnh trùng byte dùng chung.
    ref = [trang, x, y, w, h] (list, được điền khi pack)."""

    def __init__(self):
        self.items = []
        self.by_hash = {}
        self.tag = "?"
        self.area_by_tag = {}

    def add(self, img):
        key = hashlib.md5(img.tobytes() + bytes(str(img.size), "ascii")).hexdigest()
        if key in self.by_hash:
            return self.by_hash[key]
        ref = [0, 0, 0, img.width, img.height]
        self.items.append((img, ref))
        self.by_hash[key] = ref
        self.area_by_tag[self.tag] = self.area_by_tag.get(self.tag, 0) + img.width * img.height
        return ref

    def area(self):
        return sum(img.width * img.height for img, _ in self.items)

    def pack(self, out_dir, prefix):
        order = sorted(range(len(self.items)), key=lambda i: (-self.items[i][0].height, -self.items[i][0].width))
        pages = [[]]
        x = y = row_h = 0
        for i in order:
            img, ref = self.items[i]
            w, h = img.size
            if x + w > ATLAS_W:
                x = 0
                y += row_h + 1
                row_h = 0
            if y + h > ATLAS_MAX_H:
                pages.append([])
                x = y = row_h = 0
            ref[0], ref[1], ref[2] = len(pages) - 1, x, y
            pages[-1].append((img, x, y))
            x += w + 1
            row_h = max(row_h, h)
        names, sizes = [], []
        for p, content in enumerate(pages):
            used_h = max(yy + img.height for img, _, yy in content)
            used_w = max(xx + img.width for img, xx, _ in content)
            page = Image.new("RGBA", (used_w, used_h), (0, 0, 0, 0))
            for img, xx, yy in content:
                page.paste(img, (xx, yy))
            name = "%s_%d.png" % (prefix, p)
            page.save(os.path.join(out_dir, name), compress_level=6)
            names.append(name)
            sizes.append((used_w, used_h))
            log("  %s %dx%d (%d ảnh)" % (name, used_w, used_h, len(content)))
        return names, sizes


# ------------------------------------------------------------------ tiện ích ảnh

class Layers:
    def __init__(self, src, size):
        self.src = src
        self.W, self.H = size
        self.cache = {}
        self.cache_bytes = 0

    def image(self, row, u, op=255):
        key = (row["idx"], u, op)
        if key not in self.cache:
            img = Image.open(os.path.join(self.src, "L%04d_%02d.png" % (row["idx"], u))).convert("RGBA")
            if op < 255:
                a = np.asarray(img).copy()
                a[..., 3] = (a[..., 3].astype(np.int32) * op // 255).astype(np.uint8)
                img = Image.fromarray(a, "RGBA")
            size = img.width * img.height * 4
            if self.cache_bytes + size > 2_500_000_000:
                self.cache.clear()
                self.cache_bytes = 0
            self.cache[key] = img
            self.cache_bytes += size
        return self.cache[key]

    def clip(self, img, x, y):
        """Cắt ảnh theo khung bản đồ → (ảnh, x, y) hoặc None."""
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + img.width, self.W), min(y + img.height, self.H)
        if x1 <= x0 or y1 <= y0:
            return None
        if (x0, y0, x1, y1) != (x, y, x + img.width, y + img.height):
            img = img.crop((x0 - x, y0 - y, x1 - x, y1 - y))
        return img, x0, y0

    def mask(self, row, frame=0):
        """Mặt nạ alpha đủ cỡ bản đồ của layer ở frame cho trước."""
        fr = row["frames"][frame]
        m = np.zeros((self.H, self.W), bool)
        if fr is None:
            return m
        c = self.clip(self.image(row, fr[0], fr[3]), fr[1], fr[2])
        if c is None:
            return m
        img, x, y = c
        a = np.asarray(img)[..., 3] > 0
        m[y:y + a.shape[0], x:x + a.shape[1]] = a
        return m


def alpha_mask(img):
    return np.asarray(img)[..., 3] > 0


def is_static(row):
    first = row["frames"][0]
    return first is not None and all(fr == first for fr in row["frames"])


def union_box(row, L):
    box = None
    for fr in row["frames"]:
        if fr is None:
            continue
        img = L.image(row, fr[0])
        b = (fr[1], fr[2], fr[1] + img.width, fr[2] + img.height)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def overlap_ratio(box, zone):
    """Tỉ lệ diện tích khung box nằm trong zone (x0,y0,x1,y1)."""
    w = max(0, min(box[2], zone[2]) - max(box[0], zone[0]))
    h = max(0, min(box[3], zone[3]) - max(box[1], zone[1]))
    area = max(1, (box[2] - box[0]) * (box[3] - box[1]))
    return w * h / area


def in_zones(box, zones):
    """Vật thuộc vùng dọn nếu ≥ 50% khung nằm trong vùng hoặc chân (giữa mép dưới) nằm trong vùng."""
    bx, by = (box[0] + box[2]) / 2, box[3] - 1
    return any(overlap_ratio(box, z) >= 0.5 or (z[0] <= bx < z[2] and z[1] <= by < z[3]) for z in zones)


def erase_zones(img, x, y, zones):
    """Xoá phần ảnh tĩnh (decor/above) nằm trong vùng dọn."""
    arr = None
    for z in zones:
        x0, y0 = max(z[0] - x, 0), max(z[1] - y, 0)
        x1, y1 = min(z[2] - x, img.width), min(z[3] - y, img.height)
        if x1 > x0 and y1 > y0:
            if arr is None:
                arr = np.asarray(img).copy()
            arr[y0:y1, x0:x1] = 0
    return img if arr is None else Image.fromarray(arr, "RGBA")


# ------------------------------------------------------------------ node: trạng thái + chuỗi frame dùng chung

class Seqs:
    """Bảng chuỗi 96 frame dùng chung (manifest "seqs"): node chỉ lưu chỉ số."""

    def __init__(self):
        self.table = []
        self.index = {}

    def add(self, seq):
        key = tuple(seq)
        if key not in self.index:
            self.index[key] = len(self.table)
            self.table.append(list(seq))
        return self.index[key]


def make_node(name, regions, entries, seqs, extra=None):
    """entries: 96 phần tử (ri, x, y) hoặc None → node {regions, states, seq, box}. Một trạng thái = tĩnh."""
    states = []
    sidx = {}
    seq = []
    for e in entries:
        if e is None:
            seq.append(-1)
            continue
        key = tuple(e)
        if key not in sidx:
            sidx[key] = len(states)
            states.append(list(e))
        seq.append(sidx[key])
    if not states:
        return None
    node = {"name": name, "regions": regions, "states": states}
    if len(states) == 1 and all(s == 0 for s in seq):
        node["seq"] = -1
    else:
        node["seq"] = seqs.add(seq)
    x0 = min(s[1] for s in states)
    y0 = min(s[2] for s in states)
    x1 = max(s[1] + regions[s[0]][3] for s in states)
    y1 = max(s[2] + regions[s[0]][4] for s in states)
    node["box"] = [x0, y0, x1, y1]
    if extra:
        node.update(extra)
    return node


def named_node(row, L, packer, seqs, add_fade=True):
    regions = []
    index = {}
    entries = []
    for fr in row["frames"]:
        if fr is None:
            entries.append(None)
            continue
        u, x, y, op = fr
        key = (u, op)
        if key not in index:
            index[key] = len(regions)
            regions.append(packer.add(L.image(row, u, op)))
        entries.append((index[key], x, y))
    node = make_node(row["name"], regions, entries, seqs)
    if node is None:
        return None
    if add_fade and node["seq"] >= 0:
        fade = fade_for(row, L)
        if fade is not None:
            node["fade"] = fade
            FADE_REPORT.append(row["name"])
    return node


def fade_for(row, L):
    """Vật chạy vòng của bản đồ cũ: biến mất ở mép phải cũ (x≈1280–1500) giữa bản đồ mới → khoảng mờ dần
    [x_bắt_đầu, x_hết] theo mép phải của ảnh."""
    vis = [fr for fr in row["frames"] if fr is not None]
    xs = [fr[1] for fr in vis]
    if max(xs) - min(xs) < 300:
        return None
    right = max(fr[1] + L.image(row, fr[0]).width for fr in vis)
    if right >= L.W - 16:
        return None
    return [right - 90, right - 10]


def split_node(row, L, packer, seqs, zones, dilate=1, sort_offset=None):
    """Layer lớn (cụm cây, tán cây, gợn nước…) → từng mảnh theo thành phần liên thông trên hợp mọi frame.
    Mỗi mảnh là node "<tên>#k" (part_of = tên layer). Mảnh nằm trong vùng dọn (zones) bị bỏ."""
    box = union_box(row, L)
    if box is None:
        return [], 0
    x0, y0, x1, y1 = box
    union = np.zeros((y1 - y0, x1 - x0), bool)
    entries = {}
    for fr in row["frames"]:
        if fr is None or fr in entries:
            continue
        img = L.image(row, fr[0], fr[3])
        entries[fr] = img
        m = alpha_mask(img)
        union[fr[2] - y0:fr[2] - y0 + m.shape[0], fr[1] - x0:fr[1] - x0 + m.shape[1]] |= m
    grown = ndimage.binary_dilation(union, iterations=dilate) if dilate > 0 else union
    lab, n = ndimage.label(grown, structure=np.ones((3, 3), bool))
    lab = np.where(union, lab, 0)
    parts = []
    dropped = 0
    arrays = {fr: np.asarray(img) for fr, img in entries.items()}
    for k, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        cx0, cy0 = x0 + sl[1].start, y0 + sl[0].start
        cw, ch = sl[1].stop - sl[1].start, sl[0].stop - sl[0].start
        pbox = (cx0, cy0, cx0 + cw, cy0 + ch)
        if cx0 >= L.W or cy0 >= L.H or pbox[2] <= 0 or pbox[3] <= 0:
            continue
        if in_zones(pbox, zones):
            dropped += 1
            continue
        comp = lab[sl] == k
        if cw * ch > 20000 and comp.sum() < 0.12 * cw * ch:
            # chuỗi gợn nước dính nhau qua nhiều trạng thái → khung rất thưa: tách theo từng trạng thái
            pieces = sparse_pieces(row, L, packer, seqs, arrays, comp, cx0, cy0, len(parts))
            parts.extend(pieces)
            continue
        regions = []
        index = {}
        per_fr = {}
        for fr, arr_src in arrays.items():
            cell = np.zeros((ch, cw, 4), np.uint8)
            # dán ảnh của frame vào ô của mảnh
            sx0, sy0 = fr[1] - cx0, fr[2] - cy0
            ax0, ay0 = max(sx0, 0), max(sy0, 0)
            ax1, ay1 = min(sx0 + arr_src.shape[1], cw), min(sy0 + arr_src.shape[0], ch)
            if ax1 > ax0 and ay1 > ay0:
                cell[ay0:ay1, ax0:ax1] = arr_src[ay0 - sy0:ay1 - sy0, ax0 - sx0:ax1 - sx0]
            cell[~comp] = 0
            a = cell[..., 3] > 0
            if not a.any():
                per_fr[fr] = None
                continue
            ys, xs = np.nonzero(a)
            bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
            crop = cell[by0:by1, bx0:bx1]
            key = crop.tobytes() + bytes(str(crop.shape), "ascii")
            if key not in index:
                index[key] = len(regions)
                regions.append(packer.add(Image.fromarray(crop.copy(), "RGBA")))
            per_fr[fr] = (index[key], int(cx0 + bx0), int(cy0 + by0))
        entries_seq = [None if fr is None else per_fr[fr] for fr in row["frames"]]
        node = make_node("%s#%d" % (row["name"], len(parts)), regions, entries_seq, seqs, {"part_of": row["name"]})
        if node is None:
            continue
        parts.append(node)
    return parts, dropped


def sparse_pieces(row, L, packer, seqs, arrays, comp, cx0, cy0, base_index):
    """Mảnh thưa: với mỗi trạng thái (frame duy nhất), các thành phần liên thông (nở 2 px) trong vùng comp
    thành node riêng chỉ hiện ở các frame của trạng thái đó."""
    ch, cw = comp.shape
    nodes = []
    for fr, arr_src in arrays.items():
        cell = np.zeros((ch, cw, 4), np.uint8)
        sx0, sy0 = fr[1] - cx0, fr[2] - cy0
        ax0, ay0 = max(sx0, 0), max(sy0, 0)
        ax1, ay1 = min(sx0 + arr_src.shape[1], cw), min(sy0 + arr_src.shape[0], ch)
        if ax1 <= ax0 or ay1 <= ay0:
            continue
        cell[ay0:ay1, ax0:ax1] = arr_src[ay0 - sy0:ay1 - sy0, ax0 - sx0:ax1 - sx0]
        cell[~comp] = 0
        mask = cell[..., 3] > 0
        if not mask.any():
            continue
        lab, n = ndimage.label(ndimage.binary_dilation(mask, iterations=2), structure=np.ones((3, 3), bool))
        lab = np.where(mask, lab, 0)
        for k, sl in enumerate(ndimage.find_objects(lab), start=1):
            if sl is None:
                continue
            sub = cell[sl].copy()
            sub[lab[sl] != k] = 0
            if not (sub[..., 3] > 0).any():
                continue
            ref = packer.add(Image.fromarray(sub, "RGBA"))
            entry = (0, int(cx0 + sl[1].start), int(cy0 + sl[0].start))
            entries = [entry if f == fr else None for f in row["frames"]]
            node = make_node("%s#%d" % (row["name"], base_index + len(nodes)), [ref], entries, seqs, {"part_of": row["name"]})
            if node is not None:
                nodes.append(node)
    return nodes


# ------------------------------------------------------------------ below / above

class Run:
    def __init__(self, W, H):
        self.canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.after = np.zeros((H, W), bool)   # mọi pixel được vẽ SAU đợt này
        self.layers = 0


def build_flat_role(rows, L, packer, seqs, role, report, zones, hidden, extras_static, extras_named):
    """Layer tĩnh gộp thành đợt (giữ đúng thứ tự vẽ) rồi cắt ô; layer động thành node có tên hoặc tách mảnh.
    extras_static: [(ảnh, x, y)] vẽ sau cùng (tĩnh); extras_named: node đã dựng sẵn (động) thêm sau cùng."""
    W, H = L.W, L.H
    order = []          # ("run", Run) | ("anim", row) | ("node", node)
    runs = []
    stats = {"runs": 0, "tiles": 0, "named": 0, "split": 0, "parts": 0, "dropped_in_zones": 0, "skipped": 0}

    def mark_after(mask, x, y, upto):
        h, w = mask.shape
        for r in runs[:upto]:
            r.after[y:y + h, x:x + w] |= mask

    def add_static(img, x, y):
        mask = alpha_mask(img)
        h, w = mask.shape
        target = None
        for i in range(len(runs) - 1, -1, -1):
            if runs[i].after[y:y + h, x:x + w][mask].any():
                break
            target = i
        if target is None:
            runs.append(Run(W, H))
            order.append(("run", runs[-1]))
            target = len(runs) - 1
        run = runs[target]
        run.canvas.alpha_composite(img, (x, y))
        run.layers += 1
        mark_after(mask, x, y, target)

    for row in rows:
        if layer_role(row) != role:
            continue
        if row["name"] in hidden:
            stats["skipped"] += 1
            continue
        box = union_box(row, L)
        zoned = row["top"] in ("02_Decor_Duoi", "04_Above")
        if box is not None and zones and zoned and in_zones(box, zones):
            stats["dropped_in_zones"] += 1
            continue
        if is_static(row):
            u, x, y, op = row["frames"][0]
            clipped = L.clip(L.image(row, u, op), x, y)
            if clipped is None:
                continue
            img, x, y = clipped
            if zoned and zones and not row["name"].startswith(("N_day_dien", "N_xa_dien")):
                # dây điện dọc phố giữ nguyên (cột ở mép đường, dây chạy trước mặt tiền là hợp lý)
                img = erase_zones(img, x, y, zones)
            add_static(img, x, y)
        else:
            order.append(("anim", row))
            seen = set()
            for fr in row["frames"]:
                if fr is None or (fr[0], fr[1], fr[2]) in seen:
                    continue
                seen.add((fr[0], fr[1], fr[2]))
                clipped = L.clip(L.image(row, fr[0]), fr[1], fr[2])
                if clipped is None:
                    continue
                img, x, y = clipped
                mark_after(alpha_mask(img), x, y, len(runs))
    for img, x, y in extras_static:
        clipped = L.clip(img, x, y)
        if clipped is not None:
            add_static(*clipped)
    nodes = []
    for kind, value in order:
        packer.tag = role + "_tiles"
        if kind == "run":
            tiles = []
            for ty in range(0, H, TILE):
                for tx in range(0, W, TILE):
                    quad_tiles(value.canvas, tx, ty, TILE, tiles)
            for img, x, y in tiles:
                nodes.append({"static": packer.add(img), "pos": [x, y]})
            stats["tiles"] += len(tiles)
            stats["runs"] += 1
            value.canvas = None
            value.after = None
        else:
            row = value
            box = union_box(row, L)
            if box is None:
                continue
            big = (box[2] - box[0]) > SPLIT_MIN and (box[3] - box[1]) > SPLIT_MIN
            if big and row["name"] not in REQUIRED_NAMES:
                packer.tag = role + "_split"
                parts, dropped = split_node(row, L, packer, seqs, zones, dilate=1 if role == "below" else 2)
                nodes.extend(parts)
                stats["split"] += 1
                stats["parts"] += len(parts)
                stats["dropped_in_zones"] += dropped
            else:
                packer.tag = role + "_named"
                node = named_node(row, L, packer, seqs)
                if node is not None:
                    nodes.append(node)
                    stats["named"] += 1
    nodes.extend(extras_named)
    report[role] = stats
    return nodes


def quad_tiles(canvas, x, y, size, out):
    W, H = canvas.size
    crop = canvas.crop((x, y, min(x + size, W), min(y + size, H)))
    bbox = crop.getbbox()
    if bbox is None:
        return
    part = crop.crop(bbox)
    area = part.width * part.height
    filled = int((np.asarray(part)[..., 3] > 0).sum())
    if size > MIN_TILE and filled < 0.4 * area:
        half = size // 2
        for dy in (0, half):
            for dx in (0, half):
                if x + dx < W and y + dy < H:
                    quad_tiles(canvas, x + dx, y + dy, half, out)
        return
    out.append((part, x + bbox[0], y + bbox[1]))


def layer_role(row):
    return ROLE_OVERRIDE.get(row["name"], GROUP_ROLE.get(row["top"]))


# ------------------------------------------------------------------ object

def split_candidate(row):
    return row["name"].startswith("N_cay_vat_") and row["gp"].endswith("NEW_VEGETATION")


def build_objects(rows, L, packer, seqs, report, zones, hidden, extra_nodes):
    nodes = []
    stats = {"nodes": 0, "split_layers": 0, "split_parts": 0, "dropped_in_zones": 0, "skipped": 0}
    for row in rows:
        if layer_role(row) != "object":
            continue
        if row["name"] in hidden:
            stats["skipped"] += 1
            continue
        packer.tag = "object_veg" if split_candidate(row) else "object_" + row["gp"].split("/")[-1]
        if split_candidate(row):
            parts, dropped = split_node(row, L, packer, seqs, zones, dilate=1)
            nodes.extend(parts)
            stats["split_layers"] += 1
            stats["split_parts"] += len(parts)
            stats["dropped_in_zones"] += dropped
            continue
        box = union_box(row, L)
        if box is None:
            continue
        if zones and in_zones(box, zones):
            stats["dropped_in_zones"] += 1
            continue
        node = named_node(row, L, packer, seqs)
        if node is None:
            continue
        if row["name"] in SORT_Y:
            node["sort_y"] = SORT_Y[row["name"]]
        nodes.append(node)
    nodes.extend(extra_nodes)
    stats["nodes"] = len(nodes)
    report["object"] = stats
    return nodes


# ------------------------------------------------------------------ trùng lặp

def find_duplicates(rows, L):
    """Layer trùng hệt layer khác (cùng vai trò, cùng frame, cùng ảnh) → bỏ bản sau.
    Băm mỗi ảnh duy nhất của layer một lần (đọc thẳng file PNG đã xuất)."""
    seen = {}
    dups = {}
    for row in rows:
        role = layer_role(row)
        if role is None:
            continue
        hashes = {}
        sig = [role]
        for fr in row["frames"]:
            if fr is None:
                sig.append(None)
                continue
            if fr[0] not in hashes:
                with open(os.path.join(L.src, "L%04d_%02d.png" % (row["idx"], fr[0])), "rb") as f:
                    hashes[fr[0]] = hashlib.md5(f.read()).hexdigest()
            sig.append((fr[1], fr[2], fr[3], hashes[fr[0]]))
        key = hashlib.md5(repr(sig).encode()).hexdigest()
        if key in seen:
            dups[row["name"]] = seen[key]
        else:
            seen[key] = row["name"]
    return dups


# ------------------------------------------------------------------ va chạm, lưới đi, kiểm tra

def raw_collision(src, W, H):
    mask = np.zeros((H, W), bool)
    names = []
    with open(os.path.join(src, "coll.tsv"), encoding="utf8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5 or parts[3] == "-1":
                continue
            idx, x, y = int(parts[0]), int(parts[3]), int(parts[4])
            a = np.asarray(Image.open(os.path.join(src, "coll", "C%02d.png" % idx)).convert("RGBA"))[..., 3] > 0
            h, w = a.shape
            xa, ya = max(x, 0), max(y, 0)
            xb, yb = min(x + w, W), min(y + h, H)
            mask[ya:yb, xa:xb] |= a[ya - y:yb - y, xa - x:xb - x]
            names.append(parts[2])
    return mask, names


def rect_mask(mask, rect, value):
    x, y, w, h = rect
    mask[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)] = value


def foot_blocked(blocked, half):
    """Đúng như WorldPlayer._blocked_at: chân (x, y) bị chặn nếu một trong các điểm
    x ∈ {x−half, x−2, x, x+2, x+half−1} × y ∈ {y−5, y−3, y−1} bị chặn (hoặc ngoài bản đồ)."""
    H, W = blocked.shape
    pad = 12
    big = np.ones((H + 2 * pad, W + 2 * pad), bool)
    big[pad:pad + H, pad:pad + W] = blocked
    out = np.zeros((H, W), bool)
    for dy in (-5, -3, -1):
        for dx in (-half, -2, 0, 2, half - 1):
            out |= big[pad + dy:pad + dy + H, pad + dx:pad + dx + W]
    return out


def foot_blocked_dense(blocked, half):
    """Như trên nhưng xét mọi pixel trong khung chân (dò khe hở 1 px mà cách lấy mẫu thưa của player lọt qua)."""
    H, W = blocked.shape
    pad = 12
    big = np.ones((H + 2 * pad, W + 2 * pad), bool)
    big[pad:pad + H, pad:pad + W] = blocked
    out = np.zeros((H, W), bool)
    for dy in range(-5, 0):
        for dx in range(-half, half):
            out |= big[pad + dy:pad + dy + H, pad + dx:pad + dx + W]
    return out


def reach_from(free, start):
    lab, n = ndimage.label(free)
    k = lab[start[1], start[0]]
    if k == 0:
        return np.zeros_like(free)
    return lab == k


def import_as_image(path):
    """Ghi file .import để Godot nhập PNG thành Image (đọc CPU, không tạo texture GPU)."""
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    text = ('[remap]\n\nimporter="image"\ntype="Image"\nuid="%s"\npath="res://.godot/imported/%s-%s.image"\n\n'
            '[deps]\n\nsource_file="res://%s"\ndest_files=["res://.godot/imported/%s-%s.image"]\n\n[params]\n\n')
    old_uid = None
    imp = path + ".import"
    if os.path.exists(imp):
        with open(imp, encoding="utf8") as f:
            for line in f:
                if line.startswith("uid="):
                    old_uid = line.strip()[5:-1]
    h = hashlib.md5(("res://" + rel).encode()).hexdigest()
    uid = old_uid or "uid://" + base36(int(h[:15], 16))
    base = os.path.basename(path)
    with open(imp, "w", encoding="utf8", newline="\n") as f:
        f.write(text % (uid, base, h, rel, base, h))


def base36(n):
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    s = ""
    while n:
        n, r = divmod(n, 36)
        s = chars[r] + s
    return s or "0"


ROOT = ROOT_DEFAULT


# ------------------------------------------------------------------ chính

def finalize(nodes):
    """Đổi ref (list sẽ được điền khi pack) – không cần làm gì vì ref là list dùng chung; giữ cho rõ ý."""
    return nodes


def main():
    global ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("--aseprite", default=ASEPRITE_DEFAULT)
    ap.add_argument("--art", default=ART_DEFAULT)
    ap.add_argument("--export-dir", default=os.path.join(tempfile.gettempdir(), "chick_world_export"))
    ap.add_argument("--skip-export", action="store_true")
    ap.add_argument("--project", default=ROOT_DEFAULT)
    ap.add_argument("--audit-dir", default=None)
    args = ap.parse_args()
    ROOT = os.path.abspath(args.project)
    audit_dir = args.audit_dir or os.path.join(args.export_dir, "audit")
    os.makedirs(audit_dir, exist_ok=True)
    t0 = time.time()
    if not args.skip_export:
        export(args.aseprite, args.art, args.export_dir)
    rows, (W, H, count, ms) = read_rows(args.export_dir)
    log("layers: %d, size %dx%d, %d frame × %d ms" % (len(rows), W, H, count, ms))
    L = Layers(args.export_dir, (W, H))
    by_name = {r["name"]: r for r in rows}
    dups = find_duplicates(rows, L)
    log("trùng lặp (bỏ bản sau): %s" % dups)
    raw, coll_names = raw_collision(args.export_dir, W, H)
    log("05_Collision: %s, chặn=%d px" % (coll_names, int(raw.sum())))

    packer = Packer()
    seqs = Seqs()
    SEQS_TABLE[0] = seqs.table
    traffic = {r["name"] for r in rows if world_map_traffic.is_traffic(r)}
    log("giao thông tách khỏi bản đồ: %d layer" % len(traffic))
    ctx = world_map_extras.Context(rows, by_name, L, raw, packer, seqs, make_node, args.export_dir)
    ctx.hidden = set(dups) | traffic
    packer.tag = "extras"
    extra = world_map_extras.build(ctx)
    hidden = set(dups) | set(extra.hide) | traffic
    zones = extra.clear_zones
    report = {}
    below = build_flat_role(rows, L, packer, seqs, "below", report, zones, hidden, extra.below_static, extra.below_nodes)
    log("below: %s (%.1fs)" % (report["below"], time.time() - t0))
    objects = build_objects(rows, L, packer, seqs, report, zones, hidden, extra.object_nodes)
    log("object: %s (%.1fs)" % (report["object"], time.time() - t0))
    above = build_flat_role(rows, L, packer, seqs, "above", report, zones, hidden, extra.above_static, extra.above_nodes)
    log("above: %s (%.1fs)" % (report["above"], time.time() - t0))
    log("fade (vật chạy vòng bản đồ cũ): %s" % FADE_REPORT)

    out = os.path.join(ROOT, OUT_REL)
    os.makedirs(out, exist_ok=True)
    tmp_out = os.path.join(args.export_dir, "_atlas")
    os.makedirs(tmp_out, exist_ok=True)
    for name in os.listdir(tmp_out):
        os.remove(os.path.join(tmp_out, name))
    log("atlas: %d ảnh, %.1f MP" % (len(packer.items), packer.area() / 1e6))
    for tag, area in sorted(packer.area_by_tag.items(), key=lambda t: -t[1]):
        log("   %-28s %.2f MP" % (tag, area / 1e6))
    atlases, sizes = packer.pack(tmp_out, "world_atlas")
    names = {n.get("name") for n in below + objects + above if n.get("name")}
    missing = [n for n in REQUIRED_NAMES if n not in names]
    if missing:
        raise SystemExit("THIẾU node có tên mà code cần: %s" % missing)
    leftover = sorted(n for n in names if n in traffic or n in FORBIDDEN_NAMES)
    if leftover:
        raise SystemExit("CÒN node giao thông / nội dung cũ trong bản đồ: %s" % leftover)

    # Ghi ra dự án: xoá trang atlas thừa của lần dựng trước (kèm .import), giữ .uid.
    for name in os.listdir(out):
        base = name[:-7] if name.endswith(".import") else name
        if base.startswith("world_atlas_") and base.endswith(".png") and base not in atlases:
            os.remove(os.path.join(out, name))
    for name in atlases:
        shutil.move(os.path.join(tmp_out, name), os.path.join(out, name))
    manifest = {"version": 3, "frame_ms": ms, "frame_count": count, "size": [W, H],
                "atlases": atlases, "seqs": seqs.table, "below": below, "object": objects, "above": above}
    with open(os.path.join(out, "world_layers.json"), "w", encoding="utf8") as f:
        json.dump(manifest, f, separators=(",", ":"), ensure_ascii=False)
    vram = sum(w * h * 4 for w, h in sizes)
    log("VRAM atlas ≈ %.1f MB (%d trang: %s)" % (vram / 1e6, len(sizes), sizes))

    # ---- va chạm
    blocked = raw.copy()
    for name in OPEN_LAYERS:
        row = by_name.get(name)
        if row is None:
            log("  CẢNH BÁO: không có layer mở lối %s" % name)
            continue
        blocked &= ~ndimage.binary_fill_holes(L.mask(row))
    for rect in OPEN_RECTS:
        rect_mask(blocked, rect, False)
    for rect in EXTRA_BLOCKERS:
        rect_mask(blocked, rect, True)
    for zone in zones:
        x0, y0, x1, y1 = zone
        blocked[y0:y1, x0:x1] &= ~extra.zone_unblock[y0:y1, x0:x1]
    blocked |= extra.block_mask
    blocked &= ~extra.open_mask
    Image.fromarray(np.where(blocked, 255, 0).astype(np.uint8), "L").save(os.path.join(out, "collision.png"), optimize=True)
    import_as_image(os.path.join(out, "collision.png"))
    log("collision: chặn=%d px" % int(blocked.sum()))

    # ---- lưới đi 4 px (route bản đồ, test), ảnh nhỏ, kiểm tra đi bộ
    road = extra.road_mask
    foot = ~foot_blocked(blocked, FOOT_HALF)
    bike = ~foot_blocked(blocked, FOOT_HALF + BIKE_EXTRA)
    spawn = world_map_extras.SPAWN
    reach = reach_from(foot, spawn)
    reach_bike = reach_from(bike, world_map_extras.BIKE_START)
    c = NAV_CELL // 2
    nav = np.zeros((H // NAV_CELL, W // NAV_CELL), np.uint8)
    nav |= (foot[c::NAV_CELL, c::NAV_CELL]).astype(np.uint8)
    nav |= (bike[c::NAV_CELL, c::NAV_CELL]).astype(np.uint8) << 1
    road_cells = ndimage.maximum_filter(road, size=NAV_CELL)[c::NAV_CELL, c::NAV_CELL]
    nav |= road_cells.astype(np.uint8) << 2
    water = world_map_extras.water_mask(ctx)
    nav |= (ndimage.maximum_filter(water, size=NAV_CELL)[c::NAV_CELL, c::NAV_CELL]).astype(np.uint8) << 3
    nav |= (reach[c::NAV_CELL, c::NAV_CELL]).astype(np.uint8) << 4
    Image.fromarray(nav, "L").save(os.path.join(out, "nav.png"), optimize=True)
    import_as_image(os.path.join(out, "nav.png"))
    log("nav: %dx%d, đi bộ=%d ô (tới được %d), xe=%d ô" % (nav.shape[1], nav.shape[0], int((nav & 1).sum()),
                                                          int((nav & 16).sum() // 16), int((nav & 2).sum() // 2)))

    preview = compose_frame0(packer, below, objects, above, (W, H))
    preview.save(os.path.join(audit_dir, "frame0.png"))
    preview.convert("RGB").resize((W // 4, H // 4), Image.BOX).save(os.path.join(out, "minimap.png"), optimize=True)
    lanes = world_map_extras.build_lanes(blocked, extra.info, os.path.join(out, "market_lanes.json"))
    log("market lanes: %d điểm, %d nối, %d chỗ xem hàng" % (len(lanes["nodes"]), len(lanes["links"]), len(lanes["browse"])))
    shoppers = os.path.join(args.export_dir, "_extras", "shoppers.png")
    Image.open(shoppers).save(os.path.join(out, "shoppers.png"), optimize=True)
    with open(os.path.join(out, "world_map_info.json"), "w", encoding="utf8") as f:
        json.dump(extra.info, f, ensure_ascii=False, indent=1)
    audit(blocked, foot, reach, bike, reach_bike, road, preview, extra, audit_dir, spawn)
    # ---- giao thông + người đứng (dữ liệu cho hệ thống giao thông / người đi bộ lúc chạy)
    tdata, nav_water, roads = world_map_traffic.build(rows, by_name, L, out, ms, foot, reach, blocked, raw, import_as_image)
    world_map_traffic.build_people(rows, L, out, hidden, ms)
    # sửa lỗi sau dựng: nước dưới mọi cầu + rạch bị lá dừa che, vỏ lãi bốc đầu ngồi trên mặt nước, ông câu cá quay mặt ra
    # nước, vỏ lãi người chơi nhìn dọc (tools/art/world_map_fixes.py)
    world_map_fixes.apply(out, log)
    traffic_audit(tdata, nav_water, roads, preview, audit_dir)
    total = sum(os.path.getsize(os.path.join(out, n)) for n in os.listdir(out))
    log("%s: %.1f MB trên đĩa, atlas=%d, below=%d object=%d above=%d, %.1fs" % (
        OUT_REL, total / 1e6, len(atlases), len(below), len(objects), len(above), time.time() - t0))


def compose_frame0(packer, below, objects, above, size):
    """Ảnh frame 0 đúng như MapView vẽ (below → object Y-sort theo đáy/sort_y → above) – để kiểm tra và làm minimap."""
    W, H = size
    img_of = {id(ref): img for img, ref in packer.items}
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))

    def entry(node, frame=0):
        if node["seq"] < 0:
            return node["states"][0]
        return None

    def draw(node, seqs_table):
        if "static" in node:
            canvas.alpha_composite(img_of[id(node["static"])], tuple(node["pos"]))
            return
        st = node["states"][0] if node["seq"] < 0 else (
            None if seqs_table[node["seq"]][0] < 0 else node["states"][seqs_table[node["seq"]][0]])
        if st is None:
            return
        img = img_of[id(node["regions"][st[0]])]
        x, y = st[1], st[2]
        if x < W and y < H and x + img.width > 0 and y + img.height > 0:
            canvas.alpha_composite(img, (max(x, 0), max(y, 0)),
                                   (max(-x, 0), max(-y, 0)))

    seqs_table = SEQS_TABLE[0]
    for n in below:
        draw(n, seqs_table)

    def sort_key(n):
        if "sort_y" in n:
            return n["sort_y"]
        if n["seq"] < 0:
            st = n["states"][0]
        else:
            k = seqs_table[n["seq"]][0]
            st = n["states"][k] if k >= 0 else n["states"][0]
        return st[2] + n["regions"][st[0]][4]
    for n in sorted(objects, key=sort_key):
        draw(n, seqs_table)
    for n in above:
        draw(n, seqs_table)
    return canvas


SEQS_TABLE = [None]


def traffic_audit(tdata, water, roads, preview, audit_dir):
    """Ảnh kiểm tra: đường đi (màu theo đường) + nước thuyền chạy được (xanh) + mặt đường (vàng) trên bản đồ thu nhỏ ½,
    và số điểm đường lệch khỏi mặt đường/nước (> 4 px)."""
    from PIL import ImageDraw
    base = np.asarray(preview.convert("RGB")).astype(np.float32)
    base[water] = base[water] * 0.4 + np.array([0, 120, 255]) * 0.6
    base[roads] = base[roads] * 0.6 + np.array([255, 220, 0]) * 0.4
    img = Image.fromarray(base.astype(np.uint8)).resize((base.shape[1] // 2, base.shape[0] // 2), Image.BOX)
    d = ImageDraw.Draw(img)
    cols = [(255, 0, 0), (255, 0, 255), (0, 255, 255), (255, 128, 0), (0, 255, 0), (255, 255, 255), (128, 0, 255)]
    bridges = [b["rect"] for b in tdata["bridges"]]
    lines = []
    for k, r in enumerate(tdata["routes"]):
        pts = [(x / 2, y / 2) for x, y in r["points"]]
        d.line(pts, fill=cols[k % len(cols)], width=2)
        d.text((pts[0][0] + 4, pts[0][1] - 12), r["id"], fill=cols[k % len(cols)])
        mask = roads if r["kind"] == "bike" else water
        off, under, bad = 0, 0, []
        for x, y in world_map_traffic.densify(r["points"], 4):
            xi, yi = int(round(x)), int(round(y))
            if not (0 <= xi < mask.shape[1] and 0 <= yi < mask.shape[0]):
                continue  # ngoài mép bản đồ (xe vào/ra)
            if mask[max(yi - 4, 0):yi + 5, max(xi - 4, 0):xi + 5].any():
                continue
            if any(bx - 4 <= xi < bx + bw + 4 and by - 4 <= yi < by + bh + 4 for bx, by, bw, bh in bridges):
                under += 1
                continue
            off += 1
            if off <= 3:
                bad.append("(%d,%d)" % (xi, yi))
        lines.append("%-28s %4d điểm, dài %6.0f px, lệch khỏi %s (>4 px): %d mẫu, dưới cầu: %d" % (
            r["id"], len(r["points"]), r["length_px"], "đường" if r["kind"] == "bike" else "nước", off, under) + " " + " ".join(bad))
    for dk in tdata["docks"]:
        x, y = dk["pos"]
        wx, wy = dk["water_pos"]
        d.ellipse((x / 2 - 4, y / 2 - 4, x / 2 + 4, y / 2 + 4), outline=(255, 255, 255), width=2)
        d.line((x / 2, y / 2, wx / 2, wy / 2), fill=(255, 255, 255), width=2)
        d.text((x / 2 + 5, y / 2), dk["id"], fill=(255, 255, 255))
    img.save(os.path.join(audit_dir, "traffic_routes.png"))
    with open(os.path.join(audit_dir, "traffic_audit.txt"), "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")
    for line in lines:
        log("  " + line)


def audit(blocked, foot, reach, bike, reach_bike, road, preview, extra, audit_dir, spawn):
    """Kiểm tra đi bộ: vùng đi được nhưng không tới được từ SPAWN, mặt đường không tới được, khe hở 1 px."""
    H, W = blocked.shape
    lines = []
    dense = ~foot_blocked_dense(blocked, FOOT_HALF)
    reach_dense = reach_from(dense, spawn)
    leak = reach & ~ndimage.binary_dilation(reach_dense, iterations=2)
    lab, n = ndimage.label(leak)
    sizes = ndimage.sum(leak, lab, range(1, n + 1)) if n else []
    leaks = [(int(s), sl) for s, sl in zip(sizes, ndimage.find_objects(lab)) if s >= 6]
    lines.append("Khe hở (đi lọt nhờ lấy mẫu thưa, không lọt nếu xét đủ khung chân): %d vùng" % len(leaks))
    for s, sl in sorted(leaks, key=lambda t: -t[0])[:30]:
        lines.append("  leak %d px tại x=%d..%d y=%d..%d" % (s, sl[1].start, sl[1].stop, sl[0].start, sl[0].stop))
    # vùng đi được lớn nhưng không nối với SPAWN
    lab, n = ndimage.label(foot & ~reach)
    sizes = ndimage.sum(foot & ~reach, lab, range(1, n + 1)) if n else []
    islands = [(int(s), sl) for s, sl in zip(sizes, ndimage.find_objects(lab)) if s >= 400]
    lines.append("Vùng đi được nhưng không tới được từ SPAWN (≥400 px): %d" % len(islands))
    for s, sl in sorted(islands, key=lambda t: -t[0])[:40]:
        lines.append("  island %d px tại x=%d..%d y=%d..%d" % (s, sl[1].start, sl[1].stop, sl[0].start, sl[0].stop))
    road_unreach = road & foot & ~reach
    lines.append("Mặt đường đi được nhưng không tới được: %d px" % int(road_unreach.sum()))
    road_blocked = road & ~foot
    lines.append("Mặt đường bị chặn (chân không đứng được): %d px" % int(road_blocked.sum()))
    lines.append("Tới được bằng chân: %d px; bằng xe: %d px" % (int(reach.sum()), int(reach_bike.sum())))
    for pid, p in extra.info.get("check_points", {}).items():
        x, y = p
        lines.append("  điểm %-22s (%4d,%4d): chân=%s xe=%s" % (pid, x, y, bool(reach[y, x]), bool(reach_bike[y, x])))
    with open(os.path.join(audit_dir, "walk_audit.txt"), "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")
    for line in lines[:12]:
        log(line)
    # ảnh: nền + chặn (đỏ) + tới được bằng chân (xanh lá) + không tới (vàng) + khe (tím)
    base = np.asarray(preview.convert("RGB")).astype(np.float32)
    col = base.copy()
    def tint(m, rgb, k):
        col[m] = col[m] * (1 - k) + np.array(rgb, np.float32) * k
    tint(blocked, (255, 0, 0), 0.45)
    tint(reach & ~blocked, (0, 255, 80), 0.18)
    tint(foot & ~reach & ~blocked, (255, 230, 0), 0.6)
    tint(ndimage.binary_dilation(leak, iterations=3), (200, 0, 255), 0.9)
    img = Image.fromarray(col.astype(np.uint8), "RGB")
    for i, (x0, y0) in enumerate([(0, 0), (2560, 0), (0, 1080), (2560, 1080)]):
        img.crop((x0, y0, x0 + 2560, y0 + 1080)).resize((1280, 540), Image.BOX).save(
            os.path.join(audit_dir, "walk_q%d.png" % i))
    img.save(os.path.join(audit_dir, "walk_full.png"))


if __name__ == "__main__":
    main()
