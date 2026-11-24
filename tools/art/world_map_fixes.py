"""Sửa lỗi hình/lối đi của bản đồ sau khi dựng (gọi cuối tools/art/build_world_map.py, hoặc chạy riêng trên thư mục
game/art/world_map đã dựng):

    python -I tools/art/world_map_fixes.py [thư_mục_world_map]

Các bước (đều idempotent – chạy lại không đổi kết quả; traffic.json ghi "fixes" đã áp):
1. water.png: thuyền người chơi chui qua MỌI cầu (cầu thấp vẽ mặt cầu đè lên thuyền lúc chơi – traffic.gd), chỉ vật cản
   thật chặn (ghe đậu, cầu ván bến, nhà sàn, cọc, cù lao). Dưới mỗi cầu: hàng (cầu dọc bắc qua sông ngang) / cột (cầu ngang
   bắc qua kênh dọc) nào có nước ở cả hai phía cầu thì lấp nước qua mặt cầu. Kênh còn hẹp hơn thân thuyền nhìn dọc thì
   nới bằng đúng nước của layer (không đào vào bờ). Bảng "bridges" của traffic.json: player_boat_passes = true hết.
2. Vỏ lãi bốc đầu (boat_02 song_vo_lai_1_boc_dau, boat_04 vỏ lãi chạy đông của sông chính/sông nam): đuôi + vệt sóng
   luôn nằm trên mặt nước. Mỗi khung: neo y = đáy đuôi thuyền − 1 (đuôi chạm mặt nước), xoá bóng rời (boat_04: vệt bóng
   tối nằm xa phía trước mũi trong ảnh; boat_02: sprite bóng riêng lệch 16 px xuống dưới) và vẽ lại bóng sát mép nước
   dưới phần thân chạm nước + bóng mờ ngay dưới mũi đang bốc; bọt nước dời về sát chân vịt.
3. Ông câu cá (NV_ong_cau_ca, N_npc_ong_cau_ca_ao_sen): tranh vẽ ông quay lưng ra nước (nhìn lên bờ, cần câu chĩa ra sau
   lưng) → fisher_front.png: cùng ông (nón xanh, áo xanh két), quay mặt ra sông/ao, cần câu chìa về phía nước, phao đỏ
   nhấp nhô (2 khung như tranh). World ẩn node bản đồ và đặt sprite này đúng chỗ.
4. player_boat_ns.png: vỏ lãi của người chơi nhìn dọc (mũi lên / mũi xuống), vẽ pixel cùng bảng màu boat_01 (thay hình
   vẽ bằng code cũ).
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "game", "art", "world_map"))
FIX_BOATS = "boat_water_v1"

# ------------------------------------------------------------------ 1. nước dưới cầu


## Cầu không có layer riêng trong bảng cầu của world_map_traffic.py (cầu khỉ tre bản đồ cũ bắc qua rạch vườn).
EXTRA_BRIDGES = [
    {"id": "D_cau_khi_tre", "rect": [621, 765, 92, 51], "player_boat_passes": True},
]


def carve_bridges(water, bridges, reach=24):
    """water: mảng bool (H, W). Lấp nước qua mặt mỗi cầu theo hướng dòng chảy. Trả về mảng mới."""
    out = water.copy()
    H, W = water.shape
    for b in bridges:
        x, y, w, h = b["rect"]
        x0, y0, x1, y1 = max(x - 2, 1), max(y - 2, 1), min(x + w + 2, W - 2), min(y + h + 2, H - 2)
        rows = _span_fill(water, x0, y0, x1, y1, reach, axis=1)
        cols = _span_fill(water, x0, y0, x1, y1, reach, axis=0)
        # hướng nào nối được nhiều nước hơn là hướng dòng chảy dưới cầu
        best = rows if rows.sum() >= cols.sum() else cols
        out[y0 - reach:y1 + reach, x0 - reach:x1 + reach] |= best
    return out


def _span_fill(water, x0, y0, x1, y1, reach, axis):
    """Ô lấp (cùng cỡ vùng cầu nới reach): axis=1 → mỗi hàng có nước bên trái và bên phải cầu thì lấp ngang;
    axis=0 → mỗi cột có nước phía trên và phía dưới cầu thì lấp dọc."""
    sub = water[y0 - reach:y1 + reach, x0 - reach:x1 + reach]
    fill = np.zeros_like(sub)
    r = reach
    if axis == 1:
        for j in range(r, sub.shape[0] - r):
            left = np.nonzero(sub[j, :r + 1])[0]
            right = np.nonzero(sub[j, sub.shape[1] - r - 1:])[0]
            if len(left) and len(right):
                a = left.max()
                b = sub.shape[1] - r - 1 + right.min()
                fill[j, a:b + 1] = True
    else:
        for i in range(r, sub.shape[1] - r):
            top = np.nonzero(sub[:r + 1, i])[0]
            bot = np.nonzero(sub[sub.shape[0] - r - 1:, i])[0]
            if len(top) and len(bot):
                a = top.max()
                b = sub.shape[0] - r - 1 + bot.min()
                fill[a:b + 1, i] = True
    return fill


RUNTIME_HIDDEN = {"song_do_ngang", "song_do_ngang_gon"}


def compose_layer(out_dir, layer):
    """Ghép một lớp của world_layers.json ở frame 0 thành ảnh RGBA đủ cỡ bản đồ."""
    m = json.load(open(os.path.join(out_dir, "world_layers.json"), encoding="utf8"))
    atl = [Image.open(os.path.join(out_dir, a)).convert("RGBA") for a in m["atlases"]]
    W, H = m["size"]
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    items = []
    for n in m[layer]:
        if "static" in n:
            st = n["static"]
            items.append((n["pos"][1] + st[4], st, n["pos"][0], n["pos"][1]))
            continue
        if n.get("name") in RUNTIME_HIDDEN:
            continue
        seq = n["seq"]
        si = n["clock"]["states"][0] if "clock" in n else (0 if seq < 0 else m["seqs"][seq][0])
        if si < 0:
            continue
        st = n["states"][si]
        r = n["regions"][st[0]]
        items.append((n.get("sort_y") or st[2] + r[4], r, st[1], st[2]))
    items.sort(key=lambda t: t[0])
    for _, r, px, py in items:
        out.alpha_composite(atl[r[0]].crop((r[1], r[2], r[1] + r[3], r[2] + r[4])), (int(px), int(py)))
    return np.array(out)


def recover_water(out_dir, water, bridges):
    """Mặt nước bị bỏ sót: dưới tàu lá dừa/bần vươn ra kênh (mảnh lá rời bị coi là vật cản), khúc rạch vườn của bản đồ cũ.
    Ứng viên = pixel màu nước của lớp nền (below) không có vật thể cứng (lớp object: pixel không phải lá xanh) và chưa
    là nước; giữ mảng ứng viên chạm nước cũ, rồi bỏ 2 px sát bờ như water.png gốc."""
    below = compose_layer(out_dir, "below").astype(np.int16)
    obj = compose_layer(out_dir, "object").astype(np.int16)
    r, g, b = below[..., 0], below[..., 1], below[..., 2]
    is_water = (b > r + 40) & (b > g + 8) & (below[..., 3] > 0)
    orr, og, ob, oa = obj[..., 0], obj[..., 1], obj[..., 2], obj[..., 3]
    leaf = (og > orr + 8) & (og > ob)
    hard = (oa > 0) & ~leaf
    hard = ndimage.binary_dilation(hard, iterations=1)
    cand = is_water & ~hard & ~water
    lab, n = ndimage.label(cand)
    seed = ndimage.binary_dilation(water, iterations=1)
    for br in bridges:
        # khúc kênh kẹp giữa hai cầu (rạch vườn: cầu xi măng – cầu khỉ tre) cũng là sông
        x, y, w, h = br["rect"]
        seed[max(y - 8, 0):y + h + 8, max(x - 8, 0):x + w + 8] = True
    touch = np.unique(lab[seed & cand])
    keep = np.zeros(n + 1, bool)
    keep[touch] = True
    keep[0] = False
    grown = water | keep[lab]
    grown = ndimage.binary_erosion(grown, iterations=2, border_value=1) | water
    return grown


def fix_water(out_dir, data):
    path = os.path.join(out_dir, "water.png")
    water = np.array(Image.open(path).convert("L")) > 0
    before = int(water.sum())
    names = {b["id"] for b in data.get("bridges", [])}
    for extra in EXTRA_BRIDGES:
        if extra["id"] not in names:
            data.setdefault("bridges", []).append(dict(extra))
    water = recover_water(out_dir, water, data.get("bridges", []))
    carved = carve_bridges(water, data.get("bridges", []))
    # chỉ giữ mặt nước nối với nước cũ (vệt lấp không tạo ao mới)
    lab, n = ndimage.label(carved)
    keep = np.zeros(n + 1, bool)
    keep[np.unique(lab[water])] = True
    keep[0] = False
    carved = keep[lab]
    if int(carved.sum()) != before:
        Image.fromarray(carved.astype(np.uint8), "L").save(path, optimize=True)
    for b in data.get("bridges", []):
        b["player_boat_passes"] = True
    return before, int(carved.sum())


# ------------------------------------------------------------------ 2. vỏ lãi bốc đầu ngồi trên mặt nước

WATER_SHADOW = (31, 63, 124)


def _is_shadow(px):
    r, g, b, a = px
    return a > 0 and b > r + 40 and b > g + 20 and r < 70 and g < 100 and b < 140


def seat_boats(out_dir, data):
    fixes = data.setdefault("fixes", [])
    if FIX_BOATS in fixes:
        return []
    atlas_path = os.path.join(out_dir, "traffic_atlas.png")
    atlas = Image.open(atlas_path).convert("RGBA")
    arr = np.array(atlas)
    changed = []
    for look in data.get("vehicles", []):
        if look.get("kind") != "boat" or look["id"] not in ("boat_02", "boat_04"):
            continue
        anchors = {}
        for d in ("east", "west"):
            frames = look["frames"][d]
            base = look.get("frame_anchors", {}) or {}
            base_list = base.get(d) or [look["anchor"] if d == "east" else look.get("anchor_west", look["anchor"])] * len(frames)
            new_list = []
            for i, r in enumerate(frames):
                ax, ay = base_list[min(i, len(base_list) - 1)]
                x, y, w, h = r
                sub = arr[y:y + h, x:x + w]
                new_ay = _seat_frame(sub, d, ax, ay)
                new_list.append([float(ax), float(new_ay)])
            anchors[d] = new_list
        look["frame_anchors"] = anchors
        look["anchor"] = anchors["east"][0]
        look["anchor_west"] = anchors["west"][0]
        # vệt bóng tối nằm trong ảnh vệt sóng (boat_04: 27 px dưới mặt nước, dưới mũi đang bốc → thuyền như bay) – bỏ
        # (bóng sát thân đã vẽ vào khung)
        for d in ("east", "west"):
            for r in (look.get("wake") or {}).get(d, []):
                x, y, w, h = r
                sub = arr[y:y + h, x:x + w]
                dark = (sub[..., 3] > 0) & (sub[..., 3] < 160) & (sub[..., :3].astype(int).sum(axis=2) < 120)
                sub[dark] = 0
        if look.get("shadow") is not None:
            # bóng đã vẽ thẳng vào khung (sát mép nước) – bỏ sprite bóng rời
            look["shadow"] = None
            look["shadow_offset"] = None
        if look.get("foam_offset") is not None:
            # bọt nước sát chân vịt (đầu cần = mép khung phía đuôi): mép bọt phía thuyền chồng lên đầu cần 10 px, chân bọt
            # nằm trên mặt nước (+2 px) – mỗi khung bọt một độ lệch (khung bọt khác cỡ nhau)
            per = {}
            for d in ("east", "west"):
                tip = -anchors[d][0][0] if d == "east" else (look["size"][0] - anchors[d][0][0])
                per[d] = [[int(tip - f[2] + 10), int(2 - f[3])] if d == "east" else [int(tip - 10), int(2 - f[3])]
                          for f in look["foam"][d]]
            look["foam_frame_offsets"] = per
        changed.append(look["id"])
    Image.fromarray(arr, "RGBA").save(atlas_path, optimize=True)
    fixes.append(FIX_BOATS)
    return changed


def _seat_frame(sub, direction, ax, ay):
    """Sửa khung tại chỗ: xoá bóng rời, vẽ bóng sát mép nước; trả về neo y mới (đuôi chạm nước)."""
    h, w = sub.shape[:2]
    alpha = sub[..., 3] > 0
    shadow = np.zeros((h, w), bool)
    for yy in range(h):
        for xx in range(w):
            if alpha[yy, xx] and _is_shadow(tuple(sub[yy, xx])):
                shadow[yy, xx] = True
    # bóng rời = mảng bóng không dính vào thân (không kề pixel không-bóng)
    body = alpha & ~shadow
    lab, n = ndimage.label(shadow)
    near_body = ndimage.binary_dilation(body, iterations=1)
    for k in range(1, n + 1):
        part = lab == k
        if not (part & near_body).any() or part.sum() > 60:
            sub[part] = 0
    alpha = sub[..., 3] > 0
    body = alpha & ~np.array([[_is_shadow(tuple(sub[yy, xx])) for xx in range(w)] for yy in range(h)])
    # thân thuyền = mảng liền lớn nhất (bỏ bọt/tia nước rời)
    lab, n = ndimage.label(body, structure=np.ones((3, 3), bool))
    if n == 0:
        return ay
    sizes = ndimage.sum(body, lab, range(1, n + 1))
    hull = lab == (int(np.argmax(sizes)) + 1)
    cols = np.nonzero(hull.any(axis=0))[0]
    bottoms = np.full(w, -1)
    thick = np.zeros(w, int)
    for c in cols:
        ys = np.nonzero(hull[:, c])[0]
        bottoms[c] = ys.max()
        thick[c] = len(ys)
    # thân thật = cột dày ≥ 6 px (bỏ cần chân vịt mảnh chĩa xuống nước). Đuôi = phía cần chân vịt: hướng đông → bên trái
    # khung; hướng tây → bên phải. Mép nước = đáy thấp nhất của 30% thân phía đuôi.
    body_cols = [c for c in cols if thick[c] >= 6]
    lo, hi = min(body_cols), max(body_cols)
    span = hi - lo + 1
    if direction == "east":
        stern = range(lo, lo + int(span * 0.3))
    else:
        stern = range(hi - int(span * 0.3), hi + 1)
    stern_bottom = max(bottoms[c] for c in stern if thick[c] >= 6)
    waterline = stern_bottom - 1
    # bóng: dưới các cột thân, ngay dưới mép nước; độ đậm giảm theo độ cao đáy so với mặt nước
    for c in body_cols:
        lift = waterline - bottoms[c]
        if lift > 26:
            continue
        a = 200 if lift <= 3 else max(60, 190 - lift * 6)
        rows = [waterline + 1, waterline + 2, waterline + 3] if lift <= 3 else [waterline + 2, waterline + 3]
        for rr in rows:
            if 0 <= rr < h and sub[rr, c, 3] == 0:
                sub[rr, c] = (*WATER_SHADOW, a if rr < waterline + 3 else a // 2)
    return float(waterline)


# ------------------------------------------------------------------ 3. ông câu cá quay mặt ra nước

FISHER_REGIONS = [[111, 190, 53, 42], [221, 145, 53, 43]]
OUTLINE = (42, 30, 46, 255)
SKIN = (220, 170, 104, 255)
SKIN_D = (182, 124, 70, 255)
GREY = (177, 174, 170, 255)
WHITE = (236, 232, 222, 255)
ROD = (150, 98, 52, 255)
ROD_L = (198, 146, 84, 255)
LINE = (214, 220, 226, 255)
RED = (238, 88, 68, 255)
CREAM = (247, 237, 196, 255)
RIPPLE = (190, 226, 248, 200)
SHIRT_L = (95, 162, 152, 255)
EXTRA_ROWS = 16


def build_fisher(out_dir):
    """fisher_front.png: 2 khung ngang, mỗi khung 53 × (cao + EXTRA_ROWS). Gốc khung = góc trên-trái của node bản đồ."""
    people = Image.open(os.path.join(out_dir, "people_atlas.png")).convert("RGBA")
    frames = []
    for i, (x, y, w, h) in enumerate(FISHER_REGIONS):
        src = np.array(people.crop((x, y, x + w, y + h)))
        frames.append(_fisher_front(src, i))
    fh = max(f.shape[0] for f in frames)
    sheet = np.zeros((fh, 53 * len(frames), 4), np.uint8)
    for i, f in enumerate(frames):
        sheet[:f.shape[0], i * 53:i * 53 + f.shape[1]] = f
    path = os.path.join(out_dir, "fisher_front.png")
    Image.fromarray(sheet, "RGBA").save(path, optimize=True)
    return path


def _fisher_front(src, k):
    h, w = src.shape[:2]
    img = np.zeros((h + EXTRA_ROWS, w, 4), np.uint8)
    # chỉ giữ người (cột 0..22), bỏ cần câu cũ chĩa lên sau lưng
    img[:h, :23] = src[:, :23]
    for yy in range(h):
        for xx in range(19, 23):
            p = tuple(img[yy, xx])
            if p[3] and p[:3] in ((182, 124, 70), (238, 88, 68), (177, 174, 170)) and yy < 24:
                img[yy, xx] = 0
    # dòng đầu tiên có nón
    top = int(np.nonzero(img[:, :23, 3].any(axis=1))[0].min())
    put = lambda xx, yy, c: img.__setitem__((top + yy, xx), c)  # noqa: E731
    # mặt (hàng 9..17 so với đỉnh nón): viền tối giữ ở cột 4 và 18
    for yy in range(9, 18):
        for xx in range(5, 18):
            put(xx, yy, SKIN)
        put(5, yy, SKIN_D)
        put(17, yy, SKIN_D)
    for yy in range(9, 12):  # tóc mai bạc hai bên + bóng vành nón
        put(5, yy, GREY)
        put(17, yy, GREY)
    for xx in range(5, 18):
        put(xx, 9, SKIN_D)
    # chân mày bạc, mắt, má
    for xx in (7, 8, 14, 15):
        put(xx, 11, GREY)
    put(8, 13, OUTLINE)
    put(14, 13, OUTLINE)
    put(7, 14, (232, 140, 110, 255))
    put(15, 14, (232, 140, 110, 255))
    # râu bạc + miệng
    for xx in range(8, 15):
        put(xx, 15, WHITE)
    put(11, 15, SKIN_D)
    for xx in range(9, 14):
        put(xx, 16, WHITE)
    for xx in range(10, 13):
        put(xx, 17, GREY)
    # cổ áo + hàng nút phía trước
    put(10, 18, SKIN_D)
    put(11, 18, SKIN)
    put(12, 18, SKIN_D)
    put(11, 19, SKIN_D)
    for yy in (21, 24, 27):
        put(11, yy, CREAM)
    for yy in range(19, 28):
        put(10, yy, SHIRT_L)
    # cần câu: từ tay phải (cột 18, hàng 27) chìa xuống phía nước (dưới-phải), dây thả xuống phao đỏ
    x0, y0 = 18, 27
    x1, y1 = 38, 46
    n = max(abs(x1 - x0), abs(y1 - y0))
    for t in range(n + 1):
        xx = round(x0 + (x1 - x0) * t / n)
        yy = round(y0 + (y1 - y0) * t / n)
        if 0 <= top + yy < img.shape[0] and xx < w:
            put(xx, yy, ROD if t > 3 else ROD_L)
            if t > 3 and top + yy + 1 < img.shape[0]:
                if img[top + yy + 1, xx, 3] == 0:
                    put(xx, yy + 1, OUTLINE)
    put(18, 27, SKIN)
    put(19, 27, SKIN_D)
    dip = 1 if k == 1 else 0
    for yy in range(y1 + 1, y1 + 6 + dip):
        if top + yy < img.shape[0]:
            put(x1 + 1, yy, LINE)
    by = y1 + 6 + dip
    if top + by + 1 < img.shape[0]:
        put(x1 + 1, by, RED)
        put(x1 + 1, by + 1, WHITE)
        put(x1, by + 1, RED)
        put(x1 + 2, by + 1, RED)
    ry = by + 2
    if top + ry < img.shape[0]:
        for xx in range(x1 - 3 - k, x1 + 6 + k):
            if xx < w and abs(xx - (x1 + 1)) >= 2:
                put(xx, ry, RIPPLE)
    return img


# ------------------------------------------------------------------ 4. vỏ lãi người chơi nhìn dọc

def build_player_boat_ns(out_dir):
    """player_boat_ns.png: [mũi lên | mũi xuống], mỗi ô 30 × 80. Thân dài 60, rộng 28; máy đuôi tôm + cần chân vịt."""
    W, L, TAIL = 30, 60, 18
    H = L + TAIL + 2
    up = np.zeros((H, W, 4), np.uint8)
    out_c = (42, 30, 46, 255)
    cream = (247, 237, 196, 255)
    cream_d = (222, 206, 160, 255)
    blue_l = (74, 147, 204, 255)
    blue = (44, 100, 168, 255)
    blue_d = (31, 63, 124, 255)
    floor_c = (100, 57, 47, 255)
    floor_l = (126, 74, 56, 255)
    rib = (182, 124, 70, 255)
    motor = (91, 90, 110, 255)
    motor_l = (177, 174, 170, 255)
    red = (194, 44, 52, 255)
    cx = W / 2.0
    for row in range(L):
        t = row / (L - 1)
        if t < 0.38:
            half = 13.0 * (t / 0.38) ** 0.55
        elif t > 0.92:
            half = 13.0 - (t - 0.92) * 40.0
        else:
            half = 13.0
        half = max(half, 1.0)
        xa = int(np.floor(cx - half))
        xb = int(np.ceil(cx + half)) - 1
        for x in range(xa, xb + 1):
            e = min(x - xa, xb - x)
            if e == 0 or row == 0 or row == L - 1:
                c = out_c
            elif t < 0.16:
                c = blue_l if x < cx else blue  # mũi sơn xanh như boat_01
            elif e == 1:
                c = blue_l if x < cx else blue_d
            elif e == 2:
                c = cream if x < cx else cream_d
            elif e == 3:
                c = out_c if row > 0.16 * L else blue
            else:
                c = rib if row % 10 == 4 else (floor_l if x < cx - 2 else floor_c)
            up[row, x] = c
        # mũi nhọn cong: viền sáng
    up[1:4, int(cx) - 1:int(cx) + 1] = blue_l
    # ghế ngang giữa thuyền
    for x in range(int(cx) - 9, int(cx) + 10):
        if up[30, x, 3]:
            up[30, x] = rib
            up[31, x] = out_c
    # máy + cần đuôi tôm ở đuôi
    my = L - 7
    for y in range(my, my + 8):
        for x in range(int(cx) - 4, int(cx) + 4):
            c = motor
            if y in (my, my + 7) or x in (int(cx) - 4, int(cx) + 3):
                c = out_c
            elif y == my + 1:
                c = motor_l
            elif y == my + 4 and int(cx) - 3 < x < int(cx) + 2:
                c = red
            up[y, x] = c
    for k in range(TAIL):
        x = int(cx) + 1 + k // 6
        y = my + 8 + k
        if y < H and x + 1 < W:
            up[y, x] = out_c
            up[y, x + 1] = motor_l if k % 2 == 0 else out_c
    down = up[::-1].copy()
    # nhìn từ đuôi lên (mũi xuống): đổi sáng/tối hai mạn cho nắng vẫn chiếu từ trái
    sheet = np.zeros((H, W * 2, 4), np.uint8)
    sheet[:, :W] = up
    sheet[:, W:] = down
    path = os.path.join(out_dir, "player_boat_ns.png")
    Image.fromarray(sheet, "RGBA").save(path, optimize=True)
    return path


# ------------------------------------------------------------------ chạy

def apply(out_dir, log=print):
    tpath = os.path.join(out_dir, "traffic.json")
    with open(tpath, encoding="utf8") as f:
        data = json.load(f)
    before, after = fix_water(out_dir, data)
    log("fixes: nước %d → %d px (lấp dưới %d cầu)" % (before, after, len(data.get("bridges", []))))
    changed = seat_boats(out_dir, data)
    log("fixes: vỏ lãi ngồi trên mặt nước: %s" % (", ".join(changed) or "đã áp trước đó"))
    with open(tpath, "w", encoding="utf8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    log("fixes: %s" % build_fisher(out_dir))
    log("fixes: %s" % build_player_boat_ns(out_dir))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    apply(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR)
