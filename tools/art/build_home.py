# -*- coding: utf-8 -*-
"""Sinh art cho NHÀ & CHUỒNG GÀ (game/home): nền nội thất + sân sau, đồ đạc, bội gà, lò ấp, người nhà.

Vẽ hoàn toàn bằng code (Pillow), cùng ngôn ngữ pixel-art với bản đồ làng (game/art/map/map_atlas_*.png): mảng
màu phẳng, viền 1 px là sắc tối hơn của chính màu đó (không viền đen), gỗ ván ngang, cửa sổ chớp xanh, gạch tàu.
Toạ độ (px thế giới, 1 px art = 1 px thế giới; camera zoom 3) phải khớp với game/home/home_layout.gd.

GHI CHÚ: nhà giờ dùng nội thất vẽ tay (tools/art/build_home_interior.py → game/art/home/interior/). Mặc định script
này chỉ còn sinh những ảnh game vẫn dùng: vương miện gà chiến (crown), trứng (egg, egg_rare); người nhà kiểu cũ
(npc_me/npc_cha/npc_em) vẫn sinh nhưng KHÔNG còn dùng – người nhà đi lại + chân dung giờ là family_*.png của
tools/art/build_family.py (cùng kiểu nhân vật chính bản mới). Nền + đồ đạc vẽ code cũ chỉ sinh khi thêm --legacy.

Chạy:  python tools/art/build_home.py           (ghi vào game/art/home/)
       python tools/art/build_home.py --legacy  (ghi thêm nền/đồ đạc cũ – chỉ để tham khảo)
       python tools/art/build_home.py --preview DIR   (ghi thêm ảnh ghép xem trước vào DIR)
"""
from __future__ import annotations

import os
import random
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "art", "home")

MAP_W, MAP_H = 800, 288
ROOM_W = 400          # nội thất x 0..400, sân sau x 400..800
WALL_FACE = 56        # vách gỗ phía trên (mặt tường nhìn thẳng)
FLOOR_BOTTOM = 264    # vách dưới y 264..272
FRONT_DOOR = (176, 216)
BACK_DOOR = (146, 194)  # khe cửa trên vách phải (theo y)

rng = random.Random(20261117)


# ----------------------------------------------------------------------------- tiện ích vẽ

def C(h: str, a: int = 255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f: float):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


def new(w: int, h: int):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def rect(d, x, y, w, h, fill):
    if w <= 0 or h <= 0:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=fill)


def box(d, x, y, w, h, fill, edge: float = 0.62):
    """Khối màu phẳng có viền 1 px tối hơn."""
    rect(d, x, y, w, h, shade(fill, edge))
    rect(d, x + 1, y + 1, w - 2, h - 2, fill)


def px(d, x, y, c):
    d.point((x, y), fill=c)


def hline(d, x, y, w, c):
    rect(d, x, y, w, 1, c)


def vline(d, x, y, h, c):
    rect(d, x, y, 1, h, c)


def ellipse(d, x, y, w, h, fill, outline=None):
    d.ellipse([x, y, x + w - 1, y + h - 1], fill=fill, outline=outline)


def shadow(d, cx, cy, w, h, a=70):
    ellipse(d, cx - w // 2, cy - h // 2, w, h, (20, 12, 6, a))


def save(im: Image.Image, name: str):
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name))


# ----------------------------------------------------------------------------- bảng màu

WOOD = C("8a5a36")
WOOD_D = C("6e4428")
WOOD_L = C("9e6c44")
BEAM = C("4a2e1c")
TILE = C("b5603e")
TILE_D = C("8e4a30")
TILE_L = C("c8744f")
GREEN = C("3f8f3a")
GREEN_D = C("2c6a2a")
DIRT = C("a98a5c")
DIRT_D = C("957650")
DIRT_L = C("bb9c6c")
GRASS = C("6f9a48")
GRASS_D = C("557c36")
BAMBOO = C("c8a860")
BAMBOO_D = C("94763c")
STRAW = C("dcc271")
STRAW_D = C("b19a4d")
LACQUER = C("7a2a1a")
GOLD = C("e8b84a")
RED = C("c23a2a")
WHITE = C("efe9dc")
SKIN = C("e2a878")
SKIN_D = C("b97c52")
HAIR = C("2a1f1c")


# ----------------------------------------------------------------------------- nền (nội thất + sân sau)

def window(d, x, y, w=40, h=26):
    box(d, x - 6, y, 6, h, GREEN)              # cánh chớp trái
    box(d, x + w, y, 6, h, GREEN)              # cánh chớp phải
    for i in range(1, h - 1, 4):
        hline(d, x - 5, y + i, 4, GREEN_D)
        hline(d, x + w + 1, y + i, 4, GREEN_D)
    box(d, x, y, w, h, C("39424c"))            # khung tối (ngoài trời)
    rect(d, x + 1, y + 1, w - 2, h - 2, C("7fb0cf"))
    rect(d, x + 1, y + h - 9, w - 2, 8, C("6f9a58"))  # vườn ngoài cửa sổ
    for i in range(x + 4, x + w - 2, 5):
        vline(d, i, y + 1, h - 2, C("8f949a"))  # song sắt
    box(d, x - 2, y + h, w + 4, 3, WOOD_L)      # bậu cửa


def planks(d, x0, y0, w, h, base, dark, light, step=7):
    rect(d, x0, y0, w, h, base)
    for y in range(y0, y0 + h, step):
        hline(d, x0, y, w, dark)
        # mối nối ván so le
        off = rng.randrange(0, 40)
        for x in range(x0 + off, x0 + w, rng.randrange(36, 60)):
            vline(d, x, y, step, dark)
        for _ in range(w // 30):
            hline(d, x0 + rng.randrange(0, max(1, w - 8)), y + rng.randrange(2, step), rng.randrange(3, 8), light)


def build_ground():
    im, d = new(MAP_W, MAP_H)
    rect(d, 0, 0, MAP_W, MAP_H, C("21170f"))

    # ---- nội thất: vách gỗ phía trên
    planks(d, 8, 0, ROOM_W - 16, WALL_FACE, WOOD, WOOD_D, WOOD_L)
    rect(d, 8, 0, ROOM_W - 16, 4, BEAM)
    rect(d, 8, WALL_FACE - 5, ROOM_W - 16, 5, C("5a3a22"))   # ván chân tường
    hline(d, 8, WALL_FACE - 5, ROOM_W - 16, C("7a5234"))
    window(d, 104, 12)
    window(d, 244, 12, 34, 26)
    # lịch bloc
    box(d, 70, 14, 16, 20, WHITE)
    rect(d, 71, 15, 14, 5, RED)
    rect(d, 74, 23, 8, 6, C("c23a2a", 200))
    # hoành phi đỏ phía trên bàn thờ
    box(d, 172, 5, 56, 10, LACQUER)
    for i in range(178, 224, 9):
        rect(d, i, 8, 5, 4, GOLD)
    # gạch men xanh sau góc bếp
    rect(d, 296, 22, 96, WALL_FACE - 27, C("d6e2e6"))
    for x in range(296, 392, 8):
        vline(d, x, 22, WALL_FACE - 27, C("a9bfc6"))
    for y in range(22, WALL_FACE - 5, 8):
        hline(d, 296, y, 96, C("a9bfc6"))
    for x in range(300, 392, 16):
        rect(d, x, 30, 4, 4, C("5f9fb8"))
    # đồng hồ treo tường
    ellipse(d, 22, 12, 16, 16, C("efe2c0"), C("6e4428"))
    vline(d, 30, 15, 6, HAIR)
    hline(d, 30, 20, 4, HAIR)

    # ---- sàn gạch tàu
    for ty in range(WALL_FACE, FLOOR_BOTTOM, 16):
        for tx in range(8, ROOM_W - 8, 16):
            base = TILE if ((tx // 16 + ty // 16) % 3) else shade(TILE, 0.95)
            rect(d, tx, ty, 16, 16, base)
            hline(d, tx, ty, 16, TILE_D)
            vline(d, tx, ty, 16, TILE_D)
            px(d, tx + 2, ty + 2, TILE_L)
            px(d, tx + 3, ty + 2, TILE_L)
            if rng.random() < 0.25:
                px(d, tx + rng.randrange(4, 14), ty + rng.randrange(4, 14), shade(TILE, 0.9))
    # tấm chiếu trải trước bàn thờ
    rect(d, 182, 96, 36, 10, C("c9b27a"))
    for x in range(183, 217, 3):
        vline(d, x, 97, 8, C("a89058"))

    # ---- vách trái / dưới / phải (nhìn từ trên: dải gỗ tối)
    rect(d, 0, 0, 8, FLOOR_BOTTOM + 8, BEAM)
    rect(d, 0, FLOOR_BOTTOM, ROOM_W, 8, BEAM)
    hline(d, 0, FLOOR_BOTTOM, ROOM_W, C("6a4228"))
    # cửa trước: ngạch cửa + thảm chùi chân
    x0, x1 = FRONT_DOOR
    rect(d, x0, FLOOR_BOTTOM, x1 - x0, 8, C("8a6a4a"))
    hline(d, x0, FLOOR_BOTTOM + 3, x1 - x0, C("6e5238"))
    box(d, x0 + 6, FLOOR_BOTTOM - 12, x1 - x0 - 12, 10, C("b24a3a"))
    for x in range(x0 + 8, x1 - 8, 3):
        vline(d, x, FLOOR_BOTTOM - 10, 6, C("8e3a2c"))
    # ngõ trước nhà (đất) dưới ngạch
    rect(d, x0 - 8, FLOOR_BOTTOM + 8, x1 - x0 + 16, MAP_H - FLOOR_BOTTOM - 8, DIRT)
    # vách phải với khe cửa sau
    rect(d, ROOM_W - 8, 0, 8, FLOOR_BOTTOM + 8, BEAM)
    y0, y1 = BACK_DOOR
    rect(d, ROOM_W - 8, y0, 8, y1 - y0, C("8a6a4a"))
    for y in range(y0, y1, 4):
        hline(d, ROOM_W - 8, y, 8, C("7a5a3c"))
    rect(d, ROOM_W - 9, y0 - 3, 10, 3, C("3a2416"))
    rect(d, ROOM_W - 9, y1, 10, 3, C("3a2416"))

    # ---- sân sau: đất nện, cỏ, hàng rào tre
    rect(d, ROOM_W, 0, MAP_W - ROOM_W, MAP_H, DIRT)
    for _ in range(900):
        x, y = rng.randrange(ROOM_W, MAP_W), rng.randrange(0, MAP_H)
        hline(d, x, y, rng.randrange(1, 4), DIRT_D if rng.random() < 0.6 else DIRT_L)
    for _ in range(40):  # mảng đất nện sậm hơn
        x, y = rng.randrange(ROOM_W, MAP_W - 30), rng.randrange(30, MAP_H - 30)
        ellipse(d, x, y, rng.randrange(14, 30), rng.randrange(6, 12), shade(DIRT, 0.96))
    # cỏ dọc rào và góc sân
    for _ in range(260):
        side = rng.random()
        if side < 0.35:
            gx, gy = rng.randrange(ROOM_W + 4, MAP_W - 10), rng.randrange(28, 44)
        elif side < 0.6:
            gx, gy = rng.randrange(ROOM_W + 4, MAP_W - 10), rng.randrange(262, 278)
        elif side < 0.85:
            gx, gy = rng.randrange(690, 786), rng.randrange(30, 276)
        else:
            gx, gy = rng.randrange(ROOM_W + 4, MAP_W - 10), rng.randrange(30, 276)
        for k in range(rng.randrange(2, 5)):
            vline(d, gx + k * 2, gy - rng.randrange(1, 4), rng.randrange(2, 4), GRASS if k % 2 else GRASS_D)
    # tán lá chuối/dừa sau rào
    rect(d, ROOM_W, 0, MAP_W - ROOM_W, 12, C("3d6630"))
    for x in range(ROOM_W, MAP_W, 9):
        ellipse(d, x - 4, rng.randrange(-4, 4), rng.randrange(12, 18), rng.randrange(9, 13), C("4f7a3a"))
        px(d, x + 2, 3, C("6a9a4a"))
    # rào tre trên
    fence_h(d, ROOM_W, 8, MAP_W - ROOM_W, 22)
    # rào phải + dưới
    rect(d, MAP_W - 10, 0, 10, MAP_H, C("3d6630"))
    for y in range(4, MAP_H, 5):
        box(d, MAP_W - 9, y, 8, 5, BAMBOO)
    vline(d, MAP_W - 7, 0, MAP_H, BAMBOO_D)
    vline(d, MAP_W - 3, 0, MAP_H, BAMBOO_D)
    fence_h(d, ROOM_W, MAP_H - 12, MAP_W - ROOM_W, 12)
    # cánh cửa sau mở ra phía sân (ván gỗ, áp sát vách)
    box(d, ROOM_W, BACK_DOOR[0] - 26, 5, 26, WOOD_L)
    hline(d, ROOM_W + 1, BACK_DOOR[0] - 14, 3, WOOD_D)
    # đá kê trước cửa sau
    for i, (sx, sy) in enumerate([(404, 168), (416, 176), (412, 160)]):
        ellipse(d, sx, sy, 9, 6, C("a8a294"), C("7c776c"))
    return im


def fence_h(d, x0, y0, w, h):
    rect(d, x0, y0 + h // 3, w, 2, C("7a5a30"))
    rect(d, x0, y0 + (2 * h) // 3, w, 2, C("7a5a30"))
    for x in range(x0, x0 + w, 6):
        top = y0 + (x // 6 % 2)
        box(d, x, top, 5, h - (x // 6 % 2), BAMBOO)
        px(d, x + 2, top + h // 2, BAMBOO_D)
    rect(d, x0, y0 + h // 3, w, 1, C("6a4a22"))
    rect(d, x0, y0 + (2 * h) // 3, w, 1, C("6a4a22"))


# ----------------------------------------------------------------------------- đồ đạc nội thất

def build_altar():
    """Bàn thờ: tủ sơn mài đỏ, khăn điều, ảnh ông nội, bát nhang, đèn dầu, mâm ngũ quả. 64x64, chân ở đáy."""
    im, d = new(64, 66)
    shadow(d, 32, 62, 60, 6)
    # thân tủ
    box(d, 2, 30, 60, 32, LACQUER)
    rect(d, 4, 33, 56, 2, GOLD)
    for x in (6, 34):
        box(d, x, 38, 24, 20, shade(LACQUER, 1.15))
        rect(d, x + 3, 41, 18, 14, shade(LACQUER, 0.85))
        px(d, x + 20, 48, GOLD)
    # mặt bàn + khăn điều rủ xuống
    box(d, 0, 24, 64, 8, C("8e3424"))
    rect(d, 10, 30, 44, 8, RED)
    for x in range(10, 54, 4):
        px(d, x, 37, GOLD)
    rect(d, 10, 30, 44, 1, GOLD)
    # ảnh ông nội (khung đen, ảnh nâu đỏ)
    box(d, 24, 2, 16, 20, C("2a2018"))
    rect(d, 26, 4, 12, 16, C("c9a77a"))
    ellipse(d, 28, 6, 8, 8, C("8a6a4a"))          # đầu
    rect(d, 27, 13, 10, 7, C("5a4632"))           # áo
    px(d, 30, 9, C("3a2a1a"))
    px(d, 33, 9, C("3a2a1a"))
    hline(d, 30, 11, 4, C("e8e0d0"))              # râu bạc
    # bát nhang + nhang
    box(d, 28, 21, 8, 5, C("c99a3a"))
    for x, h in ((30, 9), (32, 11), (34, 9)):
        vline(d, x, 21 - h, h, C("8a4a2a"))
        px(d, x, 21 - h, C("ff7a3a"))
    # đèn dầu hai bên
    for x in (12, 48):
        box(d, x, 16, 5, 9, C("e7d9b0"))
        px(d, x + 2, 14, C("ffd060"))
        px(d, x + 2, 15, C("ff9a30"))
    # mâm ngũ quả bên phải
    ellipse(d, 50, 21, 12, 5, C("c99a3a"))
    ellipse(d, 51, 16, 5, 6, C("e9c13a"))         # chuối
    ellipse(d, 55, 16, 5, 5, C("6aa040"))         # mãng cầu
    ellipse(d, 53, 13, 5, 5, C("f08a2a"))         # cam
    # bình hoa bên trái
    box(d, 3, 15, 6, 10, C("4a7aa0"))
    for (fx, fy, fc) in ((3, 9, "f0d040"), (7, 8, "f06a6a"), (5, 6, "f0d040")):
        ellipse(d, fx, fy, 3, 3, C(fc))
    return im


def build_bed():
    """Bộ ván gõ có chiếu, gối, mền xếp và mùng cột ở bốn góc. 82x60."""
    im, d = new(82, 62)
    shadow(d, 41, 58, 80, 7)
    box(d, 1, 38, 80, 16, C("6a3e22"))            # mặt trước ván
    for x in (4, 74):
        box(d, x, 50, 5, 9, C("5a321a"))           # chân
    box(d, 1, 8, 80, 32, C("9a6438"))             # mặt ván
    # chiếu
    rect(d, 5, 11, 72, 27, C("d8c48a"))
    for y in range(12, 37, 3):
        hline(d, 5, y, 72, C("c0a86a"))
    for x in range(5, 77, 12):
        vline(d, x, 11, 27, C("b8784a"))
    rect(d, 5, 11, 72, 2, C("b23a2a"))
    rect(d, 5, 36, 72, 2, C("b23a2a"))
    # gối + mền xếp
    box(d, 8, 13, 18, 9, C("f2ece0"))
    hline(d, 10, 17, 14, C("d8cbb6"))
    box(d, 54, 22, 20, 12, C("6a8ec4"))
    hline(d, 55, 27, 18, C("5274a8"))
    # cọc mùng + mùng cột lại
    for x in (2, 77):
        vline(d, x + 1, 0, 40, C("5a321a"))
        vline(d, x + 2, 0, 40, C("7a4a2a"))
    rect(d, 2, 0, 79, 2, C("efefef", 180))
    for x in (5, 72):
        ellipse(d, x, 1, 6, 10, C("f4f4f0", 210))
    return im


def build_desk():
    """Bàn học: sách, vở, đèn bàn, ống bút. 62x44 (chiếc ghế vẽ riêng)."""
    im, d = new(62, 46)
    shadow(d, 31, 42, 60, 6)
    box(d, 1, 26, 60, 14, C("6e4428"))            # mặt trước
    rect(d, 4, 29, 24, 8, C("5e3a22"))            # hộc kéo
    px(d, 15, 32, GOLD)
    for x in (3, 55):
        box(d, x, 38, 4, 6, C("5a321a"))
    box(d, 0, 12, 62, 16, C("a2703f"))            # mặt bàn
    hline(d, 1, 13, 60, C("b88452"))
    # chồng sách
    for i, col in enumerate(("c23a2a", "3a6ab0", "4a9a4a", "e0b040")):
        box(d, 40, 12 - i * 3, 16, 4, C(col))
        vline(d, 54, 13 - i * 3, 2, WHITE)
    # vở mở
    rect(d, 18, 15, 18, 10, WHITE)
    vline(d, 27, 15, 10, C("b8b0a0"))
    for y in range(17, 24, 2):
        hline(d, 19, y, 7, C("8aa0c8"))
        hline(d, 28, y, 7, C("8aa0c8"))
    # đèn bàn
    box(d, 4, 18, 10, 4, C("2f6a4a"))
    vline(d, 8, 4, 15, C("4a5a5a"))
    box(d, 3, 1, 12, 6, C("3f8f5a"))
    rect(d, 5, 6, 8, 2, C("fff2b0"))
    # ống bút
    box(d, 36, 15, 4, 7, C("c25a8a"))
    vline(d, 37, 11, 4, C("e0d040"))
    vline(d, 38, 12, 3, C("3a6ab0"))
    return im


def build_chair():
    im, d = new(14, 22)
    shadow(d, 7, 20, 14, 4)
    box(d, 1, 0, 12, 10, C("8a5a36"))
    box(d, 0, 9, 14, 6, C("a2703f"))
    for x in (1, 11):
        vline(d, x, 15, 6, C("5a321a"))
        vline(d, x + 1, 15, 6, C("5a321a"))
    return im


def build_dining():
    """Mâm cơm: bàn gỗ thấp, nồi cơm, tô canh, dĩa cá, chén đũa, bốn ghế đẩu. 76x52."""
    im, d = new(78, 54)
    shadow(d, 39, 46, 74, 10)
    # ghế đẩu trên/dưới (vẽ sau lưng bàn trước)
    for x in (14, 52):
        box(d, x, 0, 12, 7, C("c23a2a"))
    box(d, 8, 10, 62, 26, C("a2703f"))            # mặt bàn
    hline(d, 9, 11, 60, C("b88452"))
    box(d, 8, 34, 62, 6, C("6e4428"))
    for x in (10, 64):
        box(d, x, 38, 4, 8, C("5a321a"))
    # nồi cơm điện, tô canh, dĩa cá kho, chén
    box(d, 12, 13, 12, 11, C("e8e2d6"))
    rect(d, 13, 13, 10, 3, C("c9c2b4"))
    px(d, 17, 19, RED)
    ellipse(d, 30, 15, 16, 10, C("f2ece0"), C("b8b0a0"))
    ellipse(d, 32, 17, 12, 6, C("d8b25a"))
    ellipse(d, 50, 14, 16, 9, C("f2ece0"), C("b8b0a0"))
    ellipse(d, 53, 16, 10, 5, C("8a4a2a"))
    for x in (14, 28, 46, 60):
        ellipse(d, x, 26, 7, 6, C("f2ece0"), C("8aa0c8"))
    hline(d, 36, 30, 8, C("6e4428"))
    hline(d, 36, 31, 8, C("6e4428"))
    # ghế đẩu phía trước
    for x in (14, 52):
        box(d, x, 44, 12, 7, C("c23a2a"))
        vline(d, x + 2, 50, 3, C("8e2a1e"))
        vline(d, x + 9, 50, 3, C("8e2a1e"))
    return im


def build_kitchen():
    """Góc bếp: kệ bếp ốp gạch men, bồn rửa inox có chén dĩa, bếp ga + nồi, rổ chén. 90x54.
    Bồn rửa ở x 14..40 (tâm 27) – SINK_POS trong home_layout.gd đứng ngay trước bồn."""
    im, d = new(90, 56)
    shadow(d, 45, 52, 88, 6)
    box(d, 0, 24, 90, 26, C("6aa0c0"))            # mặt trước ốp gạch xanh
    for x in range(0, 90, 6):
        vline(d, x, 25, 24, C("5a8aa8"))
    for y in range(30, 50, 6):
        hline(d, 1, y, 88, C("5a8aa8"))
    box(d, 0, 6, 90, 20, C("d8d6cc"))             # mặt kệ
    hline(d, 1, 7, 88, C("eceae2"))
    # bồn rửa
    box(d, 14, 8, 26, 15, C("b8c0c8"))
    rect(d, 16, 10, 22, 11, C("7a8490"))
    rect(d, 17, 15, 20, 5, C("8fb6cf"))           # nước
    vline(d, 27, 0, 10, C("9aa2aa"))              # vòi
    hline(d, 24, 0, 7, C("9aa2aa"))
    # chén dĩa chồng bên cạnh bồn (chờ rửa)
    for i in range(4):
        ellipse(d, 2, 16 - i * 2, 11, 5, C("f4f0e6"), C("a8b8c8"))
    ellipse(d, 3, 6, 8, 5, C("f4f0e6"), C("a8b8c8"))
    # rổ chén úp
    box(d, 42, 8, 14, 12, C("d0b070"))
    for x in range(43, 56, 3):
        vline(d, x, 9, 10, C("a88a48"))
    # bếp ga + nồi
    box(d, 58, 9, 30, 13, C("3a3a40"))
    for cx in (66, 80):
        ellipse(d, cx - 4, 12, 8, 7, C("1e1e22"))
        px(d, cx, 15, C("4a8aff"))
    ellipse(d, 60, 2, 13, 12, C("9aa2aa"), C("6a7278"))
    hline(d, 63, 1, 7, C("4a4a4a"))
    # ấm nước
    ellipse(d, 75, 5, 10, 9, C("c2c8cc"), C("7a8288"))
    vline(d, 84, 7, 3, C("7a8288"))
    return im


def build_hammock():
    """Võng dù giăng giữa hai cột (chỗ ba nằm trưa). 92x30."""
    im, d = new(92, 32)
    shadow(d, 46, 28, 80, 6)
    for x in (1, 87):
        box(d, x, 0, 4, 30, C("6e4428"))
    pts = [(5, 6), (20, 14), (46, 18), (72, 14), (87, 6)]
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=C("2e6aa0"), width=5)
    d.line([(8, 9), (46, 17), (84, 9)], fill=C("4a8ac8"), width=2)
    for x in range(14, 80, 8):
        px(d, x, 14 + (2 if 30 < x < 62 else 0), C("e0c040"))
    return im


def build_plant():
    im, d = new(18, 28)
    shadow(d, 9, 26, 16, 4)
    box(d, 3, 16, 12, 10, C("b5603e"))
    hline(d, 3, 18, 12, C("8e4a30"))
    for (lx, ly, lw, lh) in ((0, 4, 8, 12), (9, 2, 9, 13), (5, 0, 7, 15)):
        ellipse(d, lx, ly, lw, lh, C("4a8a3a"), C("2e6a2a"))
    return im


# ----------------------------------------------------------------------------- sân sau

def build_coop(door_open: bool):
    """Bội gà: lồng tre đan hình vòm (kiểu miền Tây), đáy lót rơm. 36x32, chân ở đáy giữa."""
    im, d = new(38, 34)
    shadow(d, 19, 30, 38, 7, 80)
    ellipse(d, 2, 25, 34, 7, STRAW)
    for x in range(4, 34, 3):
        px(d, x, 27 + (x % 2), STRAW_D)
    # bên trong tối
    d.pieslice([4, 3, 33, 50], 180, 360, fill=C("5a4022"))
    rect(d, 4, 26, 30, 4, C("5a4022"))
    # nan tre dọc (cong theo vòm)
    for i, x in enumerate(range(5, 34, 4)):
        top = 26 - int(22 * (1 - ((x - 19) / 15.0) ** 2) ** 0.5)
        vline(d, x, top, 29 - top, BAMBOO if i % 2 == 0 else shade(BAMBOO, 0.9))
        vline(d, x + 1, top + 1, 28 - top, BAMBOO_D)
    # vành ngang
    for y, inset in ((10, 7), (17, 3), (24, 1)):
        hline(d, 2 + inset, y, 34 - 2 * inset, shade(BAMBOO, 1.05))
        hline(d, 2 + inset, y + 1, 34 - 2 * inset, BAMBOO_D)
    d.arc([3, 3, 34, 50], 180, 360, fill=BAMBOO_D)
    # quai xách trên đỉnh
    d.arc([14, 0, 24, 8], 180, 360, fill=C("7a5a30"))
    # cửa lồng
    if door_open:
        d.pieslice([14, 17, 25, 38], 180, 360, fill=C("2e2012"))
        rect(d, 14, 27, 12, 3, C("2e2012"))
        box(d, 26, 19, 7, 10, shade(BAMBOO, 0.95))   # cửa đẩy sang bên
    else:
        d.pieslice([14, 17, 25, 38], 180, 360, fill=shade(BAMBOO, 0.95))
        for x in range(15, 25, 2):
            vline(d, x, 21, 8, BAMBOO_D)
    rect(d, 2, 29, 34, 2, STRAW_D)
    return im


def build_coop_plot():
    """Ô chuồng chưa xây: khung cọc + dây, tấm bảng dấu cộng. 38x32."""
    im, d = new(38, 34)
    ellipse(d, 2, 22, 34, 10, C("8a6e46", 120))
    for x in range(4, 34, 4):
        px(d, x, 24, C("f0e0b0", 200))
        px(d, x, 30, C("f0e0b0", 200))
    for (sx, sy) in ((3, 20), (33, 20), (3, 27), (33, 27)):
        box(d, sx - 1, sy - 2, 3, 6, C("8a5a36"))
    # bảng gỗ
    vline(d, 18, 8, 16, C("6e4428"))
    box(d, 11, 2, 15, 10, C("c8a060"))
    rect(d, 17, 4, 3, 6, C("2e7a3a"))
    rect(d, 15, 6, 7, 2, C("2e7a3a"))
    return im


def build_incubator():
    """Lò ấp: kệ gỗ hai ổ rơm, đèn sưởi chụp nhôm. 48x44. Trứng vẽ bằng code tại hai ổ (x 13 và 35, y 30)."""
    im, d = new(48, 46)
    shadow(d, 24, 42, 46, 6)
    for x in (2, 42):
        box(d, x, 4, 4, 38, C("6e4428"))
    box(d, 0, 30, 48, 8, C("8a5a36"))             # kệ
    hline(d, 1, 31, 46, C("a2703f"))
    for cx in (13, 35):
        ellipse(d, cx - 9, 25, 18, 9, STRAW)
        for k in range(-7, 8, 3):
            px(d, cx + k, 27 + (k % 2), STRAW_D)
        ellipse(d, cx - 5, 27, 10, 4, C("b8964a"))
    # thanh ngang treo đèn
    rect(d, 2, 3, 44, 3, C("5a3a22"))
    for cx in (13, 35):
        vline(d, cx, 6, 6, C("3a3a3a"))
        d.pieslice([cx - 6, 10, cx + 6, 22], 180, 360, fill=C("b8c0c8"), outline=C("7a8288"))
        ellipse(d, cx - 2, 14, 5, 4, C("ffb050"))
        px(d, cx, 15, C("fff0b0"))
    box(d, 30, 39, 12, 6, C("c23a2a"))            # ổ cắm/công tắc
    return im


def build_egg(speckled: bool):
    im, d = new(8, 10)
    ellipse(d, 0, 0, 8, 10, C("f4e8cc"), C("b8a070"))
    px(d, 2, 2, C("ffffff"))
    px(d, 2, 3, C("fffaf0"))
    if speckled:
        for (x, y) in ((4, 3), (5, 6), (2, 6), (4, 8), (6, 4)):
            px(d, x, y, C("8a5a36"))
    return im


def build_rice_jar():
    """Khạp lúa: khạp sành nâu đỏ nắp gỗ (giống A_khap_01 ngoài làng). 24x26."""
    im, d = new(24, 28)
    shadow(d, 12, 25, 24, 5)
    ellipse(d, 1, 4, 22, 22, C("a04a2a"), C("6e2e18"))
    ellipse(d, 4, 7, 8, 8, C("c06a3a"))
    hline(d, 3, 15, 18, C("d0a050"))
    box(d, 3, 1, 18, 5, C("8a5a36"))
    hline(d, 4, 2, 16, C("a2703f"))
    box(d, 10, 0, 4, 2, C("6e4428"))
    return im


def build_trough():
    """Máng ăn: ống tre bổ đôi có lúa. 42x14."""
    im, d = new(42, 16)
    shadow(d, 21, 13, 42, 5)
    box(d, 1, 3, 40, 9, BAMBOO)
    rect(d, 3, 4, 36, 4, C("e8c860"))
    for x in range(4, 38, 2):
        px(d, x, 5 + (x % 3 == 0), C("c8a040"))
    hline(d, 2, 9, 38, BAMBOO_D)
    for x in (4, 36):
        box(d, x, 10, 3, 5, C("6e4428"))
    return im


def build_water_jar():
    """Lu nước da lươn, nắp nhôm, gáo dừa. 26x28."""
    im, d = new(28, 30)
    shadow(d, 14, 27, 28, 5)
    ellipse(d, 1, 3, 26, 25, C("5a4a2a"), C("3a2e18"))
    ellipse(d, 4, 6, 9, 9, C("7a6a3a"))
    for y in (12, 18):
        hline(d, 3, y, 22, C("8a7a40"))
    ellipse(d, 4, 0, 20, 7, C("c2c8cc"), C("7a8288"))
    ellipse(d, 15, 0, 8, 5, C("6a4a2a"))
    hline(d, 19, 2, 8, C("8a6a3a"))
    return im


def build_post():
    """Cọc tập: cọc gỗ quấn dây đay + bao rơm, vòng cát dưới chân. 30x46."""
    im, d = new(30, 48)
    ellipse(d, 1, 36, 28, 10, C("d8c08a"))
    ellipse(d, 4, 38, 22, 6, C("c8ae76"))
    box(d, 12, 2, 7, 42, C("8a5a36"))
    vline(d, 13, 3, 40, C("a2703f"))
    for y in range(8, 30, 5):
        hline(d, 12, y, 7, C("d0b070"))
        hline(d, 12, y + 1, 7, C("a88a48"))
    # bao rơm treo
    vline(d, 22, 6, 6, C("7a5a30"))
    ellipse(d, 18, 11, 10, 16, STRAW, STRAW_D)
    hline(d, 19, 17, 8, C("a88a48"))
    return im


def build_banana():
    """Bụi chuối góc sân. 40x58."""
    im, d = new(40, 60)
    shadow(d, 20, 56, 30, 6)
    box(d, 17, 24, 7, 33, C("8aa05a"))
    vline(d, 18, 25, 30, C("a8bc72"))
    leaves = [((20, 26), (0, 8)), ((20, 26), (39, 10)), ((20, 24), (6, 0)), ((20, 24), (34, 0)), ((20, 28), (2, 26)),
              ((20, 28), (38, 28))]
    for (a, b) in leaves:
        d.line([a, b], fill=C("3e7a30"), width=7)
        d.line([a, b], fill=C("5e9a40"), width=3)
    ellipse(d, 22, 30, 6, 9, C("7a2a4a"))          # bắp chuối
    return im


def build_clothesline():
    """Sào phơi đồ với vài cái áo. 60x40."""
    im, d = new(62, 42)
    for x in (1, 58):
        box(d, x, 2, 3, 38, C("6e4428"))
    hline(d, 3, 5, 56, C("d8d8d0"))
    for (x, col) in ((10, "c23a2a"), (24, "f2ece0"), (38, "3a6ab0")):
        box(d, x, 6, 11, 12, C(col))
        rect(d, x - 2, 6, 3, 5, C(col))
        rect(d, x + 10, 6, 3, 5, C(col))
    shadow(d, 31, 39, 58, 4, 50)
    return im


# ----------------------------------------------------------------------------- người nhà (2 khung thở)

def person(d, ox, bob, *, hair, shirt, pants, height=42, bun=False, glasses=False, mustache=False, scarf=None,
           short=False, apron=None):
    """Nhân vật đứng nhìn thẳng kiểu NPC làng (20 px ngang, đầu to, mảng màu phẳng)."""
    top = 44 - height + bob
    head_h = 12
    # chân + dép
    leg_top = top + head_h + 14 + (0 if not short else -2)
    leg_h = 44 - leg_top - 2
    rect(d, ox + 6, leg_top, 3, leg_h, shade(pants, 0.8))
    rect(d, ox + 11, leg_top, 3, leg_h, shade(pants, 0.8))
    rect(d, ox + 5, leg_top, 10, max(2, leg_h - 4) if not short else 4, pants)
    if short:
        rect(d, ox + 6, leg_top + 4, 3, leg_h - 4, SKIN)
        rect(d, ox + 11, leg_top + 4, 3, leg_h - 4, SKIN)
    rect(d, ox + 5, 42, 4, 2, C("3a2a22"))
    rect(d, ox + 11, 42, 4, 2, C("3a2a22"))
    # thân áo + tay
    box(d, ox + 4, top + head_h, 12, 15, shirt, 0.72)
    rect(d, ox + 2, top + head_h + 1, 3, 11, shade(shirt, 0.88))
    rect(d, ox + 15, top + head_h + 1, 3, 11, shade(shirt, 0.88))
    rect(d, ox + 2, top + head_h + 11, 3, 3, SKIN)
    rect(d, ox + 15, top + head_h + 11, 3, 3, SKIN)
    if apron is not None:
        rect(d, ox + 6, top + head_h + 5, 8, 10, apron)
    if scarf is not None:
        rect(d, ox + 5, top + head_h, 10, 3, scarf)
        px(d, ox + 6, top + head_h + 1, WHITE)
        px(d, ox + 9, top + head_h + 1, WHITE)
        px(d, ox + 12, top + head_h + 1, WHITE)
    # đầu
    box(d, ox + 4, top, 12, head_h, SKIN, 0.78)
    rect(d, ox + 4, top, 12, 4, hair)
    rect(d, ox + 4, top + 3, 2, 4, hair)
    rect(d, ox + 14, top + 3, 2, 4, hair)
    if bun:
        box(d, ox + 7, top - 3, 6, 4, hair)
    px(d, ox + 7, top + 6, HAIR)
    px(d, ox + 12, top + 6, HAIR)
    if glasses:
        rect(d, ox + 6, top + 5, 3, 3, C("1e1e22"))
        rect(d, ox + 11, top + 5, 3, 3, C("1e1e22"))
        px(d, ox + 7, top + 6, C("9ac0e0"))
        px(d, ox + 12, top + 6, C("9ac0e0"))
        hline(d, ox + 9, top + 6, 2, C("1e1e22"))
    if mustache:
        hline(d, ox + 7, top + 9, 6, HAIR)
    else:
        hline(d, ox + 8, top + 9, 4, SKIN_D)


def build_people():
    out = {}
    specs = {
        # Mẹ: giáo viên – áo bà ba tím nhạt ở nhà, tóc búi, tạp dề khi nấu.
        "npc_me": dict(hair=C("1e1612"), shirt=C("b48ac8"), pants=C("2a2a36"), height=42, bun=True,
                       apron=C("e8dcc0")),
        # Cha: hiền, hài – áo thun sọc, khăn rằn quàng cổ, ria mép.
        "npc_cha": dict(hair=C("2a2420"), shirt=C("6a9a5a"), pants=C("4a4034"), height=43, mustache=True,
                        scarf=C("2a2a2a")),
        # Em trai: học sinh giỏi – áo trắng, quần xanh, đeo kính, thấp hơn.
        "npc_em": dict(hair=C("1a1410"), shirt=C("f2f2ee"), pants=C("2a4a8a"), height=36, glasses=True,
                       short=True),
    }
    for name, spec in specs.items():
        im, d = new(40, 44)
        for f in range(2):
            person(d, f * 20, 0 if f == 0 else 1, **spec)
        out[name] = im
        save(im, name + ".png")
    return out


def build_marker():
    """Vương miện vàng có nơ đỏ – đánh dấu gà chiến đang chọn. 13x11."""
    im, d = new(13, 11)
    pts = [(0, 3), (3, 6), (6, 0), (9, 6), (12, 3), (11, 9), (1, 9)]
    d.polygon(pts, fill=C("f0c040"), outline=C("a87a18"))
    rect(d, 2, 7, 9, 2, C("d89a20"))
    px(d, 6, 4, C("e03030"))
    px(d, 3, 7, C("e03030"))
    px(d, 9, 7, C("e03030"))
    rect(d, 4, 9, 5, 2, C("c23a2a"))
    return im


# ----------------------------------------------------------------------------- xuất

def main():
    preview_dir = None
    if "--preview" in sys.argv:
        preview_dir = sys.argv[sys.argv.index("--preview") + 1]
    os.makedirs(OUT, exist_ok=True)
    sprites = {
        "egg": build_egg(False), "egg_rare": build_egg(True), "crown": build_marker(),
    }
    if "--legacy" in sys.argv:
        sprites.update(legacy_sprites())
    for name, im in sprites.items():
        save(im, name + ".png")
    people = build_people()
    print("home art -> %s (%d files)" % (OUT, len(sprites) + len(people)))
    if preview_dir and "home_ground" in sprites:
        os.makedirs(preview_dir, exist_ok=True)
        sheet = Image.new("RGBA", (900, 140), C("3a4a3a"))
        x = 4
        for name, im in list(sprites.items())[1:] + list(people.items()):
            if x + im.width > 900:
                break
            sheet.paste(im, (x, 4), im)
            x += im.width + 4
        sheet.resize((1800, 280), Image.NEAREST).save(os.path.join(preview_dir, "home_props.png"))
        sprites["home_ground"].resize((1600, 576), Image.NEAREST).save(os.path.join(preview_dir, "home_ground.png"))


def legacy_sprites():
    """Nền + đồ đạc của nhà vẽ code cũ (800×288) – không còn dùng trong game."""
    return {
        "home_ground": build_ground(),
        "altar": build_altar(), "bed": build_bed(), "desk": build_desk(), "chair": build_chair(),
        "dining": build_dining(), "kitchen": build_kitchen(), "hammock": build_hammock(), "plant": build_plant(),
        "coop": build_coop(True), "coop_empty": build_coop(False), "coop_plot": build_coop_plot(),
        "incubator": build_incubator(), "egg": build_egg(False), "egg_rare": build_egg(True),
        "rice_jar": build_rice_jar(), "trough": build_trough(), "water_jar": build_water_jar(),
        "post": build_post(), "banana": build_banana(), "clothesline": build_clothesline(),
    }


if __name__ == "__main__":
    main()
