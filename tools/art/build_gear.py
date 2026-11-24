# -*- coding: utf-8 -*-
"""Sinh lớp sprite trang bị (GDD 5.3) cho hai kit chiến kê – không có art vẽ tay nên dựng thủ tục từ mặt nạ bộ phận.

Đầu vào: game/art/<kit>_sheet.png, <kit>_mask.png (kênh R = mã bộ phận × 32: 1 đầu, 2 cổ, 3 thân+cánh, 4 đuôi,
5 chân, 6 hiệu ứng), <kit>.json.
Đầu ra: game/art/gear/<kit>_<item>.png – cùng bố cục ô 128×112 × 12 cột với sheet, nên shader rooster.gdshader lấy
mẫu bằng đúng UV của sprite (lật theo hướng nhìn, theo từng frame, không rung).

Cách dựng:
  * Mỗi frame ước lượng phép biến đổi cứng (xoay + tịnh tiến) từ frame tham chiếu (idle f1) sang frame đó cho ĐẦU
    (mặt nạ vai 1) và THÂN (vai 3) bằng tương quan FFT trên mặt nạ, quét góc 10° rồi tinh chỉnh 3°; góc 0 được ưu
    tiên khi khớp gần bằng (tránh rung). Đồ trên đầu (mũ, khăn, nón) vẽ một lần trong toạ độ tham chiếu rồi biến đổi
    theo đầu → hình dạng không méo, đi theo mọi tư thế (kể cả nằm ngửa, văng).
  * Giáp/cánh/mào: tô theo TỪNG PIXEL của vùng thân / lông cánh cam / mào trong frame (khớp tuyệt đối với hoạt ảnh),
    hoa văn tính trong toạ độ tham chiếu của thân để không "trôi" khi gà di chuyển; đổ bóng theo độ sáng ảnh gốc.
  * Cựa / dao chân: phân tích từng cụm pixel chân, tìm bàn chân theo hướng "xuống" của thân, gắn lưỡi ra phía sau.
  * Quạt lông: gắn ở cụm lông cánh (đi theo cú tát cánh), nón bảo hiểm: theo đầu.
  * Frame chớp trắng có sẵn trong art (trúng đòn) → lớp trang bị cũng trắng.
Màu theo chất liệu (tầng giá): tre · sắt · đồng · thép · bạc · vàng. Mào cắt gọn dùng màu khoá magenta (255,0,255)
để shader XOÁ phần mào gốc bị cắt.

Chạy: python tools/art/build_gear.py   (Pillow + numpy). Xem thêm game/battle/fighter_view.gd (GEAR_*).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "game", "art")
OUT = os.path.join(ART, "gear")
W, H, COLS = 128, 112, 12

OUTLINE = (24, 18, 28)
ERASE = (255, 0, 255)

# Chất liệu: (sáng, giữa, tối) – tầng giá = màu.
MAT = {
    "tre": ((222, 200, 118), (168, 146, 72), (98, 84, 40)),
    "sat": ((178, 184, 192), (116, 122, 132), (60, 64, 74)),
    "dong": ((240, 178, 96), (184, 114, 52), (104, 60, 30)),
    "thep": ((214, 228, 242), (134, 150, 172), (64, 74, 94)),
    "bac": ((248, 250, 255), (188, 198, 212), (100, 108, 124)),
    "vang": ((255, 230, 110), (222, 168, 44), (134, 88, 20)),
    "lua": ((252, 196, 120), (206, 48, 52), (122, 20, 34)),
    "gio": ((236, 250, 255), (150, 210, 236), (70, 130, 168)),
    "meo": ((150, 120, 190), (60, 44, 82), (22, 16, 34)),
    "do": ((255, 120, 100), (210, 40, 36), (120, 16, 22)),
    "go": ((176, 120, 70), (120, 76, 40), (70, 42, 22)),
}


# ------------------------------------------------------------------ đọc dữ liệu

def load_kit(kit):
    sheet = np.array(Image.open(os.path.join(ART, kit + "_sheet.png")).convert("RGBA")).astype(np.int32)
    mask = np.array(Image.open(os.path.join(ART, kit + "_mask.png")).convert("RGBA")).astype(np.int32)
    with open(os.path.join(ART, kit + ".json"), encoding="utf-8") as f:
        meta = json.load(f)
    return sheet, mask, meta


def cell(arr, frame):
    x = ((frame - 1) % COLS) * W
    y = ((frame - 1) // COLS) * H
    return arr[y:y + H, x:x + W]


def roles(m):
    r = (m[:, :, 0] + 16) // 32
    r[m[:, :, 3] == 0] = 0
    return r


def hsv(c):
    rgb = c[:, :, :3].astype(np.float64) / 255.0
    mx = rgb.max(2)
    mn = rgb.min(2)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    idx = nz & (mx == r)
    h[idx] = ((g - b)[idx] / d[idx]) % 6.0
    idx = nz & (mx == g) & ~(mx == r)
    h[idx] = (b - r)[idx] / d[idx] + 2.0
    idx = nz & (mx == b) & ~(mx == r) & ~(mx == g)
    h[idx] = (r - g)[idx] / d[idx] + 4.0
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def luma(c):
    return (0.3 * c[:, :, 0] + 0.59 * c[:, :, 1] + 0.11 * c[:, :, 2]) / 255.0


# ------------------------------------------------------------------ ước lượng tư thế

def rot(pts, ang, piv):
    c, s = math.cos(ang), math.sin(ang)
    d = pts - piv
    return np.stack([d[:, 0] * c - d[:, 1] * s, d[:, 0] * s + d[:, 1] * c], 1) + piv


def match(ref_mask, frame_mask, angles):
    """Phép biến đổi tốt nhất ref → frame: p = R(a)(q − piv) + piv + t. Trả về (iou, a, t, piv)."""
    ys, xs = np.nonzero(ref_mask)
    pts = np.stack([xs, ys], 1).astype(np.float64)
    piv = pts.mean(0)
    fr = frame_mask.astype(np.float64)
    n_fr = fr.sum()
    F = np.fft.rfft2(fr, s=(H * 2, W * 2))
    best = None
    for ang in angles:
        rp = np.round(rot(pts, ang, piv)).astype(int)
        mn = rp.min(0)
        rp2 = rp - mn
        img = np.zeros((H * 2, W * 2))
        ok = (rp2[:, 0] < W * 2) & (rp2[:, 1] < H * 2)
        img[rp2[ok, 1], rp2[ok, 0]] = 1.0
        nr = img.sum()
        G = np.fft.rfft2(img, s=(H * 2, W * 2))
        corr = np.fft.irfft2(F * np.conj(G), s=(H * 2, W * 2))
        dy, dx = np.unravel_index(np.argmax(corr), corr.shape)
        val = corr[dy, dx]
        if dy >= H:
            dy -= H * 2
        if dx >= W:
            dx -= W * 2
        iou = val / max(nr + n_fr - val, 1.0)
        if best is None or iou > best[0]:
            best = (iou, ang, np.array([dx - mn[0], dy - mn[1]], dtype=np.float64), piv)
    return best


def estimate(ref_mask, frame_mask):
    if frame_mask.sum() < ref_mask.sum() * 0.2:
        return None
    coarse = match(ref_mask, frame_mask, [math.radians(a) for a in range(-180, 180, 10)])
    fine = match(ref_mask, frame_mask, [coarse[1] + math.radians(d) for d in (-6, -3, 3, 6)])
    best = fine if fine[0] > coarse[0] else coarse
    zero = match(ref_mask, frame_mask, [0.0])
    if zero[0] >= best[0] - 0.05:
        best = zero
    return {"ang": best[1], "t": best[2], "piv": best[3], "iou": best[0]}


def to_ref(tf, px, py):
    """Toạ độ frame → toạ độ tham chiếu."""
    c, s = math.cos(-tf["ang"]), math.sin(-tf["ang"])
    dx = px - tf["piv"][0] - tf["t"][0]
    dy = py - tf["piv"][1] - tf["t"][1]
    return dx * c - dy * s + tf["piv"][0], dx * s + dy * c + tf["piv"][1]


def to_frame(tf, qx, qy):
    c, s = math.cos(tf["ang"]), math.sin(tf["ang"])
    dx = qx - tf["piv"][0]
    dy = qy - tf["piv"][1]
    return dx * c - dy * s + tf["piv"][0] + tf["t"][0], dx * s + dy * c + tf["piv"][1] + tf["t"][1]


def direction(tf, vx, vy):
    c, s = math.cos(tf["ang"]), math.sin(tf["ang"])
    return np.array([vx * c - vy * s, vx * s + vy * c])


# ------------------------------------------------------------------ vẽ

def shade(mat, t):
    light, mid, dark = MAT[mat]
    if t > 0.66:
        return light
    if t > 0.33:
        return mid
    return dark


def add_outline(layer, keep=None):
    """Viền 1 px tối quanh các pixel của lớp (không đè lên pixel đã có)."""
    a = layer[:, :, 3] > 0
    grow = np.zeros_like(a)
    grow[1:, :] |= a[:-1, :]
    grow[:-1, :] |= a[1:, :]
    grow[:, 1:] |= a[:, :-1]
    grow[:, :-1] |= a[:, 1:]
    edge = grow & ~a
    if keep is not None:
        edge &= keep
    layer[edge] = OUTLINE + (255,)


def stamp_design(layer, design, tf):
    """Biến đổi một thiết kế trong toạ độ tham chiếu (dict (x, y) → rgba) sang frame (lấy mẫu gần nhất)."""
    if not design or tf is None:
        return
    pts = np.array(list(design.keys()), dtype=np.float64)
    corners = [to_frame(tf, x, y) for x, y in pts]
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    x0, x1 = int(math.floor(min(xs))) - 2, int(math.ceil(max(xs))) + 2
    y0, y1 = int(math.floor(min(ys))) - 2, int(math.ceil(max(ys))) + 2
    for py in range(max(0, y0), min(H, y1 + 1)):
        for px in range(max(0, x0), min(W, x1 + 1)):
            qx, qy = to_ref(tf, px, py)
            key = (int(round(qx)), int(round(qy)))
            if key in design:
                layer[py, px] = design[key]


# ------------------------------------------------------------------ hình học tham chiếu

class Kit:
    def __init__(self, name):
        self.name = name
        self.sheet, self.mask, self.meta = load_kit(name)
        self.count = int(self.meta["count"])
        ref_c = cell(self.sheet, 1)
        ref_r = roles(cell(self.mask, 1))
        self.ref_head = ref_r == 1
        self.ref_body = ref_r == 3
        if name == "rooster":
            white = self.ref_head & (ref_c[:, :, 0] > 245) & (ref_c[:, :, 1] > 245) & (ref_c[:, :, 2] > 245)
            ey, ex = np.nonzero(white)
            self.eye = (int(round(ex.mean())), int(round(ey.mean())))
        else:
            yel = self.ref_head & (np.abs(ref_c[:, :, 0] - 240) < 6) & (np.abs(ref_c[:, :, 1] - 196) < 6)
            ey, ex = np.nonzero(yel)
            i = int(np.argmin(ex))
            self.eye = (int(ex[i]), int(ey[i]))
        hy, hx = np.nonzero(self.ref_head)
        self.head_box = (hx.min(), hy.min(), hx.max(), hy.max())
        by, bx = np.nonzero(self.ref_body)
        self.body_box = (bx.min(), by.min(), bx.max(), by.max())
        self.frames = []
        for f in range(1, self.count + 1):
            c = cell(self.sheet, f)
            r = roles(cell(self.mask, f))
            vis = c[:, :, 3] > 0
            white = vis & (c[:, :, 0] > 240) & (c[:, :, 1] > 240) & (c[:, :, 2] > 240)
            flash = vis.sum() > 0 and white.sum() > 0.45 * vis.sum()
            self.frames.append({
                "c": c, "r": r, "flash": flash,
                "head": estimate(self.ref_head, r == 1),
                "body": estimate(self.ref_body, r == 3),
            })
        print("%s: %d frames posed" % (name, self.count))

    # Vòm mũ tham chiếu: nửa elip ngồi trên đường mày, phủ mào.
    def dome(self, pad_x=1, extra_top=0, brow=2):
        ex, ey = self.eye
        top = self.head_box[1] - 1 - extra_top
        above = self.ref_head.copy()
        above[ey - brow + 1:, :] = False
        ys, xs = np.nonzero(above)
        left = xs.min() - pad_x
        right = min(xs.max() + pad_x, ex + 4)
        cx = (left + right) / 2.0
        rx = (right - left) / 2.0 + 0.5
        bottom = ey - brow
        top = max(top, bottom - int(rx * 0.9) - extra_top)   # mũ thấp, mào gà rừng cao thì ló lên như chỏm
        ry = max(bottom - top, 3) + 0.5
        pts = []
        for y in range(top, bottom + 1):
            for x in range(int(left) - 1, int(right) + 2):
                if ((x - cx) / rx) ** 2 + ((y - bottom) / ry) ** 2 <= 1.0:
                    pts.append((x, y))
        return pts, (cx, rx, top, bottom)


# ------------------------------------------------------------------ đồ ô Đầu (thiết kế trong toạ độ đầu)

def design_dome(kit, mat, rivets=False, visor=False, nape=0, extra_top=0, stripe=None):
    pts, (cx, rx, top, bottom) = kit.dome(extra_top=extra_top)
    ex, ey = kit.eye
    d = {}
    span = max(bottom - top, 1)
    for x, y in pts:
        v = (bottom - y) / span                     # 0 ở vành, 1 ở đỉnh
        u = (x - cx) / max(rx, 1.0)                  # −1 sau … 1 trước
        t = 0.35 + 0.45 * v - 0.25 * u
        if y >= bottom - 1:
            t = 0.2                                  # vành tối
        col = shade(mat, t)
        if stripe is not None and abs(x - (cx + 1)) <= 1 and y < bottom - 1:
            col = stripe
        d[(x, y)] = col + (255,)
    # Ánh sáng đỉnh mũ.
    for x, y in pts:
        if y == top + 1 and abs(x - (cx - rx * 0.25)) <= 1.5:
            d[(x, y)] = (MAT[mat][0] if mat not in ("thep", "bac", "sat") else (255, 255, 255)) + (255,)
    if rivets:
        for x in range(int(cx - rx) + 2, int(cx + rx), 3):
            if (x, bottom - 1) in d:
                d[(x, bottom - 1)] = (255, 255, 255, 255)
    if visor:
        for x in range(int(cx + rx) - 1, int(cx + rx) + 4):
            for y in (bottom - 1, bottom):
                d[(x, y)] = shade(mat, 0.25 if y == bottom else 0.5) + (255,)
    for k in range(nape):
        for x in range(int(cx - rx), int(cx - rx * 0.2)):
            d[(x, bottom + 1 + k)] = shade(mat, 0.3) + (255,)
    return d


def design_khan_ran(kit):
    ex, ey = kit.eye
    left = kit.head_box[0] + (2 if kit.name == "rooster" else 0)
    d = {}
    for y in range(ey - 5, ey - 1):
        for x in range(left, ex + 3):
            if kit.ref_head[y, x] or kit.ref_head[min(y + 1, H - 1), x]:
                checker = ((x // 2) + (y // 2)) % 2 == 0
                d[(x, y)] = ((236, 232, 220) if checker else (28, 24, 30)) + (255,)
    # Hai đuôi khăn bay ra sau.
    kx, ky = left - 1, ey - 4
    for tail, (dx, dy) in enumerate([(-1, 0.45), (-1, 0.9)]):
        for k in range(7 - tail):
            x = int(round(kx + dx * k))
            y = int(round(ky + dy * k + tail))
            for w in range(2):
                checker = ((k // 2) + w + tail) % 2 == 0
                d[(x, y + w)] = ((236, 232, 220) if checker else (28, 24, 30)) + (255,)
    # Nút thắt.
    d[(kx, ky)] = (180, 40, 40, 255)
    d[(kx + 1, ky)] = (180, 40, 40, 255)
    return d


def design_khan_meo(kit):
    pts, (cx, rx, top, bottom) = kit.dome(extra_top=1, pad_x=2)
    ex, ey = kit.eye
    d = {}
    for x, y in pts:
        t = 0.3 + 0.4 * (bottom - y) / max(bottom - top, 1)
        d[(x, y)] = shade("meo", t) + (255,)
    # Tai mèo.
    for ear_x in (cx - rx * 0.55, cx + rx * 0.35):
        for k in range(5):
            for w in range(-(4 - k) // 2, (4 - k) // 2 + 1):
                x = int(round(ear_x + w))
                y = top - k
                inner = abs(w) < (4 - k) // 2 - 0 and k < 3
                d[(x, y)] = ((236, 140, 170) if inner else MAT["meo"][2]) + (255,)
    # Mắt mèo thêu trên mũ trùm.
    d[(int(cx) - 1, top + 3)] = (250, 220, 90, 255)
    d[(int(cx) + 2, top + 3)] = (250, 220, 90, 255)
    return d


def design_non_bao_hiem(kit):
    """Nón bảo hiểm xe máy nửa đầu: vỏ đỏ, sọc trắng giữa, kính chắn gió nhỏ, quai đen."""
    pts, (cx, rx, top, bottom) = kit.dome(extra_top=2, pad_x=2, brow=1)
    ex, ey = kit.eye
    d = {}
    for x, y in pts:
        v = (bottom - y) / max(bottom - top, 1)
        u = (x - cx) / max(rx, 1.0)
        t = 0.38 + 0.45 * v - 0.2 * u
        col = shade("do", t)
        if abs(x - cx) <= 1 and y < bottom:
            col = (246, 246, 240)
        if y == bottom:
            col = (40, 36, 44)
        d[(x, y)] = col + (255,)
    for x in range(int(cx - rx * 0.35), int(cx - rx * 0.35) + 3):
        d[(x, top + 2)] = (255, 255, 255, 255)
    # Kính chắn gió (lưỡi trai trong suốt màu khói).
    for x in range(int(cx + rx) - 1, int(cx + rx) + 4):
        d[(x, bottom)] = (90, 150, 190, 255)
        d[(x, bottom - 1)] = (150, 200, 230, 255)
    # Quai cài dưới cằm.
    for k in range(1, 7):
        d[(ex - 3, bottom + k)] = (30, 26, 34, 255)
    d[(ex - 2, bottom + 6)] = (200, 200, 210, 255)
    return d


def design_mao_sat(kit, frame_comb_ref):
    """Mào sắt: lá sắt ốp đúng hình mào tham chiếu (có đinh tán)."""
    d = {}
    for (x, y) in frame_comb_ref:
        t = 0.75 - 0.08 * (y - kit.head_box[1])
        d[(x, y)] = shade("sat", t) + (255,)
    ys = [p[1] for p in frame_comb_ref]
    if ys:
        base = max(ys)
        xs = sorted(p[0] for p in frame_comb_ref if p[1] == base)
        for x in xs[::3]:
            d[(x, base)] = (255, 255, 255, 255)
    return d


# ------------------------------------------------------------------ dựng từng món

def comb_pixels(kit, fr):
    """Mào trong frame: pixel vai đầu màu đỏ ở trên đường mắt (theo toạ độ tham chiếu của đầu)."""
    tf = fr["head"]
    if tf is None:
        return []
    c = fr["c"]
    h, s, v = hsv(c)
    red = (fr["r"] == 1) & ((h < 0.045) | (h > 0.93)) & (s > 0.4) & (v > 0.3)
    if kit.name == "dongtao":
        red = (fr["r"] == 1) & (v > 0.3) & ~((np.abs(c[:, :, 0] - 240) < 8) & (np.abs(c[:, :, 1] - 196) < 8))
    ex, ey = kit.eye
    out = []
    ys, xs = np.nonzero(red)
    for x, y in zip(xs, ys):
        qx, qy = to_ref(tf, x, y)
        lim = ey - 2 if kit.name == "rooster" else kit.head_box[1] + 4
        if qy < lim and qx < ex + 4:
            out.append((x, y, qx, qy))
    return out


def ref_comb(kit):
    fr = kit.frames[0]
    return [(int(round(qx)), int(round(qy))) for (_, _, qx, qy) in comb_pixels(kit, fr)]


def render_comb(kit, fr, layer, item):
    pix = comb_pixels(kit, fr)
    if not pix:
        return
    c = fr["c"]
    lum = luma(c)
    top_ref = min(p[3] for p in pix)
    bot_ref = max(p[3] for p in pix)
    cut = top_ref + (bot_ref - top_ref) * 0.5
    for x, y, qx, qy in pix:
        if item == "mao_cat":
            if qy < cut:
                layer[y, x] = ERASE + (255,)
            else:
                layer[y, x] = shade("do", 0.25 + lum[y, x] * 0.9) + (255,)
        elif item == "mao_dong":
            layer[y, x] = shade("dong", 0.15 + lum[y, x] * 1.3) + (255,)
        elif item == "mao_vang_meo":
            layer[y, x] = shade("vang", 0.2 + lum[y, x] * 1.3) + (255,)
    if item == "mao_cat":
        # Xoá luôn nét viền tối của phần mào bị cắt.
        tf = fr["head"]
        xs_ref = [p[2] for p in pix]
        x_lo, x_hi = min(xs_ref) - 1, max(xs_ref) + 1
        hy, hx = np.nonzero(fr["r"] == 1)
        for x, y in zip(hx, hy):
            qx, qy = to_ref(tf, x, y)
            if qy < cut and x_lo <= qx <= x_hi:
                layer[y, x] = ERASE + (255,)
        # Viền gọn trên mép cắt.
        for x, y, qx, qy in pix:
            if qy >= cut and (y - 1 >= 0) and tuple(layer[y - 1, x, :3]) == ERASE:
                layer[y, x] = (110, 20, 30, 255)
    else:
        # Mép trên sáng (kim loại).
        for x, y, qx, qy in pix:
            if y > 0 and layer[y - 1, x, 3] == 0 and fr["r"][y - 1, x] != 1:
                layer[y, x] = (255, 255, 230, 255) if item == "mao_vang_meo" else MAT["dong"][0] + (255,)
        if item == "mao_vang_meo" and fr["head"] is not None:
            # Hai đốm lấp lánh cố định theo toạ độ đầu.
            for k, (x, y, qx, qy) in enumerate(sorted(pix, key=lambda p: (p[3], p[2]))[:12]):
                if k in (2, 9):
                    layer[y, x] = (255, 255, 255, 255)
        add_outline(layer, keep=fr["c"][:, :, 3] == 0)


def body_ref_coords(kit, fr, mask):
    ys, xs = np.nonzero(mask)
    tf = fr["body"]
    out = []
    for x, y in zip(xs, ys):
        if tf is None:
            out.append((x, y, float(x), float(y)))
        else:
            qx, qy = to_ref(tf, x, y)
            out.append((x, y, qx, qy))
    return out


def render_armor(kit, fr, layer, item):
    c = fr["c"]
    body = fr["r"] == 3
    v = hsv(c)[2]
    body &= v > 0.13                      # giữ nét viền đen của art
    lum = luma(c)
    up = direction(fr["body"], 0, -1) if fr["body"] is not None else np.array([0.0, -1.0])
    for x, y, qx, qy in body_ref_coords(kit, fr, body):
        qx_i, qy_i = int(math.floor(qx)), int(math.floor(qy))
        base = 0.2 + lum[y, x] * 0.95
        if item == "giap_tre":
            slat = qx_i % 4
            node = (qy_i + (qx_i // 4) * 3) % 9 == 0
            t = base + (0.18 if slat == 1 else 0.0)
            col = shade("tre", t)
            if slat == 0 or node:
                col = MAT["tre"][2]
        elif item == "giap_dong":
            row = qy_i // 3
            xx = (qx_i + (row % 2) * 2) % 4
            yy = qy_i % 3
            t = base + (0.2 if yy == 0 else 0.0) - (0.3 if yy == 2 and xx in (0, 3) else 0.0)
            col = shade("dong", t)
            if yy == 2 and xx in (1, 2):
                col = MAT["dong"][2]
        else:  # giap_thep
            band = qy_i % 5
            t = base + (0.25 if band == 1 else 0.0)
            col = shade("thep", t)
            if band == 0:
                col = MAT["thep"][2]
            if band == 2 and qx_i % 6 == 1:
                col = (255, 255, 255)
        # Viền sáng phía trên (rim light).
        nx, ny = int(round(x + up[0])), int(round(y + up[1]))
        if 0 <= nx < W and 0 <= ny < H and fr["r"][ny, nx] != 3:
            col = MAT["thep" if item == "giap_thep" else ("dong" if item == "giap_dong" else "tre")][0]
            if item == "giap_thep":
                col = (255, 255, 255)
        layer[y, x] = col + (255,)


def wing_mask(fr):
    c = fr["c"]
    body = fr["r"] == 3
    org = body & (c[:, :, 0] > 200) & (c[:, :, 1] > 90) & (c[:, :, 1] < 180) & (c[:, :, 2] < 120)
    grow = org.copy()
    grow[1:, :] |= org[:-1, :]
    grow[:-1, :] |= org[1:, :]
    grow[:, 1:] |= org[:, :-1]
    grow[:, :-1] |= org[:, 1:]
    v = hsv(c)[2]
    return grow & body & (v > 0.13)


def render_wing(kit, fr, layer, item):
    c = fr["c"]
    lum = luma(c)
    wm = wing_mask(fr)
    for x, y, qx, qy in body_ref_coords(kit, fr, wm):
        qx_i, qy_i = int(math.floor(qx)), int(math.floor(qy))
        base = 0.15 + lum[y, x] * 1.0
        if item == "canh_lua":
            base = 0.2 + lum[y, x] * 0.55
            col = shade("lua", base)
            if (qx_i + qy_i) % 5 == 0:
                col = (255, 214, 110)
        elif item == "canh_gio":
            col = shade("gio", base + 0.1)
            if (qx_i - qy_i) % 4 == 0:
                col = (255, 255, 255)
        elif item == "canh_sat":
            col = shade("sat", base)
            if qy_i % 3 == 0:
                col = MAT["sat"][2]
            if qy_i % 3 == 1 and qx_i % 5 == 2:
                col = (255, 255, 255)
        else:  # canh_meo
            col = shade("meo", base)
            if qx_i % 5 == 1 and qy_i % 4 == 1:
                col = (236, 140, 170)
        layer[y, x] = col + (255,)
    if item == "canh_gio" and fr["body"] is not None and wm.sum() > 6:
        # Hai dải lông gió bay ra sau mép cánh.
        back = direction(fr["body"], -1, 0)
        ys, xs = np.nonzero(wm)
        proj = xs * back[0] + ys * back[1]
        order = np.argsort(-proj)[:2]
        for k, i in enumerate(order):
            for s in range(1, 6 - k):
                px = int(round(xs[i] + back[0] * s))
                py = int(round(ys[i] + back[1] * s + k))
                if 0 <= px < W and 0 <= py < H and c[py, px, 3] == 0:
                    layer[py, px] = ((255, 255, 255) if s % 2 else MAT["gio"][1]) + (255,)


def legs(fr):
    """Các cụm pixel chân (≥ 6 px): danh sách mảng (N, 2) x, y."""
    m = fr["r"] == 5
    seen = np.zeros_like(m)
    out = []
    ys, xs = np.nonzero(m)
    for sx, sy in zip(xs, ys):
        if seen[sy, sx]:
            continue
        stack = [(sx, sy)]
        seen[sy, sx] = True
        comp = []
        while stack:
            x, y = stack.pop()
            comp.append((x, y))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((nx, ny))
        if len(comp) >= 6:
            out.append(np.array(comp))
    return out


def blade(layer, start, back, down, length, mat, curve=0.0, thick=1, glint=True):
    pts = []
    for k in range(1, length + 1):
        lift = -0.35 * k + curve * k * k
        x = start[0] + back[0] * k + down[0] * lift
        y = start[1] + back[1] * k + down[1] * lift
        pts.append((int(round(x)), int(round(y)), k))
    blade_layer = np.zeros_like(layer)
    for x, y, k in pts:
        for w in range(thick if k < length - 1 else 1):
            px, py = int(round(x + down[0] * w)), int(round(y + down[1] * w))
            if 0 <= px < W and 0 <= py < H:
                edge = w == 0
                col = MAT[mat][0] if edge else MAT[mat][1]
                if glint and edge and k in (length // 2, length // 2 + 1):
                    col = (255, 255, 255)
                blade_layer[py, px] = col + (255,)
    add_outline(blade_layer)
    a = blade_layer[:, :, 3] > 0
    layer[a] = blade_layer[a]


def leg_anchor(fr, comp):
    down = direction(fr["body"], 0, 1) if fr["body"] is not None else np.array([0.0, 1.0])
    back = direction(fr["body"], -1, 0) if fr["body"] is not None else np.array([-1.0, 0.0])
    proj = comp[:, 0] * down[0] + comp[:, 1] * down[1]
    foot = comp[np.argmax(proj)]
    a = foot - down * 4.0
    # Trượt ra mép sau của ống chân.
    pset = {(int(p[0]), int(p[1])) for p in comp}
    p = a.copy()
    for _ in range(8):
        q = p + back
        if (int(round(q[0])), int(round(q[1]))) not in pset:
            break
        p = q
    return np.array([round(p[0]), round(p[1])]), back, down


def render_spur(kit, fr, layer, item):
    if fr["body"] is None:
        return
    mat = {"cua_tre": "tre", "cua_sat": "sat", "cua_dong": "dong", "cua_bac": "bac"}[item]
    length = {"cua_tre": 4, "cua_sat": 5, "cua_dong": 5, "cua_bac": 6}[item]
    for comp in legs(fr):
        start, back, down = leg_anchor(fr, comp)
        blade(layer, start, back, down, length, mat, curve=0.02, thick=2 if item != "cua_tre" else 1,
              glint=item in ("cua_bac", "cua_dong"))


def render_dao_chan(kit, fr, layer):
    if fr["body"] is None:
        return
    comps = legs(fr)
    if not comps:
        return
    fwd = direction(fr["body"], 1, 0)
    comp = max(comps, key=lambda cp: float((cp[:, 0] * fwd[0] + cp[:, 1] * fwd[1]).mean()))
    start, back, down = leg_anchor(fr, comp)
    blade(layer, start + down * 1.0, back, down, 8, "thep", curve=0.045, thick=2)
    # Dây buộc đỏ quấn ống chân.
    for k in range(-1, 2):
        p = start - back * (1 + k) - down * 1.0
        x, y = int(round(p[0])), int(round(p[1]))
        if 0 <= x < W and 0 <= y < H and fr["r"][y, x] == 5:
            layer[y, x] = (214, 36, 40, 255)


def render_fan(kit, fr, layer):
    tf = fr["body"]
    if tf is None:
        return
    wm = wing_mask(fr)
    fwd = direction(tf, 1, 0)
    up = direction(tf, 0, -1)
    bx0, by0, bx1, by1 = kit.body_box
    anchor = np.array(to_frame(tf, (bx0 + bx1) * 0.5 + 4, by0 + 12))
    body_ys, body_xs = np.nonzero(fr["r"] == 3)
    if len(body_xs):
        reach = float((body_xs * fwd[0] + body_ys * fwd[1]).max())
        ref_reach = float(np.array(to_frame(tf, bx1, (by0 + by1) * 0.5)) @ fwd)
        if reach > ref_reach + 8 and wm.sum() >= 4:
            # Cánh đang tát ra trước (Tát Cánh): quạt theo đầu cánh.
            ys, xs = np.nonzero(wm)
            proj = xs * fwd[0] + ys * fwd[1]
            i = int(np.argmax(proj))
            anchor = np.array([xs[i], ys[i]], dtype=np.float64)
    radius = 9.5
    fan = np.zeros_like(layer)
    for py in range(max(0, int(anchor[1] - radius - 2)), min(H, int(anchor[1] + radius + 3))):
        for px in range(max(0, int(anchor[0] - radius - 2)), min(W, int(anchor[0] + radius + 3))):
            d = np.array([px - anchor[0], py - anchor[1]])
            r = float(np.hypot(d[0], d[1]))
            if r > radius or r < 1.0:
                continue
            fx = float(d @ fwd)
            fy = float(d @ up)
            ang = math.degrees(math.atan2(fy, fx))     # 0 = phía trước, 90 = phía trên
            if ang < -15 or ang > 120:
                continue
            spoke = int((ang + 15) // 15)
            scallop = r > radius - 1.5 - (0.8 if spoke % 2 else 0.0)
            col = (250, 246, 232) if spoke % 2 == 0 else (226, 214, 190)
            if abs(((ang + 15) % 15) - 7.5) < 1.2 and r < radius - 1:
                col = (150, 100, 60)                   # sống lông
            if scallop:
                col = (196, 168, 120)
            fan[py, px] = col + (255,)
    # Cán quạt.
    for k in range(0, 5):
        p = anchor - fwd * (k * 0.6) - up * (k * 0.8) * -1
        x, y = int(round(p[0])), int(round(p[1]))
        if 0 <= x < W and 0 <= y < H:
            fan[y, x] = MAT["go"][1] + (255,)
    add_outline(fan)
    a = fan[:, :, 3] > 0
    layer[a] = fan[a]


# ------------------------------------------------------------------ chạy

HEAD_ITEMS = ["mao_sat", "khan_ran", "mu_dong", "mu_thep", "khan_meo"]
ARMOR_ITEMS = ["giap_tre", "giap_dong", "giap_thep"]
WING_ITEMS = ["canh_lua", "canh_gio", "canh_sat", "canh_meo"]
SPUR_ITEMS = ["cua_tre", "cua_sat", "cua_dong", "cua_bac"]
COMB_ITEMS = ["mao_cat", "mao_dong", "mao_vang_meo"]
WEAPON_ITEMS = ["dao_chan", "quat_long", "non_bao_hiem"]
ALL_ITEMS = HEAD_ITEMS + ARMOR_ITEMS + WING_ITEMS + SPUR_ITEMS + COMB_ITEMS + WEAPON_ITEMS


def head_design(kit, item):
    if item == "mao_sat":
        return design_mao_sat(kit, ref_comb(kit))
    if item == "khan_ran":
        return design_khan_ran(kit)
    if item == "mu_dong":
        return design_dome(kit, "dong", rivets=False)
    if item == "mu_thep":
        return design_dome(kit, "thep", rivets=True, visor=True, nape=2, extra_top=1)
    if item == "khan_meo":
        return design_khan_meo(kit)
    if item == "non_bao_hiem":
        return design_non_bao_hiem(kit)
    return {}


def build(kit, item):
    rows = (kit.count + COLS - 1) // COLS
    sheet = np.zeros((rows * H, COLS * W, 4), dtype=np.uint8)
    design = None
    if item in HEAD_ITEMS or item == "non_bao_hiem":
        design = head_design(kit, item)
        lay = np.zeros((H, W, 4), dtype=np.int32)
        for (x, y), col in design.items():
            if 0 <= x < W and 0 <= y < H:
                lay[y, x] = col
        add_outline(lay)
        design = {(x, y): tuple(int(v) for v in lay[y, x]) for y, x in zip(*np.nonzero(lay[:, :, 3]))}
    for f in range(1, kit.count + 1):
        fr = kit.frames[f - 1]
        layer = np.zeros((H, W, 4), dtype=np.int32)
        if (fr["r"] == 6).sum() > 0.6 * max((fr["r"] > 0).sum(), 1):
            pass  # frame hiệu ứng (lông bay) – không có gà
        elif design is not None:
            stamp_design(layer, design, fr["head"])
        elif item in ARMOR_ITEMS:
            render_armor(kit, fr, layer, item)
        elif item in WING_ITEMS:
            render_wing(kit, fr, layer, item)
        elif item in SPUR_ITEMS:
            render_spur(kit, fr, layer, item)
        elif item in COMB_ITEMS:
            render_comb(kit, fr, layer, item)
        elif item == "dao_chan":
            render_dao_chan(kit, fr, layer)
        elif item == "quat_long":
            render_fan(kit, fr, layer)
        if fr["flash"]:
            a = layer[:, :, 3] > 0
            keep_erase = (layer[:, :, 0] == 255) & (layer[:, :, 1] == 0) & (layer[:, :, 2] == 255)
            layer[a & ~keep_erase, :3] = 255
        x = ((f - 1) % COLS) * W
        y = ((f - 1) // COLS) * H
        sheet[y:y + H, x:x + W] = layer.astype(np.uint8)
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for name in ("rooster", "dongtao"):
        kit = Kit(name)
        for item in ALL_ITEMS:
            if only and item not in only:
                continue
            img = Image.fromarray(build(kit, item), "RGBA")
            path = os.path.join(OUT, "%s_%s.png" % (name, item))
            img.save(path, optimize=True)
            print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
