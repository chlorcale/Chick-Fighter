# -*- coding: utf-8 -*-
"""Hai sân đấu mới cho BattleArena (config "arena_variant"): &"lien_tinh" và &"olympic".

  lien_tinh – sới tỉnh lớn ban ngày: phố chợ phía xa, khán đài có mái tôn che trên cột thép, băng rôn
              "GIẢI ĐÁ GÀ LIÊN TỈNH MIỀN TÂY", dây cờ đuôi nheo, khán đài bê tông sơn sọc, rào sắt + bảng sơn,
              nền đất nện đỏ có vòng sơn trắng.
  olympic   – nhà thi đấu trong nhà: trần dàn thép + giàn đèn pha, khán đài tầng trên (đám đông lấm tấm), màn hình
              lớn với HUY HIỆU GÀ VÀNG nguyên bản (đầu gà trống trong vòng tròn + bông lúa – KHÔNG dùng vòng tròn
              Olympic thật), cờ các tỉnh, ghế đỏ tầng dưới, bảng LED quanh sàn, sàn thảm xanh có huy hiệu.

Cùng khung lớp với tools/art/build_arena.py (L_SKY … L_FRONT, mỗi pixel ảnh = 2 pixel thế giới) để hệ thị sai,
khán giả (arena_crowd.png) và kiểm tra phủ khung nhìn dùng chung. Lien_tinh dùng lại trời arena_sky.png.
Kích thước sàn đấu KHÔNG đổi (GDD nói sàn Olympic 1.400 px – OPEN, giữ 1.000 px của mô phỏng).

Chạy: python tools/art/build_arena_venues.py   → game/art/arena/arena_<variant>_<lớp>.png
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import build_arena as BA  # noqa: E402  (tiện ích + khung lớp dùng chung)

PX = BA.PX
rgba = BA.rgba
mix = BA.mix
rect = BA.rect
w2a = BA.w2a
rng = np.random.default_rng(4242)

# ------------------------------------------------------------------ phông pixel 5×7 có dấu

GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "Đ": ["11110", "10001", "10001", "11101", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["111", "010", "010", "010", "010", "010", "111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Ơ": ["011101", "100010", "10001", "10001", "10001", "10001", "01110"],
    " ": ["000", "000", "000", "000", "000", "000", "000"],
    "–": ["000", "000", "000", "111", "000", "000", "000"],
}
MARK_ACUTE = ["001", "010"]
MARK_GRAVE = ["100", "010"]
MARK_HOOK = ["110", "010"]
MARK_HAT = ["010", "101"]
ACCENTS = {"Á": ("A", [MARK_ACUTE]), "À": ("A", [MARK_GRAVE]), "Ả": ("A", [MARK_HOOK]), "Â": ("A", [MARK_HAT]),
           "Ê": ("E", [MARK_HAT]), "Ề": ("E", [MARK_HAT, MARK_GRAVE]), "Ỉ": ("I", [MARK_HOOK]),
           "Ạ": ("A", []), "Ố": ("O", [MARK_HAT, MARK_ACUTE])}


def text_width(text):
    total = 0
    for ch in text:
        base = ACCENTS.get(ch, (ch, []))[0]
        total += len(GLYPHS.get(base, GLYPHS[" "])[0]) + 1
    return total - 1


def draw_text(img, text, x, y, col, shadow=None):
    for ch in text:
        base, marks = ACCENTS.get(ch, (ch, []))
        g = GLYPHS.get(base, GLYPHS[" "])
        gw = len(g[0])
        for gy, row in enumerate(g):
            for gx, bit in enumerate(row):
                if bit == "1":
                    if shadow:
                        rect(img, x + gx + 1, y + gy + 1, 1, 1, shadow)
                    rect(img, x + gx, y + gy, 1, 1, col)
        mx = x + max(0, (gw - 3) // 2)
        for k, mark in enumerate(marks):
            for my, row in enumerate(mark):
                for mxx, bit in enumerate(row):
                    if bit == "1":
                        rect(img, mx + mxx + k * 2, y - 3 + my, 1, 1, col)
        x += gw + 1


def banner(text, w, h, cloth, ink, trim):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rect(img, 0, 0, w, h, cloth)
    rect(img, 0, 0, w, 1, trim)
    rect(img, 0, h - 1, w, 1, trim)
    for x in range(0, w, 6):
        rect(img, x, h - 2, 3, 1, mix(cloth, (0, 0, 0), 0.25))
    draw_text(img, text, (w - text_width(text)) // 2, (h - 7) // 2 + 1, ink, mix(cloth, (0, 0, 0), 0.45))
    return img


def emblem(r):
    """Huy hiệu gà vàng nguyên bản: vòng tròn đỏ viền vàng, đầu gà trống nhìn phải, hai bông lúa ôm dưới."""
    size = r * 2 + 6
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size // 2
    gold, gold_d, gold_l = (236, 184, 60), (170, 112, 28), (255, 230, 140)
    d.ellipse([c - r, c - r, c + r, c + r], fill=rgba(gold_d))
    d.ellipse([c - r + 2, c - r + 2, c + r - 2, c + r - 2], fill=rgba((150, 26, 30)))
    d.ellipse([c - r + 4, c - r + 4, c + r - 4, c + r - 4], outline=rgba(gold), width=1)
    s = r / 22.0
    # Đầu + cổ gà (đa giác), mào răng cưa, mỏ, mắt.
    neck = [(-6, 14), (-9, 2), (-6, -6), (0, -10), (6, -9), (9, -5), (8, 0), (4, 4), (2, 14)]
    d.polygon([(c + x * s, c + y * s) for x, y in neck], fill=rgba(gold))
    comb = [(-5, -8), (-6, -14), (-3, -11), (-1, -17), (1, -12), (4, -16), (5, -10), (7, -13), (7, -7)]
    d.polygon([(c + x * s, c + y * s) for x, y in comb], fill=rgba(gold_l))
    beak = [(8, -5), (14, -3), (8, -1)]
    d.polygon([(c + x * s, c + y * s) for x, y in beak], fill=rgba(gold_l))
    wattle = [(5, 0), (7, 6), (3, 3)]
    d.polygon([(c + x * s, c + y * s) for x, y in wattle], fill=rgba(gold_l))
    d.rectangle([c + 3 * s, c - 6 * s, c + 4 * s + 1, c - 5 * s + 1], fill=rgba((40, 10, 12)))
    # Hai bông lúa.
    for side in (-1, 1):
        for k in range(6):
            a = math.radians(200 - k * 22) if side < 0 else math.radians(-20 + k * 22)
            rr = r - 6
            px = c + math.cos(a) * rr * (1 if side > 0 else 1)
            py = c + math.sin(a) * rr * 0.9 + 6 * s
            if py < c - 2:
                continue
            d.ellipse([px - 2, py - 1, px + 2, py + 1], fill=rgba(gold))
    return img


# ------------------------------------------------------------------ LIÊN TỈNH

def lt_far():
    spec = BA.L_FAR
    img = BA.new_layer(spec)
    d = ImageDraw.Draw(img)
    w, h = spec[2], spec[3]
    _, ground = w2a(spec, 0, -150)
    facades = [(236, 214, 150), (176, 206, 220), (232, 176, 168), (214, 228, 196), (240, 232, 214), (196, 186, 222)]
    x = 0
    i = 0
    while x < w:
        bw = int(rng.integers(18, 34))
        bh = int(rng.integers(30, 70))
        col = facades[i % len(facades)]
        top = ground - bh
        d.rectangle([x, top, x + bw - 1, ground], fill=rgba(col))
        d.rectangle([x, top, x + bw - 1, top + 2], fill=rgba(mix(col, (120, 70, 60), 0.4)))
        for wy in range(top + 6, ground - 6, 9):
            for wx in range(x + 3, x + bw - 4, 7):
                d.rectangle([wx, wy, wx + 3, wy + 4], fill=rgba(mix(col, (60, 70, 90), 0.55)))
        if i % 3 == 0:
            d.rectangle([x + 2, top - 4, x + bw - 3, top - 1], fill=rgba((200, 80, 60)))  # biển hiệu
        x += bw + int(rng.integers(0, 4))
        i += 1
    # Tháp nước + dừa.
    tx, _ = w2a(spec, 1180, 0)
    d.rectangle([tx, ground - 110, tx + 3, ground], fill=rgba((150, 156, 160)))
    d.rectangle([tx + 18, ground - 110, tx + 21, ground], fill=rgba((150, 156, 160)))
    d.ellipse([tx - 6, ground - 140, tx + 28, ground - 104], fill=rgba((186, 196, 204)))
    for wx in (-260, 140, 760, 1300):
        px, _ = w2a(spec, wx, 0)
        d.line([px, ground, px + 4, ground - 60], fill=rgba((110, 90, 60)), width=2)
        for k in range(6):
            a = math.radians(-160 + k * 28)
            d.line([px + 4, ground - 60, px + 4 + math.cos(a) * 16, ground - 60 + math.sin(a) * 8 + 4], fill=rgba((70, 130, 70)), width=2)
    rect(img, 0, ground, w, h - ground, (170, 160, 140))
    return BA.haze(img, BA.HAZE_FAR, 0.38)


def lt_mid():
    spec = BA.L_MID
    img = BA.new_layer(spec)
    d = ImageDraw.Draw(img)
    w, h = spec[2], spec[3]
    _, roof_y = w2a(spec, 0, -470)
    _, eave_y = w2a(spec, 0, -330)
    _, base_y = w2a(spec, 0, -60)
    # Phố chợ tỉnh ló lên sau mái (nhà ống, tháp nước) – mờ xa.
    town = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    td = ImageDraw.Draw(town)
    facades = [(236, 214, 150), (176, 206, 220), (232, 176, 168), (214, 228, 196), (240, 232, 214)]
    x = 0
    i = 0
    while x < w:
        bw = int(rng.integers(16, 30))
        bh = int(rng.integers(12, 34))
        col = facades[i % len(facades)]
        td.rectangle([x, roof_y - bh, x + bw - 1, roof_y + 2], fill=rgba(col))
        for wy in range(roof_y - bh + 4, roof_y - 2, 7):
            for wx in range(x + 3, x + bw - 4, 6):
                td.rectangle([wx, wy, wx + 2, wy + 3], fill=rgba(mix(col, (60, 70, 90), 0.5)))
        x += bw + int(rng.integers(1, 5))
        i += 1
    tx, _ = w2a(spec, 1180, 0)
    td.rectangle([tx, roof_y - 40, tx + 2, roof_y], fill=rgba((150, 156, 160)))
    td.rectangle([tx + 14, roof_y - 40, tx + 16, roof_y], fill=rgba((150, 156, 160)))
    td.ellipse([tx - 5, roof_y - 58, tx + 21, roof_y - 36], fill=rgba((186, 196, 204)))
    img.alpha_composite(BA.haze(town, BA.HAZE_FAR, 0.45))
    # Bóng râm dưới mái (khán đài có mái che).
    rect(img, 0, eave_y, w, base_y - eave_y, (92, 88, 96))
    for y in range(eave_y, base_y):
        k = (y - eave_y) / max(1, base_y - eave_y)
        rect(img, 0, y, w, 1, mix((70, 66, 78), (128, 120, 118), k))
    # Mái tôn dốc, sóng tôn xanh xám.
    for y in range(roof_y, eave_y):
        k = (y - roof_y) / max(1, eave_y - roof_y)
        for x in range(w):
            ripple = (x // 3) % 2
            c = mix((150, 170, 186), (112, 132, 150), k)
            if ripple:
                c = mix(c, (190, 206, 216), 0.35)
            img.putpixel((x, y), rgba(c))
    rect(img, 0, eave_y, w, 3, (80, 92, 104))
    rect(img, 0, roof_y, w, 2, (206, 216, 224))
    # Cột thép + kèo chéo.
    for x in range(10, w, 60):
        rect(img, x, eave_y, 3, base_y - eave_y, (64, 70, 82))
        d.line([x + 1, eave_y + 2, x + 22, eave_y + 18], fill=rgba((64, 70, 82)), width=1)
    # Băng rôn lớn dưới mép mái.
    text = "GIẢI ĐÁ GÀ LIÊN TỈNH MIỀN TÂY"
    b = banner(text, text_width(text) + 24, 13, (186, 34, 30), (255, 220, 80), (236, 186, 60))
    bx, _ = w2a(spec, 500, 0)
    BA.paste(img, b, bx - b.width // 2, eave_y + 18)
    for wx in (-180, 1180):
        b2 = banner("LIÊN TỈNH", text_width("LIÊN TỈNH") + 12, 11, (28, 80, 160), (250, 250, 240), (236, 186, 60))
        px, _ = w2a(spec, wx, 0)
        BA.paste(img, b2, px - b2.width // 2, eave_y + 8)
    # Bảng tỷ số gỗ ở giữa.
    sx, _ = w2a(spec, 500, 0)
    sy = eave_y + 38
    rect(img, sx - 30, sy, 60, 22, (40, 50, 40))
    rect(img, sx - 30, sy, 60, 2, (180, 150, 90))
    for k, col in enumerate([(230, 60, 50), (60, 120, 230)]):
        rect(img, sx - 24 + k * 30, sy + 6, 18, 11, mix(col, (20, 20, 20), 0.3))
        rect(img, sx - 20 + k * 30, sy + 8, 10, 7, col)
    return BA.haze(img, BA.HAZE_MID, 0.12)


def pennants(spec, y_world, colors, sag=14.0, gap=None):
    img = BA.new_layer(spec)
    w = spec[2]
    _, y0 = w2a(spec, 0, y_world)
    poles = list(range(0, w + 1, 170))
    if gap is not None:
        g0, _ = w2a(spec, gap[0], 0)
        g1, _ = w2a(spec, gap[1], 0)
        poles = [p for p in poles if p <= g0 or p >= g1]
    for a, b in zip(poles, poles[1:]):
        if gap is not None and a <= w2a(spec, gap[0], 0)[0] and b >= w2a(spec, gap[1], 0)[0]:
            continue
        for x in range(a, b):
            t = (x - a) / (b - a)
            y = int(y0 + sag * 4 * t * (1 - t))
            img.putpixel((x, y), rgba((60, 50, 40)))
            if (x - a) % 9 == 2:
                col = colors[((x - a) // 9) % len(colors)]
                for k in range(6):
                    for j in range(-(3 - k // 2), 4 - k // 2):
                        if 0 <= x + j < w:
                            img.putpixel((x + j, y + 1 + k), rgba(col))
    return img


def lt_bunt():
    spec = BA.L_BUNT
    img = pennants(spec, -380, [(220, 50, 40), (250, 210, 60), (40, 110, 210), (60, 170, 80)])
    img.alpha_composite(pennants(spec, -336, [(250, 210, 60), (220, 50, 40), (250, 250, 240)], sag=10, gap=(230, 770)))
    # Băng dọc màu tỉnh treo hai bên.
    for wx, col in [(-300, (40, 110, 210)), (-90, (220, 50, 40)), (1090, (60, 170, 80)), (1300, (250, 180, 40))]:
        x, y = w2a(spec, wx, -400)
        rect(img, x, y, 10, 44, col)
        rect(img, x, y, 10, 2, (236, 186, 60))
        for k in range(3):
            rect(img, x + 2 + k * 3, y + 44, 2, 3 + k % 2, col)
        rect(img, x + 3, y + 10, 4, 4, (250, 240, 200))
    return img


def lt_stands():
    spec = BA.L_STANDS
    img = BA.new_layer(spec)
    w, h = spec[2], spec[3]
    for row in range(4):
        for x in range(w):
            wx = spec[0] + x * PX
            q = ((wx - 500.0) / 610.0) ** 2
            top_w = -64 - 26 * row - 12 + 34 * q * 0.8 - 2
            _, ty = w2a(spec, wx, top_w)
            for y in range(max(0, ty), h):
                c = (186, 186, 182) if (y - ty) > 1 else (214, 214, 208)
                if (y - ty) in (3, 4):
                    c = (60, 110, 190) if (x // 24) % 2 == 0 else (236, 236, 230)
                img.putpixel((x, y), rgba(c))
    return BA.haze(img, BA.HAZE_CROWD, 0.22)


def lt_fence():
    spec = BA.L_FENCE
    img = BA.new_layer(spec)
    w, h = spec[2], spec[3]
    arr = np.zeros((h, w, 4), np.uint8)
    for x in range(w):
        wx = spec[0] + x * PX
        base = BA.fence_base(wx)
        hh = BA.fence_height(wx) * 0.8
        _, by = w2a(spec, wx, base)
        _, ty = w2a(spec, wx, base - hh)
        panel = (x // 40) % 2
        for y in range(max(0, ty), min(h, by + 1)):
            c = (196, 52, 44) if panel else (240, 236, 226)
            if y - ty < 2 or by - y < 2:
                c = (150, 156, 164)
            arr[y, x] = rgba(c)
        if 0 <= ty - 1 < h:
            arr[ty - 1, x] = rgba((210, 216, 222))
        if x % 40 == 0:
            for y in range(max(0, ty - 3), min(h, by + 1)):
                arr[y, x] = rgba((110, 116, 126))
    img = Image.fromarray(arr, "RGBA")
    # Hình gà trống đơn giản trên bảng trắng (họa tiết chung, không nhãn hàng).
    for x0 in range(20, w, 80):
        wx = spec[0] + (x0 + 20) * PX
        _, by = w2a(spec, wx, BA.fence_base(wx))
        cy = by - 10
        d = ImageDraw.Draw(img)
        d.ellipse([x0 + 14, cy - 4, x0 + 24, cy + 3], fill=rgba((196, 52, 44)))
        d.polygon([(x0 + 22, cy - 4), (x0 + 26, cy - 9), (x0 + 28, cy - 6), (x0 + 25, cy - 2)], fill=rgba((196, 52, 44)))
        d.polygon([(x0 + 14, cy - 2), (x0 + 9, cy - 8), (x0 + 12, cy + 1)], fill=rgba((40, 40, 50)))
    return img


def lt_floor():
    spec = BA.L_FLOOR
    w, h = spec[2], spec[3]
    arr = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.uint8)
    noise = rng.integers(-5, 6, size=(h, w)).astype(np.float32)
    clay, clay_d = np.array((196, 120, 84), np.float32), np.array((150, 88, 62), np.float32)
    for y in range(h):
        wy = spec[1] + y * PX
        for x in range(w):
            wx = spec[0] + x * PX
            base = BA.fence_base(wx)
            if wy < base - 6:
                continue
            alpha[y, x] = 255
            t = np.clip((wy - base) / 50.0, 0.0, 1.0)
            c = clay_d + (clay - clay_d) * t
            if wy > 50:
                c = c + (clay_d - c) * np.clip((wy - 50) / 240.0, 0.0, 1.0) * 0.7
            arr[y, x] = c + noise[y, x]
    img = BA.from_np(arr, alpha)
    cx, cy = w2a(spec, 500, 14)
    rx, ry = 480 // PX, 40 // PX
    for i in range(900):
        a = 2 * math.pi * i / 900
        for dr in (0, 1):
            x = int(round(cx + (rx + dr) * math.cos(a)))
            y = int(round(cy + ry * math.sin(a)))
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((x, y), (246, 240, 228, 255))
    for sx in (370, 630):
        ax, ay = w2a(spec, sx, 0)
        for k in range(-4, 5):
            img.putpixel((ax, ay + k), (246, 240, 228, 255))
    return img


def lt_front():
    spec = BA.L_FRONT
    img = BA.new_layer(spec)
    w, h = spec[2], spec[3]
    d = ImageDraw.Draw(img)
    # Lan can sắt mờ ở tiền cảnh + vài ghế nhựa đỏ ở hai mép.
    for x in range(0, w, 3):
        wx = spec[0] + x * PX
        if 40 < wx < 960:
            continue
        rect(img, x, 40, 2, 60, (60, 64, 72), 150)
    rect(img, 0, 40, w, 3, (90, 96, 106), 170)
    for wx in (-300, -160, 1120, 1260):
        x, _ = w2a(spec, wx, 0)
        d.rectangle([x, 70, x + 22, 82], fill=(170, 40, 34, 190))
        d.rectangle([x + 2, 82, x + 4, 100], fill=(150, 34, 30, 190))
        d.rectangle([x + 18, 82, x + 20, 100], fill=(150, 34, 30, 190))
    return img


# ------------------------------------------------------------------ OLYMPIC

def ol_sky():
    spec = BA.L_SKY
    w, h = spec[2], spec[3]
    arr = BA.dither_gradient(h, w, [(0.0, (10, 12, 26)), (0.6, (22, 26, 52)), (1.0, (44, 40, 70))])
    img = BA.from_np(arr)
    d = ImageDraw.Draw(img)
    # Dàn thép mái.
    for y in range(40, h, 70):
        d.line([0, y, w, y], fill=rgba((70, 76, 96)), width=1)
    for x in range(0, w, 40):
        d.line([x, 0, x + 20, h], fill=rgba((48, 52, 72)), width=1)
        d.line([x + 40, 0, x + 20, h], fill=rgba((48, 52, 72)), width=1)
    # Giàn đèn pha.
    for gx in range(30, w, 150):
        gy = h - 60
        d.rectangle([gx, gy, gx + 60, gy + 6], fill=rgba((80, 84, 100)))
        for k in range(5):
            d.rectangle([gx + 2 + k * 12, gy + 6, gx + 10 + k * 12, gy + 12], fill=rgba((255, 250, 220)))
            d.rectangle([gx + 4 + k * 12, gy + 8, gx + 8 + k * 12, gy + 10], fill=rgba((255, 255, 255)))
    return img


def ol_far():
    spec = BA.L_FAR
    w, h = spec[2], spec[3]
    img = BA.new_layer(spec)
    rect(img, 0, 0, w, h, (26, 26, 44))
    cols = [(200, 60, 50), (230, 200, 80), (60, 110, 210), (230, 230, 230), (80, 170, 90), (220, 120, 60)]
    for row in range(0, h - 20, 7):
        shade = 0.35 + 0.45 * row / h
        rect(img, 0, row + 5, w, 2, mix((30, 30, 48), (60, 60, 84), shade))
        for x in range(int(rng.integers(0, 4)), w, 4):
            c = mix(cols[int(rng.integers(0, len(cols)))], (30, 30, 50), 0.55 - 0.3 * shade)
            rect(img, x, row + 1, 2, 2, mix(c, (240, 210, 180), 0.25))
            rect(img, x, row + 3, 3, 2, c)
    rect(img, 0, h - 20, w, 20, (40, 40, 60))
    rect(img, 0, h - 20, w, 2, (236, 184, 60))
    return img


def ol_mid():
    spec = BA.L_MID
    w, h = spec[2], spec[3]
    img = BA.new_layer(spec)
    d = ImageDraw.Draw(img)
    # Màn hình lớn treo giữa với huy hiệu + chữ.
    cx, _ = w2a(spec, 500, 0)
    top, _ = 30, 0
    sw, sh = 150, 96
    d.rectangle([cx - sw // 2 - 3, top - 3, cx + sw // 2 + 2, top + sh + 2], fill=rgba((20, 22, 30)))
    d.rectangle([cx - sw // 2, top, cx + sw // 2 - 1, top + sh - 1], fill=rgba((16, 30, 70)))
    for y in range(top, top + sh, 2):
        d.line([cx - sw // 2, y, cx + sw // 2 - 1, y], fill=rgba((22, 40, 88)))
    em = emblem(28)
    BA.paste(img, em, cx - em.width // 2, top + 6)
    t = "OLYMPIC ĐÁ GÀ"
    draw_text(img, t, cx - text_width(t) // 2, top + sh - 16, (255, 220, 90), (90, 40, 10))
    d.line([cx - 30, top - 3, cx - 30, 0], fill=rgba((70, 76, 96)))
    d.line([cx + 30, top - 3, cx + 30, 0], fill=rgba((70, 76, 96)))
    # Hai màn phụ + băng rôn đỏ vàng có huy hiệu nhỏ.
    for wx in (-160, 1160):
        x, _ = w2a(spec, wx, 0)
        d.rectangle([x - 34, 52, x + 34, 100], fill=rgba((20, 22, 30)))
        d.rectangle([x - 32, 54, x + 32, 98], fill=rgba((150, 26, 30)))
        small = emblem(14)
        BA.paste(img, small, x - small.width // 2, 58)
        t2 = "HUYỀN THOẠI"
        draw_text(img, t2, x - text_width(t2) // 2, 89, (255, 220, 90))
    for wx in (180, 820):
        x, _ = w2a(spec, wx, 0)
        d.rectangle([x - 8, 20, x + 8, 120], fill=rgba((176, 30, 34)))
        d.rectangle([x - 8, 20, x + 8, 22], fill=rgba((236, 184, 60)))
        small = emblem(7)
        BA.paste(img, small, x - small.width // 2, 40)
        for k in range(3):
            d.rectangle([x - 6 + k * 5, 120, x - 4 + k * 5, 124 + k % 2], fill=rgba((176, 30, 34)))
    # Lan can tầng trên.
    rect(img, 0, h - 26, w, 3, (236, 184, 60))
    rect(img, 0, h - 23, w, 23, (30, 30, 46))
    return img


def ol_bunt():
    spec = BA.L_BUNT
    img = BA.new_layer(spec)
    w = spec[2]
    _, y0 = w2a(spec, 0, -420)
    rect(img, 0, y0, w, 1, (90, 96, 110))
    cols = [(200, 40, 40), (250, 200, 50), (40, 90, 200), (60, 160, 80), (240, 240, 240), (230, 110, 40), (120, 60, 160)]
    g0, _ = w2a(spec, 250, 0)
    g1, _ = w2a(spec, 750, 0)
    for i, x in enumerate(range(4, w, 22)):
        if g0 - 14 < x < g1:
            continue  # chừa màn hình lớn ở giữa
        c = cols[i % len(cols)]
        rect(img, x, y0 + 1, 14, 20, c)
        rect(img, x, y0 + 1, 14, 2, mix(c, (255, 255, 255), 0.4))
        rect(img, x + 4, y0 + 8, 6, 6, mix(c, (255, 255, 255), 0.55) if i % 2 else mix(c, (0, 0, 0), 0.35))
    return img


def ol_stands():
    spec = BA.L_STANDS
    w, h = spec[2], spec[3]
    img = BA.new_layer(spec)
    for row in range(4):
        for x in range(w):
            wx = spec[0] + x * PX
            q = ((wx - 500.0) / 610.0) ** 2
            top_w = -64 - 26 * row - 12 + 34 * q * 0.8 - 2
            _, ty = w2a(spec, wx, top_w)
            for y in range(max(0, ty), h):
                k = y - ty
                c = (60, 60, 76)
                if k in (1, 2, 3):
                    c = (168, 34, 40) if (x % 4) != 0 else (120, 24, 30)
                if k == 0:
                    c = (200, 60, 64)
                img.putpixel((x, y), rgba(c))
    return img


def ol_fence():
    spec = BA.L_FENCE
    w, h = spec[2], spec[3]
    arr = np.zeros((h, w, 4), np.uint8)
    for x in range(w):
        wx = spec[0] + x * PX
        base = BA.fence_base(wx)
        hh = BA.fence_height(wx) * 0.7
        _, by = w2a(spec, wx, base)
        _, ty = w2a(spec, wx, base - hh)
        seg = (x // 70) % 3
        for y in range(max(0, ty), min(h, by + 1)):
            k = (y - ty) / max(1, by - ty)
            col = [(20, 90, 200), (200, 40, 50), (230, 170, 40)][seg]
            c = mix(col, (10, 12, 30), 0.25 + 0.4 * k)
            if (x + y) % 4 == 0:
                c = mix(c, (255, 255, 255), 0.25)  # điểm LED
            if y - ty < 1:
                c = (230, 236, 250)
            arr[y, x] = rgba(c)
    img = Image.fromarray(arr, "RGBA")
    # Chữ chạy trên bảng LED.
    for x0 in range(30, w, 210):
        wx = spec[0] + (x0 + 40) * PX
        _, by = w2a(spec, wx, BA.fence_base(wx))
        draw_text(img, "OLYMPIC ĐÁ GÀ", x0, by - 12, (255, 255, 230))
    return img


def ol_floor():
    spec = BA.L_FLOOR
    w, h = spec[2], spec[3]
    arr = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.uint8)
    mat, mat_d = np.array((40, 70, 140), np.float32), np.array((20, 34, 78), np.float32)
    for y in range(h):
        wy = spec[1] + y * PX
        for x in range(w):
            wx = spec[0] + x * PX
            base = BA.fence_base(wx)
            if wy < base - 6:
                continue
            alpha[y, x] = 255
            dx = (wx - BA.RING_CX) / BA.RING_RX
            dy = (wy - BA.RING_CY) / BA.RING_RY
            inside = dx * dx + dy * dy <= 1.0
            t = np.clip((wy - base) / 40.0, 0.0, 1.0)
            c = mat_d + (mat - mat_d) * t
            if not inside:
                c = c * 0.55
            if wy > 60:
                c = c * (1.0 - 0.4 * np.clip((wy - 60) / 200.0, 0.0, 1.0))
            arr[y, x] = c
    img = BA.from_np(arr, alpha)
    # Vòng vàng + huy hiệu nằm (ép dẹt theo phối cảnh).
    cx, cy = w2a(spec, 500, 14)
    for rx, ry, col in [(480 // PX, 40 // PX, (236, 184, 60)), (470 // PX, 37 // PX, (180, 130, 40))]:
        for i in range(900):
            a = 2 * math.pi * i / 900
            x = int(round(cx + rx * math.cos(a)))
            y = int(round(cy + ry * math.sin(a)))
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((x, y), rgba(col))
    em = emblem(40).resize((90, 26), Image.NEAREST)
    a = np.asarray(em).astype(np.float32)
    a[..., 3] *= 0.55
    em = Image.fromarray(a.astype(np.uint8), "RGBA")
    BA.paste(img, em, cx - em.width // 2, cy - em.height // 2 + 4)
    for sx in (370, 630):
        ax, ay = w2a(spec, sx, 0)
        for k in range(-4, 5):
            img.putpixel((ax, ay + k), (236, 236, 250, 255))
    return img


def ol_front():
    spec = BA.L_FRONT
    img = BA.new_layer(spec)
    w = spec[2]
    d = ImageDraw.Draw(img)
    # Bóng đầu khán giả hàng đầu + máy quay ở hai mép (tối, mờ).
    for wx in list(range(-400, 40, 26)) + list(range(960, 1420, 26)):
        x, _ = w2a(spec, wx, 0)
        r = 7 + (wx // 26) % 3
        d.ellipse([x - r, 74 - r, x + r, 74 + r], fill=(8, 8, 16, 220))
        d.rectangle([x - r - 3, 74, x + r + 3, 120], fill=(8, 8, 16, 220))
    for wx in (-120, 1110):
        x, _ = w2a(spec, wx, 0)
        d.rectangle([x - 10, 50, x + 14, 64], fill=(20, 20, 26, 230))
        d.rectangle([x + 14, 54, x + 22, 60], fill=(30, 30, 40, 230))
        d.line([x, 64, x - 8, 110], fill=(20, 20, 26, 230), width=2)
        d.line([x + 4, 64, x + 10, 110], fill=(20, 20, 26, 230), width=2)
    return img


def main():
    out = BA.OUT_DIR
    os.makedirs(out, exist_ok=True)
    sets = {
        "lien_tinh": {"far": lt_far, "mid": lt_mid, "bunt": lt_bunt, "stands": lt_stands, "fence": lt_fence,
                      "floor": lt_floor, "front": lt_front},
        "olympic": {"sky": ol_sky, "far": ol_far, "mid": ol_mid, "bunt": ol_bunt, "stands": ol_stands,
                    "fence": ol_fence, "floor": ol_floor, "front": ol_front},
    }
    for variant, layers in sets.items():
        for layer, fn in layers.items():
            img = fn()
            name = "arena_%s_%s.png" % (variant, layer)
            img.save(os.path.join(out, name), optimize=True)
            print("wrote", name, img.size)


if __name__ == "__main__":
    main()
