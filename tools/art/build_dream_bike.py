"""Xe máy kiểu Dream (underbone) cho nhân vật chính: sườn, trước, sau + khung bánh xe thứ hai.
Dùng: python tools/art/build_dream_bike.py <project_root>
Viền 1 px màu (42,30,46) như NPC trên bản đồ.

bike_side/_b/front/back/parked.png: chỉ có xe (không người).
bike_ride_side/_b/front/back.png: người lái ngồi trên xe (ảnh ghép, cao 60 px, mép dưới = mặt đất);
đầu lấy từ game/art/player_sheet.png thu ×0,8 NEAREST nên không đổi cỡ khi lên/xuống xe."""
import math
import os
import sys
from PIL import Image, ImageDraw, ImageOps

OL = (42, 30, 46, 255)
TIRE = (40, 34, 42, 255)
HUB = (96, 92, 104, 255)
RIMC = (176, 176, 188, 255)
SPOKE = (214, 214, 224, 255)
WHEEL_IN = (70, 62, 74, 255)
PLUM = (138, 36, 62, 255)
PLUM_L = (178, 62, 88, 255)
PLUM_D = (92, 22, 44, 255)
CREAM = (238, 226, 196, 255)
CREAM_D = (196, 182, 150, 255)
SEAT = (30, 26, 34, 255)
SEAT_L = (62, 56, 68, 255)
CHROME = (196, 198, 208, 255)
CHROME_D = (130, 132, 146, 255)
CHROME_L = (240, 240, 248, 255)
ENG = (84, 80, 94, 255)
LAMP = (255, 238, 150, 255)
RED = (214, 50, 44, 255)
JEAN = (62, 100, 166, 255)
JEAN_D = (42, 70, 124, 255)
SHOE = (36, 30, 38, 255)


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def poly(img, pts, c):
    ImageDraw.Draw(img).polygon(pts, fill=c)


def rect(img, x0, y0, x1, y1, c):
    ImageDraw.Draw(img).rectangle((x0, y0, x1, y1), fill=c)


def line(img, a, b, c, w=1):
    ImageDraw.Draw(img).line((a, b), fill=c, width=w)


def px(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c)


def outline(img):
    """Viền 1 px (4 hướng) quanh phần đục; ảnh phải có lề trống 1 px."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and src.getpixel((nx, ny))[3] > 0:
                    img.putpixel((x, y), OL)
                    break


def wheel_side(img, cx, cy, phase):
    for y in range(-10, 11):
        for x in range(-10, 11):
            d = math.hypot(x, y)
            if d <= 9.5:
                c = TIRE if d > 7.4 else (RIMC if d > 6.3 else WHEEL_IN)
                px(img, cx + x, cy + y, c)
    for k in range(6):
        a = phase + k * math.pi / 3
        for t in range(2, 7):
            px(img, cx + round(math.cos(a) * t), cy + round(math.sin(a) * t), SPOKE)
    rect(img, cx - 1, cy - 1, cx + 1, cy + 1, HUB)
    px(img, cx, cy, CHROME_L)


def build_side(phase):
    W, H = 68, 42
    im = canvas(W, H)
    rw, fw = (14, 31), (54, 31)  # tâm bánh sau / trước
    wheel_side(im, *rw, phase)
    wheel_side(im, *fw, phase)
    # chắn bùn sau (đen) + đuôi xe + giá chở hàng
    poly(im, [(5, 21), (9, 19), (20, 19), (23, 22), (21, 22), (17, 21), (9, 22), (6, 24)], SEAT)
    rect(im, 3, 17, 13, 17, CHROME)
    rect(im, 3, 15, 3, 17, CHROME_D)
    rect(im, 5, 16, 5, 17, CHROME_D)
    rect(im, 8, 16, 8, 17, CHROME_D)
    rect(im, 2, 18, 4, 20, RED)                      # đèn hậu
    # động cơ
    rect(im, 22, 27, 36, 33, ENG)
    rect(im, 24, 28, 28, 30, CHROME_D)
    rect(im, 30, 31, 37, 34, SEAT_L)                 # cần số/bàn đạp
    # thân sau (tem) màu mận
    poly(im, [(10, 20), (24, 19), (34, 21), (36, 26), (28, 27), (20, 25), (12, 24)], PLUM)
    poly(im, [(12, 21), (24, 20), (32, 22)], PLUM_L)
    line(im, (13, 24), (27, 26), PLUM_D)
    # yên dài phẳng
    poly(im, [(9, 16), (13, 14), (36, 14), (39, 17), (36, 19), (12, 19)], SEAT)
    line(im, (14, 14), (35, 14), SEAT_L)
    # sàn để chân + yếm
    rect(im, 36, 27, 44, 29, PLUM)
    rect(im, 36, 29, 44, 29, PLUM_D)
    poly(im, [(39, 16), (45, 12), (49, 13), (49, 27), (45, 30), (40, 29), (38, 24)], CREAM)
    poly(im, [(39, 16), (45, 12), (49, 13), (49, 15), (46, 15), (41, 19)], PLUM)
    line(im, (49, 15), (49, 27), CREAM_D)
    line(im, (40, 28), (45, 29), CREAM_D)
    # cổ lái / phuộc trước
    line(im, (47, 11), (54, 31), CHROME_D, 3)
    line(im, (46, 11), (53, 30), CHROME_L, 1)
    # chắn bùn trước
    poly(im, [(46, 21), (51, 19), (59, 19), (63, 24), (60, 24), (56, 22), (50, 23)], PLUM)
    line(im, (50, 19), (60, 19), PLUM_L)
    # đèn pha vuông + tay lái
    rect(im, 49, 8, 55, 13, CREAM)
    rect(im, 53, 9, 56, 12, LAMP)
    px(im, 56, 9, CHROME_L)
    rect(im, 43, 6, 51, 9, PLUM_D)
    rect(im, 44, 7, 49, 7, PLUM)
    rect(im, 41, 6, 43, 8, SEAT)                      # tay nắm
    rect(im, 47, 3, 49, 6, CHROME_D)                  # gương
    px(im, 47, 3, CHROME_L)
    # ống xả crôm phía dưới bên phải, chĩa ra sau
    line(im, (30, 32), (7, 28), CHROME_D, 4)
    line(im, (30, 31), (7, 27), CHROME, 2)
    line(im, (26, 30), (10, 27), CHROME_L, 1)
    rect(im, 5, 26, 7, 30, SEAT)                      # miệng ống
    outline(im)
    return im


def build_front_layers():
    """Xe nhìn từ trước, không người. Trả về một lớp (30x42)."""
    W, H = 30, 42
    im = canvas(W, H)
    cx = 15
    # bánh trước (hẹp)
    rect(im, cx - 3, 22, cx + 2, 40, TIRE)
    for y in range(24, 40, 4):
        rect(im, cx - 1, y, cx, y + 1, HUB)
    rect(im, cx - 3, 23, cx - 3, 38, WHEEL_IN)
    # chắn bùn trước
    poly(im, [(cx - 5, 24), (cx - 3, 18), (cx + 2, 18), (cx + 4, 24)], PLUM)
    line(im, (cx - 3, 19), (cx + 1, 19), PLUM_L)
    # yếm kem
    poly(im, [(8, 12), (21, 12), (20, 20), (18, 30), (12, 30), (10, 20)], CREAM)
    rect(im, 8, 12, 21, 13, PLUM)
    line(im, (13, 29), (17, 29), CREAM_D)
    rect(im, 14, 14, 15, 28, CREAM_D)
    # phuộc
    rect(im, 11, 20, 11, 29, CHROME)
    rect(im, 18, 20, 18, 29, CHROME)
    # đèn pha vuông
    rect(im, 11, 6, 18, 11, CREAM)
    rect(im, 12, 7, 17, 10, LAMP)
    px(im, 12, 7, CHROME_L)
    # tay lái + gương
    rect(im, 4, 10, 25, 11, PLUM_D)
    rect(im, 2, 9, 5, 12, SEAT)
    rect(im, 24, 9, 27, 12, SEAT)
    rect(im, 5, 3, 5, 8, CHROME_D)
    rect(im, 24, 3, 24, 8, CHROME_D)
    rect(im, 3, 1, 7, 3, CHROME)
    rect(im, 22, 1, 26, 3, CHROME)
    return im


def build_front():
    im = build_front_layers()
    outline(im)
    return im


def build_back_layers():
    """Xe nhìn từ sau, không người: (lớp xa = tay lái + gương, lớp gần = phần còn lại), 30x42."""
    W, H = 30, 42
    far = canvas(W, H)
    near = canvas(W, H)
    cx = 15
    # tay lái hai bên (nhìn từ sau) — nằm sau lưng người lái
    rect(far, 3, 6, 26, 7, SEAT)
    rect(far, 2, 5, 5, 8, SEAT)
    rect(far, 24, 5, 27, 8, SEAT)
    rect(far, 3, 1, 7, 3, CHROME)
    rect(far, 22, 1, 26, 3, CHROME)
    rect(far, 5, 3, 5, 5, CHROME_D)
    rect(far, 24, 3, 24, 5, CHROME_D)
    rect(near, cx - 3, 22, cx + 2, 40, TIRE)
    for y in range(24, 40, 4):
        rect(near, cx - 1, y, cx, y + 1, HUB)
    # chắn bùn sau đen
    poly(near, [(cx - 6, 24), (cx - 4, 17), (cx + 3, 17), (cx + 5, 24)], SEAT)
    # đuôi mận + yên + giá
    poly(near, [(8, 12), (21, 12), (20, 22), (10, 22)], PLUM)
    rect(near, 11, 13, 18, 14, PLUM_L)
    rect(near, 9, 12, 20, 12, SEAT)
    rect(near, 7, 10, 22, 11, CHROME)
    rect(near, 9, 8, 9, 10, CHROME_D)
    rect(near, 20, 8, 20, 10, CHROME_D)
    rect(near, 12, 18, 17, 20, RED)                     # đèn hậu
    px(near, 12, 18, (255, 120, 100, 255))
    # ống xả bên phải ảnh, miệng chĩa về phía camera
    rect(near, 20, 25, 24, 33, CHROME_D)
    rect(near, 21, 25, 22, 33, CHROME)
    rect(near, 20, 32, 24, 34, SEAT)
    return far, near


def build_back():
    far, near = build_back_layers()
    im = far.copy()
    im.alpha_composite(near)
    outline(im)
    return im


# ---------------------------------------------------------------- người lái ngồi trên xe
# Ảnh ghép người + xe: cao 60 (= 18 px phía trên xe cho thân và đầu + 42 px xe), gốc toạ độ ở
# mép dưới (điểm chạm đất). Đầu lấy từ player_sheet.png thu ×0,8 (giống hệt lúc đi bộ).

RIDE_OY = 18
SKIN = (231, 180, 140, 255)
SKIN_D = (201, 142, 104, 255)
SH = (192, 40, 58, 255)        # áo sơ mi caro đỏ
SH_M = (152, 28, 44, 255)
SH_D = (74, 20, 24, 255)
SH_DD = (42, 11, 14, 255)
SH_L = (227, 36, 43, 255)
SH_Y = (184, 149, 63, 255)
PJ = (74, 111, 176, 255)       # quần jean
PJ_D = (47, 74, 128, 255)
PJ_DD = (34, 53, 94, 255)
PJ_L = (127, 162, 214, 255)
PSHOE = (30, 30, 36, 255)
PSOLE = (165, 110, 80, 255)
# màu đánh dấu tạm, được tô lại thành caro
M_SHIRT = (255, 0, 255, 255)
M_SHIRT_D = (200, 0, 200, 255)

_SHIRT_ROW_COLORS = {(74, 20, 24), (42, 11, 14), (192, 40, 58), (152, 28, 44), (163, 32, 47), (227, 36, 43)}


def scaled_frame(sheet, f):
    """Khung f của player_sheet thu ×0,8 kiểu NEAREST (giống Sprite2D scale 0,8): 51x51."""
    fr = sheet.crop((f * 64, 0, f * 64 + 64, 64))
    out = canvas(51, 51)
    for y in range(51):
        sy = min(63, int((y + 0.5) / 0.8))
        for x in range(51):
            sx = min(63, int((x + 0.5) / 0.8))
            out.putpixel((x, y), fr.getpixel((sx, sy)))
    return out


def head_of(sheet, f):
    """(ảnh đầu + cổ đã thu ×0,8, x tâm cổ, hàng cuối của cổ) — cắt trước hàng có áo."""
    fr = sheet.crop((f * 64, 0, f * 64 + 64, 64))
    shirt_row = 64
    for y in range(24, 64):  # bỏ qua vành mũ đỏ
        if any(fr.getpixel((x, y))[:3] in _SHIRT_ROW_COLORS and fr.getpixel((x, y))[3] > 0 for x in range(64)):
            shirt_row = y
            break
    sc = scaled_frame(sheet, f)
    last = max(y for y in range(51) if int((y + 0.5) / 0.8) < shirt_row)
    head = canvas(51, 51)
    for y in range(last + 1):
        for x in range(51):
            head.putpixel((x, y), sc.getpixel((x, y)))
    xs = [x for x in range(51) if head.getpixel((x, last))[3] > 0]
    return head, (min(xs) + max(xs)) / 2.0, last


def paste_head(layer, head_info, neck_x, neck_y):
    """Đặt đầu sao cho tâm hàng cổ cuối cùng nằm ở (neck_x, neck_y)."""
    head, cx, last = head_info
    layer.alpha_composite(head, (int(round(neck_x - cx)), neck_y - last))


def plaid(x, y, dark=False):
    """Caro đỏ: sọc dọc mỗi 3 px, sọc ngang mỗi 4 px, chỉ vàng thưa."""
    v = x % 3 == 0
    h = y % 4 == 1
    if v and h:
        c = SH_DD
    elif v or h:
        c = SH_D
    elif (x + y) % 6 == 2 and y % 4 == 3:
        c = SH_Y
    else:
        c = SH
    if dark:
        c = {SH: SH_M, SH_D: SH_DD, SH_Y: SH_D, SH_DD: SH_DD}[c]
    return c


def tint_shirt(img):
    for y in range(img.height):
        for x in range(img.width):
            p = img.getpixel((x, y))
            if p == M_SHIRT:
                img.putpixel((x, y), plaid(x, y))
            elif p == M_SHIRT_D:
                img.putpixel((x, y), plaid(x, y, True))


def layer_over(base, layer, ring=OL):
    """Dán layer lên base; viền 1 px quanh layer đè lên những gì nằm dưới (tách khối như NPC)."""
    w, h = base.size
    la = layer.load()
    pts = []
    for y in range(h):
        for x in range(w):
            if la[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and la[nx, ny][3] > 0:
                    pts.append((x, y))
                    break
    base.alpha_composite(layer)
    if ring is not None:
        for p in pts:
            base.putpixel(p, ring)


def shifted(img, ox, oy, w, h):
    out = canvas(w, h)
    out.alpha_composite(img, (ox, oy))
    return out


def rider_side(sheet):
    """Người lái nhìn ngang (quay phải), toạ độ ảnh ghép 68x60: (lớp thân, lớp tay gần)."""
    W, H = 68, 42 + RIDE_OY
    body = canvas(W, H)
    # Toạ độ ảnh ghép: mặt yên ở y=32, tay nắm x 41..43 y 24..26, sàn để chân y 45.
    # đùi nằm trên yên (ngắn, gần ngang) ló ra dưới vạt áo, gối ngay sau yếm
    poly(body, [(24, 28), (36, 28), (38, 29), (38, 31), (24, 31)], PJ)
    line(body, (29, 28), (35, 28), PJ_L)
    line(body, (24, 31), (34, 31), PJ_D)
    # cẳng chân từ gối thả xuống sàn
    poly(body, [(35, 30), (38, 30), (38, 33), (37, 41), (34, 41), (34, 33)], PJ)
    line(body, (38, 31), (37, 41), PJ_D)
    rect(body, 34, 40, 37, 41, PJ_DD)
    # giày đặt trên sàn để chân
    rect(body, 33, 42, 39, 43, PSHOE)
    px(body, 40, 43, PSHOE)
    rect(body, 33, 44, 39, 44, PSOLE)
    # thân áo: hông trên yên, vai đổ nhẹ về trước
    poly(body, [(21, 30), (22, 23), (24, 20), (26, 19), (31, 19), (33, 21), (33, 24), (30, 28), (29, 30)], M_SHIRT)
    line(body, (21, 30), (22, 23), M_SHIRT_D)
    line(body, (21, 30), (29, 30), M_SHIRT_D)
    tint_shirt(body)
    # cổ + đầu (giống lúc đi bộ)
    paste_head(body, head_of(sheet, 18), 29, 19)
    arm = canvas(W, H)
    # tay gần: vai -> khuỷu -> tay nắm
    line(arm, (29, 21), (34, 24), M_SHIRT, 3)
    line(arm, (34, 24), (37, 25), M_SHIRT, 3)
    tint_shirt(arm)
    rect(arm, 38, 24, 40, 26, SKIN)
    px(arm, 38, 26, SKIN_D)
    return body, arm


def build_ride_side(sheet, phase):
    W, H = 68, 42 + RIDE_OY
    im = canvas(W, H)
    layer_over(im, shifted(build_side(phase), 0, RIDE_OY, W, H), None)
    body, arm = rider_side(sheet)
    layer_over(im, body)
    layer_over(im, arm)
    return im


def _sleeve(img, a, b):
    line(img, a, b, M_SHIRT, 3)


def rider_front(sheet):
    """Người lái nhìn từ trước, ảnh ghép 30x60: (lớp sau xe = thân + đầu, lớp trước xe = tay + chân)."""
    W, H = 30, 42 + RIDE_OY
    back = canvas(W, H)
    # thân (phần lớn khuất sau đèn pha / yếm)
    poly(back, [(9, 31), (9, 22), (11, 19), (19, 19), (21, 22), (21, 31)], M_SHIRT)
    line(back, (15, 19), (15, 31), SH_DD)              # nẹp áo
    tint_shirt(back)
    paste_head(back, head_of(sheet, 0), 15, 19)
    front = canvas(W, H)
    # tay: vai -> tay nắm hai bên
    for sx, gx in ((10, 4), (20, 25)):
        _sleeve(front, (sx, 21), ((sx + gx) // 2, 25))
        _sleeve(front, ((sx + gx) // 2, 25), (gx, 27))
    tint_shirt(front)
    rect(front, 3, 27, 5, 29, SKIN)
    rect(front, 24, 27, 26, 29, SKIN)
    # gối chĩa ra hai bên yếm, cẳng chân chụm vào trong, giày trên sàn (vẽ bên trái rồi lật)
    leg = canvas(W, H)
    poly(leg, [(2, 33), (3, 31), (7, 31), (8, 33), (8, 35), (2, 35)], PJ)
    line(leg, (3, 31), (6, 31), PJ_L)
    line(leg, (2, 35), (8, 35), PJ_D)
    poly(leg, [(3, 36), (7, 36), (8, 41), (5, 41)], PJ)
    line(leg, (7, 36), (8, 41), PJ_D)
    rect(leg, 4, 42, 9, 43, PSHOE)
    rect(leg, 5, 42, 8, 42, (68, 60, 78, 255))
    front.alpha_composite(leg)
    front.alpha_composite(ImageOps.mirror(leg))
    return back, front


def build_ride_front(sheet):
    W, H = 30, 42 + RIDE_OY
    im = canvas(W, H)
    back, front = rider_front(sheet)
    layer_over(im, back)
    layer_over(im, shifted(build_front_layers(), 0, RIDE_OY, W, H))
    layer_over(im, front)
    return im


def rider_back(sheet):
    """Người lái nhìn từ sau, ảnh ghép 30x60: một lớp (đầu, lưng, tay, chân) nằm giữa tay lái và đuôi xe."""
    W, H = 30, 42 + RIDE_OY
    body = canvas(W, H)
    # chân ôm hai bên đuôi xe, cẳng chân chụm vào gác chân (vẽ bên trái rồi lật)
    leg = canvas(W, H)
    poly(leg, [(3, 31), (5, 29), (9, 29), (9, 34), (4, 34)], PJ)
    line(leg, (5, 29), (8, 29), PJ_L)
    poly(leg, [(4, 35), (8, 35), (9, 39), (6, 39)], PJ)
    line(leg, (4, 35), (8, 35), PJ_D)
    line(leg, (4, 35), (6, 39), PJ_D)
    rect(leg, 5, 40, 9, 41, PSHOE)
    rect(leg, 5, 42, 9, 42, PSOLE)
    body.alpha_composite(leg)
    body.alpha_composite(ImageOps.mirror(leg))
    rect(body, 9, 28, 20, 31, PJ)                        # mông trên yên
    # lưng áo
    poly(body, [(8, 29), (8, 22), (10, 19), (20, 19), (22, 22), (22, 29)], M_SHIRT)
    tint_shirt(body)
    # tay giang ra hai tay nắm
    arm = canvas(W, H)
    _sleeve(arm, (9, 21), (5, 24))
    _sleeve(arm, (21, 21), (25, 24))
    tint_shirt(arm)
    rect(arm, 2, 23, 4, 25, SKIN)
    rect(arm, 25, 23, 27, 25, SKIN)
    paste_head(body, head_of(sheet, 10), 15, 19)
    return body, arm


def build_ride_back(sheet):
    W, H = 30, 42 + RIDE_OY
    far, near = build_back_layers()
    im = canvas(W, H)
    layer_over(im, shifted(far, 0, RIDE_OY, W, H))
    body, arm = rider_back(sheet)
    layer_over(im, body)
    layer_over(im, arm)
    layer_over(im, shifted(near, 0, RIDE_OY, W, H))
    return im


def main(root):
    art = os.path.join(root, "game", "art")
    sheet = Image.open(os.path.join(art, "player_sheet.png")).convert("RGBA")
    # xe không người (xe đỗ / lớp xe)
    build_side(0.0).save(os.path.join(art, "bike_side.png"))
    build_side(math.pi / 6).save(os.path.join(art, "bike_side_b.png"))
    build_side(0.0).save(os.path.join(art, "bike_parked.png"))
    build_front().save(os.path.join(art, "bike_front.png"))
    build_back().save(os.path.join(art, "bike_back.png"))
    # người + xe
    build_ride_side(sheet, 0.0).save(os.path.join(art, "bike_ride_side.png"))
    build_ride_side(sheet, math.pi / 6).save(os.path.join(art, "bike_ride_side_b.png"))
    build_ride_front(sheet).save(os.path.join(art, "bike_ride_front.png"))
    build_ride_back(sheet).save(os.path.join(art, "bike_ride_back.png"))
    print("dream bike: side 68x42 (x2 khung), front/back 30x42; ride side 68x60 (x2), ride front/back 30x60")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
