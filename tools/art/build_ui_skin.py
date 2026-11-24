# -*- coding: utf-8 -*-
"""Bộ khung giao diện pixel kiểu "gỗ + giấy dó" (vẽ hoàn toàn bằng code, không chép tài sản của ai).

Vẽ ở tỉ lệ 1× rồi phóng NEAREST ×2 (một pixel thiết kế = 2 px màn hình, khớp chữ cỡ ×2 của font game).
Đầu ra game/art/ui/ (game/ui/ui_skin.gd đọc tên file + lề 9-slice ở bảng PANELS bên dưới, nhân 2):
  panel_wood.png      khung gỗ có đinh tán bốn góc + ruột giấy dó (hộp thoại, bảng lớn)
  panel_dark.png      khung gỗ sẫm + ruột nâu sẫm (HUD trên bản đồ, thông báo)
  panel_plate.png     bảng tên (tấm ván nhỏ có đinh hai đầu)
  panel_portrait.png  khung chân dung (viền đồng + nền trời nhạt)
  panel_tooltip.png   ô chú thích (viền mảnh, giấy sáng)
  panel_paper.png     trang giấy (sổ tay, chú thích bản đồ)
  panel_sign.png      biển gỗ (đồng hồ góc phải)
  panel_book.png      bìa sổ da có góc đồng (sổ tay V)
  panel_tab_on/off.png thẻ đánh dấu trang
  panel_button*.png   nút thường / đang chọn / đang nhấn
  panel_toast.png     dải thông báo thành tựu
  panel_slot.png      ô chữ (nhập tên)
  node_*.png          khung nút thành tựu (đã mở / chưa mở / bí mật / mục tiêu)
  cursor.png, next.png, arrow_up.png, arrow_down.png
  icons.png           bảng biểu tượng 12×12 (thứ tự ở ICON_NAMES – ui_skin.gd giữ cùng danh sách)
Chạy: python tools/art/build_ui_skin.py [--preview <file.png>]
"""
from __future__ import annotations

import os
import random
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "art", "ui")
SCALE = 2

# ------------------------------------------------------------------ bảng màu
K = (46, 26, 16, 255)          # viền tối
WD = (104, 58, 30, 255)        # gỗ sẫm
WM = (150, 90, 46, 255)        # gỗ
WL = (190, 126, 66, 255)       # gỗ sáng
WH = (224, 168, 98, 255)       # gỗ ánh
PA = (246, 230, 190, 255)      # giấy
PS = (232, 208, 158, 255)      # giấy bóng
PD = (210, 176, 120, 255)      # giấy sẫm
BR = (238, 192, 80, 255)       # đồng
BD = (160, 104, 38, 255)       # đồng sẫm
BL = (255, 238, 160, 255)      # đồng sáng
DK = (28, 17, 11, 255)
DD = (58, 36, 22, 255)
DM = (84, 54, 32, 255)
DL = (116, 78, 46, 255)
DI = (44, 30, 22, 240)         # ruột sẫm (hơi trong)
SKY1 = (176, 212, 196, 255)
SKY2 = (206, 226, 190, 255)
SKY3 = (232, 234, 196, 255)
RED = (176, 52, 40, 255)
REDL = (220, 90, 64, 255)
RED_D = (112, 30, 26, 255)
LE1 = (120, 44, 36, 255)       # da bìa sổ
LE2 = (150, 60, 44, 255)
LE3 = (90, 30, 26, 255)
GRN = (78, 128, 62, 255)
GRNL = (120, 170, 84, 255)
STONE1 = (70, 70, 78, 255)
STONE2 = (96, 96, 104, 255)
STONE3 = (126, 126, 134, 255)
CLEAR = (0, 0, 0, 0)

PANELS: dict[str, int] = {}  # tên → lề 9-slice (1×)


def img(w: int, h: int, fill=CLEAR) -> Image.Image:
	return Image.new("RGBA", (w, h), fill)


def rect(im: Image.Image, x: int, y: int, w: int, h: int, c) -> None:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if 0 <= xx < im.width and 0 <= yy < im.height:
				im.putpixel((xx, yy), c)


def frame(im: Image.Image, inset: int, c) -> None:
	w, h = im.size
	rect(im, inset, inset, w - 2 * inset, 1, c)
	rect(im, inset, h - 1 - inset, w - 2 * inset, 1, c)
	rect(im, inset, inset, 1, h - 2 * inset, c)
	rect(im, w - 1 - inset, inset, 1, h - 2 * inset, c)


def round_corners(im: Image.Image, r: int = 1) -> None:
	w, h = im.size
	for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
		im.putpixel((x, y), CLEAR)
	if r >= 2:
		for (x, y) in [(1, 0), (0, 1), (w - 2, 0), (w - 1, 1), (0, h - 2), (1, h - 1), (w - 1, h - 2), (w - 2, h - 1)]:
			im.putpixel((x, y), CLEAR)
		for (x, y) in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]:
			im.putpixel((x, y), K)


def stud(im: Image.Image, cx: int, cy: int) -> None:
	"""Đinh tán đồng 4×4 có viền."""
	pat = [".kk.", "kBbk", "kbdk", ".kk."]
	cmap = {"k": K, "B": BL, "b": BR, "d": BD}
	for r, row in enumerate(pat):
		for c, ch in enumerate(row):
			if ch != ".":
				im.putpixel((cx + c, cy + r), cmap[ch])


def grain(im: Image.Image, x0: int, y0: int, w: int, h: int, base, dark, light, seed: int, horizontal: bool = True) -> None:
	rnd = random.Random(seed)
	rect(im, x0, y0, w, h, base)
	if horizontal:
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				v = rnd.random()
				if v < 0.10:
					im.putpixel((x, y), dark)
				elif v < 0.16:
					im.putpixel((x, y), light)
	else:
		for x in range(x0, x0 + w):
			for y in range(y0, y0 + h):
				v = rnd.random()
				if v < 0.10:
					im.putpixel((x, y), dark)
				elif v < 0.16:
					im.putpixel((x, y), light)


def paper(im: Image.Image, x0: int, y0: int, w: int, h: int, seed: int, base=PA, speck=PS) -> None:
	rnd = random.Random(seed)
	rect(im, x0, y0, w, h, base)
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if rnd.random() < 0.05:
				im.putpixel((x, y), speck)


def save(im: Image.Image, name: str) -> None:
	big = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
	big.save(os.path.join(OUT, name + ".png"))


# ------------------------------------------------------------------ khung

def panel_wood() -> None:
	s = 36
	im = img(s, s)
	rect(im, 0, 0, s, s, K)
	# viền gỗ 6 px: ánh – gỗ – vân – sẫm
	rect(im, 1, 1, s - 2, s - 2, WH)
	rect(im, 2, 2, s - 4, s - 4, WL)
	grain(im, 3, 3, s - 6, s - 6, WM, WD, WL, 7)
	rect(im, 6, 6, s - 12, s - 12, WD)
	rect(im, 7, 7, s - 14, s - 14, K)
	paper(im, 8, 8, s - 16, s - 16, 11)
	# bóng trong (trên + trái) cho giấy lõm xuống khung
	rect(im, 8, 8, s - 16, 1, PD)
	rect(im, 8, 8, 1, s - 16, PS)
	round_corners(im, 2)
	for (x, y) in [(2, 2), (s - 6, 2), (2, s - 6), (s - 6, s - 6)]:
		stud(im, x, y)
	PANELS["wood"] = 10
	save(im, "panel_wood")


def panel_dark() -> None:
	s = 28
	im = img(s, s)
	rect(im, 0, 0, s, s, DK)
	rect(im, 1, 1, s - 2, s - 2, DL)
	grain(im, 2, 2, s - 4, s - 4, DM, DD, DL, 3)
	rect(im, 4, 4, s - 8, s - 8, DK)
	rect(im, 5, 5, s - 10, s - 10, DI)
	round_corners(im, 2)
	for (x, y) in [(1, 1), (s - 5, 1), (1, s - 5), (s - 5, s - 5)]:
		stud(im, x, y)
	PANELS["dark"] = 7
	save(im, "panel_dark")


def panel_plate() -> None:
	w, h = 28, 14
	im = img(w, h)
	rect(im, 0, 0, w, h, K)
	grain(im, 1, 1, w - 2, h - 2, DM, DD, DL, 5)
	rect(im, 1, 1, w - 2, 1, DL)
	rect(im, 1, h - 2, w - 2, 1, DD)
	round_corners(im, 1)
	for x in (2, w - 4):
		im.putpixel((x, 5), BL)
		im.putpixel((x + 1, 5), BR)
		im.putpixel((x, 6), BR)
		im.putpixel((x + 1, 6), BD)
	PANELS["plate"] = 5
	save(im, "panel_plate")


def panel_portrait() -> None:
	s = 24
	im = img(s, s)
	rect(im, 0, 0, s, s, K)
	rect(im, 1, 1, s - 2, s - 2, BR)
	rect(im, 1, 1, s - 2, 1, BL)
	rect(im, 1, 1, 1, s - 2, BL)
	rect(im, 2, s - 2, s - 3, 1, BD)
	rect(im, s - 2, 2, 1, s - 3, BD)
	rect(im, 3, 3, s - 6, s - 6, K)
	# nền trời ba dải
	inner = s - 8
	for y in range(inner):
		c = SKY1 if y < inner * 0.45 else (SKY2 if y < inner * 0.8 else SKY3)
		rect(im, 4, 4 + y, inner, 1, c)
	round_corners(im, 1)
	PANELS["portrait"] = 5
	save(im, "panel_portrait")


def panel_tooltip() -> None:
	s = 12
	im = img(s, s)
	rect(im, 0, 0, s, s, K)
	rect(im, 1, 1, s - 2, s - 2, WL)
	rect(im, 2, 2, s - 4, s - 4, PA)
	rect(im, 2, 2, s - 4, 1, (255, 246, 216, 255))
	round_corners(im, 1)
	PANELS["tooltip"] = 4
	save(im, "panel_tooltip")


def panel_paper() -> None:
	s = 16
	im = img(s, s)
	paper(im, 0, 0, s, s, 21)
	frame(im, 0, PD)
	rect(im, 1, s - 2, s - 2, 1, PS)
	im.putpixel((0, 0), CLEAR)
	im.putpixel((s - 1, 0), CLEAR)
	im.putpixel((0, s - 1), CLEAR)
	im.putpixel((s - 1, s - 1), CLEAR)
	PANELS["paper"] = 3
	save(im, "panel_paper")


def panel_sign() -> None:
	w, h = 30, 22
	im = img(w, h)
	rect(im, 0, 0, w, h, K)
	# hai tấm ván ngang
	grain(im, 1, 1, w - 2, 10, WM, WD, WL, 31)
	grain(im, 1, 11, w - 2, 10, WM, WD, WL, 37)
	rect(im, 1, 10, w - 2, 1, WD)
	rect(im, 1, 1, w - 2, 1, WH)
	rect(im, 1, 11, w - 2, 1, WL)
	rect(im, 1, h - 2, w - 2, 1, WD)
	round_corners(im, 1)
	for (x, y) in [(2, 4), (w - 4, 4), (2, 15), (w - 4, 15)]:
		im.putpixel((x, y), BL)
		im.putpixel((x + 1, y), BR)
		im.putpixel((x, y + 1), BR)
		im.putpixel((x + 1, y + 1), BD)
	PANELS["sign"] = 6
	save(im, "panel_sign")


def panel_book() -> None:
	s = 32
	im = img(s, s)
	rect(im, 0, 0, s, s, K)
	grain(im, 1, 1, s - 2, s - 2, LE1, LE3, LE2, 41)
	rect(im, 1, 1, s - 2, 1, LE2)
	frame(im, 3, (196, 148, 70, 255))  # chỉ vàng dập nổi
	# góc đồng
	for (x, y, fx, fy) in [(1, 1, 1, 1), (s - 2, 1, -1, 1), (1, s - 2, 1, -1), (s - 2, s - 2, -1, -1)]:
		for i in range(6):
			im.putpixel((x + i * fx, y), BR)
			im.putpixel((x, y + i * fy), BR)
		for i in range(4):
			im.putpixel((x + 1 * fx + i * fx, y + 1 * fy), BD)
			im.putpixel((x + 1 * fx, y + 1 * fy + i * fy), BD)
		im.putpixel((x, y), BL)
	rect(im, 6, 6, s - 12, s - 12, K)
	paper(im, 7, 7, s - 14, s - 14, 43)
	round_corners(im, 1)
	PANELS["book"] = 9
	save(im, "panel_book")


def panel_tab(on: bool) -> None:
	w, h = 16, 12
	im = img(w, h)
	rect(im, 0, 0, w, h, K)
	if on:
		paper(im, 1, 1, w - 2, h - 1, 51)
		rect(im, 1, 1, w - 2, 1, (255, 246, 216, 255))
		rect(im, 0, h - 1, w, 1, CLEAR)
		im.putpixel((0, h - 1), K)
		im.putpixel((w - 1, h - 1), K)
		rect(im, 1, h - 1, w - 2, 1, PA)
	else:
		paper(im, 1, 1, w - 2, h - 2, 53, base=PD, speck=PS)
		rect(im, 1, h - 2, w - 2, 1, (186, 150, 98, 255))
	im.putpixel((0, 0), CLEAR)
	im.putpixel((w - 1, 0), CLEAR)
	PANELS["tab_on" if on else "tab_off"] = 4
	save(im, "panel_tab_on" if on else "panel_tab_off")


def panel_button(kind: str) -> None:
	w, h = 16, 16
	im = img(w, h)
	rect(im, 0, 0, w, h, K)
	if kind == "pressed":
		rect(im, 1, 1, w - 2, h - 2, WD)
		grain(im, 1, 2, w - 2, h - 3, WM, WD, WL, 61)
	else:
		hi = kind == "hover"
		grain(im, 1, 1, w - 2, h - 2, WL if hi else WM, WM if hi else WD, WH, 61)
		rect(im, 1, 1, w - 2, 1, BL if hi else WH)
		rect(im, 1, h - 3, w - 2, 2, WD)
		if hi:
			frame(im, 1, BR)
			rect(im, 1, 1, w - 2, 1, BL)
	round_corners(im, 1)
	name = {"normal": "button", "hover": "button_hover", "pressed": "button_pressed"}[kind]
	PANELS[name] = 5
	save(im, "panel_" + name)


def panel_toast() -> None:
	w, h = 24, 16
	im = img(w, h)
	rect(im, 0, 0, w, h, DK)
	rect(im, 1, 1, w - 2, h - 2, BR)
	rect(im, 1, 1, w - 2, 1, BL)
	rect(im, 1, h - 2, w - 2, 1, BD)
	rect(im, 3, 3, w - 6, h - 6, DK)
	rect(im, 4, 4, w - 8, h - 8, (52, 34, 24, 245))
	round_corners(im, 1)
	PANELS["toast"] = 6
	save(im, "panel_toast")


def panel_slot() -> None:
	s = 12
	im = img(s, s)
	rect(im, 0, 0, s, s, K)
	rect(im, 1, 1, s - 2, s - 2, (255, 248, 226, 255))
	rect(im, 1, 1, s - 2, 1, PD)
	rect(im, 1, 1, 1, s - 2, PD)
	PANELS["slot"] = 3
	save(im, "panel_slot")


def nodes() -> None:
	"""Khung nút thành tựu 22×22 (vẽ nguyên, không 9-slice)."""
	s = 22

	def base(edge, fill, hi, lo, seed):
		im = img(s, s)
		rect(im, 0, 0, s, s, K)
		rect(im, 1, 1, s - 2, s - 2, edge)
		rect(im, 1, 1, s - 2, 1, hi)
		rect(im, 1, 1, 1, s - 2, hi)
		rect(im, 1, s - 2, s - 2, 1, lo)
		rect(im, s - 2, 1, 1, s - 2, lo)
		rect(im, 3, 3, s - 6, s - 6, K)
		rect(im, 4, 4, s - 8, s - 8, fill)
		round_corners(im, 2)
		return im

	save(base(WM, PA, WH, WD, 1), "node_open")
	save(base(BR, (255, 244, 200, 255), BL, BD, 2), "node_gold")
	im = base(STONE2, (40, 40, 46, 255), STONE3, STONE1, 3)
	save(im, "node_locked")
	# bí mật: viền đỏ thẫm có gai bốn hướng
	im = base(RED, (52, 30, 34, 255), REDL, RED_D, 4)
	for (x, y) in [(10, 0), (11, 0), (0, 10), (0, 11), (21, 10), (21, 11), (10, 21), (11, 21)]:
		im.putpixel((x, y), K)
	save(im, "node_secret")
	# mục tiêu (nhà vô địch…): khung tròn góc đồng
	im = base(BR, (255, 244, 200, 255), BL, BD, 5)
	for (x, y) in [(2, 2), (s - 3, 2), (2, s - 3), (s - 3, s - 3)]:
		im.putpixel((x, y), BL)
	save(im, "node_goal")


# ------------------------------------------------------------------ hình nhỏ vẽ bằng chữ

PAL = {
	".": CLEAR, "k": K, "w": (255, 255, 255, 255), "c": PA, "C": PD, "y": (250, 214, 80, 255), "Y": BL,
	"o": (226, 132, 48, 255), "r": RED, "R": REDL, "b": WM, "B": WD, "l": WL, "g": GRN, "G": (48, 92, 40, 255),
	"h": GRNL, "u": (70, 120, 200, 255), "U": (40, 70, 140, 255), "i": (150, 200, 240, 255), "s": STONE3,
	"S": STONE1, "p": (240, 150, 170, 255), "m": (130, 80, 170, 255), "d": BD, "e": (255, 248, 230, 255),
	"n": (60, 60, 64, 255), "f": (255, 110, 60, 255), "t": (110, 200, 190, 255),
}


def from_rows(rows: list[str]) -> Image.Image:
	h = len(rows)
	w = max(len(r) for r in rows)
	im = img(w, h)
	for y, row in enumerate(rows):
		for x, ch in enumerate(row):
			im.putpixel((x, y), PAL[ch])
	return im


CURSOR = [
	"...kk.....",
	"...kYk....",
	"kkkkYYk...",
	"kYYYYYYk..",
	"kyyyyyyyk.",
	"koooooyk..",
	"kkkkoyk...",
	"...kok....",
	"...kk.....",
]
NEXT = [
	"kkkkkkkkk",
	"kYYYYYYYk",
	".kyyyyyk.",
	"..kyyyk..",
	"...kok...",
	"....k....",
]
ARROW_UP = [
	"....k....",
	"...kck...",
	"..kccck..",
	".kcccCCk.",
	"kkkkkkkkk",
]
ARROW_DOWN = list(reversed([r.replace("C", "c") for r in ARROW_UP]))

# 12×12 – biểu tượng dùng cho sổ tay, đồng hồ, bản đồ, thông báo.
ICONS: dict[str, list[str]] = {
	"chicken": [
		"....rr......",
		"...rRrk.....",
		"..kwwwwk....",
		"..kwkwwwk...",
		".ykwwwwwk...",
		"yykwwwwwwk.k",
		"..kRwwwwwwkk",
		"...kwwwwwwk.",
		"...kwwwwwk..",
		"....kkkkk...",
		".....y.y....",
		"....yy.yy...",
	],
	"sword": [
		"..........kk",
		".........kek",
		"........kek.",
		".......kek..",
		"......kek...",
		".....kek....",
		"..k.kek.....",
		"..kkek......",
		"...kk.......",
		"..kdkk......",
		".kdk.k......",
		".kk.........",
	],
	"card": [
		"..kkkkkkk...",
		"..kcccccck..",
		"..kcrrrcck..",
		"..kcrRrcck..",
		"..kccrccck..",
		"..kcccccck..",
		"..kcyyyyck..",
		"..kcyYYyck..",
		"..kcyyyyck..",
		"..kcccccck..",
		"..kkkkkkkk..",
		"............",
	],
	"book": [
		"............",
		".kkkkkkkkkk.",
		".kuuuukiiik.",
		".kuUUukiiik.",
		".kuuuukiiik.",
		".kuUUukiiik.",
		".kuuuukiiik.",
		".kuuuukiiik.",
		".kkkkkkkkkk.",
		"..kcccccck..",
		"...kkkkkk...",
		"............",
	],
	"coin": [
		"............",
		"....kkkk....",
		"...kYYYyk...",
		"..kYyyyyok..",
		"..kYykkyok..",
		"..kyykyyok..",
		"..kyykyyok..",
		"..kyyyyyok..",
		"...kooook...",
		"....kkkk....",
		"............",
		"............",
	],
	"egg": [
		"............",
		".....kk.....",
		"....keek....",
		"...keeeck...",
		"...keeeck...",
		"..keeeeeck..",
		"..keeeeeck..",
		"..keeeeCck..",
		"...keeCck...",
		"....kkkk....",
		"............",
		"............",
	],
	"flask": [
		"....kkkk....",
		"....kcck....",
		"....kcck....",
		"...kcccck...",
		"..kcccccck..",
		"..khhhhhhk..",
		".khhwhhhhhk.",
		".khhhhhwhhk.",
		".khhhhhhhhk.",
		"..kkkkkkkk..",
		"............",
		"............",
	],
	"house": [
		".....kk.....",
		"....krrk....",
		"...krRRrk...",
		"..krRRRRrk..",
		".krrrrrrrrk.",
		"kkkkkkkkkkkk",
		".kcccccccck.",
		".kcikckkcck.",
		".kcikckbkck.",
		".kccckbbkck.",
		".kkkkkkkkkk.",
		"............",
	],
	"map": [
		"............",
		"kkkkkkkkkkkk",
		"kcchccccuuck",
		"kchhhcccuuck",
		"kcchccrccuck",
		"kcccccrrcuck",
		"kcuucccrrcck",
		"kcuuucccrcck",
		"kccuucccchck",
		"kcccccccchhk",
		"kkkkkkkkkkkk",
		"............",
	],
	"boat": [
		"............",
		".....k......",
		".....kw.....",
		".....kww....",
		".....kwww...",
		".....kkkk...",
		"kkkkkkkkkkkk",
		"kbbbbbbbbbbk",
		".kBbbbbbbBk.",
		"..kkkkkkkk..",
		"iuuiuuiuuiuu",
		"............",
	],
	"bike": [
		"............",
		"......kkk...",
		".......kr...",
		"..kkkkrrr...",
		".krrrrrrrk..",
		"..kkk.kkk...",
		".kkkkk.kkkk.",
		"knnsnkknsnnk",
		"knsksnknskn.",
		"knnsnk.knnk.",
		".kkk....kk..",
		"............",
	],
	"siren": [
		"............",
		".k..kkkk..k.",
		"..kkuuRRkk..",
		"...kuiRrk...",
		"k..kuuRrk..k",
		"...kuuRrk...",
		"..kkkkkkkk..",
		"..kssssssk..",
		"..kkkkkkkk..",
		"............",
		"............",
		"............",
	],
	"trophy": [
		"............",
		".kkkkkkkkkk.",
		"kykYYYyyyoyk",
		"kyk.YyyyokYk",
		".kkkyyyyokk.",
		"...kyyyok...",
		"....kyok....",
		".....ko.....",
		"....kyok....",
		"...kddddk...",
		"...kkkkkk...",
		"............",
	],
	"star": [
		".....kk.....",
		".....kyk....",
		"....kyyk....",
		"kkkkkyYykkkk",
		"kyyyyyYyyyyk",
		".kyyyyyyyyk.",
		"..kyyyyyyk..",
		"..kyyookyk..",
		".kyook.koyk.",
		".kok.....kk.",
		".kk.........",
		"............",
	],
	"lock": [
		"............",
		"....kkkk....",
		"...ks..sk...",
		"...ks..sk...",
		"..kkkkkkkk..",
		"..kYyyyyyk..",
		"..kyykkyyk..",
		"..kyykkyyk..",
		"..kyyykyyk..",
		"..kooooook..",
		"..kkkkkkkk..",
		"............",
	],
	"cat": [
		"............",
		".k.......k..",
		".kok....kok.",
		".koookkkoook",
		".kooooooooek",
		".kokeoookeek",
		".kooooooooek",
		"..kooopoook.",
		"...kkoookk..",
		"....koeek...",
		"....kkkkk...",
		"............",
	],
	"fish": [
		"............",
		"............",
		"....kkkk....",
		"..kkiiiikk.k",
		".kiwkiiiiikk",
		"kiiiiiiiiiik",
		".kuuuuuuuukk",
		"..kkuuuukk.k",
		"....kkkk....",
		"............",
		"............",
		"............",
	],
	"temple": [
		".....kk.....",
		"....kyyk....",
		".kkkkkkkkkk.",
		"krrrrrrrrrrk",
		".kkkkkkkkkk.",
		"..krkkkkrk..",
		"..krkyykrk..",
		"..krkyykrk..",
		"..krkyykrk..",
		".kkkkkkkkkk.",
		"kddddddddddk",
		"kkkkkkkkkkkk",
	],
	"market": [
		"............",
		"kkkkkkkkkkkk",
		"krwrwrwrwrwk",
		"krwrwrwrwrwk",
		"kkkkkkkkkkkk",
		".kb......bk.",
		".kb.ko.g.bk.",
		".kbkkkkkkbk.",
		".kbkoykhgbk.",
		".kbkkkkkkbk.",
		".kk......kk.",
		"............",
	],
	"flag": [
		"..k.........",
		"..kkkkk.....",
		"..krrRrkk...",
		"..krRyRrrk..",
		"..krrRrrkk..",
		"..kkkkk.....",
		"..k.........",
		"..k.........",
		"..k.........",
		"..k.........",
		".kkk........",
		"............",
	],
	"heart": [
		"............",
		"..kkk..kkk..",
		".kRRrkkrRrk.",
		".kRwrrrrrrk.",
		".krrrrrrrrk.",
		".krrrrrrrrk.",
		"..krrrrrrk..",
		"...krrrrk...",
		"....krrk....",
		".....kk.....",
		"............",
		"............",
	],
	"clock": [
		"............",
		"...kkkkkk...",
		"..keeeeeek..",
		".keeekeeeek.",
		".keeekeeeek.",
		".keeekkkeek.",
		".keeeeeeeek.",
		".keeeeeeeek.",
		"..keeeeeek..",
		"...kkkkkk...",
		"............",
		"............",
	],
	"jar": [
		"............",
		"...kkkkkk...",
		"...krrrrk...",
		"..kkkkkkkk..",
		"..koooooyk..",
		"..kohooook..",
		"..kooooohk..",
		"..kohoooook.",
		"..koooohok..",
		"..kkkkkkkk..",
		"............",
		"............",
	],
	"ticket": [
		"............",
		"............",
		"kkkkkkkkkkkk",
		"kppppkpppppk",
		".kpppkprrppk",
		"kppppkpprppk",
		".kpppkpprppk",
		"kppppkprrrpk",
		"kkkkkkkkkkkk",
		"............",
		"............",
		"............",
	],
	"sign": [
		"............",
		"kkkkkkkkkk..",
		"klllllllllk.",
		"klBBlBBBlllk",
		"kllllllllllk",
		"klBBBlBBllk.",
		"kkkkkkkkkk..",
		"....kbk.....",
		"....kbk.....",
		"....kbk.....",
		"...kkbkk....",
		"..ggggggg...",
	],
	"bridge": [
		"............",
		"............",
		"..kkkkkkkk..",
		".kssssssssk.",
		"kssssssssssk",
		"kskkkkkkkksk",
		"ksk......ksk",
		"ksk......ksk",
		"kskiuuiuuksk",
		"iuuiuuiuuiuu",
		"uiuuiuuiuuiu",
		"............",
	],
	"key": [
		"............",
		"kkkkkkkkkkk.",
		"kcccccccccCk",
		"kcccccccccCk",
		"kcckkkkkccCk",
		"kccckccccCCk",
		"kccckccccCCk",
		"kcccccccccCk",
		"kCCCCCCCCCCk",
		"kkkkkkkkkkk.",
		"............",
		"............",
	],
	"shield": [
		"............",
		".kkkkkkkkkk.",
		".kssiiiissk.",
		".ksiuuuuisk.",
		".ksiuwuuisk.",
		".ksiuuuuisk.",
		"..ksiuuisk..",
		"..ksiuuisk..",
		"...ksiisk...",
		"....kssk....",
		".....kk.....",
		"............",
	],
	"fire": [
		"......k.....",
		".....kfk....",
		"....kffk.k..",
		"...kfffkkfk.",
		"..kffyfffffk",
		"..kfyyyfffk.",
		".kffyYyyffk.",
		".kfyyYYyyfk.",
		".kfyYYYYyfk.",
		"..kfyyyyfk..",
		"...kkkkkk...",
		"............",
	],
	"medal": [
		"..kk...kk...",
		"..kuk.kuk...",
		"...kuku k...",
		"....kuk.....",
		"...kkkkk....",
		"..kyYYyok...",
		".kyYyyyyok..",
		".kyyykyyok..",
		".kyykkyyok..",
		"..kyyyyok...",
		"...kkkkk....",
		"............",
	],
	"dog": [
		"............",
		".kk.........",
		"kbbk.....k..",
		"kbBbkkkk.kk.",
		"kbbbbbbbkbk.",
		".kkbbbbbbbk.",
		"...kbbbbbbk.",
		"...kbbbbbk..",
		"...kbk.kbk..",
		"...kbk.kbk..",
		"...kk..kk...",
		"............",
	],
	"plate": [
		"............",
		"............",
		"...kkkkkk...",
		".kkiiiiiikk.",
		"kieeeeeeeeik",
		"kieeiiiieeik",
		"kieeeeeeeeik",
		".kkiiiiiikk.",
		"...kkkkkk...",
		"..i...i..i..",
		".i.i.i.i....",
		"............",
	],
	"dna": [
		"............",
		"..kk....kk..",
		"..kmk..kuk..",
		"...kmkkuk...",
		"....kmuk....",
		"...kkuuk....",
		"...kukmmk...",
		"..kuk..kmk..",
		"..kk....kk..",
		"..kmk..kuk..",
		"...kmkkuk...",
		"....kkkk....",
	],
	"coop": [
		"............",
		"....kkkk....",
		"..kkbbbbkk..",
		".kbbbbbbbbk.",
		"kkkkkkkkkkkk",
		".kllllllllk.",
		".klkkkkkllk.",
		".klkBBBklyk.",
		".klkBBBkllk.",
		".klkkkkklyk.",
		".kkkkkkkkkk.",
		"..g..g...g..",
	],
	"sparkle": [
		"............",
		".....k......",
		".....y......",
		"....kYk.....",
		".kyyYwYyyk..",
		"....kYk.....",
		".....y....k.",
		".....k...kyk",
		"..........k.",
		"..k.........",
		".kyk........",
		"..k.........",
	],
	"sun": [
		"............",
		".y...y...y..",
		"..y.kkkk.y..",
		"...kyYYyk...",
		"..kyYYyyok..",
		"yykyYyyyokyy",
		"..kyyyyyok..",
		"...kyyook...",
		"..y.kkkk.y..",
		".y...y...y..",
		"............",
		"............",
	],
	"sunset": [
		"............",
		"............",
		"..o..o..o...",
		"....kkkk....",
		"o..kyYyok..o",
		"..kyyyyook..",
		"kkkkkkkkkkkk",
		"oooooooooooo",
		"............",
		"ffffffffffff",
		"............",
		"............",
	],
	"moon": [
		"............",
		"....kkk...w.",
		"...kYYk.....",
		"..kYYk......",
		"..kYyk...w..",
		"..kYyk......",
		"..kYyyk.....",
		"...kyyykkk..",
		"....kkkk....",
		".w..........",
		"............",
		"............",
	],
	"you": [
		"............",
		"....kkkk....",
		"...kRRRRk...",
		"..kRRwwRRk..",
		"..kRwkkwRk..",
		"..kRRwwRRk..",
		"...kRRRRk...",
		"....kRRk....",
		".....kk.....",
		"............",
		"............",
		"............",
	],
	"target": [
		"............",
		"...kkkkkk...",
		"..kyyyyyyk..",
		".kyykkkkyyk.",
		".kykyyyykyk.",
		".kykykkykyk.",
		".kykykkykyk.",
		".kykyyyykyk.",
		".kyykkkkyyk.",
		"..kyyyyyyk..",
		"...kkkkkk...",
		"............",
	],
	"question": [
		"............",
		"...kkkkk....",
		"..kyyyyyk...",
		"..kykkkyk...",
		"..kkk.kyk...",
		"....kkyk....",
		"....kyk.....",
		"....kkk.....",
		"....kyk.....",
		"....kkk.....",
		"............",
		"............",
	],
	"school": [
		"............",
		"....kkkk....",
		"...kyyyyk...",
		"..kkkkkkkk..",
		".kcccccccck.",
		".kciickiick.",
		".kcccccccck.",
		".kciickiick.",
		".kcccbbcccck",
		".kkkkbbkkkk.",
		"gggggggggggg",
		"............",
	],
	"race": [
		"............",
		"kkkkkkkkkk..",
		"kwnwnwnwnk..",
		"knwnwnwnwk..",
		"kwnwnwnwnk..",
		"kkkkkkkkkk..",
		"k...........",
		"k...........",
		"k...........",
		"k...........",
		"k...........",
		"............",
	],
	"rice": [
		"............",
		"..h....h....",
		"..hg..hg..h.",
		"...hg.g..hg.",
		"..y.hgg.hg..",
		"..yy.gghg...",
		"...yy.gg....",
		".....kggk...",
		"....kbbbbk..",
		"....kbbbbk..",
		".....kkkk...",
		"............",
	],
	"brick": [
		"............",
		"............",
		"kkkkkkkkkkkk",
		"krrrrkrrrrrk",
		"kkkkkkkkkkkk",
		"krrkrrrrrkrk",
		"kkkkkkkkkkkk",
		"krrrrrkrrrrk",
		"kkkkkkkkkkkk",
		"............",
		"............",
		"............",
	],
	"fight": [
		"............",
		"rr........kk",
		"rRrk....kwwk",
		".kwwk..kwwk.",
		".kwwwkkwwwk.",
		"..kwwk.kwk..",
		"..kwwwkwwk..",
		"...kwwwwk...",
		"....kyyk....",
		"...yy..yy...",
		"............",
		"............",
	],
	"gear": [
		"............",
		"...kk..kk...",
		"..kssksssk..",
		"..kssssssk..",
		".kksskkssk..",
		"kssskskssskk",
		"kssskskssssk",
		".kksskkssk..",
		"..kssssssk..",
		"..kssksssk..",
		"...kk..kk...",
		"............",
	],
}
ICON_NAMES = list(ICONS.keys())
ICON_SIZE = 12
ICON_COLS = 8


def icons() -> None:
	rows = (len(ICON_NAMES) + ICON_COLS - 1) // ICON_COLS
	sheet = img(ICON_COLS * ICON_SIZE, rows * ICON_SIZE)
	for i, name in enumerate(ICON_NAMES):
		art = [r.replace(" ", ".") for r in ICONS[name]]
		im = from_rows([r.ljust(ICON_SIZE, ".")[:ICON_SIZE] for r in art[:ICON_SIZE]])
		sheet.paste(im, ((i % ICON_COLS) * ICON_SIZE, (i // ICON_COLS) * ICON_SIZE), im)
	save(sheet, "icons")


def small() -> None:
	save(from_rows(CURSOR), "cursor")
	save(from_rows(NEXT), "next")
	save(from_rows(ARROW_UP), "arrow_up")
	save(from_rows(ARROW_DOWN), "arrow_down")


def preview(path: str) -> None:
	"""Ghép mọi mảnh lên một tấm (kiểm tra bằng mắt)."""
	files = sorted(f for f in os.listdir(OUT) if f.endswith(".png"))
	ims = [Image.open(os.path.join(OUT, f)) for f in files]
	w = 900
	x = y = 8
	row_h = 0
	sheet = Image.new("RGBA", (w, 900), (88, 130, 70, 255))
	for im in ims:
		if x + im.width > w - 8:
			x = 8
			y += row_h + 8
			row_h = 0
		sheet.paste(im, (x, y), im)
		x += im.width + 8
		row_h = max(row_h, im.height)
	# khung lớn kéo giãn thử
	sheet.save(path)


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	panel_wood()
	panel_dark()
	panel_plate()
	panel_portrait()
	panel_tooltip()
	panel_paper()
	panel_sign()
	panel_book()
	panel_tab(True)
	panel_tab(False)
	for k in ("normal", "hover", "pressed"):
		panel_button(k)
	panel_toast()
	panel_slot()
	nodes()
	small()
	icons()
	print("9-slice (1×):", PANELS)
	print("icons:", len(ICON_NAMES), ICON_NAMES)
	if "--preview" in sys.argv:
		preview(sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
	main()
