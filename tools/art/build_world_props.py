# -*- coding: utf-8 -*-
"""Vẽ bằng code các công trình mới đặt lên bản đồ thế giới (kiểu pixel art của bản đồ, viền (42,30,46)).

Chạy:  python -I tools/art/build_world_props.py [--preview <thư_mục>]
Ghi vào game/art/world/:
    cat_shop.png          Tiệm Mèo: sạp gỗ mái sọc, bảng hiệu cá + dấu chân, hũ khô, khô gà treo (64×58)
    cat_shop_cat.png      mèo tam thể mập ngồi quầy, 6 khung 20×16 (ngồi, chớp mắt, vẫy đuôi ×3, ngáp)
    arena_lien_tinh.png   Sân Liên tỉnh miền Tây: khán đài có mái, vòng sới, tường trước + cổng soát vé (400×176)
    arena_lien_tinh_flags.png   cờ đuôi nheo trên cột, 4 khung 12×10
    arena_olympic.png     Sân Olympic Đá Gà: mặt tiền sân vận động, biểu tượng 5 mào gà, bậc thềm (300×200)
    arena_olympic_torch.png     ngọn đuốc, 4 khung 12×16
    arena_olympic_carpet.png    thảm đỏ trải từ bậc thềm xuống đường (lớp mặt đất)
    parked_bike_a.png / parked_bike_b.png   xe máy đậu (nhìn nghiêng) trước sân
    signpost.png          cột biển chỉ đường (gỗ) 7×40
    signpost_boards.png   tấm biển: mỗi hàng một nơi (SIGN_ROWS), mỗi cột một hướng ← → ↑ ↓ (44×9 mỗi ô)
    ticket_booth.png      chòi bán vé (Liên tỉnh)
Không có số ngẫu nhiên không gieo hạt: chạy lại cho ra cùng ảnh. Toạ độ đặt trên bản đồ nằm trong game/world/world.gd.
"""
from __future__ import annotations

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "art", "world")

O = (42, 30, 46, 255)          # viền chung của mọi vật trên bản đồ
SHADOW = (24, 20, 30, 70)
WOOD = (150, 98, 58, 255)
WOOD_D = (110, 68, 40, 255)
WOOD_L = (188, 134, 84, 255)
CREAM = (250, 236, 200, 255)
ORANGE = (236, 128, 52, 255)
ORANGE_D = (196, 92, 36, 255)
RED = (206, 52, 48, 255)
RED_D = (150, 34, 38, 255)
YELLOW = (250, 206, 72, 255)
YELLOW_D = (214, 160, 44, 255)
BLUE = (66, 116, 196, 255)
BLUE_D = (44, 80, 150, 255)
BLUE_L = (120, 168, 226, 255)
WHITE = (246, 244, 236, 255)
GREY = (176, 176, 180, 255)
GREY_D = (124, 122, 132, 255)
SAND = (232, 200, 140, 255)
SAND_D = (206, 168, 108, 255)
GREEN = (84, 160, 72, 255)
GLASS = (150, 206, 222, 255)
SKIN = (240, 196, 150, 255)
BLACK = (36, 30, 38, 255)

SIGN_ROWS = ["CHO BINH KE", "TRUONG THPT", "SAN LIEN TINH", "SAN OLYMPIC", "BEN DO", "SOI AO LANG", "TIEM MEO"]

# Phông pixel 3×5 (chữ in hoa không dấu, như biển hiệu có sẵn trên bản đồ).
FONT = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
    "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
    "K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
    "M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
    "O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
    "Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "011"], "V": ["101", "101", "101", "010", "010"],
    "W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["110", "001", "010", "100", "111"], "3": ["110", "001", "010", "001", "110"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"],
    "6": ["011", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
    "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "110"],
    " ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"],
    ".": ["000", "000", "000", "000", "010"], "!": ["010", "010", "010", "000", "010"],
}


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def text_width(s):
    return len(s) * 4 - 1


def put_text(img, x, y, s, col):
    px = img.load()
    for i, ch in enumerate(s):
        glyph = FONT.get(ch, FONT[" "])
        for gy, line in enumerate(glyph):
            for gx, bit in enumerate(line):
                if bit == "1":
                    xx, yy = x + i * 4 + gx, y + gy
                    if 0 <= xx < img.width and 0 <= yy < img.height:
                        px[xx, yy] = col


def rect(d, x0, y0, x1, y1, fill, outline=None):
    d.rectangle([x0, y0, x1, y1], fill=fill, outline=outline)


def outline(img, col=O):
    """Viền 1 px quanh mọi pixel đục (giống viền vật thể của bản đồ)."""
    arr = np.asarray(img).copy()
    m = arr[..., 3] > 0
    n = np.zeros_like(m)
    n[1:, :] |= m[:-1, :]
    n[:-1, :] |= m[1:, :]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    edge = n & ~m
    arr[edge] = col
    return Image.fromarray(arr, "RGBA")


def pad(img, p=1):
    out = canvas(img.width + 2 * p, img.height + 2 * p)
    out.paste(img, (p, p))
    return out


def stripes(d, x0, y0, x1, y1, a, b, w=4):
    for x in range(x0, x1 + 1):
        col = a if ((x - x0) // w) % 2 == 0 else b
        d.line([x, y0, x, y1], fill=col)


# ------------------------------------------------------------------ Tiệm Mèo

def cat_shop():
    W, H = 64, 58
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # cột + quầy gỗ
    rect(d, 4, 18, 6, 50, WOOD_D)
    rect(d, 57, 18, 59, 50, WOOD_D)
    rect(d, 2, 36, 61, 51, WOOD)            # thân quầy
    rect(d, 2, 36, 61, 38, WOOD_L)          # mặt quầy
    for x in range(6, 60, 9):
        d.line([x, 40, x, 51], fill=WOOD_D)
    rect(d, 2, 51, 61, 53, WOOD_D)          # chân quầy
    # kệ sau quầy: hũ khô (hũ thuỷ tinh nắp đỏ)
    rect(d, 7, 24, 56, 35, (96, 64, 44, 255))
    for i, x in enumerate((9, 18, 27, 38, 47)):
        rect(d, x, 27, x + 6, 34, GLASS)
        rect(d, x, 25, x + 6, 26, RED if i % 2 == 0 else ORANGE)
        rect(d, x + 1, 30, x + 5, 33, (196, 120, 64, 255) if i % 2 else (214, 150, 90, 255))
    # mái sọc cam-kem có diềm răng cưa
    rect(d, 0, 6, 63, 15, ORANGE)
    stripes(d, 0, 6, 63, 15, ORANGE, CREAM, 5)
    for x in range(0, 64, 5):
        d.polygon([(x, 16), (x + 4, 16), (x + 2, 18)], fill=ORANGE_D if (x // 5) % 2 == 0 else CREAM)
    rect(d, 0, 5, 63, 6, ORANGE_D)
    # thanh treo khô gà (dải thịt khô đỏ nâu)
    d.line([7, 19, 56, 19], fill=WOOD_D)
    for x in range(9, 56, 5):
        ln = 6 + (x * 7) % 4
        rect(d, x, 20, x + 1, 20 + ln, (170, 70, 46, 255))
        d.point((x, 20 + ln), fill=(120, 44, 30, 255))
    # bảng hiệu trên mái: cá + dấu chân mèo + chữ
    rect(d, 14, 0, 49, 5, BLUE)
    put_text(img, 18, 1 - 1 + 0, "", WHITE)
    img2 = outline(pad(img, 1))
    d2 = ImageDraw.Draw(img2)
    # chữ TIEM MEO trên bảng xanh (vẽ sau viền cho rõ)
    put_text(img2, 18, 1, "TIEM", WHITE)
    # cá nhỏ trên bảng (trái)
    fx, fy = 16, 2
    for (x, y) in [(0, 1), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2), (3, 1), (4, 0), (4, 2)]:
        d2.point((fx + x - 1, fy + y), fill=YELLOW)
    # dấu chân mèo (phải)
    px, py = 44, 1
    for (x, y) in [(1, 2), (2, 2), (1, 3), (2, 3), (0, 0), (2, 0), (3, 1), (0, 1) if False else (3, 1)]:
        d2.point((px + x, py + y), fill=(255, 190, 200, 255))
    put_text(img2, 35, 1, "", WHITE)
    # cái chén cá trên quầy
    rect(d2, 50, 35, 55, 37, WHITE)
    d2.point((52, 34), fill=(130, 170, 200, 255))
    return img2


def cat_frames():
    """Mèo tam thể mập ngồi trên quầy (nhìn chính diện): 0 ngồi, 1 chớp mắt, 2-4 vẫy đuôi, 5 ngáp."""
    FW, FH = 20, 16
    sheet = canvas(FW * 6, FH)
    for f in range(6):
        img = canvas(FW - 2, FH - 2)
        d = ImageDraw.Draw(img)
        body = WHITE
        # thân tròn mập
        d.ellipse([3, 5, 14, 14], fill=body)
        # đốm tam thể
        rect(d, 4, 8, 7, 11, ORANGE)
        rect(d, 11, 6, 13, 9, BLACK)
        rect(d, 10, 11, 13, 13, ORANGE)
        # đầu
        d.ellipse([4, 1, 13, 9], fill=body)
        d.polygon([(4, 3), (5, 0), (7, 2)], fill=ORANGE)       # tai trái cam
        d.polygon([(10, 2), (12, 0), (13, 3)], fill=BLACK)     # tai phải đen
        rect(d, 9, 2, 12, 4, BLACK)                            # mảng đen trên đầu
        # mắt
        if f == 1:
            d.line([6, 5, 7, 5], fill=O)
            d.line([10, 5, 11, 5], fill=O)
        elif f == 5:
            d.point((6, 5), fill=O)
            d.point((11, 5), fill=O)
        else:
            rect(d, 6, 4, 7, 5, (90, 170, 80, 255))
            rect(d, 10, 4, 11, 5, (90, 170, 80, 255))
            d.point((7, 5), fill=O)
            d.point((11, 5), fill=O)
        # mũi/miệng
        d.point((8, 6), fill=(240, 130, 150, 255))
        d.point((9, 6), fill=(240, 130, 150, 255))
        if f == 5:
            rect(d, 8, 7, 9, 8, (190, 60, 80, 255))
        # chân trước
        rect(d, 6, 13, 7, 13, CREAM)
        rect(d, 10, 13, 11, 13, CREAM)
        # đuôi: cong sang phải, vẫy lên theo khung
        tail = {0: [(15, 13), (16, 12), (17, 11)], 1: [(15, 13), (16, 12), (17, 11)],
                2: [(15, 13), (16, 12), (17, 10), (17, 9)], 3: [(15, 13), (16, 11), (16, 10), (17, 8)],
                4: [(15, 13), (16, 13), (17, 12)], 5: [(15, 13), (16, 12), (17, 11)]}[f]
        for (x, y) in tail:
            rect(d, x - 1, y, x, y, ORANGE)
        sheet.paste(outline(pad(img, 1)), (f * FW, 0))
    return sheet


# ------------------------------------------------------------------ Sân Liên tỉnh

def crowd_dots(d, x0, y0, x1, y1, seed, rows=2):
    rng = np.random.default_rng(seed)
    cols = [RED, BLUE, YELLOW, GREEN, WHITE, ORANGE, (170, 90, 200, 255)]
    for r in range(rows):
        y = y0 + r * 5
        if y + 4 > y1:
            break
        for x in range(x0 + (r % 2) * 2, x1 - 2, 4):
            if rng.random() < 0.12:
                continue
            c = cols[int(rng.integers(0, len(cols)))]
            rect(d, x, y + 2, x + 2, y + 4, c)          # áo
            rect(d, x, y, x + 2, y + 1, SKIN)           # đầu
            if rng.random() < 0.3:
                rect(d, x, y, x + 2, y, BLACK)          # tóc


def arena_lien_tinh():
    W, H = 400, 176
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # nền sân trong (đất nện) + tường bao
    rect(d, 6, 30, W - 7, 150, (196, 160, 112, 255))
    # khán đài sau: mái tôn xanh có sọc, hàng ghế đông người
    rect(d, 6, 4, W - 7, 22, BLUE)
    for x in range(6, W - 6, 6):
        d.line([x, 4, x, 22], fill=BLUE_D)
    rect(d, 6, 22, W - 7, 24, BLUE_D)
    for x in range(14, W - 10, 48):
        rect(d, x, 24, x + 2, 52, GREY_D)                 # cột khán đài
    rect(d, 6, 25, W - 7, 52, (160, 150, 140, 255))      # bậc khán đài
    for y in range(28, 52, 6):
        d.line([6, y, W - 7, y], fill=(134, 124, 116, 255))
    crowd_dots(d, 10, 26, W - 10, 52, 11, rows=5)
    # khán đài hai bên (thấp hơn, mái đỏ)
    for x0 in (6, W - 66):
        rect(d, x0, 52, x0 + 59, 132, (160, 150, 140, 255))
        crowd_dots(d, x0 + 3, 56, x0 + 57, 130, 20 + x0, rows=15)
        rect(d, x0, 50, x0 + 59, 56, RED)
        for xx in range(x0, x0 + 60, 5):
            d.line([xx, 50, xx, 56], fill=RED_D)
    # vòng sới giữa: cát + hàng rào tre vàng
    cx, cy, rx, ry = W // 2, 92, 92, 34
    d.ellipse([cx - rx - 6, cy - ry - 5, cx + rx + 6, cy + ry + 5], fill=SAND_D)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=SAND)
    d.ellipse([cx - rx + 10, cy - ry + 6, cx + rx - 10, cy + ry - 6], outline=(240, 214, 160, 255))
    for k in range(0, 360, 10):
        a = np.radians(k)
        x = cx + (rx + 3) * np.cos(a)
        y = cy + (ry + 3) * np.sin(a)
        rect(d, int(x) - 1, int(y) - 4, int(x), int(y), YELLOW_D)
    # hai chiến kê giữa sới
    for (x, col) in ((cx - 14, RED), (cx + 9, (240, 190, 60, 255))):
        rect(d, x, cy - 2, x + 5, cy + 2, col)
        rect(d, x + (4 if col == RED else -1), cy - 4, x + (6 if col == RED else 1), cy - 2, col)
        d.point((x + (6 if col == RED else 0), cy - 5), fill=RED_D)
    # tường trước (gạch sơn trắng-xanh) với băng rôn
    rect(d, 0, 132, W - 1, 160, WHITE)
    rect(d, 0, 152, W - 1, 160, (120, 160, 210, 255))
    for x in range(0, W, 16):
        d.line([x, 152, x, 160], fill=BLUE_D)
    # cổng chính giữa: vòm + bảng tên
    gx0, gx1 = W // 2 - 34, W // 2 + 33
    rect(d, gx0 - 6, 104, gx1 + 6, 112, RED)              # bảng tên trên cổng
    rect(d, gx0 - 6, 112, gx0 + 2, 160, (210, 200, 186, 255))
    rect(d, gx1 - 2, 112, gx1 + 6, 160, (210, 200, 186, 255))
    rect(d, gx0 + 3, 116, gx1 - 3, 160, (70, 54, 48, 255))  # lối vào tối
    rect(d, gx0 + 3, 150, gx1 - 3, 160, (150, 120, 90, 255))
    for x in range(gx0 + 6, gx1 - 3, 6):
        d.line([x, 116, x, 149], fill=(120, 120, 128, 255))  # cửa lưới kéo
    # băng rôn hai bên cổng
    for bx in (30, W - 110):
        rect(d, bx, 136, bx + 80, 148, YELLOW)
        rect(d, bx, 136, bx + 80, 137, YELLOW_D)
    # cột cờ trên tường (cờ vẽ bằng sprite động riêng)
    for x in (12, 100, W - 101, W - 13):
        rect(d, x, 112, x + 1, 133, GREY_D)
    img = outline(pad(img, 1))
    # chữ (vẽ sau viền)
    name = "SAN LIEN TINH"
    put_text(img, W // 2 - text_width(name) // 2 + 1, 106, name, YELLOW)
    put_text(img, 31 + 40 - text_width("GIAI DA GA") // 2 + 1, 139, "GIAI DA GA", RED_D)
    put_text(img, W - 109 + 40 - text_width("MIEN TAY") // 2 + 1, 139, "MIEN TAY", RED_D)
    return img


def flag_frames(c1, c2):
    FW, FH = 12, 10
    sheet = canvas(FW * 4, FH)
    for f in range(4):
        img = canvas(FW - 2, FH - 2)
        d = ImageDraw.Draw(img)
        wave = [0, 1, 0, -1][f]
        for x in range(0, 9):
            off = int(round(np.sin((x + f * 2) * 0.9) * 1.0)) if x > 1 else 0
            top = 1 + off
            bot = 5 + off - (x // 4)
            if bot < top:
                bot = top
            for y in range(top, bot + 1):
                img.putpixel((x, y), c1 if (y - top) < (bot - top + 1) / 2 else c2)
        _ = wave
        sheet.paste(outline(pad(img, 1)), (f * FW, 0))
    return sheet


def ticket_booth():
    img = canvas(26, 30)
    d = ImageDraw.Draw(img)
    rect(d, 1, 8, 24, 29, (226, 214, 190, 255))
    rect(d, 0, 2, 25, 8, RED)
    stripes(d, 0, 2, 25, 8, RED, WHITE, 3)
    rect(d, 4, 12, 21, 20, GLASS)
    rect(d, 4, 18, 21, 20, WOOD)
    rect(d, 10, 13, 15, 17, SKIN)          # cô bán vé
    rect(d, 10, 13, 15, 14, BLACK)
    img = outline(pad(img, 1))
    put_text(img, 9, 23, "VE", RED_D)
    return img


def parked_bike(body):
    img = canvas(30, 18)
    d = ImageDraw.Draw(img)
    for cx in (6, 23):
        d.ellipse([cx - 4, 10, cx + 4, 17], fill=BLACK)
        d.ellipse([cx - 2, 12, cx + 2, 15], fill=GREY)
    rect(d, 8, 8, 20, 12, body)
    rect(d, 9, 5, 17, 7, BLACK)            # yên
    rect(d, 21, 3, 22, 11, GREY)           # phuộc
    rect(d, 19, 2, 25, 3, GREY)            # tay lái
    rect(d, 23, 5, 25, 7, YELLOW)          # đèn
    return outline(pad(img, 1))


# ------------------------------------------------------------------ Sân Olympic

def comb(d, x, y, col, dark):
    """Một mào gà (3 răng) – mô-típ của biểu tượng 5 mào."""
    d.polygon([(x, y + 9), (x + 2, y + 2), (x + 4, y + 6), (x + 6, y), (x + 8, y + 6), (x + 10, y + 2),
               (x + 12, y + 9)], fill=col)
    d.line([x, y + 9, x + 12, y + 9], fill=dark)


def arena_olympic():
    W, H = 300, 200
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # thân sân vận động cong (nhìn từ trước): tầng trên + vòm
    d.ellipse([0, 0, W - 1, 120], fill=(222, 216, 204, 255))
    rect(d, 0, 60, W - 1, 150, (222, 216, 204, 255))
    d.ellipse([10, 6, W - 11, 110], fill=(236, 232, 222, 255))
    rect(d, 10, 58, W - 11, 150, (236, 232, 222, 255))
    # mái vòm xanh trên đỉnh (lộ trên mép sau)
    d.chord([20, -30, W - 21, 60], 0, 180, fill=BLUE_L)
    d.chord([20, -30, W - 21, 60], 0, 180, outline=BLUE_D)
    # dãy cửa vòm tầng trên
    for i, x in enumerate(range(24, W - 30, 22)):
        rect(d, x, 64, x + 12, 86, (96, 120, 160, 255))
        d.pieslice([x, 58, x + 12, 70], 180, 360, fill=(96, 120, 160, 255))
        rect(d, x + 2, 70, x + 10, 86, GLASS if i % 2 else BLUE_L)
    # đai đỏ giữa hai tầng
    rect(d, 0, 92, W - 1, 100, RED)
    for x in range(0, W, 10):
        d.line([x, 92, x, 100], fill=RED_D)
    # tầng dưới: cột trắng + 3 cổng lớn
    for x in range(8, W - 6, 18):
        rect(d, x, 100, x + 6, 150, WHITE)
        d.line([x + 6, 100, x + 6, 150], fill=GREY)
    for gx in (W // 2 - 26, 50, W - 90):
        gw = 52 if gx == W // 2 - 26 else 40
        rect(d, gx, 112, gx + gw, 150, (60, 48, 52, 255))
        d.pieslice([gx, 102, gx + gw, 124], 180, 360, fill=(60, 48, 52, 255))
        rect(d, gx + 2, 140, gx + gw - 2, 150, (170, 40, 44, 255))
    # biểu tượng 5 mào gà xếp hai hàng (không phải vòng tròn Olympic)
    ex, ey = W // 2 - 38, 18
    cols = [(BLUE, BLUE_D), (BLACK, (20, 16, 20, 255)), (RED, RED_D), (YELLOW, YELLOW_D), (GREEN, (50, 110, 44, 255))]
    for i, (c, dk) in enumerate(cols):
        x = ex + i * 16 if i < 3 else ex + 8 + (i - 3) * 16
        y = ey if i < 3 else ey + 9
        comb(d, x, y, c, dk)
    rect(d, ex - 4, ey + 21, ex + 50, ey + 29, CREAM)     # bảng tên dưới biểu tượng
    # bậc thềm trước cổng
    for i in range(4):
        rect(d, 40 - i * 6, 150 + i * 6, W - 41 + i * 6, 155 + i * 6, (210, 204, 194, 255) if i % 2 == 0 else (196, 190, 180, 255))
    # bệ đuốc hai bên (ngọn lửa là sprite động riêng)
    for x in (18, W - 30):
        rect(d, x, 132, x + 11, 172, GREY)
        rect(d, x - 2, 128, x + 13, 132, GREY_D)
        rect(d, x + 2, 120, x + 9, 128, (190, 150, 60, 255))
    # cột cờ trước mặt tiền
    for x in range(60, W - 60, 36):
        rect(d, x, 104, x + 1, 128, GREY_D)
    img = outline(pad(img, 1))
    put_text(img, W // 2 - 38 - 4 + 1 + (54 - text_width("DA GA")) // 2, ey + 23, "DA GA", RED_D)
    title = "SAN OLYMPIC DA GA"
    rect(ImageDraw.Draw(img), W // 2 - text_width(title) // 2 - 3, 41, W // 2 + text_width(title) // 2 + 3, 49, RED)
    put_text(img, W // 2 - text_width(title) // 2 + 1, 43, title, YELLOW)
    return img


def torch_frames():
    FW, FH = 12, 16
    sheet = canvas(FW * 4, FH)
    shapes = [
        [(5, 1), (4, 3), (6, 3), (3, 6), (7, 5), (3, 9), (8, 8)],
        [(4, 0), (5, 2), (3, 4), (7, 4), (2, 7), (8, 6), (3, 10)],
        [(6, 1), (4, 2), (7, 4), (3, 5), (8, 7), (2, 9), (7, 9)],
        [(5, 0), (6, 3), (3, 3), (8, 6), (2, 6), (8, 9), (3, 9)],
    ]
    for f in range(4):
        img = canvas(FW - 2, FH - 2)
        d = ImageDraw.Draw(img)
        pts = shapes[f]
        d.polygon([(1, 13), (9, 13)] + sorted(pts, key=lambda p: -p[0]), fill=ORANGE)
        d.polygon([(3, 13), (7, 13), (5, 4 + f % 2)], fill=YELLOW)
        d.point((5, 11), fill=WHITE)
        sheet.paste(outline(pad(img, 1), (120, 40, 30, 255)), (f * FW, 0))
    return sheet


def carpet():
    img = canvas(40, 48)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, 39, 47, (190, 36, 44, 255))
    rect(d, 2, 0, 37, 47, RED)
    for y in range(4, 48, 8):
        d.line([4, y, 35, y], fill=(222, 70, 66, 255))
    rect(d, 0, 0, 1, 47, YELLOW_D)
    rect(d, 38, 0, 39, 47, YELLOW_D)
    return img


# ------------------------------------------------------------------ biển chỉ đường

def signpost():
    img = canvas(5, 38)
    d = ImageDraw.Draw(img)
    rect(d, 1, 0, 3, 37, WOOD)
    d.line([3, 0, 3, 37], fill=WOOD_D)
    rect(d, 0, 35, 4, 37, WOOD_D)
    return outline(pad(img, 1))


def signpost_boards():
    """Hàng = nơi (SIGN_ROWS), cột = hướng mũi tên: 0 trái, 1 phải, 2 lên, 3 xuống. Ô 52×9."""
    CW, CH = 52, 9
    colors = [ORANGE, BLUE, RED, (120, 70, 170, 255), (60, 140, 160, 255), (150, 98, 58, 255), (200, 110, 150, 255)]
    sheet = canvas(CW * 4, CH * len(SIGN_ROWS))
    for r, label in enumerate(SIGN_ROWS):
        tw = text_width(label)
        for c in range(4):
            board_w = tw + 12
            img = canvas(board_w, 7)
            d = ImageDraw.Draw(img)
            col = colors[r % len(colors)]
            if c == 0:
                d.polygon([(0, 3), (3, 0), (board_w - 1, 0), (board_w - 1, 6), (3, 6)], fill=col)
            elif c == 1:
                d.polygon([(0, 0), (board_w - 4, 0), (board_w - 1, 3), (board_w - 4, 6), (0, 6)], fill=col)
            else:
                rect(d, 0, 0, board_w - 1, 6, col)
            put_text(img, 4 if c != 1 else 3, 1, label, WHITE)
            if c == 2:
                for (x, y) in [(1, 2), (2, 1), (3, 2), (2, 3), (2, 4)]:
                    img.putpixel((board_w - 4 + x - 1, y), YELLOW)
            if c == 3:
                for (x, y) in [(2, 1), (2, 2), (1, 3), (3, 3), (2, 4)]:
                    img.putpixel((board_w - 4 + x - 1, y), YELLOW)
            img = outline(pad(img, 1))
            sheet.paste(img, (c * CW + (CW - img.width) // 2, r * CH))
    return sheet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    outputs = {
        "cat_shop.png": cat_shop(),
        "cat_shop_cat.png": cat_frames(),
        "arena_lien_tinh.png": arena_lien_tinh(),
        "arena_lien_tinh_flags.png": flag_frames(RED, YELLOW),
        "arena_olympic.png": arena_olympic(),
        "arena_olympic_torch.png": torch_frames(),
        "arena_olympic_flags.png": flag_frames(BLUE, WHITE),
        "arena_olympic_carpet.png": carpet(),
        "parked_bike_a.png": parked_bike(RED),
        "parked_bike_b.png": parked_bike(BLUE),
        "signpost.png": signpost(),
        "signpost_boards.png": signpost_boards(),
        "ticket_booth.png": ticket_booth(),
    }
    for name, img in outputs.items():
        img.save(os.path.join(OUT, name))
        print(name, img.size)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        for name, img in outputs.items():
            img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(os.path.join(args.preview, "x3_" + name))


if __name__ == "__main__":
    main()
