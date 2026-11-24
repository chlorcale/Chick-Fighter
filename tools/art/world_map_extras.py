# -*- coding: utf-8 -*-
"""Nội dung thêm vào bản đồ thế giới lúc dựng (build_world_map.py gọi build(ctx)).

- Chợ Bình Kê đông đúc: thêm sạp (ghép từ sạp + mái che có sẵn trong tranh), 4 sạp riêng (gà, trứng, gạo cám,
  đồ nghề) đặt vào chỗ trống còn lại của chợ, người đứng mua (NPC có sẵn, đổi màu áo), thúng/sọt/bao hàng, ghe xuồng
  cập kè chợ nổi.
- Xe khô gà lá chanh của Lão Gà Khô: dùng layer của chủ dự án (N_lao_ga_kho_xe_kho_ga_la_chanh, chợ, 8 khung × 80 ms) –
  chỉ thêm va chạm gốc xe + điểm tương tác "cat_shop" trước xe (id giữ nguyên).
- Sân gà Liên tỉnh + Sân gà Olympia: dùng hai sân chủ dự án vẽ (03_Object/NEW_ARENA…) – chặn cổng (người chơi dừng ở
  cổng, không vào trong sới) + điểm tương tác "arena_lien_tinh"/"arena_olympic" ở cổng.
- Bảng chỉ đường ở các ngã ba chính.
- Tấm người đi chợ (shoppers.png) + mạng lối đi trong chợ (market_lanes.json) cho game/world/market_crowd.gd.
Mọi toạ độ là pixel bản đồ 5120×2160 (bản đồ cũ 1280×1080 nằm nguyên ở góc trên-trái).
"""
from __future__ import annotations

import json
import math
import os
import random

import numpy as np
from PIL import Image
from scipy import ndimage

import world_map_pixel as px

SPAWN = (131, 206)
BIKE_START = (186, 214)
OUT_REL = os.path.join("game", "art", "world_map")

# ------------------------------------------------------------------ vị trí (đã chọn trên ảnh bản đồ)

## Xe khô gà của chủ dự án (layer trong 03_Object/NEW_MARKET) – node bản đồ có tên này (world.gd: LAO_NODE).
LAO_LAYER = "N_lao_ga_kho_xe_kho_ga_la_chanh"
## Chỗ đứng mua khô gà: phía trước-trái xe (ngay trước xe là mái sạp N_cho_sap__17 che mất người).
LAO_STAND = (2968, 1044)
## Hai sân của chủ dự án: layer biển tên trên cổng → khoảng cổng; chặn ngưỡng cổng (không vào sới), chỗ đứng ở cổng.
## "interior": khối chặn đặc bên trong tường rào (x, y, w, h) – vách hai bên khán đài chỉ dày 1–2 px, có khe lọt.
ARENAS = {
    "arena_lien_tinh": {"sign": "N_san_lien_tinh_cong_bang_ten", "block_h": 24, "stand": (4508, 1080),
                        "interior": (4316, 850, 356, 216)},
    "arena_olympic": {"sign": "N_san_olympia_cong_bang_ten", "block_h": 30, "stand": (4938, 1413),
                      "interior": (4771, 1150, 337, 220)},
}
## Sạp riêng (góc trên-trái ảnh 56×50 → đáy +50): chỗ trống đông bắc cũ giờ là xe khô gà của chủ dự án → chia ra
## các khoảng trống còn lại của sân chợ phía đông (vị trí ưu tiên; build dò chỗ trống gần nhất, không đè vật của tranh).
SPECIAL_STALLS = {
    "market_chicken": (3098, 921),
    "market_eggs": (3098, 996),
    "market_food": (2784, 940),
    "market_gear": (2800, 1120),
}
## Sạp chép thêm: (x, y) góc trên-trái của sạp (48×44, như N_cho_sap) + layer nguồn.
## (Các chỗ (2904, 1052), (2784, 948), (2816, 1146) nhường cho sạp riêng; (2904, 1052) giờ là lối trước xe khô gà.)
EXTRA_STALLS = [
    (2178, 949, "N_cho_sap__03"), (2178, 1037, "N_cho_sap__06"), (2178, 1123, "N_cho_sap__10"),
]
## Bảng chỉ đường: (id, x, y gốc cột) – đặt trên cỏ sát mép đường ở các ngã ba chính.
SIGNPOSTS = [
    ("sign_village", 1296, 186),     # đầu đường làng phía bắc, nơi bản đồ cũ nối sang khu mới
    ("sign_south_road", 1300, 552),  # đường dừa bờ nam nối sang khu mới
    ("sign_market_nw", 1986, 794),   # góc tây bắc chợ Bình Kê
    ("sign_market_se", 3186, 1246),  # góc đông nam chợ
    ("sign_bridge", 3648, 540),      # đầu cầu bê tông qua sông chính (bờ nam)
    ("sign_east", 4272, 1064),       # ngã tư phía đông (bãi cỏ góc tây nam Sân gà Liên tỉnh) – hướng hai sân gà
    ("sign_thpt", 3975, 345),        # đường trường THPT
]


class Context:
    def __init__(self, rows, by_name, L, raw, packer, seqs, make_node, export_dir):
        self.rows = rows
        self.by_name = by_name
        self.L = L
        self.raw = raw
        self.packer = packer
        self.seqs = seqs
        self.make_node = make_node
        self.export_dir = export_dir
        self.W, self.H = L.W, L.H

    def frame(self, name, fi=0):
        row = self.by_name[name]
        fr = row["frames"][fi]
        if fr is None:
            return None
        return self.L.image(row, fr[0], fr[3]), fr[1], fr[2]

    def unique(self, name):
        """→ (danh sách ảnh duy nhất theo thứ tự xuất hiện, chuỗi 96 chỉ số (−1 = ẩn), vị trí từng frame)."""
        row = self.by_name[name]
        imgs, index, seq, pos = [], {}, [], []
        for fr in row["frames"]:
            if fr is None:
                seq.append(-1)
                pos.append(None)
                continue
            key = (fr[0], fr[3])
            if key not in index:
                index[key] = len(imgs)
                imgs.append(self.L.image(row, fr[0], fr[3]))
            seq.append(index[key])
            pos.append((fr[1], fr[2]))
        return imgs, seq, pos

    def components(self, name, area, min_px=12):
        """Thành phần liên thông (frame 0) của layer nằm trong vùng area → [(ảnh, x, y)]."""
        got = self.frame(name)
        if got is None:
            return []
        img, x, y = got
        arr = np.asarray(img)
        lab, n = ndimage.label(arr[..., 3] > 0, structure=np.ones((3, 3), bool))
        out = []
        for k, sl in enumerate(ndimage.find_objects(lab), start=1):
            if sl is None:
                continue
            bx0, by0 = x + sl[1].start, y + sl[0].start
            bx1, by1 = x + sl[1].stop, y + sl[0].stop
            if bx0 < area[0] or by0 < area[1] or bx1 > area[2] or by1 > area[3]:
                continue
            sub = arr[sl].copy()
            sub[lab[sl] != k] = 0
            if (sub[..., 3] > 0).sum() < min_px:
                continue
            out.append((Image.fromarray(sub, "RGBA"), bx0, by0))
        return out


class Extra:
    def __init__(self, W, H):
        self.hide = set()
        self.clear_zones = []
        self.below_static = []
        self.below_nodes = []
        self.object_nodes = []
        self.above_static = []
        self.above_nodes = []
        self.block_mask = np.zeros((H, W), bool)
        self.open_mask = np.zeros((H, W), bool)
        self.zone_unblock = np.zeros((H, W), bool)
        self.road_mask = np.zeros((H, W), bool)
        self.info = {"places": {}, "doors": {}, "signposts": {}, "check_points": {}, "stalls": {}, "npcs": {}}


# ------------------------------------------------------------------ node

def add_node(ctx, ex, name, frames, seq, pos, role="object", sort_y=None):
    """frames: ảnh (PIL/numpy) duy nhất; seq: 96 chỉ số (−1 = ẩn) hoặc None (tĩnh, ảnh 0);
    pos: (x, y) cố định hoặc danh sách 96 (x, y)."""
    regions = []
    for f in frames:
        img = f if isinstance(f, Image.Image) else px.to_img(f)
        regions.append(ctx.packer.add(img))
    if seq is None:
        seq = [0] * 96
    entries = []
    for i, s in enumerate(seq):
        if s < 0:
            entries.append(None)
            continue
        p = pos[i] if isinstance(pos, list) else pos
        entries.append((s, int(p[0]), int(p[1])))
    extra = {"sort_y": float(sort_y)} if sort_y is not None else None
    node = ctx.make_node(name, regions, entries, ctx.seqs, extra)
    {"object": ex.object_nodes, "below": ex.below_nodes, "above": ex.above_nodes}[role].append(node)
    return node


def shifted(seq, k):
    return seq[k:] + seq[:k]


def block_rect(ex, x, y, w, h):
    ex.block_mask[max(y, 0):y + h, max(x, 0):x + w] = True


def block_alpha(ex, arr, x, y, top_skip=0):
    a = (arr[..., 3] > 0)
    a[:top_skip] = False
    h, w = a.shape
    ex.block_mask[y:y + h, x:x + w] |= a


# ------------------------------------------------------------------ NPC tái dùng

NPC_POOL = [
    "N_npc_di_cho", "N_npc_di_cho_02", "N_npc_di_cho_03", "N_npc_di_cho_04", "N_npc_di_cho_05",
    "N_npc_di_cho_06", "N_npc_di_cho_07", "N_npc_di_cho_08", "N_npc_di_cho_09", "N_npc_di_cho_10",
    "N_npc_di_cho_11", "N_npc_di_cho_12", "N_npc_di_cho_13", "N_npc_di_cho_15", "N_npc_di_cho_16",
    "N_npc_di_cho_18", "N_npc_di_cho_19", "N_npc_di_cho_20", "N_npc_pho_bac", "N_npc_pho_bac_03",
    "N_npc_pho_bac_05", "N_npc_pho_bac_07", "N_npc_pho_bac_08", "N_npc_pho_bac_11", "N_npc_dan_hem",
    "N_npc_dan_cu_moi", "N_npc_dan_cu_moi_03", "N_npc_dan_cu_moi_05", "N_npc_pho_dich_vu_02",
    "N_npc_ben_cho_02", "N_npc_an_sang_02",
]


def npc_images(ctx, name):
    imgs, seq, pos = ctx.unique(name)
    return [px.from_img(i) for i in imgs], seq


def recolor_npc(arr, deg, top=0.38):
    """Đổi màu áo/quần (phần dưới tỉ lệ top của ảnh) cho đa dạng; giữ đầu/da."""
    h = arr.shape[0]
    mask = np.zeros(arr.shape[:2], bool)
    mask[int(h * top):] = True
    return px.hue_shift(arr, deg, mask)


# ------------------------------------------------------------------ chính

def build(ctx):
    global NPC_POOL
    NPC_POOL = [n for n in NPC_POOL if n in ctx.by_name]
    ex = Extra(ctx.W, ctx.H)
    rng = random.Random(20261117)
    _roads(ctx, ex)
    _owner_cart(ctx, ex)
    _owner_arenas(ctx, ex)
    _market(ctx, ex, rng)
    _quay(ctx, ex, rng)
    _signposts(ctx, ex)
    _shoppers(ctx, ex, rng)
    _thpt_and_npcs(ctx, ex)
    # Sửa tranh: khạp nước (thành phần của N_cay_vat_X2_Y1) nằm lơ lửng giữa sông cạnh nhà sàn x≈1590 → bỏ.
    ex.clear_zones.append((1578, 539, 1603, 565))
    # vùng dọn: bỏ va chạm cũ (nhà/cây/NPC đã ẩn) nhưng giữ nước
    water = ctx.raw & _water_mask(ctx)
    for z in ex.clear_zones:
        x0, y0, x1, y1 = z
        ex.zone_unblock[y0:y1, x0:x1] = True
    ex.zone_unblock &= ~water
    return ex


def water_mask(ctx):
    """Mặt nước (không nở) – sông, kênh, ao."""
    m = np.zeros((ctx.H, ctx.W), bool)
    for name in ("N_song_kenh_nen", "song_rach_nen", "ao_ca_tra", "ao_lang"):
        if name in ctx.by_name:
            m |= ctx.L.mask(ctx.by_name[name])
    return m & ctx.raw


def _water_mask(ctx):
    m = np.zeros((ctx.H, ctx.W), bool)
    for name in ("N_song_kenh_nen", "song_rach_nen", "ao_ca_tra", "ao_lang"):
        if name in ctx.by_name:
            m |= ctx.L.mask(ctx.by_name[name])
    return ndimage.binary_dilation(m, iterations=2)


def _roads(ctx, ex):
    for name in ("N_duong_be_tong", "N_duong_dat", "N_via_he", "N_san_cho_xi_mang", "N_ke_ben_cho",
                 "duong_lang_noi_dai_B", "duong_dua_be_tong", "duong_doc_F", "duong_dat_ra_ruong",
                 "D_cau_xi_mang_mat", "N_cau_pho_chinh_kenh_xang", "N_cau_T3_kenh_xang", "N_cau_T3_rach_vuon",
                 "N_cau_pho_chinh_rach_nho", "N_cau_T3_rach_nho", "N_cau_S8_rach_nho", "N_cau_be_tong_song_chinh"):
        if name in ctx.by_name:
            ex.road_mask |= ctx.L.mask(ctx.by_name[name])
    # khúc đường làng bản đồ cũ (nằm trong co_nen nên không có layer riêng): y≈200–243, x 0–640
    ex.road_mask[200:244, 0:640] = True


# ================================================================== xe khô gà + hai sân gà của chủ dự án

def occupancy(ctx, area):
    """Mặt nạ "có vật" (frame 0) trong vùng area = (x0, y0, x1, y1): mọi layer 03_Object/04_Above không bị ẩn
    (trừ giao thông) + va chạm của tranh. Dùng để đặt đồ thêm vào chỗ thật sự trống."""
    key = tuple(area)
    cache = getattr(ctx, "_occ_cache", {})
    if key in cache:
        return cache[key]
    x0, y0, x1, y1 = area
    m = ctx.raw.copy()
    hidden = getattr(ctx, "hidden", set())
    for row in ctx.rows:
        if row["top"] not in ("03_Object", "04_Above") or row["name"] in hidden:
            continue
        fr = row["frames"][0]
        if fr is None:
            continue
        img = ctx.L.image(row, fr[0], fr[3])
        if fr[1] >= x1 or fr[2] >= y1 or fr[1] + img.width <= x0 or fr[2] + img.height <= y0:
            continue
        a = np.asarray(img)[..., 3] > 0
        xa, ya = max(fr[1], 0), max(fr[2], 0)
        xb, yb = min(fr[1] + img.width, ctx.W), min(fr[2] + img.height, ctx.H)
        m[ya:yb, xa:xb] |= a[ya - fr[2]:yb - fr[2], xa - fr[1]:xb - fr[1]]
    out = np.zeros_like(m)
    out[y0:y1, x0:x1] = m[y0:y1, x0:x1]
    cache[key] = out
    ctx._occ_cache = cache
    return out


def _stand_spot(ctx, ex, pref, radius=24):
    """Chỗ đứng gần pref nhất mà khung chân (và lề 2 px) không bị chặn."""
    px0, py0 = pref
    for r in range(0, radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = px0 + dx, py0 + dy
                if not (ctx.raw[y - 7:y + 2, x - 7:x + 7].any() or ex.block_mask[y - 7:y + 2, x - 7:x + 7].any()):
                    return (x, y)
    raise SystemExit("không tìm được chỗ đứng gần %s" % (pref,))


def _layer_box(ctx, name):
    """Khung hợp (mọi frame) của layer → (x0, y0, x1, y1) + mặt nạ alpha hợp (cắt theo khung)."""
    row = ctx.by_name[name]
    box = None
    for fr in row["frames"]:
        if fr is None:
            continue
        img = ctx.L.image(row, fr[0])
        b = (fr[1], fr[2], fr[1] + img.width, fr[2] + img.height)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    x0, y0, x1, y1 = box
    m = np.zeros((y1 - y0, x1 - x0), bool)
    for fr in row["frames"]:
        if fr is None:
            continue
        a = np.asarray(ctx.L.image(row, fr[0]))[..., 3] > 0
        m[fr[2] - y0:fr[2] - y0 + a.shape[0], fr[1] - x0:fr[1] - x0 + a.shape[1]] |= a
    return box, m


def _owner_cart(ctx, ex):
    """Xe khô gà lá chanh của chủ dự án (mèo tam thể khóc cười, hai bụi mía, hũ khô gà) ở sân chợ phía đông.
    Layer có 8 ảnh khác nhau, đổi mỗi frame bản đồ (80 ms, vòng 640 ms) và nhích 1 px → node động thường của MapView.
    Va chạm: chủ dự án đã chặn bánh xe; thêm một khối liền dưới gốc hai bụi mía + thân xe (cao 18 px tính từ đáy) để
    không còn khe giữa mía và xe. Điểm tương tác ở phía trước-trái xe (LAO_STAND)."""
    if LAO_LAYER not in ctx.by_name:
        raise SystemExit("thiếu layer xe khô gà %s trong file art" % LAO_LAYER)
    (x0, y0, x1, y1), m = _layer_box(ctx, LAO_LAYER)
    cols = np.nonzero(m[-18:].any(axis=0))[0]
    bx0, bx1 = x0 + int(cols.min()) + 3, x0 + int(cols.max()) - 2
    block_rect(ex, bx0, y1 - 18, bx1 - bx0, 18)
    stand = _stand_spot(ctx, ex, LAO_STAND)
    top = int(np.nonzero(m.any(axis=1))[0].min())
    head_cols = np.nonzero(m[top:top + 12].any(axis=0))[0]
    head = [x0 + int((head_cols.min() + head_cols.max()) // 2), y0 + top]
    ex.info["places"]["cat_shop"] = {"pos": list(stand)}
    ex.info["doors"]["cat_shop"] = list(stand)
    ex.info["check_points"]["cat_shop_door"] = list(stand)
    row = ctx.by_name[LAO_LAYER]
    images = len({fr[0] for fr in row["frames"] if fr is not None})
    ex.info["lao_ga_kho"] = {"node": LAO_LAYER, "box": [x0, y0, x1, y1], "frames": images, "frame_ms": 80,
                             "block": [bx0, y1 - 18, bx1 - bx0, 18], "door": list(stand), "head": head}


def _owner_arenas(ctx, ex):
    """Sân gà Liên tỉnh (khán đài + vòng rào + biển "SÂN GÀ LIÊN TỈNH") và Sân gà Olympia (khán đài + võ đài + biển
    "SÂN GÀ OLYMPIA") của chủ dự án. Va chạm khán đài/rào/khán giả đã có trong 05_Collision của tranh; chỉ chặn ngưỡng
    cổng (giữa hai trụ, dưới biển tên) để người chơi dừng ở cổng – vào sới là cảnh trận đấu riêng."""
    for pid, cfg in ARENAS.items():
        (sx0, sy0, sx1, sy1), _ = _layer_box(ctx, cfg["sign"])
        block_rect(ex, sx0, sy1, sx1 - sx0, cfg["block_h"])
        block_rect(ex, *cfg["interior"])
        stand = _stand_spot(ctx, ex, cfg["stand"])
        ex.info["places"][pid] = {"pos": list(stand)}
        ex.info["doors"][pid] = list(stand)
        ex.info["check_points"][pid + "_door"] = list(stand)
        ex.info.setdefault("arenas", {})[pid] = {"sign": cfg["sign"], "gate": [sx0, sy0, sx1, sy1],
                                                 "threshold_block": [sx0, sy1, sx1 - sx0, cfg["block_h"]],
                                                 "interior_block": list(cfg["interior"]),
                                                 "stand": list(stand)}


def _stall_spot(ctx, ex, pref, occ, radius=40):
    """Góc trên-trái sạp riêng (56×50 + chỗ đứng mua 16 px phía trước) gần pref nhất, không đè vật/va chạm."""
    px0, py0 = pref
    for r in range(0, radius + 1, 2):
        for dy in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = px0 + dx, py0 + dy
                if occ[y - 4:y + 70, x - 4:x + 60].any() or ex.block_mask[y - 4:y + 70, x - 4:x + 60].any():
                    continue
                return (x, y)
    raise SystemExit("không còn chỗ trống cho sạp gần %s" % (pref,))




# ================================================================== chợ: sạp thêm, sạp riêng, người mua, hàng hoá

def _covers(ctx):
    """Mái che/dù (thành phần của các layer tán cây ở vùng chợ) → [(ảnh, x, y)]."""
    out = []
    for row in ctx.rows:
        if row["name"].startswith("N_tan_cay_"):
            out += ctx.components(row["name"], (1990, 760, 3190, 1250), min_px=200)
    return out


def _stall_unit(ctx, stall_name, covers):
    """Ảnh sạp + mái che/dù (khớp theo sạp gốc) → (ảnh từng khung, chuỗi, độ lệch ảnh so với góc sạp)."""
    imgs, seq, pos = ctx.unique(stall_name)
    sx, sy = pos[0]
    cover = None
    for img, x, y in covers:
        cxm = x + img.width / 2
        if abs(cxm - (sx + 24)) <= 10 and sy - 40 <= y + img.height <= sy + 34:
            cover = (img, x - sx, y - sy)
            break
    pole = px.canvas(4, 36)
    px.rect(pole, 1, 0, 2, 36, px.STEEL[3])
    px.vline(pole, 1, 0, 35, px.STEEL[2])
    ox = min(0, cover[1]) if cover else 0
    oy = min(0, cover[2]) if cover else 0
    w = max(48, (cover[1] + cover[0].width) if cover else 48) - ox
    h = 44 - oy
    frames = []
    for im in imgs:
        a = px.canvas(w, h)
        px.paste(a, im, -ox, -oy)
        if cover is not None:
            cimg, cx, cy = cover
            if cimg.height < 30:  # mái bạt: hai cột
                px.paste(a, pole, cx - ox, cy - oy + cimg.height - 4)
                px.paste(a, pole, cx - ox + cimg.width - 4, cy - oy + cimg.height - 4)
            else:                 # dù: một cột giữa
                px.paste(a, pole, cx - ox + cimg.width // 2 - 2, cy - oy + cimg.height // 2)
            px.paste(a, cimg, cx - ox, cy - oy)
        frames.append(a)
    return frames, seq, (ox, oy)


def _special_stall(ctx, kind, rng):
    w, h = 56, 50
    awn = {"market_chicken": (px.RED[1], px.WHITE), "market_eggs": (px.YELLOW[0], px.WHITE),
           "market_food": (px.GREEN[1], px.WHITE), "market_gear": (px.TIN_BLUE[1], px.WHITE)}[kind]
    label = {"market_chicken": "GA GIONG", "market_eggs": "TRUNG", "market_food": "GAO CAM",
             "market_gear": "DO NGHE"}[kind]
    vendor = {"market_chicken": "N_npc_ben_cho", "market_eggs": "N_npc_ba_Lan_ban_com",
              "market_food": "N_npc_pho_dich_vu_05", "market_gear": "N_npc_tho_lot_dua"}[kind]
    vimgs, vseq = npc_images(ctx, vendor)
    frames = []
    for vi in vimgs:
        a = px.canvas(w, h)
        # người bán đứng sau quầy
        px.paste(a, vi, (w - vi.shape[1]) // 2, 10)
        # cột + mái bạt sọc
        for xx in (2, w - 4):
            px.rect(a, xx, 8, 2, 34, px.STEEL[3])
        px.stripes(a, 0, 2, w, 9, awn[0], awn[1], 4)
        for xx in range(0, w, 4):
            px.put(a, xx + 1, 11, awn[0] if (xx // 4) % 2 == 0 else awn[1])
        px.hline(a, 0, w - 1, 2, px.shade(awn[0], 1.15))
        # bàn gỗ
        px.rect(a, 3, 32, w - 6, 4, px.WOOD[0])
        px.rect(a, 3, 36, w - 6, 10, px.WOOD[1])
        px.hline(a, 3, w - 4, 36, px.WOOD[3])
        for xx in range(6, w - 6, 8):
            px.vline(a, xx, 37, 45, px.WOOD[2])
        _stall_goods(a, kind, rng)
        board = px.sign_board(label, (250, 246, 226, 255), px.RED[2], px.FONT3x5, pad=1)
        px.paste(a, board, (w - board.shape[1]) // 2, 0)
        px.outline(a)
        frames.append(a)
    return frames, vseq


def _stall_goods(a, kind, rng):
    r = random.Random(kind)
    if kind == "market_chicken":
        for k, cx in enumerate((6, 20, 34)):          # lồng tre có gà
            px.rect(a, cx, 22, 14, 11, (0, 0, 0, 0))
            body = [(236, 120, 40, 255), (250, 240, 220, 255), (60, 48, 40, 255)][k]
            px.rect(a, cx + 4, 26, 6, 5, body)
            px.put(a, cx + 8, 24, px.RED[1])
            px.put(a, cx + 9, 25, body)
            px.put(a, cx + 10, 26, px.GOLD[2])
            for xx in range(cx, cx + 14, 3):
                px.vline(a, xx, 23, 32, px.WOOD[0])
            px.hline(a, cx, cx + 13, 22, px.WOOD[2])
            px.hline(a, cx + 1, cx + 12, 21, px.WOOD[0])
            px.hline(a, cx, cx + 13, 32, px.WOOD[2])
    elif kind == "market_eggs":
        for k, cx in enumerate((5, 21, 37)):          # rổ trứng
            px.rect(a, cx, 28, 14, 5, px.WOOD[1])
            px.hline(a, cx, cx + 13, 28, px.WOOD[0])
            for j in range(9):
                ex_ = cx + 1 + (j % 5) * 3 - (j // 5)
                ey = 24 + (j // 5) * 2
                col = [(252, 246, 230, 255), (240, 214, 170, 255), (210, 236, 236, 255)][(k + j) % 3]
                px.rect(a, ex_, ey, 2, 3, col)
    elif kind == "market_food":
        for k, cx in enumerate((4, 18, 32)):          # bao gạo / cám
            col = [(242, 238, 222, 255), (226, 214, 180, 255), (200, 220, 240, 255)][k]
            px.rect(a, cx, 21, 13, 12, col)
            px.hline(a, cx + 1, cx + 11, 20, col)
            px.hline(a, cx, cx + 12, 26, px.TIN_BLUE[1] if k != 1 else px.GREEN[1])
            px.put(a, cx + 6, 20, px.WOOD[3])
        px.rect(a, 46, 26, 7, 6, px.GOLD[0])           # thúng lúa
        px.hline(a, 46, 52, 31, px.WOOD[2])
    elif kind == "market_gear":
        px.rect(a, 4, 30, 48, 3, (110, 30, 40, 255))   # khăn đỏ trải bàn
        for k, cx in enumerate(range(7, 49, 8)):       # cựa sắt / dao chân
            px.line(a, cx, 31, cx + 4, 27, px.STEEL[0])
            px.put(a, cx + 5, 26, px.STEEL[1])
            px.put(a, cx, 32, px.WOOD[3])
        px.rect(a, 22, 22, 12, 5, px.STEEL[1])          # mào sắt
        for xx in range(23, 33, 3):
            px.put(a, xx, 21, px.STEEL[0])
        px.hline(a, 22, 33, 26, px.STEEL[3])


def _market(ctx, ex, rng):
    covers = _covers(ctx)
    # sạp chép thêm
    for k, (sx, sy, src) in enumerate(EXTRA_STALLS):
        frames, seq, (ox, oy) = _stall_unit(ctx, src, covers)
        hue = [0, 30, 160, 210, 300, 90, 250][k % 7]
        frames = [recolor_npc(f, hue, top=0.78) for f in frames]  # chỉ đổi màu hàng hoá trên mặt sạp
        add_node(ctx, ex, "X_cho_sap_them_%d" % k, frames, shifted(seq, 13 * k + 5), (sx + ox, sy + oy), sort_y=sy + 44)
        block_rect(ex, sx, sy + 18, 48, 26)
        ex.clear_zones.append((sx - 2, sy - 6, sx + 50, sy + 46))
    # NPC đứng chỗ sạp thêm → ẩn
    for name in ("N_npc_di_cho_02", "N_npc_di_cho_12"):
        ex.hide.add(name)
    ctx.hidden = set(getattr(ctx, "hidden", set())) | ex.hide
    # sạp riêng có tương tác: dò chỗ trống gần vị trí ưu tiên (không đè vật/người của tranh)
    occ = occupancy(ctx, (1990, 640, 3200, 1260))
    for kind, pref in SPECIAL_STALLS.items():
        sx, sy = _stall_spot(ctx, ex, pref, occ)
        frames, seq = _special_stall(ctx, kind, rng)
        add_node(ctx, ex, "X_" + kind, frames, shifted(seq, len(kind) * 7), (sx, sy))
        block_rect(ex, sx + 2, sy + 22, 52, 28)
        ex.clear_zones.append((sx - 2, sy - 4, sx + 58, sy + 52))
        door = (sx + 28, sy + 62)
        ex.info["stalls"][kind] = {"pos": list(door), "rect": [sx, sy, 56, 50]}
        ex.info["check_points"][kind] = list(door)
    # người đứng mua trước sạp (đứng yên, nhún nhẹ), đổi màu áo; chỉ đặt ở lối rộng
    buyers = [
        (2030, 1000), (2112, 1086), (2196, 1172), (2268, 998), (2350, 1088), (2424, 1172),
        (2560, 1002), (2652, 1100), (2742, 1196), (2830, 1100), (2918, 1196), (3006, 1100),
        (2590, 892), (2716, 896), (2468, 960), (2105, 930),
        (2450, 1214), (2690, 1214), (3110, 1196),
    ]
    for k, (bx, by) in enumerate(buyers):
        name = NPC_POOL[(k * 7) % len(NPC_POOL)]
        imgs, seq = npc_images(ctx, name)
        hue = (k * 47) % 360
        imgs = [recolor_npc(i, hue) for i in imgs]
        h = imgs[0].shape[0]
        nx, ny = bx - imgs[0].shape[1] // 2, by - h
        if _overlaps_blocked(ex, ctx, nx, by - 14, imgs[0].shape[1], 18):
            continue
        add_node(ctx, ex, "X_cho_nguoi_mua_%d" % k, imgs, shifted(seq, (k * 17) % 96), (nx, ny))
        block_rect(ex, bx - 4, by - 4, 8, 4)
    # thúng, sọt, bao hàng sát hông sạp
    goods = [(2075, 984), (2153, 1072), (2231, 984), (2309, 1160), (2385, 1072), (2605, 1088), (2693, 1182),
             (2869, 1088), (2957, 1182), (3045, 1088), (2470, 1110), (3140, 1110), (2060, 1225), (3150, 1000)]
    for k, (gx, gy) in enumerate(goods):
        img = _goods_pile(k)
        if _overlaps_blocked(ex, ctx, gx, gy - 6, img.shape[1], 6):
            continue
        add_node(ctx, ex, "X_cho_hang_%d" % k, [img], None, (gx, gy - img.shape[0]))
        block_rect(ex, gx + 1, gy - 6, img.shape[1] - 2, 6)


def _overlaps_blocked(ex, ctx, x, y, w, h):
    """Đè va chạm của tranh / vật đã thêm / người đứng của tranh (NEW_NPC, vd. khách mua khô gà)?"""
    if ctx.raw[y:y + h, x:x + w].any() or ex.block_mask[y:y + h, x:x + w].any():
        return True
    npc = getattr(ctx, "_npc_occ", None)
    if npc is None:
        npc = np.zeros((ctx.H, ctx.W), bool)
        for row in ctx.rows:
            if row["gp"].endswith("NEW_NPC") and row["frames"][0] is not None and row["name"] not in getattr(ctx, "hidden", set()):
                npc |= ctx.L.mask(row)
        ctx._npc_occ = npc
    return bool(npc[max(y - 2, 0):y + h + 2, max(x - 2, 0):x + w + 2].any())


def _goods_pile(k):
    kind = k % 4
    if kind == 0:      # thúng trái cây
        a = px.canvas(16, 12)
        px.rect(a, 1, 6, 14, 6, px.WOOD[1])
        px.hline(a, 1, 14, 6, px.WOOD[0])
        cols = [(250, 160, 40, 255), (120, 200, 60, 255), (230, 60, 50, 255)]
        for j in range(8):
            px.rect(a, 2 + (j % 4) * 3, 3 + (j // 4) * 2, 3, 3, cols[(j + k) % 3])
    elif kind == 1:    # chồng sọt nhựa
        a = px.canvas(14, 16)
        for j, col in enumerate((px.TIN_BLUE[1], px.GREEN[1], px.RED[1])):
            px.rect(a, 1, 11 - j * 5, 12, 5, col)
            for xx in range(2, 12, 3):
                px.put(a, xx, 13 - j * 5, px.shade(col, 0.6))
    elif kind == 2:    # bao tải
        a = px.canvas(16, 13)
        for j, xx in enumerate((1, 8)):
            px.rect(a, xx, 3 + j, 7, 10 - j, (226, 210, 170, 255))
            px.hline(a, xx + 1, xx + 5, 2 + j, (226, 210, 170, 255))
            px.hline(a, xx, xx + 6, 8, px.WOOD[2])
    else:              # nải chuối + dừa
        a = px.canvas(16, 11)
        for j in range(3):
            px.rect(a, 1 + j * 5, 4, 4, 6, (110, 76, 40, 255))
            px.put(a, 2 + j * 5, 5, (150, 110, 60, 255))
        px.rect(a, 4, 1, 9, 3, px.YELLOW[0])
        px.hline(a, 4, 12, 3, px.YELLOW[2])
    px.outline(a)
    return a


def _quay(ctx, ex, rng):
    """Mép chợ nổi: ghe xuồng cập kè, người bán ngồi với thúng, sọt hàng."""
    boats = [("N_cho_noi_xuong__03", 2560, 640), ("N_cho_noi_xuong__10", 2655, 652), ("N_cho_noi_xuong__08", 2860, 646),
             ("N_cho_noi_xuong__05", 2395, 648)]
    for k, (src, bx, by) in enumerate(boats):
        imgs, seq, pos = ctx.unique(src)
        base = pos[0]
        offs = [None if p is None else (bx + p[0] - base[0], by + p[1] - base[1]) for p in pos]
        frames = [px.from_img(i) for i in imgs]
        add_node(ctx, ex, "X_ke_ghe_%d" % k, frames, shifted(seq, 9 * k + 3), shifted(offs, 9 * k + 3))
    sellers = [("N_cho_ngoi_ban__01", 2400, 714), ("N_cho_ngoi_ban__04", 2610, 716), ("N_cho_ngoi_ban__02", 2805, 712),
               ("N_cho_ngoi_ban__05", 2985, 712), ("N_cho_ngoi_ban__03", 2700, 720)]
    for k, (src, sx, sy) in enumerate(sellers):
        imgs, seq = npc_images(ctx, src)
        imgs = [recolor_npc(i, 70 * k) for i in imgs]
        h0, w0 = imgs[0].shape[:2]
        if _overlaps_blocked(ex, ctx, sx - 2, sy + h0 // 3, w0 + 4, h0 - h0 // 3 + 4):
            continue
        add_node(ctx, ex, "X_ke_nguoi_ban_%d" % k, imgs, shifted(seq, 11 * k), (sx, sy))
        block_rect(ex, sx + 2, sy + imgs[0].shape[0] - 10, imgs[0].shape[1] - 4, 10)
    for k, (gx, gy) in enumerate(((2455, 744), (2540, 712), (2670, 744), (2760, 722), (2900, 744), (3020, 728),
                                   (2430, 724), (2875, 716))):
        img = _goods_pile(k + 1)
        if _overlaps_blocked(ex, ctx, gx - 2, gy - img.shape[0], img.shape[1] + 4, img.shape[0] + 3):
            continue
        add_node(ctx, ex, "X_ke_hang_%d" % k, [img], None, (gx, gy - img.shape[0]))
        block_rect(ex, gx + 1, gy - 6, img.shape[1] - 2, 6)


# ================================================================== bảng chỉ đường

SIGN_TARGETS = {
    "sign_village": ["home", "market", "arena_lien_tinh"],
    "sign_south_road": ["market", "school", "arena_olympic"],
    "sign_market_nw": ["market", "cat_shop", "home"],
    "sign_market_se": ["arena_lien_tinh", "arena_olympic", "market"],
    "sign_bridge": ["thpt", "market", "arena_lien_tinh"],
    "sign_east": ["arena_lien_tinh", "arena_olympic", "thpt"],
    "sign_thpt": ["thpt", "market", "home"],
}
## Toạ độ sơ bộ của các điểm đến (chỉ để quyết định mũi tên trái/phải trên tấm bảng vẽ).
APPROX_TARGETS = {
    "home": (131, 196), "market": (2600, 1000), "arena_lien_tinh": (4508, 1080), "arena_olympic": (4938, 1413),
    "school": (899, 740), "cat_shop": (2968, 1044), "thpt": (4540, 312),
}


def _signpost(dirs):
    w, h = 26, 40
    a = px.canvas(w, h)
    px.rect(a, 12, 4, 3, h - 4, px.WOOD[2])
    px.vline(a, 12, 4, h - 1, px.WOOD[1])
    px.rect(a, 11, 2, 5, 3, px.WOOD[3])
    cols = [px.RED[1], px.TIN_BLUE[1], px.GREEN[1]]
    for k, d in enumerate(dirs):
        y = 6 + k * 8
        col = cols[k]
        if d > 0:
            px.rect(a, 6, y, 16, 6, col)
            for j in range(3):
                px.vline(a, 22 + j, y + j, y + 5 - j, col)
        else:
            px.rect(a, 4, y, 16, 6, col)
            for j in range(3):
                px.vline(a, 3 - j, y + j, y + 5 - j, col)
        px.hline(a, 7 if d > 0 else 5, 18 if d > 0 else 16, y + 2, px.WHITE)
        px.hline(a, 7 if d > 0 else 5, 14 if d > 0 else 12, y + 4, (220, 220, 210, 255))
    px.outline(a)
    return a


def _signposts(ctx, ex):
    for sid, x, y in SIGNPOSTS:
        x, y = _free_spot(ctx, ex, x, y)
        dirs = [1 if APPROX_TARGETS[t][0] >= x else -1 for t in SIGN_TARGETS[sid]]
        img = _signpost(dirs)
        add_node(ctx, ex, "X_" + sid, [img], None, (x - 13, y - img.shape[0]))
        block_rect(ex, x - 2, y - 4, 5, 4)
        ex.info["signposts"][sid] = {"pos": [x, y + 8], "targets": SIGN_TARGETS[sid]}
        ex.info["check_points"][sid] = [x, y + 8]


def _free_spot(ctx, ex, x, y):
    """Chỗ cắm cột gần (x, y) nhất: không chặn đường, không đè vật, có chỗ đứng đọc phía nam."""
    best = None
    for r in range(0, 40):
        for dx in range(-r, r + 1):
            for dy in (-r, r) if abs(dx) != r else range(-r, r + 1):
                xx, yy = x + dx, y + dy
                if not (8 <= xx < ctx.W - 8 and 8 <= yy < ctx.H - 20):
                    continue
                if ex.road_mask[yy - 6:yy + 1, xx - 3:xx + 4].any():
                    continue
                if ctx.raw[yy - 30:yy + 1, xx - 8:xx + 9].any() or ex.block_mask[yy - 30:yy + 1, xx - 8:xx + 9].any():
                    continue
                if ctx.raw[yy + 2:yy + 14, xx - 6:xx + 7].any():
                    continue
                best = (xx, yy)
                break
            if best:
                break
        if best:
            break
    return best or (x, y)


# ================================================================== người đi chợ (runtime) + mạng lối đi

SHOPPER_SRC = ["N_npc_di_cho", "N_npc_di_cho_03", "N_npc_di_cho_05", "N_npc_di_cho_07", "N_npc_di_cho_09",
               "N_npc_di_cho_10", "N_npc_di_cho_13", "N_npc_di_cho_16", "N_npc_di_cho_19", "N_npc_pho_bac_03",
               "N_npc_pho_bac_07", "N_npc_dan_cu_moi", "N_npc_dan_hem", "N_npc_an_sang_02", "N_npc_pho_dich_vu_02",
               "N_npc_pho_bac_05", "N_npc_dan_cu_moi_05"]
SHOP_CELL = (24, 46)
## Khối chợ: hai sân chợ + đường giữa + đường trước chợ + kè chợ nổi (lối chỉ đặt ở chỗ trống).
MARKET_AREAS = [(2010, 668, 3176, 1238)]


def _walk_frames(arr):
    """4 khung đi: đứng, nhấc chân trái, đứng nhún xuống 1 px, nhấc chân phải (5 hàng dưới tách đôi)."""
    alpha = arr[..., 3] > 0
    ys = np.nonzero(alpha.any(axis=1))[0]
    xs = np.nonzero(alpha.any(axis=0))[0]
    bottom = int(ys.max())
    mid = int((xs.min() + xs.max() + 1) // 2)
    legs_top = bottom - 4

    def step(side):
        out = arr.copy()
        cols = slice(0, mid) if side < 0 else slice(mid, arr.shape[1])
        leg = arr[legs_top:bottom + 1, cols].copy()
        out[legs_top:bottom + 1, cols] = 0
        out[legs_top - 1:bottom, cols] = np.where(leg[..., 3:4] > 0, leg, out[legs_top - 1:bottom, cols])
        return out

    bob = np.zeros_like(arr)
    bob[1:bottom + 1] = arr[0:bottom]
    bob[legs_top + 1:bottom + 1] = arr[legs_top + 1:bottom + 1]
    return [arr, step(-1), bob, step(1)]


def _shoppers(ctx, ex, rng):
    cw, ch = SHOP_CELL
    variants = []
    for k, name in enumerate(SHOPPER_SRC):
        if name not in ctx.by_name:
            continue
        img, _, _ = ctx.frame(name)
        if img.width > cw - 2 or img.height > ch:
            continue  # người gánh hàng/cầm cào rộng hơn ô → bỏ
        arr = px.from_img(img)
        for hue in (0, 140):
            v = recolor_npc(arr, (hue + k * 23) % 360) if hue else arr
            variants.append(v)
    sheet = px.canvas(cw * 4, ch * len(variants))
    for i, v in enumerate(variants):
        for f, fr in enumerate(_walk_frames(v)):
            h, w = fr.shape[:2]
            px.paste(sheet, fr, f * cw + (cw - w) // 2, i * ch + ch - h)
    out = os.path.join(ctx.export_dir, "_extras")
    os.makedirs(out, exist_ok=True)
    px.to_img(sheet).save(os.path.join(out, "shoppers.png"))
    ex.info["shoppers"] = {"cell": [cw, ch], "count": len(variants), "frames": 4, "foot": [cw // 2, ch - 1]}


def build_lanes(blocked, extra_info, out_path):
    """Mạng lối đi trong chợ: điểm lưới 12 px có khoảng trống rộng (người đứng được, cách vật ≥ 8 px),
    nối 4 hướng. Ghi market_lanes.json: {"step", "nodes": [[x,y]...], "links": [[i,j]...], "browse": [i...]}."""
    step = 12
    pad = 8
    nodes, index = [], {}
    for ax0, ay0, ax1, ay1 in MARKET_AREAS:
        for y in range(ay0 + 10, ay1 - 2, step):
            for x in range(ax0 + 10, ax1 - 10, step):
                if (x, y) in index:
                    continue
                if blocked[y - 6 - pad // 2:y + 2, x - 5 - pad // 2:x + 6 + pad // 2].any():
                    continue
                index[(x, y)] = len(nodes)
                nodes.append([x, y])
    links = []
    for (x, y), i in index.items():
        for dx, dy in ((step, 0), (0, step)):
            j = index.get((x + dx, y + dy))
            if j is None:
                continue
            # đoạn nối phải trống hẳn
            if blocked[min(y, y + dy) - 6:max(y, y + dy) + 1, min(x, x + dx) - 5:max(x, x + dx) + 6].any():
                continue
            links.append([i, j])
    # điểm "xem hàng": ngay dưới mép sạp (ô chặn ở 4–14 px phía bắc)
    browse = []
    for (x, y), i in index.items():
        if blocked[y - 20:y - 8, x - 1:x + 2].any():
            browse.append(i)
    # giữ thành phần liên thông lớn nhất
    n = len(nodes)
    parent = list(range(n))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i, j in links:
        parent[find(i)] = find(j)
    counts = {}
    for i in range(n):
        counts[find(i)] = counts.get(find(i), 0) + 1
    best = max(counts, key=counts.get) if counts else None
    keep = [i for i in range(n) if find(i) == best]
    remap = {old: new for new, old in enumerate(keep)}
    data = {"step": step, "nodes": [nodes[i] for i in keep],
            "links": [[remap[i], remap[j]] for i, j in links if i in remap and j in remap],
            "browse": [remap[i] for i in browse if i in remap],
            "areas": [list(a) for a in MARKET_AREAS]}
    with open(out_path, "w", encoding="utf8") as f:
        json.dump(data, f, separators=(",", ":"))
    return data


# ================================================================== THPT, NPC hàng xóm

NEIGHBOURS = {
    "npc_ba_lan": "N_npc_ba_Lan_ban_com",
    "npc_chu_bay": "N_npc_chu_quan_vong",
    "npc_ong_tam": "N_npc_danh_co_tuong",
    "npc_ong_sau": "N_npc_ong_cau_ca_ao_sen",
    "npc_chu_muoi": "N_npc_chu_vuon_kieng",
}


def _thpt_and_npcs(ctx, ex):
    # cổng THPT: điểm đánh dấu NEW_GUIDE_TUONG_TAC_E_THPT của tác giả (06_Guide, ẩn) tại (4502, 304) 77×11
    gx, gy, gw, gh = _guide_rect(ctx, "NEW_GUIDE_TUONG_TAC_E_THPT") or (4502, 304, 77, 11)
    ex.info["places"]["thpt"] = {"pos": [gx + gw // 2, gy + gh // 2 + 4]}
    ex.info["check_points"]["thpt_gate"] = [gx + gw // 2, gy + gh // 2 + 4]
    for pid, layer in NEIGHBOURS.items():
        got = ctx.frame(layer)
        if got is None:
            continue
        img, x, y = got
        ex.info["npcs"][pid] = {"node": layer, "pos": [x + img.width // 2, y + img.height + 10]}
        ex.info["check_points"][pid] = [x + img.width // 2, y + img.height + 10]


def _guide_rect(ctx, name):
    path = os.path.join(ctx.export_dir, "guide.tsv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf8") as f:
        for i, line in enumerate(f, start=1):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 5 and p[2] == name and p[3] != "-1":
                img = Image.open(os.path.join(ctx.export_dir, "guide", "G%02d.png" % int(p[0])))
                box = img.getbbox()
                return (int(p[3]) + box[0], int(p[4]) + box[1], box[2] - box[0], box[3] - box[1])
    return None
