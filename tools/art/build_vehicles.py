"""Xe máy NPC mới cho bản đồ (vẽ pixel bằng code, không logo/nhãn hiệu) → game/art/vehicles/vehicles_atlas.png + vehicles.json.

    python -I tools/art/build_vehicles.py [--preview <thư_mục>]

Mỗi kiểu xe nhìn ngang quay sang đông (hướng tây = lật gương), 4 khung bánh xe quay, bóng đổ riêng; cùng cỡ/viền với xe
NPC của bản đồ (bike_01..04 trong game/art/world_map/traffic.json: khung ~72×60 gồm cả người lái, viền 1 px tối
(42, 30, 46), bánh ~18 px). Gốc (anchor) = điểm giữa hai bánh chạm đất.
Mỗi mẫu xe có 2–3 biến thể người lái (đổi màu áo/nón, có khi thêm người ngồi sau).

Mẫu (lấy cảm hứng từ dáng/màu ảnh chủ dự án gửi, KHÔNG chép logo/tên hãng):
  dream    xe số kiểu "Dream" trắng – đỏ đô, yếm trắng, ống xả mạ (khác xe Dream đỏ đô của nhân vật chính)
  scooter  xe tay ga cổ kiểu Ý thân tròn nâu sô-cô-la, yên da bò, đèn tròn trên đầu
  cruiser  mô-tô cruiser bình xăng giọt nước xanh dương, máy đen + mạ crôm, bánh béo, yên thấp
  cub      xe Cub cũ xanh ngọc chở bao gạo
  family   xe tay ga đỏ chở cả nhà ba người (bé đứng trước, mẹ ngồi sau)
  chicken  xe số chở lồng gà tre to sau yên
  ba_gac   xe ba gác máy: đầu xe số + thùng gỗ chở dừa/dưa hấu (dài hơn)
  bicycle  xe đạp cũ khung sơn xanh, người đội nón lá (chậm, không tiếng máy)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "art", "vehicles")

OUT = (42, 30, 46, 255)
TIRE = (40, 34, 44, 255)
TIRE_L = (70, 62, 74, 255)
CHROME_D = (130, 132, 146, 255)
CHROME = (176, 176, 188, 255)
CHROME_L = (226, 228, 236, 255)
BLACK = (46, 42, 56, 255)
BLACK_L = (84, 80, 94, 255)
SEAT = (40, 34, 42, 255)
LAMP = (255, 236, 160, 255)
TAIL = (214, 50, 50, 255)
SKIN = (220, 170, 104, 255)
SKIN_D = (182, 124, 70, 255)
SKIN2 = (242, 196, 150, 255)
SKIN2_D = (208, 150, 106, 255)
SHADOW = (42, 30, 74, 92)
W, H = 100, 70          # khung vẽ tạm; cắt theo vùng có hình
GROUND = 66             # hàng mặt đất (đáy bánh)


# ------------------------------------------------------------------ nét vẽ cơ bản

class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.img.putpixel((int(x), int(y)), c)

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=c)

    def poly(self, pts, c):
        self.d.polygon([(float(x), float(y)) for x, y in pts], fill=c)

    def line(self, a, b, c, w=1):
        self.d.line([a, b], fill=c, width=w)

    def ellipse(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0, y0, x1, y1], fill=c)

    def disc(self, cx, cy, r, c):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self.px(x, y, c)

    def ring(self, cx, cy, r0, r1, c):
        for y in range(int(cy - r1 - 1), int(cy + r1 + 2)):
            for x in range(int(cx - r1 - 1), int(cx + r1 + 2)):
                d2 = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
                if r0 * r0 <= d2 <= r1 * r1:
                    self.px(x, y, c)

    def paste(self, other):
        self.img.alpha_composite(other.img)


def outline(img):
    """Viền 1 px tối quanh mọi pixel có hình (4 hướng), như sprite của bản đồ."""
    a = np.array(img)
    solid = a[..., 3] > 0
    edge = np.zeros_like(solid)
    edge[1:, :] |= solid[:-1, :]
    edge[:-1, :] |= solid[1:, :]
    edge[:, 1:] |= solid[:, :-1]
    edge[:, :-1] |= solid[:, 1:]
    edge &= ~solid
    a[edge] = OUT
    return Image.fromarray(a, "RGBA")


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


# ------------------------------------------------------------------ bộ phận

def wheel(cv, cx, cy, r, frame, rim=CHROME, spokes=True, hub=CHROME_L, fat=False):
    cv.disc(cx, cy, r, TIRE)
    tread = 3 if fat else 2
    cv.ring(cx, cy, r - tread - 0.2, r - tread + 1.0, rim)
    cv.disc(cx, cy, r - tread - 0.4, (60, 54, 66, 255) if spokes else BLACK)
    if spokes:
        n = 6
        for k in range(n):
            a = (frame * (math.pi / 12.0)) + k * math.pi / 3.0 * (1 if n == 6 else 2)
            ex = cx + math.cos(a) * (r - tread - 0.6)
            ey = cy + math.sin(a) * (r - tread - 0.6)
            cv.line((cx, cy), (ex, ey), CHROME_D)
    else:
        # bánh đúc / bánh tay ga: vành đặc, chấm sáng xoay theo khung
        cv.disc(cx, cy, r - tread - 1.2, rim)
        a = frame * (math.pi / 2.0) + 0.6
        cv.px(round(cx + math.cos(a) * (r - tread - 2.0) - 0.5), round(cy + math.sin(a) * (r - tread - 2.0) - 0.5), CHROME_L)
        cv.px(round(cx - math.cos(a) * (r - tread - 2.0) - 0.5), round(cy - math.sin(a) * (r - tread - 2.0) - 0.5), CHROME_D)
    cv.disc(cx, cy, 1.6, hub)
    # gai lốp nhấp nháy theo khung (cảm giác lăn)
    for k in range(8):
        a = frame * (math.pi / 16.0) + k * math.pi / 4.0
        cv.px(round(cx + math.cos(a) * (r - 0.8) - 0.5), round(cy + math.sin(a) * (r - 0.8) - 0.5), TIRE_L)


def rider(cv, hip, seat_y, shirt, pants, hand, foot, head="helmet", hat=(200, 60, 60, 255), skin=SKIN, skin_d=SKIN_D,
          lean=2, torso_h=14, shirt_d=None, hair=(40, 30, 34, 255), visor=True, small=False):
    """Người ngồi xe nhìn ngang quay sang phải. hip = (x, y) hông; hand = tay lái; foot = chỗ để chân."""
    hx, hy = hip
    shirt_d = shirt_d or shade(shirt, 0.72)
    pants_d = shade(pants, 0.75)
    tw = 8 if small else 11
    th = 11 if small else torso_h
    # chân: đùi tới gối, ống chân xuống chỗ để chân
    knee = (hx + (8 if small else 11), hy - 2)
    cv.poly([(hx - 4, hy - 4), (knee[0] + 1, knee[1] - 3), (knee[0] + 3, knee[1] + 2), (hx - 3, hy + 2)], pants)
    cv.line((hx - 3, hy - 4), (knee[0], knee[1] - 3), shade(pants, 1.2))
    cv.poly([(knee[0] - 2, knee[1] - 2), (knee[0] + 3, knee[1]), (foot[0] + 2, foot[1] - 1), (foot[0] - 2, foot[1] - 1)], pants_d)
    cv.rect(foot[0] - 2, foot[1] - 1, foot[0] + 4, foot[1] + 1, BLACK)
    # thân
    top = hy - th
    cv.poly([(hx - tw // 2 - 1, hy), (hx + tw // 2, hy), (hx + tw // 2 + lean, top), (hx - tw // 2 + lean - 1, top)], shirt)
    cv.poly([(hx - tw // 2 - 1, hy), (hx - tw // 2 + 1, hy), (hx - tw // 2 + lean + 1, top), (hx - tw // 2 + lean - 1, top)], shirt_d)
    # tay: vai → tay lái
    sh = (hx + lean + 1, top + 3)
    cv.line(sh, hand, shirt, 4 if not small else 3)
    cv.line((sh[0], sh[1] + 1), hand, shirt_d)
    cv.rect(hand[0] - 2, hand[1] - 1, hand[0] + 1, hand[1] + 1, skin)
    # đầu
    hs = 7 if small else 10
    cx = hx + lean
    hx0 = cx - hs // 2
    hy0 = top - hs
    cv.rect(hx0, hy0, hx0 + hs - 1, top - 1, skin)
    cv.rect(hx0, top - 2, hx0 + hs - 1, top - 1, skin_d)
    cv.px(hx0 + hs - 2, hy0 + hs // 2 - 1, OUT)  # mắt
    if head == "helmet":
        # nón bảo hiểm trùm đầu, kính tối ngang mắt (như xe của bản đồ)
        cv.ellipse(hx0 - 2, hy0 - 5, hx0 + hs + 1, hy0 + hs - 2, hat)
        cv.rect(hx0 - 2, hy0 + 1, hx0 + 2, top - 2, hat)
        cv.px(hx0, hy0 - 3, shade(hat, 1.35))
        cv.px(hx0 + 1, hy0 - 4, shade(hat, 1.35))
        cv.px(hx0 + 2, hy0 - 4, shade(hat, 1.2))
        cv.rect(hx0 - 1, hy0 + hs - 4, hx0 + 2, hy0 + hs - 3, shade(hat, 0.75))
        if visor:
            cv.rect(hx0 + hs - 5, hy0 + 1, hx0 + hs + 1, hy0 + 3, (40, 40, 56, 255))
            cv.px(hx0 + hs - 1, hy0 + 1, (150, 210, 240, 255))
    elif head == "openface":
        cv.ellipse(hx0 - 2, hy0 - 4, hx0 + hs + 1, hy0 + 3, hat)
        cv.px(hx0 + 1, hy0 - 3, shade(hat, 1.4))
        cv.rect(hx0 + hs - 4, hy0 + hs - 3, hx0 + hs - 1, top - 1, (90, 60, 44, 255))  # râu
        cv.rect(hx0 + 2, hy0 + 2, hx0 + hs, hy0 + 3, (30, 30, 40, 255))  # kính đen
    elif head == "nonla":
        cv.poly([(hx0 - 5, hy0 + 1), (hx0 + hs + 4, hy0 + 1), (cx + 0.5, hy0 - 7)], (232, 200, 120, 255))
        cv.line((hx0 - 4, hy0 + 1), (hx0 + hs + 3, hy0 + 1), (196, 160, 86, 255))
        cv.line((cx - 1, hy0 - 4), (cx + 2, hy0 - 4), (250, 228, 160, 255))
    elif head == "cap":
        cv.rect(hx0 - 1, hy0 - 2, hx0 + hs, hy0 + 1, hat)
        cv.rect(hx0 + hs - 1, hy0, hx0 + hs + 3, hy0 + 1, shade(hat, 0.8))
        cv.rect(hx0 - 1, hy0 + 1, hx0, hy0 + 4, hair)
    elif head == "hair":
        cv.rect(hx0 - 1, hy0 - 2, hx0 + hs, hy0 + 1, hair)
        cv.rect(hx0 - 2, hy0, hx0 + 1, hy0 + hs + 1, hair)
    elif head == "bun_helmet":  # nón bảo hiểm nửa đầu + tóc dài phía sau (cô gái)
        cv.rect(hx0 - 3, hy0 + 1, hx0 + 1, top + 3, hair)
        cv.ellipse(hx0 - 2, hy0 - 4, hx0 + hs + 1, hy0 + 3, hat)
        cv.px(hx0 + 1, hy0 - 3, shade(hat, 1.25))
        cv.rect(hx0 + hs - 2, hy0 + 1, hx0 + hs + 2, hy0 + 2, shade(hat, 0.8))
    return (cx, hy0)


def shadow_img(length):
    img = Image.new("RGBA", (length, 7), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, length - 1, 6], fill=SHADOW)
    return img


# ------------------------------------------------------------------ các mẫu xe (quay sang đông)
# Mỗi hàm vẽ một khung (frame 0..3) cho biến thể v; trả về Canvas.

def m_dream(f, v):
    cv = Canvas()
    rx, fx, r = 26, 63, 9
    cy = GROUND - r
    shirts = [((70, 120, 190, 255), (60, 56, 70, 255), (232, 200, 60, 255), "helmet"),
              ((200, 80, 60, 255), (70, 80, 110, 255), (250, 250, 250, 255), "helmet"),
              ((90, 160, 90, 255), (110, 90, 70, 255), None, "nonla")][v]
    wheel(cv, rx, cy, r, f)
    # ống xả mạ dài bên phải
    cv.poly([(16, cy + 3), (42, cy + 1), (44, cy + 4), (17, cy + 7)], CHROME)
    cv.line((17, cy + 4), (42, cy + 3), CHROME_L)
    cv.rect(13, cy + 3, 16, cy + 6, CHROME_D)
    # thân sau trắng + hông đỏ đô
    body = (238, 236, 228, 255)
    body_d = (200, 198, 192, 255)
    maroon = (138, 36, 62, 255)
    cv.poly([(16, cy - 13), (40, cy - 16), (46, cy - 9), (44, cy - 3), (22, cy - 4), (15, cy - 9)], body)
    cv.poly([(18, cy - 8), (42, cy - 9), (43, cy - 5), (22, cy - 5)], maroon)
    cv.line((17, cy - 12), (39, cy - 15), (252, 252, 248, 255))
    cv.rect(13, cy - 12, 16, cy - 10, TAIL)  # đèn hậu
    # yên đen dài
    cv.poly([(18, cy - 15), (42, cy - 18), (46, cy - 16), (20, cy - 13)], SEAT)
    cv.line((20, cy - 16), (40, cy - 18), BLACK_L)
    # khung xương cá (underbone) + máy
    cv.poly([(42, cy - 6), (52, cy - 12), (55, cy - 10), (46, cy - 3)], body_d)
    cv.rect(34, cy - 3, 46, cy + 2, BLACK)
    cv.rect(36, cy - 2, 41, cy, BLACK_L)
    # yếm trắng (leg shield) + mặt nạ đỏ đô
    cv.poly([(50, cy - 22), (56, cy - 24), (60, cy - 10), (56, cy - 4), (52, cy - 8)], body)
    cv.poly([(52, cy - 20), (55, cy - 21), (58, cy - 11), (55, cy - 8)], body_d)
    # phuộc trước + chắn bùn
    cv.line((57, cy - 22), (fx, cy), CHROME_D, 2)
    cv.poly([(fx - 9, cy - 9), (fx + 2, cy - 11), (fx + 6, cy - 6), (fx + 4, cy - 5), (fx - 6, cy - 7)], maroon)
    # đầu xe: tay lái + đèn
    cv.poly([(53, cy - 30), (62, cy - 31), (64, cy - 26), (56, cy - 24)], body)
    cv.rect(60, cy - 29, 63, cy - 27, LAMP)
    cv.line((55, cy - 31), (52, cy - 34), BLACK, 2)
    # để chân
    cv.rect(40, cy - 1, 44, cy, BLACK_L)
    if v == 1:
        # người ngồi sau (áo hồng, tóc)
        rider(cv, (23, cy - 15), cy - 15, (230, 120, 160, 255), (60, 70, 120, 255), (34, cy - 26), (32, cy - 1),
              head="hair", hair=(50, 34, 30, 255), skin=SKIN2, skin_d=SKIN2_D, small=True, lean=1)
    sh, pn, hat, head = shirts
    rider(cv, (33, cy - 17), cy - 17, sh, pn, (52, cy - 33), (42, cy - 2), head=head, hat=hat or (200, 60, 60, 255))
    wheel(cv, fx, cy, r, f)
    cv.line((fx - 3, cy - 13), (fx, cy), CHROME, 2)
    return cv


def m_scooter(f, v):
    cv = Canvas()
    rx, fx, r = 28, 61, 7
    cy = GROUND - r
    choc = (92, 58, 44, 255)
    choc_l = (124, 82, 60, 255)
    choc_d = (66, 40, 34, 255)
    tan = (196, 150, 100, 255)
    wheel(cv, rx, cy, r, f, rim=CHROME, spokes=False)
    # thân sau tròn (bầu xe kiểu Ý)
    cv.ellipse(14, cy - 18, 46, cy + 2, choc)
    cv.ellipse(16, cy - 17, 42, cy - 6, choc_l)
    cv.ellipse(18, cy - 15, 30, cy - 9, (150, 104, 76, 255))
    cv.rect(13, cy - 10, 16, cy - 8, TAIL)
    # sàn để chân + yếm cong
    cv.poly([(40, cy - 3), (54, cy - 3), (56, cy + 1), (40, cy + 1)], choc_d)
    cv.poly([(52, cy - 26), (58, cy - 27), (62, cy - 8), (58, cy - 1), (53, cy - 2), (55, cy - 10)], choc)
    cv.poly([(54, cy - 24), (57, cy - 25), (60, cy - 9), (57, cy - 5)], choc_l)
    # chắn bùn trước tròn
    cv.ellipse(fx - 9, cy - 10, fx + 7, cy + 2, choc)
    cv.ellipse(fx - 6, cy - 9, fx + 3, cy - 5, choc_l)
    # yên da bò hai tầng
    cv.poly([(20, cy - 19), (44, cy - 20), (46, cy - 17), (22, cy - 16)], tan)
    cv.line((22, cy - 19), (42, cy - 20), (226, 184, 132, 255))
    # đầu xe + đèn tròn
    cv.ellipse(54, cy - 35, 65, cy - 27, choc)
    cv.disc(63, cy - 31, 2.6, LAMP)
    cv.px(63, cy - 32, (255, 255, 230, 255))
    cv.line((55, cy - 34), (50, cy - 36), CHROME_D, 2)
    cv.rect(31, cy - 12, 38, cy - 10, CHROME)  # nẹp mạ hông
    if v == 0:
        rider(cv, (34, cy - 21), cy - 21, (246, 238, 222, 255), (240, 232, 214, 255), (51, cy - 35), (47, cy - 3),
              head="bun_helmet", hat=(240, 226, 190, 255), skin=SKIN2, skin_d=SKIN2_D, hair=(36, 26, 30, 255))
        # tà áo dài bay phía sau
        cv.poly([(29, cy - 22), (22, cy - 14), (19, cy - 12), (27, cy - 16)], (246, 238, 222, 255))
    elif v == 1:
        rider(cv, (34, cy - 21), cy - 21, (230, 170, 60, 255), (60, 70, 110, 255), (51, cy - 35), (47, cy - 3),
              head="bun_helmet", hat=(200, 70, 90, 255), skin=SKIN2, skin_d=SKIN2_D, hair=(70, 40, 30, 255))
    else:
        rider(cv, (34, cy - 21), cy - 21, (70, 90, 70, 255), (196, 180, 150, 255), (51, cy - 35), (47, cy - 3),
              head="helmet", hat=(240, 240, 236, 255))
    wheel(cv, fx, cy, r, f, rim=CHROME, spokes=False)
    return cv


def m_cruiser(f, v):
    cv = Canvas()
    rx, fx, r = 24, 70, 9
    cy = GROUND - r
    blue = (44, 100, 190, 255)
    blue_l = (90, 150, 230, 255)
    blue_d = (30, 62, 130, 255)
    if v == 2:
        blue, blue_l, blue_d = (150, 30, 40, 255), (210, 70, 70, 255), (96, 20, 32, 255)
    wheel(cv, rx, cy, r, f, rim=BLACK_L, fat=True)
    # chắn bùn sau ngắn
    cv.poly([(14, cy - 10), (30, cy - 12), (33, cy - 9), (15, cy - 6)], BLACK)
    cv.rect(12, cy - 10, 14, cy - 8, TAIL)
    # ống xả đôi mạ crôm chạy dọc
    cv.poly([(16, cy + 1), (50, cy - 3), (51, cy + 1), (17, cy + 4)], CHROME)
    cv.line((17, cy + 1), (49, cy - 2), CHROME_L)
    cv.poly([(20, cy - 3), (48, cy - 7), (49, cy - 4), (21, cy - 1)], CHROME_D)
    # máy V-twin đen + nắp mạ
    cv.poly([(38, cy - 4), (44, cy - 18), (50, cy - 18), (54, cy - 6), (48, cy + 1), (40, cy + 1)], BLACK)
    cv.rect(42, cy - 16, 46, cy - 12, CHROME_D)
    cv.rect(48, cy - 15, 51, cy - 11, CHROME_D)
    cv.disc(45, cy - 5, 3, CHROME)
    cv.px(44, cy - 6, CHROME_L)
    # khung + yên thấp
    cv.line((28, cy - 14), (60, cy - 22), BLACK, 3)
    cv.poly([(22, cy - 17), (38, cy - 17), (42, cy - 15), (24, cy - 13)], SEAT)
    # bình xăng giọt nước
    cv.ellipse(40, cy - 27, 60, cy - 17, blue)
    cv.ellipse(43, cy - 26, 55, cy - 22, blue_l)
    cv.line((44, cy - 19), (58, cy - 20), blue_d)
    # phuộc trước nghiêng + bánh béo
    cv.line((62, cy - 30), (fx, cy), CHROME, 3)
    cv.line((63, cy - 30), (fx + 1, cy - 2), CHROME_L)
    cv.poly([(fx - 8, cy - 11), (fx + 4, cy - 12), (fx + 7, cy - 8), (fx - 5, cy - 8)], BLACK)
    # tay lái cao + đèn tròn
    cv.disc(66, cy - 29, 3.2, CHROME)
    cv.disc(67, cy - 29, 1.8, LAMP)
    cv.line((60, cy - 32), (56, cy - 38), CHROME_D, 2)
    if v == 0:
        rider(cv, (31, cy - 18), cy - 18, (58, 44, 40, 255), (50, 64, 96, 255), (56, cy - 38), (54, cy - 6),
              head="openface", hat=(30, 28, 36, 255), lean=-1, shirt_d=(40, 30, 28, 255))
    elif v == 1:
        rider(cv, (31, cy - 18), cy - 18, (30, 30, 34, 255), (40, 40, 48, 255), (56, cy - 38), (54, cy - 6),
              head="helmet", hat=(30, 30, 36, 255), lean=-1)
    else:
        rider(cv, (31, cy - 18), cy - 18, (236, 232, 220, 255), (50, 64, 96, 255), (56, cy - 38), (54, cy - 6),
              head="openface", hat=(150, 30, 40, 255), lean=-1, shirt_d=(190, 186, 176, 255))
    wheel(cv, fx, cy, r, f, rim=BLACK_L, fat=True)
    return cv


def m_cub(f, v):
    cv = Canvas()
    rx, fx, r = 26, 61, 9
    cy = GROUND - r
    teal = (70, 160, 160, 255)
    teal_l = (120, 200, 196, 255)
    teal_d = (44, 110, 116, 255)
    if v == 1:
        teal, teal_l, teal_d = (210, 120, 60, 255), (240, 170, 100, 255), (150, 80, 40, 255)
    wheel(cv, rx, cy, r, f)
    cv.poly([(16, cy + 2), (40, cy), (41, cy + 3), (17, cy + 5)], CHROME_D)
    cv.poly([(18, cy - 11), (40, cy - 14), (44, cy - 6), (24, cy - 4)], teal)
    cv.line((19, cy - 10), (38, cy - 13), teal_l)
    cv.rect(15, cy - 12, 18, cy - 10, TAIL)
    # yên
    cv.poly([(30, cy - 16), (44, cy - 17), (46, cy - 14), (31, cy - 13)], SEAT)
    # máy + yếm
    cv.rect(36, cy - 4, 46, cy + 1, BLACK)
    cv.poly([(46, cy - 6), (53, cy - 22), (58, cy - 22), (59, cy - 9), (52, cy - 2)], teal)
    cv.poly([(53, cy - 20), (56, cy - 20), (57, cy - 10), (53, cy - 6)], teal_l)
    cv.line((57, cy - 24), (fx, cy), CHROME_D, 2)
    cv.poly([(fx - 8, cy - 10), (fx + 3, cy - 11), (fx + 6, cy - 6), (fx - 6, cy - 7)], teal)
    cv.poly([(53, cy - 30), (61, cy - 30), (62, cy - 25), (55, cy - 24)], teal_d)
    cv.rect(59, cy - 29, 62, cy - 27, LAMP)
    cv.line((55, cy - 31), (51, cy - 34), BLACK, 2)
    # bao gạo trắng chất trên baga sau (2–3 bao)
    sack = (236, 230, 214, 255)
    sack_d = (196, 188, 168, 255)
    cv.poly([(9, cy - 28), (28, cy - 30), (30, cy - 16), (8, cy - 14)], sack)
    cv.line((10, cy - 22), (29, cy - 23), sack_d)
    cv.line((19, cy - 29), (19, cy - 15), sack_d)
    cv.rect(13, cy - 26, 16, cy - 25, (60, 130, 70, 255))  # chữ in màu trên bao (không logo)
    if v == 2:
        cv.poly([(11, cy - 36), (26, cy - 37), (27, cy - 29), (10, cy - 28)], sack)
        cv.line((12, cy - 32), (26, cy - 33), sack_d)
    rider(cv, (36, cy - 18), cy - 18, (120, 140, 180, 255) if v != 1 else (220, 220, 210, 255), (60, 50, 44, 255),
          (52, cy - 34), (44, cy - 2), head="nonla")
    wheel(cv, fx, cy, r, f)
    return cv


def m_family(f, v):
    cv = Canvas()
    rx, fx, r = 26, 63, 7
    cy = GROUND - r
    red = (200, 50, 54, 255)
    red_l = (236, 100, 96, 255)
    red_d = (140, 30, 40, 255)
    if v == 1:
        red, red_l, red_d = (236, 236, 232, 255), (252, 252, 250, 255), (190, 190, 186, 255)
    wheel(cv, rx, cy, r, f, spokes=False, rim=CHROME)
    cv.poly([(12, cy - 16), (42, cy - 19), (48, cy - 6), (40, cy + 1), (18, cy - 1), (12, cy - 8)], red)
    cv.poly([(14, cy - 14), (40, cy - 17), (42, cy - 13), (16, cy - 11)], red_l)
    cv.rect(11, cy - 12, 14, cy - 10, TAIL)
    cv.poly([(40, cy - 3), (54, cy - 3), (55, cy + 1), (41, cy + 1)], BLACK)
    cv.poly([(51, cy - 28), (57, cy - 29), (62, cy - 9), (57, cy - 2), (53, cy - 3), (55, cy - 12)], red)
    cv.poly([(fx - 8, cy - 9), (fx + 4, cy - 10), (fx + 6, cy - 5), (fx - 6, cy - 6)], red_d)
    cv.poly([(53, cy - 35), (63, cy - 35), (64, cy - 29), (56, cy - 28)], red_d)
    cv.rect(61, cy - 34, 64, cy - 32, LAMP)
    cv.poly([(16, cy - 20), (46, cy - 22), (47, cy - 19), (17, cy - 17)], SEAT)
    # mẹ ngồi sau (nón bảo hiểm hồng), bố lái (nón xanh), bé đứng trước sàn
    rider(cv, (22, cy - 21), cy - 21, (240, 150, 170, 255), (80, 70, 110, 255), (36, cy - 30), (34, cy - 3),
          head="bun_helmet", hat=(240, 140, 170, 255), skin=SKIN2, skin_d=SKIN2_D, lean=1)
    rider(cv, (35, cy - 21), cy - 21, (70, 130, 200, 255) if v == 0 else (90, 150, 90, 255), (60, 60, 70, 255),
          (53, cy - 36), (47, cy - 3), head="helmet", hat=(60, 120, 200, 255))
    # bé đứng trên sàn (chỉ thấy nửa trên + nón nhỏ vàng)
    bx, by = 48, cy - 4
    cv.rect(bx - 2, by - 10, bx + 3, by - 1, (250, 210, 70, 255))
    cv.rect(bx - 2, by - 16, bx + 3, by - 11, SKIN2)
    cv.ellipse(bx - 3, by - 20, bx + 4, by - 13, (250, 200, 40, 255))
    cv.px(bx + 2, by - 14, OUT)
    wheel(cv, fx, cy, r, f, spokes=False, rim=CHROME)
    return cv


def m_chicken(f, v):
    cv = Canvas()
    rx, fx, r = 28, 63, 9
    cy = GROUND - r
    body = (70, 70, 80, 255) if v == 0 else (40, 90, 160, 255)
    body_l = shade(body, 1.4)
    wheel(cv, rx, cy, r, f)
    cv.poly([(18, cy + 2), (42, cy), (43, cy + 3), (19, cy + 5)], CHROME_D)
    cv.poly([(20, cy - 12), (44, cy - 15), (48, cy - 6), (26, cy - 4)], body)
    cv.line((21, cy - 11), (42, cy - 14), body_l)
    cv.poly([(32, cy - 17), (46, cy - 18), (48, cy - 15), (33, cy - 14)], SEAT)
    cv.rect(38, cy - 4, 48, cy + 1, BLACK)
    cv.poly([(48, cy - 6), (55, cy - 22), (59, cy - 22), (60, cy - 9), (53, cy - 2)], body)
    cv.line((58, cy - 24), (fx, cy), CHROME_D, 2)
    cv.poly([(fx - 8, cy - 10), (fx + 3, cy - 11), (fx + 6, cy - 6), (fx - 6, cy - 7)], body)
    cv.poly([(54, cy - 30), (62, cy - 30), (63, cy - 25), (56, cy - 24)], body)
    cv.rect(60, cy - 29, 63, cy - 27, LAMP)
    cv.line((56, cy - 31), (52, cy - 34), BLACK, 2)
    # lồng tre to (2 tầng) sau yên, gà đỏ/trắng thò đầu
    bam = (196, 150, 80, 255)
    bam_d = (150, 104, 52, 255)
    x0, y0, x1, y1 = 4, cy - 34, 31, cy - 13
    cv.rect(x0, y0, x1, y1, (120, 80, 40, 255))
    for x in range(x0 + 1, x1, 3):
        cv.line((x, y0 + 1), (x, y1 - 1), bam)
    for y in (y0, (y0 + y1) // 2, y1):
        cv.line((x0, y), (x1, y), bam_d, 2 if y == y1 else 1)
    hens = [(9, y0 + 6, (220, 60, 40, 255)), (19, y0 + 5, (245, 240, 230, 255)), (13, y1 - 5, (200, 120, 50, 255)),
            (25, y1 - 6, (220, 60, 40, 255))]
    for k, (hx, hy, c) in enumerate(hens):
        bob = 1 if (f + k) % 2 else 0
        cv.rect(hx - 2, hy - 2 - bob, hx + 1, hy + 1 - bob, c)
        cv.px(hx - 1, hy - 3 - bob, (230, 40, 40, 255))
        cv.px(hx + 2, hy - 1 - bob, (250, 200, 60, 255))
    rider(cv, (38, cy - 19), cy - 19, (60, 140, 80, 255) if v == 0 else (230, 200, 80, 255), (70, 60, 50, 255),
          (54, cy - 34), (46, cy - 2), head="cap" if v == 0 else "nonla", hat=(220, 60, 50, 255))
    wheel(cv, fx, cy, r, f)
    return cv


def m_ba_gac(f, v):
    cv = Canvas()
    rx, fx, r = 22, 78, 8
    cy = GROUND - r
    wood = (176, 116, 64, 255)
    wood_l = (210, 150, 90, 255)
    wood_d = (126, 80, 44, 255)
    wheel(cv, rx, cy, r, f)
    # thùng gỗ dài
    cv.rect(4, cy - 20, 50, cy - 8, wood)
    for x in range(6, 50, 6):
        cv.line((x, cy - 19), (x, cy - 9), wood_d)
    cv.line((4, cy - 20), (50, cy - 20), wood_l)
    cv.line((4, cy - 8), (50, cy - 8), wood_d)
    cv.rect(18, cy - 8, 30, cy - 4, BLACK)  # cầu sau
    # hàng hoá
    if v == 0:  # dừa xiêm
        for k, x in enumerate(range(7, 48, 6)):
            cv.disc(x + 0.5, cy - 23 - (k % 2), 3.4, (90, 160, 60, 255))
            cv.px(x - 1, cy - 25 - (k % 2), (150, 210, 100, 255))
        for k, x in enumerate(range(10, 44, 7)):
            cv.disc(x + 0.5, cy - 28, 3.2, (110, 176, 70, 255))
    else:  # dưa hấu
        for k, x in enumerate(range(8, 48, 8)):
            cv.ellipse(x - 4, cy - 27, x + 4, cy - 20, (50, 120, 50, 255))
            cv.line((x - 3, cy - 24), (x + 3, cy - 24), (110, 180, 90, 255))
        cv.ellipse(18, cy - 32, 34, cy - 25, (50, 120, 50, 255))
        cv.line((19, cy - 29), (33, cy - 29), (110, 180, 90, 255))
    # đầu xe số
    cv.poly([(50, cy - 12), (60, cy - 16), (64, cy - 6), (52, cy - 3)], (90, 90, 100, 255))
    cv.poly([(50, cy - 18), (62, cy - 19), (63, cy - 16), (51, cy - 15)], SEAT)
    cv.rect(54, cy - 4, 62, cy + 1, BLACK)
    cv.poly([(63, cy - 6), (69, cy - 22), (73, cy - 22), (74, cy - 9), (68, cy - 2)], (60, 110, 160, 255))
    cv.line((72, cy - 24), (fx, cy), CHROME_D, 2)
    cv.poly([(fx - 7, cy - 9), (fx + 3, cy - 10), (fx + 5, cy - 6), (fx - 5, cy - 6)], (60, 110, 160, 255))
    cv.rect(73, cy - 29, 77, cy - 26, LAMP)
    cv.line((70, cy - 30), (66, cy - 33), BLACK, 2)
    rider(cv, (54, cy - 19), cy - 19, (200, 190, 170, 255) if v == 0 else (190, 80, 60, 255), (60, 70, 90, 255),
          (67, cy - 33), (62, cy - 2), head="nonla")
    wheel(cv, fx, cy, r, f)
    return cv


def m_bicycle(f, v):
    cv = Canvas()
    rx, fx, r = 24, 54, 10
    cy = GROUND - r
    frame_c = (60, 130, 110, 255) if v == 0 else (160, 50, 50, 255)
    for cx_ in (rx,):
        cv.ring(cx_, cy, r - 1.4, r, TIRE)
        cv.ring(cx_, cy, r - 2.2, r - 1.4, CHROME)
        for k in range(8):
            a = f * math.pi / 16 + k * math.pi / 4
            cv.line((cx_, cy), (cx_ + math.cos(a) * (r - 2), cy + math.sin(a) * (r - 2)), CHROME_D)
    # khung tam giác
    seat = (32, cy - 18)
    crank = (38, cy)
    head_ = (50, cy - 19)
    cv.line((rx, cy), crank, frame_c, 2)
    cv.line((rx, cy), seat, frame_c, 2)
    cv.line(seat, crank, frame_c, 2)
    cv.line(seat, (head_[0], head_[1] + 3), frame_c, 2)
    cv.line(crank, head_, frame_c, 2)
    cv.line(head_, (fx, cy), CHROME_D, 2)
    cv.rect(28, cy - 21, 35, cy - 19, SEAT)
    cv.line((49, cy - 22), (45, cy - 25), CHROME, 2)
    cv.disc(crank[0], crank[1], 2.4, CHROME_D)
    a = f * math.pi / 2
    pedal = (crank[0] + math.cos(a) * 4, crank[1] + math.sin(a) * 4)
    cv.rect(10, cy - 12, 22, cy - 10, (150, 110, 60, 255))  # baga
    if v == 1:
        # giỏ rau sau baga
        cv.rect(8, cy - 18, 21, cy - 12, (190, 140, 70, 255))
        for k, x in enumerate(range(9, 21, 3)):
            cv.disc(x + 1, cy - 19, 2.0, (80, 160, 70, 255))
    rider(cv, (32, cy - 21), cy - 21, (240, 240, 230, 255) if v == 0 else (150, 90, 160, 255), (40, 40, 50, 255),
          (45, cy - 26), (round(pedal[0]), round(pedal[1])), head="nonla", lean=3, torso_h=12)
    cv.ring(fx, cy, r - 1.4, r, TIRE)
    cv.ring(fx, cy, r - 2.2, r - 1.4, CHROME)
    for k in range(8):
        a2 = f * math.pi / 16 + k * math.pi / 4
        cv.line((fx, cy), (fx + math.cos(a2) * (r - 2), cy + math.sin(a2) * (r - 2)), CHROME_D)
    cv.line(head_, (fx, cy), CHROME_D, 2)
    return cv


# id, mẫu, số biến thể, tốc độ (px/s), kiểu (type), racer, tên tay đua gắn với biến thể 0 (race_riders.gd)
MODELS = [
    ("dream", m_dream, 3, (150.0, 172.0), "underbone", True),
    ("scooter", m_scooter, 3, (148.0, 170.0), "scooter", True),
    ("cruiser", m_cruiser, 3, (176.0, 198.0), "cruiser", True),
    ("cub", m_cub, 3, (126.0, 146.0), "cub", True),
    ("family", m_family, 2, (128.0, 148.0), "scooter", False),
    ("chicken", m_chicken, 2, (140.0, 160.0), "underbone", True),
    ("ba_gac", m_ba_gac, 2, (110.0, 130.0), "ba_gac", True),
    ("bicycle", m_bicycle, 2, (62.0, 80.0), "bicycle", False),
]


def render_model(fn, v):
    frames = [outline(fn(f, v).img) for f in range(4)]
    # vùng chung của 4 khung
    box = None
    for im in frames:
        b = im.getbbox()
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    frames = [im.crop(box) for im in frames]
    return frames, box


class Packer:
    def __init__(self, width=1024):
        self.width = width
        self.items = []
        self.x = 0
        self.y = 0
        self.row_h = 0

    def add(self, img):
        w, h = img.size
        if self.x + w > self.width:
            self.x = 0
            self.y += self.row_h + 1
            self.row_h = 0
        pos = (self.x, self.y)
        self.items.append((img, pos))
        self.x += w + 1
        self.row_h = max(self.row_h, h)
        return [pos[0], pos[1], w, h]

    def save(self, path):
        hgt = self.y + self.row_h + 1
        page = Image.new("RGBA", (self.width, hgt), (0, 0, 0, 0))
        for img, pos in self.items:
            page.alpha_composite(img, pos)
        page.save(path, optimize=True)
        return [self.width, hgt]


def build(out_dir=OUT_DIR, preview_dir=None):
    os.makedirs(out_dir, exist_ok=True)
    pk = Packer()
    looks = []
    sheets = []
    n = 5
    for model, fn, variants, speed, vtype, racer in MODELS:
        for v in range(variants):
            frames, box = render_model(fn, v)
            w, h = frames[0].size
            # gốc: giữa hai điểm bánh chạm đất (x trung bình của bánh sau/trước ≈ giữa khung), y = đáy khung
            alpha = np.array(frames[0])[..., 3] > 0
            bottom = np.nonzero(alpha[-1])[0]
            ax = float(round((bottom.min() + bottom.max()) / 2.0 * 2) / 2)
            ay = float(h - 1)
            east = [pk.add(im) for im in frames]
            west = [pk.add(im.transpose(Image.FLIP_LEFT_RIGHT)) for im in frames]
            sh_len = max(40, int(w * 0.86))
            shadow = pk.add(shadow_img(sh_len))
            look_id = "bike_%02d" % n
            n += 1
            looks.append({
                "id": look_id, "kind": "bike", "model": model, "variant": v, "type": vtype, "racer": racer,
                "silent": vtype == "bicycle", "atlas": "res://game/art/vehicles/vehicles_atlas.png",
                "frames": {"east": east, "west": west}, "frame_ms": 80,
                "anchor": [ax, ay], "anchor_west": [float(w - 1) - ax, ay], "frame_anchors": None,
                "size": [w, h], "speed_px_s": round((speed[0] + speed[1]) / 2.0, 1), "speed_range": list(speed),
                "shadow": {"east": shadow, "west": shadow},
                "shadow_offset": {"east": [int(-sh_len / 2), -3], "west": [int(-sh_len / 2), -3]},
                "wake": None, "wake_offset": None, "wake_ms": None, "mirrored": "west", "source_layers": [],
            })
            sheets.append((look_id, model, v, frames))
    size = pk.save(os.path.join(out_dir, "vehicles_atlas.png"))
    data = {"version": 1, "atlas": "vehicles_atlas.png", "atlas_size": size, "vehicles": looks,
            "notes": ["Xe NPC mới vẽ bằng tools/art/build_vehicles.py – cùng định dạng 'vehicles' của traffic.json, thêm "
                      "atlas (đường dẫn res://), model/variant/type, racer (thách đua được), silent (không tiếng máy), "
                      "speed_range [min, max] px/s."]}
    with open(os.path.join(out_dir, "vehicles.json"), "w", encoding="utf8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    if preview_dir:
        preview(sheets, preview_dir)
    return data


def preview(sheets, preview_dir):
    """So sánh ×4: hàng đầu = 4 xe gốc của bản đồ, rồi từng mẫu mới (khung 0, có bóng), trên nền đường đất."""
    os.makedirs(preview_dir, exist_ok=True)
    tdir = os.path.join(ROOT, "game", "art", "world_map")
    tj = json.load(open(os.path.join(tdir, "traffic.json"), encoding="utf8"))
    atl = Image.open(os.path.join(tdir, "traffic_atlas.png")).convert("RGBA")
    orig = []
    for look in tj["vehicles"][:4]:
        r = look["frames"]["east"][0]
        orig.append(atl.crop((r[0], r[1], r[0] + r[2], r[1] + r[3])))
    cell_w, cell_h = 96, 74
    items = [("map", im) for im in orig] + [(lid, fr[0]) for lid, _m, _v, fr in sheets]
    cols = 6
    rows = (len(items) + cols - 1) // cols
    page = Image.new("RGBA", (cols * cell_w, rows * cell_h), (196, 170, 120, 255))
    d = ImageDraw.Draw(page)
    for i, (label, im) in enumerate(items):
        x = (i % cols) * cell_w
        y = (i // cols) * cell_h
        d.rectangle([x, y + cell_h - 10, x + cell_w, y + cell_h], fill=(150, 150, 150, 255))
        sh = shadow_img(max(40, int(im.size[0] * 0.86)))
        gx = x + (cell_w - im.size[0]) // 2
        page.alpha_composite(sh, (gx + im.size[0] // 2 - sh.size[0] // 2, y + cell_h - 14))
        page.alpha_composite(im, (gx, y + cell_h - 11 - im.size[1]))
        d.text((x + 2, y + 1), label, fill=(60, 30, 20, 255))
    page = page.resize((page.size[0] * 4, page.size[1] * 4), Image.NEAREST)
    page.save(os.path.join(preview_dir, "vehicles_preview_x4.png"))
    # dải 4 khung của từng mẫu (kiểm tra bánh quay)
    strip = Image.new("RGBA", (4 * cell_w, len(sheets) * cell_h), (120, 160, 100, 255))
    for j, (_lid, _m, _v, fr) in enumerate(sheets):
        for k, im in enumerate(fr):
            strip.alpha_composite(im, (k * cell_w + 4, j * cell_h + cell_h - 4 - im.size[1]))
    strip.resize((strip.size[0] * 3, strip.size[1] * 3), Image.NEAREST).save(os.path.join(preview_dir, "vehicles_frames_x3.png"))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    pv = None
    if "--preview" in sys.argv:
        pv = sys.argv[sys.argv.index("--preview") + 1]
    out = build(preview_dir=pv)
    print("vehicles: %d kiểu xe, atlas %s" % (len(out["vehicles"]), out["atlas_size"]))
