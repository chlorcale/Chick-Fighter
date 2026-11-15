# -*- coding: utf-8 -*-
"""Dựng ảnh sân đấu "Sới gà Ao Làng" (màn đánh nhau nhìn ngang) cho BattleArena.

Chạy:  python tools/art/build_arena.py            (ghi vào game/art/arena/)
       python tools/art/build_arena.py --preview <thư_mục>   (thêm ảnh xem trước ghép lớp)

Mọi ảnh vẽ ở "pixel ảnh"; trong game mỗi pixel ảnh = 2 pixel thế giới (PX = 2, lọc NEAREST).
Toạ độ thế giới: mặt đất (vạch chân gà) y = 0, sân 0..1000, mô phỏng kẹp x trong 32..968.
Các lớp tĩnh được nướng sẵn thành PNG để mỗi khung hình chỉ vài lệnh vẽ; phần động (cờ, lồng đèn,
tán cây, khói, ghe, khán giả) là sprite cắt từ hai atlas `arena_props.png` và `arena_crowd.png`.
Vị trí mọi phần tử phải khớp với hằng số trong game/battle/battle_arena.gd (ghi chú "khớp build_arena.py").

Tái dùng tranh thật của bản đồ (game/art/map/map_atlas_*.png + map_layers.json): tường đình, cây đa,
dừa, chuối, lồng đèn, dây cờ hội, cờ, băng rôn, cột điện, lư hương, khói bếp, ghế nhựa, vách nhà lá.
Không có số ngẫu nhiên không gieo hạt: chạy lại cho ra cùng một ảnh.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAP_DIR = os.path.join(ROOT, "game", "art", "map")
NPC_DIR = os.path.join(ROOT, "game", "art", "npc")
OUT_DIR = os.path.join(ROOT, "game", "art", "arena")

PX = 2  # 1 pixel ảnh = 2 pixel thế giới

# Lớp: (gốc thế giới x, y, rộng, cao theo pixel ảnh). Khớp LAYERS trong battle_arena.gd.
L_SKY = (-400, -1100, 900, 520)
L_FAR = (-400, -340, 900, 200)
L_MID = (-400, -520, 900, 240)
L_BUNT = (-400, -440, 900, 170)
L_STANDS = (-400, -240, 900, 96)
L_FENCE = (-400, -170, 900, 120)
L_FLOOR = (-400, -80, 900, 250)
L_FRONT = (-400, 20, 900, 120)

# Vòng sới (ellipse chân hàng rào phía sau) — khớp RING_* trong battle_arena.gd.
RING_CX, RING_CY, RING_RX, RING_RY = 500.0, 14.0, 700.0, 70.0

rng = np.random.default_rng(2026)


# ------------------------------------------------------------------ tiện ích

def rgba(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), int(a))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def new_layer(spec):
    return Image.new("RGBA", (spec[2], spec[3]), (0, 0, 0, 0))


def w2a(spec, wx, wy):
    """Toạ độ thế giới → pixel ảnh của lớp."""
    return int(round((wx - spec[0]) / PX)), int(round((wy - spec[1]) / PX))


def paste(dst, src, x, y):
    """Dán có alpha, cho phép toạ độ âm / tràn mép."""
    x, y = int(x), int(y)
    sx0, sy0 = max(0, -x), max(0, -y)
    sx1, sy1 = min(src.width, dst.width - x), min(src.height, dst.height - y)
    if sx1 <= sx0 or sy1 <= sy0:
        return
    part = src.crop((sx0, sy0, sx1, sy1))
    dst.alpha_composite(part, (x + sx0, y + sy0))


def rect(img, x, y, w, h, c, a=255):
    d = ImageDraw.Draw(img)
    if w <= 0 or h <= 0:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=rgba(c, a))


def blend_rect(img, x, y, w, h, c, a):
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rect(over, x, y, w, h, c, a)
    img.alpha_composite(over)


BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0


def dither_gradient(h, w, stops):
    """Dải màu dọc theo bậc + hoà trộn Bayer 4×4 giữa hai bậc (kiểu pixel-art)."""
    ys = np.linspace(0.0, 1.0, h)
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float32)
    out = np.zeros((h, w, 3), dtype=np.float32)
    levels = 7.0
    for y in range(h):
        k = np.interp(ys[y], pos, np.arange(len(stops)))
        i0 = int(math.floor(k))
        i1 = min(i0 + 1, len(stops) - 1)
        f = k - i0
        q = f * levels
        base = math.floor(q)
        frac = q - base
        row_thr = BAYER4[y % 4]
        thr = np.tile(row_thr, w // 4 + 1)[:w]
        step = base + (frac > thr).astype(np.float32)
        t = np.clip(step / levels, 0.0, 1.0)[:, None]
        out[y] = cols[i0] * (1 - t) + cols[i1] * t
    return out


def from_np(arr, alpha=None):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    if alpha is None:
        alpha = np.full(a.shape[:2], 255, np.uint8)
    return Image.fromarray(np.dstack([a, alpha.astype(np.uint8)]), "RGBA")


def haze(img, col, t, dark=1.0):
    """Làm mờ xa: trộn màu về `col` theo t, giữ alpha (khử bão hoà cho lớp sau)."""
    a = np.asarray(img).astype(np.float32)
    rgb = a[..., :3] * dark
    rgb = rgb + (np.array(col, np.float32) - rgb) * t
    a[..., :3] = rgb
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def outline(img, col, a=255):
    """Viền 1 px quanh vùng đặc (4 lân cận)."""
    arr = np.asarray(img).copy()
    m = arr[..., 3] > 0
    n = np.zeros_like(m)
    n[1:, :] |= m[:-1, :]
    n[:-1, :] |= m[1:, :]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    edge = n & ~m
    arr[edge] = rgba(col, a)
    return Image.fromarray(arr, "RGBA")


# ------------------------------------------------------------------ tranh bản đồ

class MapArt:
    def __init__(self):
        with open(os.path.join(MAP_DIR, "map_layers.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        self.atlases = [Image.open(os.path.join(MAP_DIR, n)).convert("RGBA") for n in data["atlases"]]
        self.nodes = {}
        for sec in ("below", "object", "above"):
            for e in data[sec]:
                if e.get("name"):
                    self.nodes[e["name"]] = e

    def frame(self, name, i=0):
        a, x, y, w, h = self.nodes[name]["regions"][i]
        return self.atlases[a].crop((x, y, x + w, y + h))

    def frames(self, name):
        """Trả về (ảnh các khung đã canh theo vị trí bản đồ, chuỗi thứ tự khung 96 bước × 80 ms)."""
        e = self.nodes[name]
        regs = e["regions"]
        seq = e.get("frames") or []
        pos = {}
        for f in seq:
            if f is not None and f[0] not in pos:
                pos[f[0]] = (f[1], f[2])
        for i in range(len(regs)):
            pos.setdefault(i, (0, 0))
        minx = min(pos[i][0] for i in range(len(regs)))
        miny = min(pos[i][1] for i in range(len(regs)))
        cw = max(pos[i][0] - minx + regs[i][3] for i in range(len(regs)))
        ch = max(pos[i][1] - miny + regs[i][4] for i in range(len(regs)))
        out = []
        for i in range(len(regs)):
            cell = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            cell.alpha_composite(self.frame(name, i), (pos[i][0] - minx, pos[i][1] - miny))
            out.append(cell)
        order = "".join(str(f[0]) if f is not None else "0" for f in seq) if seq else "0"
        return out, order


# ------------------------------------------------------------------ bảng màu

SKY_TOP = (86, 132, 196)
SKY_MID = (150, 178, 214)
SKY_PEACH = (244, 200, 156)
SKY_LOW = (252, 226, 176)
HAZE_FAR = (196, 196, 186)
HAZE_MID = (236, 210, 172)
HAZE_CROWD = (238, 214, 180)

TOI_TOP = (44, 46, 96)
TOI_MID = (104, 80, 128)
TOI_PEACH = (218, 120, 104)
TOI_LOW = (246, 170, 112)


# ------------------------------------------------------------------ lớp trời

def cloud_shape(w, h, seed):
    r = np.random.default_rng(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    puffs = []
    n = max(3, w // 14)
    for i in range(n):
        cx = int(w * (0.12 + 0.76 * i / max(1, n - 1)) + r.integers(-3, 4))
        rr = int(h * (0.28 + 0.34 * math.sin(math.pi * (i + 0.5) / n)) + r.integers(0, 3))
        puffs.append((cx, h - 4 - rr // 2, rr))
    for cx, cy, rr in puffs:
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 255, 255, 255))
    arr = np.asarray(img).copy()
    arr[h - 4:, :, 3] = 0  # đáy mây phẳng
    return Image.fromarray(arr, "RGBA")


def shade_cloud(shape, lit, mid, shadow):
    arr = np.asarray(shape).astype(np.int32).copy()
    m = arr[..., 3] > 0
    h, w = m.shape
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            if not m[y, x]:
                continue
            up = y - 2 >= 0 and m[y - 2, x]
            down = y + 2 < h and m[y + 2, x]
            c = mid
            if not up:
                c = lit
            elif not down:
                c = shadow
            out[y, x] = rgba(c, 235)
    return Image.fromarray(out, "RGBA")


def paint_sky(evening=False):
    spec = L_SKY
    w, h = spec[2], spec[3]
    if evening:
        stops = [(0.0, TOI_TOP), (0.45, TOI_MID), (0.78, TOI_PEACH), (1.0, TOI_LOW)]
    else:
        stops = [(0.0, SKY_TOP), (0.45, SKY_MID), (0.78, SKY_PEACH), (1.0, SKY_LOW)]
    img = from_np(dither_gradient(h, w, stops))
    # Mặt trời chiều (bên phải, thấp) + quầng sáng theo bậc.
    sx, sy = w2a(spec, 780, -300)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    rings = [(70, 26), (52, 34), (38, 48), (28, 70)] if not evening else [(80, 30), (58, 40), (40, 56)]
    gcol = (255, 236, 190) if not evening else (255, 170, 110)
    for r, a in rings:
        gd.ellipse([sx - r, sy - r, sx + r, sy + r], fill=rgba(gcol, a))
    img.alpha_composite(glow)
    if not evening:
        d = ImageDraw.Draw(img)
        d.ellipse([sx - 15, sy - 15, sx + 15, sy + 15], fill=rgba((255, 246, 214)))
        d.ellipse([sx - 12, sy - 13, sx + 12, sy + 11], fill=rgba((255, 252, 236)))
    else:
        # Sao hôm.
        for (x, y) in [(120, 60), (300, 30), (520, 80), (690, 44), (820, 96), (210, 140), (610, 150)]:
            rect(img, x, y, 1, 1, (255, 240, 220), 220)
        rect(img, 560, 118, 2, 2, (255, 250, 230), 255)
    # Mây tĩnh (dải mỏng gần chân trời).
    lit = (255, 244, 232) if not evening else (250, 170, 150)
    mid = (248, 226, 214) if not evening else (196, 120, 136)
    sh = (230, 188, 176) if not evening else (128, 84, 120)
    for i, (cx, cy, cw) in enumerate([(60, 330, 120), (330, 360, 160), (640, 345, 110), (820, 372, 90)]):
        c = shade_cloud(cloud_shape(cw, 14, 50 + i), lit, mid, sh)
        paste(img, c, cx, cy)
    return img


def paint_clouds(evening=False):
    """Ba đám mây rời (trôi chậm trong game)."""
    lit = (255, 246, 236) if not evening else (246, 164, 150)
    mid = (250, 230, 220) if not evening else (176, 112, 140)
    sh = (226, 186, 182) if not evening else (112, 78, 118)
    out = []
    for i, (cw, chh) in enumerate([(72, 22), (54, 18), (90, 26)]):
        out.append(shade_cloud(cloud_shape(cw, chh, 10 + i), lit, mid, sh))
    return out


# ------------------------------------------------------------------ lớp xa: sông + bờ bên kia

def paint_far(art):
    spec = L_FAR
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    _, horizon = w2a(spec, 0, -222)
    # Nước sông: sáng, phản chiếu trời.
    water = dither_gradient(h - horizon, w, [(0.0, (196, 200, 188)), (0.25, (162, 184, 186)), (1.0, (136, 164, 170))])
    paste(img, from_np(water), 0, horizon)
    # Vệt sáng mặt trời trên sông.
    sx, _ = w2a(spec, 780, 0)
    for i in range(26):
        y = horizon + 2 + int(i * 1.6)
        ww = max(2, 22 - i // 2 + int(rng.integers(-3, 4)))
        x = sx - ww // 2 + int(rng.integers(-6, 7))
        rect(img, x, y, ww, 1, (255, 240, 206), 210 - i * 5)
    for i in range(70):
        x = int(rng.integers(0, w))
        y = horizon + 3 + int(rng.integers(0, 60))
        rect(img, x, y, int(rng.integers(3, 10)), 1, (226, 222, 204), 150)
    # Hàng cây bờ bên kia (xanh xám, bị khí quyển làm nhạt).
    tree_far = (138, 160, 150)
    tree_far2 = (122, 146, 140)
    d = ImageDraw.Draw(img)
    for x in range(w):
        hh = 10 + 4 * math.sin(x * 0.045) + 3 * math.sin(x * 0.17 + 1.3) + 2 * math.sin(x * 0.53)
        d.line([x, horizon - int(hh), x, horizon], fill=rgba(tree_far))
    for x in range(0, w, 2):
        hh = 6 + 3 * math.sin(x * 0.09 + 2.0)
        d.line([x, horizon - int(hh), x, horizon], fill=rgba(tree_far2))
    # Dừa xa (bóng).
    for px in [40, 96, 180, 270, 410, 470, 600, 655, 760, 860]:
        top = horizon - int(rng.integers(22, 30))
        for y in range(top, horizon - 6):
            xx = px + int(2 * math.sin((y - top) * 0.08))
            rect(img, xx, y, 1, 1, tree_far2)
        for k in range(6):
            a = math.pi + math.pi * k / 5.0
            for s in range(9):
                lx = px + int(math.cos(a) * s)
                ly = top + int(math.sin(a) * s * 0.45 + 0.05 * s * s)
                rect(img, lx, ly, 2, 1, tree_far2)
    # Nhà sàn / mái tôn xa.
    for hx, hw in [(140, 18), (330, 14), (520, 22), (720, 16)]:
        rect(img, hx, horizon - 9, hw, 7, (176, 170, 156))
        for k in range(4):
            rect(img, hx - 2 + k, horizon - 12 + k, hw + 4 - 2 * k, 1, (150, 120, 110))
        rect(img, hx + 2, horizon - 2, 1, 4, (120, 120, 116))
        rect(img, hx + hw - 3, horizon - 2, 1, 4, (120, 120, 116))
    # Bờ đất gần chân trời.
    rect(img, 0, horizon, w, 1, (170, 168, 150))
    return img


def paint_boat(person=True, length=30):
    img = Image.new("RGBA", (length + 4, 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    hull = (112, 82, 66)
    hull_l = (146, 112, 86)
    for x in range(length):
        k = abs((x - length / 2) / (length / 2))
        top = 9 + int(round(k * k * -2))
        d.line([x + 2, top, x + 2, 12], fill=rgba(hull))
        d.point([x + 2, top], fill=rgba(hull_l))
    if person:
        rect(img, length // 2 - 1, 4, 3, 5, (92, 80, 96))
        # Nón lá.
        rect(img, length // 2 - 3, 3, 7, 1, (236, 214, 150))
        rect(img, length // 2 - 2, 2, 5, 1, (236, 214, 150))
        rect(img, length // 2, 1, 1, 1, (236, 214, 150))
        # Mái chèo.
        for i in range(6):
            d.point([length // 2 + 2 + i, 5 + i], fill=rgba((120, 92, 70)))
    rect(img, 4, 13, length - 4, 1, (226, 230, 214), 140)
    return haze(img, HAZE_FAR, 0.25)


# ------------------------------------------------------------------ lớp giữa: đình, cây, quán

def paint_roof(width, height, base, dark, ridge):
    """Mái đình ngói đỏ, đầu đao cong."""
    img = Image.new("RGBA", (width + 24, height + 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(height):
        k = y / max(1, height - 1)
        inset = int((1 - k) * 18)
        x0, x1 = 12 + inset - int(k * 10), 12 + width - inset + int(k * 10)
        c = base if (y // 2) % 2 == 0 else dark
        d.line([x0, 8 + y, x1, 8 + y], fill=rgba(c))
    # Hàng ngói.
    for x in range(14, width + 10, 4):
        d.line([x, 10, x - 3, 8 + height - 1], fill=rgba(dark))
    # Bờ nóc + đầu đao.
    rect(img, 26, 5, width - 28, 3, ridge)
    rect(img, 26, 4, width - 28, 1, (232, 196, 120))
    for sx, dirx in [(2, -1), (width + 21, 1)]:
        for i in range(7):
            d.point([sx - dirx * i // 2, 8 + height - 2 - i], fill=rgba(ridge))
            d.point([sx - dirx * i // 2 + 1, 8 + height - 2 - i], fill=rgba(ridge))
    # Lưỡng long chầu nguyệt (giản lược): mặt trăng vàng giữa nóc.
    cx = 12 + width // 2
    d.ellipse([cx - 4, 0, cx + 4, 7], fill=rgba((236, 182, 60)))
    for side in (-1, 1):
        for i in range(10):
            d.point([cx + side * (6 + i), 4 - int(2 * math.sin(i * 0.7))], fill=rgba((92, 150, 110)))
            d.point([cx + side * (6 + i), 5 - int(2 * math.sin(i * 0.7))], fill=rgba((92, 150, 110)))
    # Mép mái tối.
    rect(img, 2, 8 + height - 1, width + 20, 2, (90, 40, 34))
    return img


def paint_thatch(width, height):
    img = Image.new("RGBA", (width + 12, height + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(7)
    for y in range(height):
        k = y / max(1, height - 1)
        inset = int((1 - k) * 10)
        x0, x1 = 6 + inset - int(k * 6), 6 + width - inset + int(k * 6)
        for x in range(x0, x1):
            v = int(r.integers(-10, 11))
            base = (176, 140, 82) if (x + y // 2) % 5 else (150, 116, 66)
            d.point([x, y], fill=rgba((base[0] + v, base[1] + v, base[2] + v // 2)))
    rect(img, 0, height - 1, width + 12, 2, (118, 88, 52))
    return img


def paint_banner_text(text_rows, w, h):
    """Băng rôn vải đỏ chữ vàng bằng phông pixel 5×7 tự vẽ."""
    font = {
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
        "I": ["111", "010", "010", "010", "010", "010", "111"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    }
    marks = {"Ả": ("A", ["010", "001", "010"]), "À": ("A", ["100", "010"])}
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cloth = (176, 40, 34)
    rect(img, 0, 0, w, h, cloth)
    rect(img, 0, 0, w, 1, (230, 182, 64))
    rect(img, 0, h - 1, w, 1, (230, 182, 64))
    rect(img, 0, 1, w, 1, (140, 28, 26))
    for x in range(0, w, 6):
        rect(img, x, h - 2, 3, 1, (140, 28, 26))
    text = text_rows
    glyphs = []
    for ch in text:
        if ch in marks:
            base, mark = marks[ch]
            glyphs.append((font[base], mark))
        else:
            glyphs.append((font[ch], None))
    tw = sum(len(g[0][0]) + 1 for g in glyphs) - 1
    x = (w - tw) // 2
    y = (h - 7) // 2 + 1
    for g, mark in glyphs:
        gw = len(g[0])
        for gy, row in enumerate(g):
            for gx, bit in enumerate(row):
                if bit == "1":
                    rect(img, x + gx + 1, y + gy + 1, 1, 1, (96, 18, 16))
                    rect(img, x + gx, y + gy, 1, 1, (255, 214, 72))
        if mark:
            mh = len(mark)
            for my, row in enumerate(mark):
                for mx, bit in enumerate(row):
                    if bit == "1":
                        rect(img, x + 1 + mx, y - mh - 1 + my, 1, 1, (255, 214, 72))
        x += gw + 1
    return img


def paint_mid(art):
    spec = L_MID
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    # Bờ gần (cỏ) — kéo xuống tận đáy lớp để khi thị sai dọc không lộ khoảng trống.
    _, bank = w2a(spec, 0, -214)
    grass = dither_gradient(h - bank, w, [(0.0, (150, 160, 104)), (0.25, (134, 146, 96)), (1.0, (120, 128, 88))])
    paste(img, from_np(grass), 0, bank)
    d = ImageDraw.Draw(img)
    for x in range(0, w, 3):
        hh = int(rng.integers(1, 4))
        d.line([x, bank - hh, x, bank], fill=rgba((128, 142, 92)))

    def put_world(src, wx, wy_bottom, center=True):
        ax, ay = w2a(spec, wx, wy_bottom)
        paste(img, src, ax - (src.width // 2 if center else 0), ay - src.height)

    # Cột điện + dây (dây vắt qua toàn cảnh).
    pole = art.frame("B_cot_dien_01")
    poles = [-260, 260, 1180]
    for px in poles:
        put_world(pole, px, -196)
    for a, b in zip(poles[:-1], poles[1:]):
        ax0, ay0 = w2a(spec, a, -196 - pole.height * PX + 6)
        ax1, _ = w2a(spec, b, 0)
        for wire in range(2):
            for x in range(ax0, ax1 + 1):
                t = (x - ax0) / max(1, ax1 - ax0)
                y = ay0 + wire * 3 + int(10 * 4 * t * (1 - t))
                d.point([x, y], fill=rgba((70, 64, 66), 200))
    # Đình làng (tường + mái tự vẽ) ở giữa-phải, cách xa vùng chữ thông báo giữa màn hình.
    wall = art.frame("B_dinh_tuong_cot")
    dinh_x = 640
    put_world(wall, dinh_x, -200)
    roof = paint_roof(wall.width - 10, 18, (170, 72, 52), (146, 58, 44), (126, 50, 40))
    ax, ay = w2a(spec, dinh_x, -200 - wall.height * PX)
    paste(img, roof, ax - roof.width // 2, ay - roof.height + 4)
    steps = art.frame("B_dinh_bac_tam_cap")
    put_world(steps, dinh_x, -196)
    # Cột cờ đình.
    put_world(art.frame("B_cot_co_dinh"), 892, -204)
    # Cây đa lớn bên trái (thân; tán là sprite động).
    put_world(art.frame("B_cay_da_01_goc"), 70, -200)
    # Thân dừa (tán là sprite động).
    for name, x in [("B_dua_03_than", -150), ("B_dua_05_than", 960), ("B_dua_01_than", 1090), ("B_dua_03_than", 330)]:
        put_world(art.frame(name), x, -198)
    # Quán lá bên phải (vách + mái lá).
    hut = art.frame("C_nha_la_tuong")
    hut_x = 1150
    put_world(hut, hut_x, -200)
    th = paint_thatch(hut.width, 14)
    ax, ay = w2a(spec, hut_x, -200 - hut.height * PX)
    paste(img, th, ax - th.width // 2, ay - th.height + 3)
    # Quán nước nhỏ bên trái (khung tre + mái lá).
    stall_x = -60
    ax, ay = w2a(spec, stall_x, -200)
    th2 = paint_thatch(54, 10)
    for px in (ax - 26, ax + 26):
        rect(img, px, ay - 30, 2, 30, (120, 92, 56))
    paste(img, th2, ax - th2.width // 2, ay - 40)
    rect(img, ax - 22, ay - 14, 44, 3, (150, 110, 66))  # quầy
    for i, c in enumerate([(220, 120, 60), (90, 150, 80), (230, 200, 90), (200, 80, 70)]):
        rect(img, ax - 18 + i * 9, ay - 18, 6, 4, c)  # trái cây, chai nước
    # Nhạt theo khoảng cách (giữ đậm nhạt nhưng giảm tương phản).
    img = haze(img, HAZE_MID, 0.30)
    return img


def paint_rays():
    """Tia nắng chéo (cộng sáng) từ mặt trời phía phải-trên."""
    spec = L_MID
    w, h = spec[2], spec[3]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sx, sy = w2a(spec, 820, -560)
    for ang, width, a in [(2.05, 0.05, 34), (2.25, 0.035, 26), (2.42, 0.06, 30), (2.62, 0.03, 22), (2.8, 0.045, 18)]:
        far = 900
        p0 = (sx, sy)
        p1 = (sx + far * math.cos(ang - width), sy + far * math.sin(ang - width))
        p2 = (sx + far * math.cos(ang + width), sy + far * math.sin(ang + width))
        d.polygon([p0, p1, p2], fill=(255, 236, 190, a))
    arr = np.asarray(img).astype(np.float32).copy()
    # Mờ dần về phía dưới (không phủ vùng đánh nhau).
    ys = np.arange(h, dtype=np.float32)[:, None]
    _, fade_end = w2a(spec, 0, -150)
    fade = np.clip((fade_end - ys) / 80.0, 0.0, 1.0)
    arr[..., 3] *= fade
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ dây cờ, lồng đèn (cột tre + dây)

BUNT_POLES = [-380, 304, 988, 1672]
LANTERN_ROPE_Y = -334.0
LANTERN_SAG = 26.0


def rope_y(x0, x1, wx):
    t = (wx - x0) / (x1 - x0)
    return LANTERN_ROPE_Y + LANTERN_SAG * 4 * t * (1 - t)


def lantern_spots():
    """Toạ độ thế giới (tâm trên) của lồng đèn treo trên dây võng giữa các cột tre."""
    spots = []
    for x0, x1 in zip(BUNT_POLES[:-1], BUNT_POLES[1:]):
        for k in range(1, 6):
            wx = x0 + (x1 - x0) * k / 6.0
            if 140 < wx < 320 or wx > 1250:
                continue  # chừa chỗ băng rôn; bỏ phần ngoài khung nhìn
            spots.append((round(wx), round(rope_y(x0, x1, wx))))
    return spots


def paint_bunt():
    spec = L_BUNT
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    d = ImageDraw.Draw(img)
    bamboo = (204, 174, 104)
    bamboo_d = (160, 128, 70)
    for px in BUNT_POLES:
        x, ytop = w2a(spec, px, -368)
        for y in range(ytop, h):
            d.point([x, y], fill=rgba(bamboo))
            d.point([x + 1, y], fill=rgba(bamboo_d))
            if (y - ytop) % 10 == 0:
                d.point([x, y], fill=rgba(bamboo_d))
    for x0, x1 in zip(BUNT_POLES[:-1], BUNT_POLES[1:]):
        prev = None
        for wx in range(int(x0), int(x1) + 1, 2):
            pt = w2a(spec, wx, rope_y(x0, x1, wx))
            if prev:
                d.line([prev, pt], fill=(84, 64, 52, 230))
            prev = pt
    # Dây treo băng rôn.
    for bx in (156, 296):
        x0, y0 = w2a(spec, bx, rope_y(304, -380, bx) if bx < 304 else LANTERN_ROPE_Y)
        x1, y1 = w2a(spec, bx, -300)
        d.line([x0, y0, x1, y1], fill=(84, 64, 52, 230))
    return haze(img, HAZE_MID, 0.15)


# Phần tử động: (lớp, khoá atlas, x, y thế giới góc trên-trái, lật ngang, kiểu). Khớp DYN trong battle_arena.gd.
def dynamic_layout():
    dyn = [
        ("sky", "may_a", -200, -760, False, "cloud"),
        ("sky", "may_b", 420, -640, False, "cloud"),
        ("sky", "may_c", 900, -840, False, "cloud"),
        ("far", "ghe_a", 120, -238, False, "boat"),
        ("far", "ghe_b", 760, -232, True, "boat"),
        ("mid", "dua_a", -257, -427, False, "anim"),
        ("mid", "dua_c", 236, -419, False, "anim"),
        ("mid", "dua_b", 857, -446, False, "anim"),
        ("mid", "dua_a", 982, -415, True, "anim"),
        ("mid", "da", -29, -440, False, "anim"),
        ("mid", "chuoi", 150, -262, False, "anim"),
        ("mid", "chuoi", 800, -258, True, "anim"),
        ("mid", "co_to_quoc", 893, -380, False, "anim"),
        ("mid", "khoi_nhang", 548, -262, False, "anim"),
        ("mid", "khoi_bep", 1160, -386, False, "anim"),
        ("bunt", "day_co_a", -380, -366, False, "anim"),
        ("bunt", "day_co_b", 304, -366, False, "anim"),
        ("bunt", "day_co_a", 988, -366, False, "anim"),
        ("bunt", "co_dt", 306, -400, False, "anim"),
        ("bunt", "co_hoi", -378, -404, False, "anim"),
        ("bunt", "co_dt", 990, -400, True, "anim"),
        ("bunt", "banner", 150, -300, False, "banner"),
    ]
    for i, (wx, wy) in enumerate(lantern_spots()):
        dyn.append(("bunt", "den_long_a" if i % 2 == 0 else "den_long_b", wx - 14, wy, False, "lantern"))
    return dyn


# ------------------------------------------------------------------ khán đài phía sau hàng rào

def paint_stands():
    spec = L_STANDS
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    wood = (186, 150, 108)
    wood_d = (164, 128, 90)
    wood_l = (204, 172, 128)
    # Ba bậc ghế gỗ (bậc sau cao hơn), cong nhẹ theo vòng sới.
    for row in range(3):
        for x in range(w):
            wx = spec[0] + x * PX
            q = ((wx - 500.0) / 610.0) ** 2
            top_w = -64 - 26 * row - 12 + 34 * q * 0.8 - 2
            _, ty = w2a(spec, wx, top_w)
            for y in range(max(0, ty), h):
                c = wood if (y - ty) > 1 else wood_l
                if (y - ty) == 4:
                    c = wood_d
                img.putpixel((x, y), rgba(c))
    # Cột chống.
    for x in range(0, w, 34):
        rect(img, x, 0, 2, h, wood_d)
    # Mái che tre phía sau (một dải lá ở đỉnh) — khán giả đứng dưới bóng râm.
    return haze(img, HAZE_CROWD, 0.3)


# ------------------------------------------------------------------ hàng rào sới

def fence_base(wx):
    dx = (wx - RING_CX) / RING_RX
    if abs(dx) >= 1.0:
        return RING_CY
    return RING_CY - RING_RY * math.sqrt(1.0 - dx * dx)


def fence_height(wx):
    q = ((wx - 500.0) / 640.0) ** 2
    return 46.0 * (1.0 + 0.4 * q)


def paint_fence():
    spec = L_FENCE
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    panel = (216, 190, 130)
    panel_d = (202, 174, 116)
    rail = (184, 148, 90)
    rail_l = (236, 212, 152)
    post = (178, 140, 82)
    post_l = (226, 196, 132)
    post_d = (138, 104, 62)
    px_arr = np.zeros((h, w, 4), np.uint8)

    def setp(x, y, c, a=255):
        if 0 <= x < w and 0 <= y < h:
            px_arr[y, x] = rgba(c, a)

    tops = []
    for x in range(w):
        wx = spec[0] + x * PX
        base = fence_base(wx)
        hh = fence_height(wx)
        _, by = w2a(spec, wx, base)
        _, ty = w2a(spec, wx, base - hh)
        tops.append((ty, by))
        for y in range(ty, by + 1):
            k = (y - ty) / max(1, by - ty)
            c = panel_d if ((x // 3) + (y // 2)) % 2 else panel
            if k > 0.85:
                c = mix(c, (176, 146, 96), 0.35)
            setp(x, y, c)
        # Ray trên, giữa, dưới.
        for ry in (ty, ty + 1):
            setp(x, ry, rail)
        setp(x, ty - 1, rail_l)
        mid = ty + (by - ty) // 2
        setp(x, mid, rail)
        setp(x, mid - 1, rail_l)
        setp(x, by - 2, rail)
    # Cọc tre: khoảng cách giãn dần ra hai mép (gần mắt hơn).
    wx = -420.0
    gate_x = 500.0
    while wx < 1420.0:
        q = ((wx - 500.0) / 640.0) ** 2
        step = 26.0 * (1.0 + 0.4 * q)
        if abs(wx - gate_x) < 40:
            wx += step
            continue
        x, _ = w2a(spec, wx, 0)
        if 0 <= x < w - 3:
            ty, by = tops[x]
            cap = ty - 4
            for y in range(cap, by + 1):
                setp(x, y, post_l)
                setp(x + 1, y, post)
                setp(x + 2, y, post_d)
                if (y - cap) % 9 == 0:
                    setp(x, y, post_d)
                    setp(x + 1, y, post_d)
            setp(x + 1, cap - 1, post_d)
        wx += step
    # Cổng sới ở giữa (hai trụ cao + bảng đỏ nhỏ).
    for gx in (gate_x - 38, gate_x + 34):
        x, _ = w2a(spec, gx, 0)
        ty, by = tops[x]
        for y in range(ty - 16, by + 1):
            setp(x, y, post_l)
            setp(x + 1, y, post)
            setp(x + 2, y, post)
            setp(x + 3, y, post_d)
    gx0, _ = w2a(spec, gate_x - 38, 0)
    gx1, _ = w2a(spec, gate_x + 34, 0)
    ty, _ = tops[(gx0 + gx1) // 2]
    for x in range(gx0 - 2, gx1 + 6):
        for y in range(ty - 15, ty - 9):
            c = (172, 52, 40)
            if y == ty - 15 or y == ty - 10:
                c = (226, 176, 70)
            setp(x, y, c)
    cx = (gx0 + gx1) // 2 + 2
    for y in range(ty - 14, ty - 10):
        for x in range(cx - 2, cx + 3):
            if (x - cx) ** 2 + (y - (ty - 12)) ** 2 <= 4:
                setp(x, y, (240, 200, 90))
    return Image.fromarray(px_arr, "RGBA")


# ------------------------------------------------------------------ nền sới

def paint_floor():
    spec = L_FLOOR
    w, h = spec[2], spec[3]
    arr = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.uint8)
    noise = rng.integers(-5, 6, size=(h, w)).astype(np.float32)
    ring_in = (226, 198, 148)
    ring_back = (198, 168, 120)
    earth = (196, 162, 116)
    earth_d = (160, 128, 90)
    for y in range(h):
        wy = spec[1] + y * PX
        for x in range(w):
            wx = spec[0] + x * PX
            base = fence_base(wx)
            if wy < base - 6:
                continue
            alpha[y, x] = 255
            dx = (wx - RING_CX) / RING_RX
            dy = (wy - RING_CY) / RING_RY
            inside = dx * dx + dy * dy <= 1.0
            # Ánh sáng: sáng nhất ngay dưới chân gà (y ≈ -10..40), tối dần về hàng rào và mép dưới.
            t_back = np.clip((wy - base) / 40.0, 0.0, 1.0)
            c = np.array(ring_back) + (np.array(ring_in) - np.array(ring_back)) * t_back
            if wy > 40:
                c = c + (np.array(earth_d) - c) * np.clip((wy - 40) / 260.0, 0.0, 1.0) * 0.8
            if not inside:
                c = c * 0.5 + np.array(earth) * 0.5
                c = c + (np.array(earth_d) - c) * np.clip((wy - 60) / 200.0, 0.0, 1.0) * 0.5
            arr[y, x] = c + noise[y, x] * (0.6 if inside else 1.0)
    img = from_np(arr, alpha)
    d = ImageDraw.Draw(img)
    # Bóng tối dưới chân hàng rào (AO).
    for x in range(w):
        wx = spec[0] + x * PX
        _, by = w2a(spec, wx, fence_base(wx))
        for k in range(4):
            if 0 <= by + k < h:
                c = img.getpixel((x, by + k))
                f = 0.80 + 0.05 * k
                img.putpixel((x, by + k), (int(c[0] * f), int(c[1] * f), int(c[2] * f), 255))
    # Vòng phấn trắng.
    cx, cy = w2a(spec, 500, 14)
    rx, ry = 480 // PX, 40 // PX
    for i in range(720):
        a = 2 * math.pi * i / 720
        x = int(round(cx + rx * math.cos(a)))
        y = int(round(cy + ry * math.sin(a)))
        if (i // 9) % 5 == 4:
            continue  # phấn mòn, đứt quãng
        if 0 <= x < w and 0 <= y < h:
            c = img.getpixel((x, y))
            img.putpixel((x, y), (int(c[0] * 0.3 + 244 * 0.7), int(c[1] * 0.3 + 236 * 0.7), int(c[2] * 0.3 + 214 * 0.7), 255))
    # Vạch xuất phát hai bên (x = 370 / 630, khớp START_X).
    for sx in (370, 630):
        ax, ay = w2a(spec, sx, 0)
        for k in range(-3, 4):
            c = img.getpixel((ax, ay + k))
            img.putpixel((ax, ay + k), (int(c[0] * 0.4 + 244 * 0.6), int(c[1] * 0.4 + 236 * 0.6), int(c[2] * 0.4 + 214 * 0.6), 255))
    # Vết cào chân gà (nhạt).
    for i in range(46):
        x = int(rng.integers(40, w - 40))
        wy = float(rng.uniform(-30, 70))
        _, y = w2a(spec, 0, wy)
        ln = int(rng.integers(3, 9))
        c = (196, 166, 120, 255)
        d.line([x, y, x + ln, y + int(rng.integers(-1, 2))], fill=c)
    # Rơm vụn + lông gà ở mép sân (không rải giữa vùng đánh).
    for i in range(70):
        wx = float(rng.choice([rng.uniform(-400, 60), rng.uniform(940, 1400), rng.uniform(-400, 1400)]))
        wy = float(rng.uniform(40, 180)) if 60 < wx < 940 else float(rng.uniform(-20, 160))
        x, y = w2a(spec, wx, wy)
        ln = int(rng.integers(2, 5))
        d.line([x, y, x + ln, y - int(rng.integers(0, 2))], fill=(232, 204, 120, 255))
    feathers = [((-60, 30), (236, 232, 222)), ((90, 74), (176, 64, 40)), ((960, 40), (60, 50, 50)),
                ((1050, 80), (236, 232, 222)), ((150, 120), (210, 120, 50)), ((880, 110), (176, 64, 40))]
    for (wx, wy), col in feathers:
        x, y = w2a(spec, wx, wy)
        d.line([x, y, x + 3, y - 1], fill=rgba(col))
        d.point([x + 1, y + 1], fill=rgba(col))
        d.point([x + 4, y - 2], fill=rgba(mix(col, (255, 255, 255), 0.3)))
    return img


def paint_props(art):
    """Đồ vật ngoài mép sân (ngoài 0..1000 để không đứng sau thân gà): lồng gà, lu nước, ghế nhựa, trống."""
    spec = L_FENCE
    img = new_layer(spec)

    def put_world(src, wx, wy_bottom):
        ax, ay = w2a(spec, wx, wy_bottom)
        # Bóng tiếp đất mềm.
        sh = Image.new("RGBA", (src.width + 4, 3), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([0, 0, src.width + 3, 2], fill=(90, 60, 40, 80))
        paste(img, sh, ax - sh.width // 2, ay - 2)
        paste(img, src, ax - src.width // 2, ay - src.height)

    put_world(paint_cage(), -70, -24)
    put_world(paint_cage(rooster=(176, 60, 40)), 1080, -22)
    put_world(paint_cage(), 1124, -14)
    put_world(paint_jar(), -112, -16)
    put_world(paint_jar(), 1040, -28)
    stool = art.frame("A_ghe_nhua_01")
    put_world(stool, -24, -30)
    put_world(stool, 1160, -10)
    put_world(paint_drum(), -150, -8)
    return img


def paint_cage(rooster=(60, 52, 56)):
    w, h = 22, 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Gà trong lồng (bóng).
    d.ellipse([6, 7, 15, 14], fill=rgba(rooster))
    rect(img, 13, 5, 3, 4, rooster)
    rect(img, 14, 4, 2, 1, (200, 50, 40))
    # Nan tre hình chuông.
    for x in range(1, w - 1, 3):
        k = abs((x - w / 2) / (w / 2))
        top = int(2 + k * k * 8)
        d.line([x, top, x, h - 2], fill=rgba((196, 156, 90)))
    d.arc([1, 1, w - 2, 22], 180, 360, fill=rgba((150, 112, 62)))
    rect(img, 0, h - 2, w, 2, (150, 112, 62))
    rect(img, w // 2 - 1, 0, 3, 2, (150, 112, 62))
    return img


def paint_jar():
    w, h = 14, 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 2, w - 1, h - 1], fill=rgba((128, 74, 48)))
    d.ellipse([2, 4, 6, 10], fill=rgba((166, 104, 66)))
    rect(img, 3, 1, w - 6, 3, (110, 62, 40))
    rect(img, 4, 1, w - 8, 1, (70, 90, 110))
    return img


def paint_drum():
    w, h = 18, 18
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x in (2, w - 3):
        d.line([x, 8, x - 1 if x < 9 else x + 1, h - 1], fill=rgba((110, 76, 48)))
    rect(img, 2, 3, w - 4, 9, (170, 48, 40))
    rect(img, 2, 3, w - 4, 1, (226, 176, 70))
    rect(img, 2, 11, w - 4, 1, (226, 176, 70))
    d.ellipse([2, 1, w - 3, 5], fill=rgba((232, 214, 170)))
    d.line([w - 2, 0, w - 6, 4], fill=rgba((120, 86, 56)))
    return img


# ------------------------------------------------------------------ tiền cảnh mờ

def paint_front():
    spec = L_FRONT
    w, h = spec[2], spec[3]
    img = new_layer(spec)
    d = ImageDraw.Draw(img)
    col = (58, 40, 32, 255)

    def head(wx, wy, hat):
        x, y = w2a(spec, wx, wy)
        d.ellipse([x - 13, y, x + 13, y + 30], fill=col)
        d.rectangle([x - 18, y + 22, x + 18, y + 60], fill=col)
        if hat:
            d.polygon([(x - 26, y + 8), (x, y - 12), (x + 26, y + 8)], fill=col)

    head(-130, 66, True)
    head(-60, 92, False)
    head(40, 112, True)
    head(1000, 106, False)
    head(1080, 80, True)
    head(1170, 70, False)
    # Đầu cọc rào gần ống kính.
    for wx, wy in [(-200, 60), (1230, 64)]:
        x, y = w2a(spec, wx, wy)
        d.rectangle([x - 5, y, x + 5, h], fill=col)
    img = img.filter(ImageFilter.GaussianBlur(1.6))
    arr = np.asarray(img).copy()
    a = arr[..., 3]
    q = np.where(a > 190, 225, np.where(a > 110, 150, np.where(a > 40, 70, 0)))
    arr[..., 3] = q.astype(np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = col[0], col[1], col[2]
    return Image.fromarray(arr, "RGBA")


# ------------------------------------------------------------------ atlas đồ vật động

PROP_SPECS = [
    # (khoá trong game, tên node bản đồ)
    ("da", "B_cay_da_01_tan"),
    ("dua_a", "B_dua_03_tan"),
    ("dua_b", "B_dua_05_tan"),
    ("dua_c", "B_dua_01_tan"),
    ("chuoi", "B_chuoi_01"),
    ("day_co_a", "F_day_co_hoi_01"),
    ("day_co_b", "F_day_co_hoi_02"),
    ("den_long_a", "B_den_long_01"),
    ("den_long_b", "B_den_long_02"),
    ("co_to_quoc", "F_co_to_quoc"),
    ("co_hoi", "B_co_hoi_dinh"),
    ("co_dt", "B_co_dau_truong_01"),
    ("khoi_nhang", "B_khoi_nhang"),
    ("khoi_bep", "C_khoi_bep"),
]


def build_props_atlas(art, clouds_day, clouds_toi):
    rows = []  # (key, frames, order)
    for key, node in PROP_SPECS:
        frames, order = art.frames(node)
        rows.append((key, frames, order))
    rows.append(("ghe_a", [paint_boat(True, 30)], "0"))
    rows.append(("ghe_b", [paint_boat(False, 24)], "0"))
    rows.append(("may_a", [clouds_day[0]], "0"))
    rows.append(("may_b", [clouds_day[1]], "0"))
    rows.append(("may_c", [clouds_day[2]], "0"))
    rows.append(("may_toi_a", [clouds_toi[0]], "0"))
    rows.append(("may_toi_b", [clouds_toi[1]], "0"))
    rows.append(("may_toi_c", [clouds_toi[2]], "0"))
    rows.append(("banner", [paint_banner_text("GIẢI AO LÀNG", 76, 13)], "0"))
    rows.append(("glow", [paint_glow(28)], "0"))
    rows.append(("mote", [paint_mote()], "0"))
    width = max(max(f.width for f in frames) * len(frames) for _, frames, _ in rows)
    y = 0
    placed = []
    for key, frames, order in rows:
        cw = max(f.width for f in frames)
        ch = max(f.height for f in frames)
        placed.append((key, y, cw, ch, len(frames), order, frames))
        y += ch + 1
    atlas = Image.new("RGBA", (width, y), (0, 0, 0, 0))
    meta = {}
    for key, yy, cw, ch, n, order, frames in placed:
        assert cw * n <= width, key
        for i, f in enumerate(frames):
            atlas.alpha_composite(f, (i * cw, yy))
        meta[key] = (yy, cw, ch, n, order)
    return atlas, meta


def paint_glow(r):
    img = Image.new("RGBA", (r * 2, r * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for rr, a in [(r, 40), (int(r * 0.7), 70), (int(r * 0.45), 110), (int(r * 0.25), 160)]:
        d.ellipse([r - rr, r - rr, r + rr - 1, r + rr - 1], fill=(255, 200, 120, a))
    return img


def paint_mote():
    img = Image.new("RGBA", (2, 2), (255, 244, 210, 255))
    return img


# ------------------------------------------------------------------ atlas khán giả

CROWD_NPCS = ["crowd_1", "crowd_2", "crowd_3", "crowd_4", "crowd_5", "lady", "lottery", "shop",
              "temple_man", "mc", "chu_tu", "teo"]
CELL_W, CELL_H = 36, 48
ROW_HAZE = [0.20, 0.34, 0.48]


def raised_arms(src):
    """Tạo khung "giơ tay" từ sprite NPC đứng thẳng (tay buông → tay giơ cao cạnh đầu)."""
    im = src.convert("RGBA")
    w, h = im.size
    pad = 5
    out = Image.new("RGBA", (w + pad * 2, h), (0, 0, 0, 0))
    out.alpha_composite(im, (pad, 0))
    a = np.asarray(out).copy()
    m = a[..., 3] > 0
    outline_c = np.array([42, 30, 46, 255], np.uint8)

    def span(y):
        xs = np.nonzero(m[y])[0]
        return (int(xs.min()), int(xs.max())) if len(xs) else (None, None)

    head_l, head_r = span(min(12, h - 1))
    # Hàng vai: hàng đầu tiên (≥ 12) rộng hơn đầu.
    sy = None
    for y in range(12, min(h - 8, 26)):
        l, r = span(y)
        if l is not None and (l < head_l or r > head_r):
            sy = y
            break
    if sy is None:
        return out
    # Chỉ xét dải cạnh mặt (dưới vành nón, trên vai) để không nhầm vành nón với tay đã giơ.
    upper = m[max(0, sy - 8):max(1, sy - 2)]
    up_xs = np.nonzero(upper.any(axis=0))[0]
    body_l, body_r = span(sy + 3)
    raised_left = len(up_xs) and up_xs.min() < body_l - 1
    raised_right = len(up_xs) and up_xs.max() > body_r + 1
    skin = None
    for y in range(sy + 4, min(h, sy + 12)):
        px = a[y, body_l + 1]
        if px[3] > 0 and px[0] > px[2] + 30:
            skin = px.copy()
            break
    if skin is None:
        skin = np.array([232, 180, 120, 255], np.uint8)
    for side in ("l", "r"):
        if (side == "l" and raised_left) or (side == "r" and raised_right):
            continue
        sl, sr = span(sy + 4)
        edge = sl if side == "l" else sr
        sign = -1 if side == "l" else 1
        sleeve = a[sy + 1, edge - sign * 1].copy() if a[sy + 1, edge - sign * 1][3] > 0 else skin
        # Xoá tay buông (3 cột ngoài cùng ở thân) và kẻ lại viền thân.
        for y in range(sy, min(h, sy + 12)):
            for k in range(3):
                x = edge - sign * k
                if 0 <= x < a.shape[1] and m[y, x]:
                    a[y, x] = 0
            x = edge - sign * 3
            if 0 <= x < a.shape[1] and a[y, x][3] > 0:
                a[y, x] = outline_c
        # Tay giơ: từ vai chéo lên ngoài đầu, nắm tay ở trên.
        hx = (head_l - 2) if side == "l" else (head_r + 2)
        pts = []
        for i in range(sy - 1 - 3 + 1):
            y = sy + 1 - i
            t = i / max(1, sy - 3)
            x = int(round(edge - sign * 1 + (hx - (edge - sign * 1)) * min(1.0, t * 1.6)))
            pts.append((x, y))
        arm = np.zeros(m.shape, bool)
        for x, y in pts:
            for dx in (0, sign):
                xx = x + dx
                if 0 <= xx < a.shape[1] and 0 <= y < h:
                    arm[y, xx] = True
        # Nắm tay 3×3 ở đỉnh.
        fx, fy = pts[-1]
        for yy in range(fy - 2, fy + 1):
            for xx in range(fx - 1, fx + 2):
                if 0 <= xx < a.shape[1] and 0 <= yy < h:
                    arm[yy, xx] = True
        for y in range(h):
            for x in range(a.shape[1]):
                if arm[y, x]:
                    a[y, x] = sleeve if y >= sy - 2 else skin
        # Viền tay.
        ring = np.zeros_like(arm)
        ring[1:, :] |= arm[:-1, :]
        ring[:-1, :] |= arm[1:, :]
        ring[:, 1:] |= arm[:, :-1]
        ring[:, :-1] |= arm[:, 1:]
        ring &= ~arm
        ring &= a[..., 3] == 0
        a[ring] = outline_c
    return Image.fromarray(a, "RGBA")


def build_crowd_atlas():
    cols = len(CROWD_NPCS)
    atlas = Image.new("RGBA", (cols * CELL_W, len(ROW_HAZE) * 2 * CELL_H), (0, 0, 0, 0))
    heights = []
    for c, name in enumerate(CROWD_NPCS):
        src = Image.open(os.path.join(NPC_DIR, name + ".png")).convert("RGBA")
        heights.append(src.height)
        cheer = raised_arms(src)
        for r, t in enumerate(ROW_HAZE):
            for pose, im in enumerate((src, cheer)):
                hz = haze(im, HAZE_CROWD, t)
                cx = c * CELL_W + (CELL_W - im.width) // 2
                cy = (r * 2 + pose) * CELL_H + (CELL_H - im.height)
                atlas.alpha_composite(hz, (cx, cy))
    return atlas, heights


# ------------------------------------------------------------------ xuất

def save(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    img.save(os.path.join(OUT_DIR, name), optimize=True)


def main():
    art = MapArt()
    sky = paint_sky(False)
    sky_toi = paint_sky(True)
    far = paint_far(art)
    mid = paint_mid(art)
    rays = paint_rays()
    bunt = paint_bunt()
    stands = paint_stands()
    fence = paint_fence()
    props = paint_props(art)
    fence.alpha_composite(props)
    floor = paint_floor()
    front = paint_front()
    props_atlas, meta = build_props_atlas(art, paint_clouds(False), paint_clouds(True))
    crowd_atlas, heights = build_crowd_atlas()
    for img, name in [(sky, "arena_sky.png"), (sky_toi, "arena_sky_toi.png"), (far, "arena_far.png"),
                      (mid, "arena_mid.png"), (rays, "arena_rays.png"), (bunt, "arena_bunt.png"),
                      (stands, "arena_stands.png"),
                      (fence, "arena_fence.png"), (floor, "arena_floor.png"), (front, "arena_front.png"),
                      (props_atlas, "arena_props.png"), (crowd_atlas, "arena_crowd.png")]:
        save(img, name)
    print("PROPS = {")
    for k, (y, cw, ch, n, order) in meta.items():
        print('\t"%s": [%d, %d, %d, %d, "%s"],' % (k, y, cw, ch, n, order if n > 1 else ""))
    print("}")
    print("CROWD_HEIGHTS =", heights)
    print("DYN = [")
    for layer, key, x, y, flip, kind in dynamic_layout():
        print('\t[&"%s", "%s", %d, %d, %s, &"%s"],' % (layer, key, x, y, "true" if flip else "false", kind))
    print("]")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "props_meta.txt"), "w", encoding="utf-8") as fh:
            fh.write("PROPS = %r\nB_HEIGHTS = %r\nDYN = %r\n" % (meta, heights, dynamic_layout()))
        props_atlas.resize((props_atlas.width * 2, props_atlas.height * 2), Image.NEAREST).save(os.path.join(out, "props_x2.png"))
        crowd_atlas.resize((crowd_atlas.width * 3, crowd_atlas.height * 3), Image.NEAREST).save(os.path.join(out, "crowd_x3.png"))


if __name__ == "__main__":
    main()
