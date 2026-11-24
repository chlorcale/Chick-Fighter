"""Dựng art cho các trang mini-game (game/art/minigames/<trang>/…) – vẽ hoàn toàn bằng code, phong cách pixel ấm
kiểu Stardew Valley: nền 384×216 (camera phóng ×3 = 1152×648), viền nâu sẫm mềm, đổ bóng, chi tiết nhỏ.

Chạy:  python tools/art/build_minigames.py            (dựng tất cả)
       python tools/art/build_minigames.py fish farm  (chỉ vài trang)
       python tools/art/build_minigames.py --preview DIR   (thêm ảnh ghép xem thử ×2 vào DIR)

Mỗi trang gồm bg.png (cảnh tĩnh) + các mảnh rời (người, cá, gạch…) mà script GDScript ghép và cho động.
Không đụng ảnh của bản đồ; nhân vật dùng lại sprite NPC có sẵn ở game/art/npc khi hợp.
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "art" / "minigames"
W, H = 384, 216

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 + 1.0 / 32.0


# ============================================================================ tiện ích vẽ

def hx(h: str, a: int = 255) -> tuple:
	h = h.lstrip("#")
	return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c0: tuple, c1: tuple, t: float) -> tuple:
	return tuple(int(round(c0[i] + (c1[i] - c0[i]) * t)) for i in range(4))


def new(w: int, h: int) -> Image.Image:
	return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(im, x0, y0, x1, y1, col):
	"""Hình chữ nhật [x0, x1) × [y0, y1)."""
	if x1 <= x0 or y1 <= y0:
		return
	ImageDraw.Draw(im).rectangle([int(x0), int(y0), int(x1) - 1, int(y1) - 1], fill=col)


def poly(im, pts, col):
	ImageDraw.Draw(im).polygon([(int(round(x)), int(round(y))) for x, y in pts], fill=col)


def ell(im, x0, y0, x1, y1, col):
	ImageDraw.Draw(im).ellipse([int(x0), int(y0), int(x1) - 1, int(y1) - 1], fill=col)


def line(im, pts, col, w=1):
	ImageDraw.Draw(im).line([(int(round(x)), int(round(y))) for x, y in pts], fill=col, width=w)


def px(im, x, y, col):
	if 0 <= x < im.width and 0 <= y < im.height:
		im.putpixel((int(x), int(y)), col)


def paste(dst, src, x, y):
	dst.alpha_composite(src, (int(x), int(y)))


def outline(im, col=hx("2a1a12"), diag=False):
	"""Viền 1 px quanh phần đục của ảnh (ra ngoài)."""
	a = np.array(im)
	alpha = a[:, :, 3] > 0
	pad = np.pad(alpha, 1)
	grow = np.zeros_like(alpha)
	shifts = [(0, 1), (0, -1), (1, 0), (-1, 0)]
	if diag:
		shifts += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
	h, w = alpha.shape
	for dy, dx in shifts:
		grow |= pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
	edge = grow & ~alpha
	out = a.copy()
	out[edge] = col
	return Image.fromarray(out, "RGBA")


def inner_shade(im, col, side="bottom", width=1):
	"""Tô viền trong (cạnh dưới/phải tối, trên/trái sáng) cho khối đục."""
	a = np.array(im)
	alpha = a[:, :, 3] > 0
	dy, dx = {"bottom": (-1, 0), "top": (1, 0), "right": (0, -1), "left": (0, 1)}[side]
	mask = np.zeros_like(alpha)
	cur = alpha.copy()
	for _ in range(width):
		shifted = np.roll(np.roll(cur, dy, 0), dx, 1)
		edge = alpha & ~shifted
		mask |= edge
		cur = cur & shifted
	out = a.copy()
	out[mask] = col
	return Image.fromarray(out, "RGBA")


def vgrad(im, x0, y0, x1, y1, cols, sharp=6.0):
	"""Dải màu dọc theo nhiều bậc, chuyển bậc bằng dither Bayer (gọn như tranh pixel)."""
	n = len(cols) - 1
	h = max(1, y1 - y0 - 1)
	a = np.array(im)
	for y in range(y0, y1):
		t = (y - y0) / h * n
		i = min(int(t), n - 1)
		f = t - i
		f = min(1.0, max(0.0, (f - 0.5) * sharp + 0.5))
		for x in range(x0, x1):
			c = cols[i + 1] if f > BAYER[y % 4, x % 4] else cols[i]
			a[y, x] = c
	im.paste(Image.fromarray(a, "RGBA"))


def speckle(im, x0, y0, x1, y1, cols, n, seed, size=1, mask=None):
	rng = random.Random(seed)
	for _ in range(n):
		x = rng.randrange(x0, x1)
		y = rng.randrange(y0, y1)
		if mask is not None and mask.getpixel((x, y))[3] == 0:
			continue
		c = rng.choice(cols)
		rect(im, x, y, x + size, y + size, c)


def blob(im, cx, cy, r, cols, seed, count=7, spread=1.0):
	"""Bụi lá/đám mây: nhiều vòng tròn, lớp sáng lệch lên trên-trái."""
	rng = random.Random(seed)
	circles = []
	for _ in range(count):
		ox = rng.uniform(-r, r) * spread
		oy = rng.uniform(-r * 0.5, r * 0.4) * spread
		rr = rng.uniform(r * 0.45, r * 0.8)
		circles.append((cx + ox, cy + oy, rr))
	for k, col in enumerate(cols):
		sh = k * 1.6
		for (x, y, rr) in circles:
			rr2 = rr - k * 1.4
			if rr2 <= 0.8:
				continue
			ell(im, x - rr2 - sh * 0.5, y - rr2 - sh, x + rr2 - sh * 0.5 + 1, y + rr2 - sh + 1, col)


def cloud(im, cx, cy, w, seed, light=hx("fffaf0"), mid=hx("f3e6d6"), shade=hx("d9c6c4")):
	rng = random.Random(seed)
	parts = []
	n = max(3, int(w / 9))
	for i in range(n):
		t = i / (n - 1) - 0.5
		rr = (1.0 - abs(t) * 1.2) * w * 0.22 + rng.uniform(1, 3)
		parts.append((cx + t * w, cy - rr * 0.35 + rng.uniform(-1, 1), rr))
	for col, dy in [(shade, 0), (mid, -2), (light, -4)]:
		for x, y, r in parts:
			rr = r - (0 if col == shade else (1 if col == mid else 2.4))
			if rr <= 0:
				continue
			ell(im, x - rr, y - rr * 0.8 + dy, x + rr + 1, y + rr * 0.8 + dy + 1, col)


def save(im, page, name):
	d = OUT / page
	d.mkdir(parents=True, exist_ok=True)
	im.save(d / f"{name}.png")


def frames(images):
	"""Ghép các khung ngang thành một sheet."""
	w = sum(i.width for i in images)
	h = max(i.height for i in images)
	sheet = new(w, h)
	x = 0
	for i in images:
		paste(sheet, i, x, h - i.height)
		x += i.width
	return sheet


def npc(name):
	return Image.open(ROOT / "game" / "art" / "npc" / f"{name}.png").convert("RGBA")


def hero(frame):
	sheet = Image.open(ROOT / "game" / "art" / "player_sheet_v2.png").convert("RGBA")
	return sheet.crop((frame * 64, 0, frame * 64 + 64, 64))


OUTL = hx("2a1a12")
OUTL_SOFT = hx("3b2618")

# Bảng màu chung
SKY_DAY = [hx("8fd3e8"), hx("a9dfea"), hx("c6e9e6"), hx("e4f0dc"), hx("f8efcf")]
SKY_WARM = [hx("7cc4e4"), hx("9fd5e6"), hx("c9e6e0"), hx("f2e8c8"), hx("fbdca8")]
GRASS = [hx("2f5e2a"), hx("3f7a32"), hx("5a9a3a"), hx("78b547"), hx("9ccf5c")]
WOOD = [hx("4a2c18"), hx("6b4224"), hx("8a5a32"), hx("a8703d"), hx("c48d52")]
GOLD = [hx("8c5a1c"), hx("b07a28"), hx("d49c34"), hx("ecc24a"), hx("ffe27e")]
SKIN = [hx("8a4f32"), hx("c27c52"), hx("e2a477"), hx("f4c49a")]


# ============================================================================ phần tử dùng lại

def tree_line(im, y, color_far, color_near, seed, height=18, x0=0, x1=W):
	"""Rặng cây xa: hàng tán tròn + vài cây dừa."""
	rng = random.Random(seed)
	x = x0 - 10
	while x < x1 + 10:
		r = rng.uniform(6, 12)
		ell(im, x - r, y - height * rng.uniform(0.5, 1.0) - r, x + r, y + r, color_far)
		x += r * rng.uniform(0.9, 1.4)
	rect(im, x0, y - 3, x1, y + 6, color_far)
	x = x0 - 6
	while x < x1 + 6:
		r = rng.uniform(4, 8)
		ell(im, x - r, y - height * 0.35 - r, x + r, y + r * 0.6, color_near)
		x += r * rng.uniform(1.2, 2.4)
	rect(im, x0, y + 1, x1, y + 6, color_near)


def palm(im, x, y, h, lean, frond, frond_dark, trunk, trunk_dark, seed, scale=1.0):
	"""Cây dừa: thân cong có khấc, tán lá xoè."""
	rng = random.Random(seed)
	pts = []
	for i in range(int(h) + 1):
		t = i / h
		pts.append((x + lean * t * t * h * 0.35, y - i))
	for i, (tx, ty) in enumerate(pts):
		wdt = max(2, int(3 * scale - i / h * 1.2 * scale))
		col = trunk_dark if i % 4 == 0 else trunk
		rect(im, tx - wdt // 2, ty, tx - wdt // 2 + wdt, ty + 1, col)
		px(im, tx - wdt // 2, ty, trunk_dark)
	top = pts[-1]
	# trái dừa
	for k in range(3):
		ell(im, top[0] - 3 + k * 2, top[1] + 1, top[0] + k * 2, top[1] + 4, hx("6e7a2a"))
	for k in range(9):
		ang = math.pi * (-0.05 - k * 0.11) - math.pi * 0.0
		ang = -math.pi / 2 + (k - 4) * 0.42 + rng.uniform(-0.08, 0.08)
		length = (14 + rng.uniform(0, 5)) * scale
		droop = 0.9 if abs(k - 4) > 1 else 0.35
		prev = top
		for s in range(1, int(length) + 1):
			t = s / length
			fx = top[0] + math.cos(ang) * s * 1.05
			fy = top[1] + math.sin(ang) * s * 0.7 + droop * t * t * length * 0.9
			col = frond if s % 3 else frond_dark
			line(im, [prev, (fx, fy)], col)
			if s % 2 == 0 and s > 2:
				leaf = 2 + int(2 * (1 - t))
				px(im, fx, fy + leaf * 0.6, frond_dark)
				px(im, fx, fy + leaf, frond_dark)
				px(im, fx + 1, fy + 1, frond)
			prev = (fx, fy)


def bamboo_clump(im, x, y, h, seed, cols=(hx("2f5e2a"), hx("4b8a3a"), hx("78b547"))):
	rng = random.Random(seed)
	for k in range(7):
		sx = x + rng.randint(-8, 8)
		sh = h * rng.uniform(0.7, 1.0)
		lean = rng.uniform(-0.25, 0.25)
		for i in range(int(sh)):
			cx = sx + lean * i
			col = cols[0] if i % 7 == 0 else cols[1]
			px(im, cx, y - i, col)
			px(im, cx + 1, y - i, cols[2] if i % 7 else cols[0])
		blob(im, sx + lean * sh, y - sh, 6, [cols[0], cols[1], cols[2]], seed + k, count=4)


def nonla(im, cx, top, w=12, col=hx("f1d98a"), dark=hx("b8924a")):
	"""Nón lá nhìn ngang."""
	poly(im, [(cx - w / 2, top + w * 0.42), (cx, top), (cx + w / 2, top + w * 0.42)], col)
	line(im, [(cx - w / 2, top + w * 0.42), (cx + w / 2, top + w * 0.42)], dark)
	line(im, [(cx - 1, top + 2), (cx - w / 4, top + w * 0.4)], dark)


def person(shirt, pants, hat=None, skin=SKIN[2], pose="stand", hair=hx("2b1d16"), w=16, h=34, face="front"):
	"""Người nhỏ (cùng cỡ NPC có sẵn ~ 18×40): đứng/ giơ tay/ cúi gặt/ ngồi."""
	im = new(w + 8, h + 10)
	cx = (w + 8) // 2
	base = h + 8
	dark_shirt = mix(shirt, (0, 0, 0, 255), 0.28)
	dark_pants = mix(pants, (0, 0, 0, 255), 0.3)
	dark_skin = SKIN[1]
	if pose == "bend":
		# cúi gặt: lưng ngang, đầu thấp bên phải
		rect(im, cx - 6, base - 12, cx - 3, base, pants)
		rect(im, cx - 1, base - 12, cx + 2, base, dark_pants)
		poly(im, [(cx - 8, base - 22), (cx + 6, base - 20), (cx + 6, base - 12), (cx - 7, base - 11)], shirt)
		rect(im, cx - 7, base - 13, cx + 6, base - 11, dark_shirt)
		ell(im, cx + 4, base - 22, cx + 12, base - 14, skin)
		rect(im, cx + 4, base - 14, cx + 9, base - 6, skin)  # tay
		rect(im, cx + 5, base - 7, cx + 10, base - 5, dark_skin)
		if hat:
			nonla(im, cx + 8, base - 30, 14)
		else:
			rect(im, cx + 4, base - 23, cx + 12, base - 19, hair)
		return outline(im, OUTL_SOFT)
	if pose == "sit":
		rect(im, cx - 5, base - 8, cx + 6, base - 4, pants)
		rect(im, cx + 3, base - 8, cx + 6, base, dark_pants)
		rect(im, cx - 6, base - 22, cx + 4, base - 8, shirt)
		rect(im, cx - 6, base - 10, cx + 4, base - 8, dark_shirt)
		ell(im, cx - 5, base - 32, cx + 4, base - 22, skin)
		if hat:
			nonla(im, cx - 1, base - 37, 14)
		else:
			rect(im, cx - 5, base - 33, cx + 4, base - 28, hair)
		return outline(im, OUTL_SOFT)
	# đứng
	leg = 11
	rect(im, cx - 5, base - leg, cx - 1, base, pants)
	rect(im, cx + 1, base - leg, cx + 5, base, dark_pants)
	rect(im, cx - 6, base, cx - 1, base + 1, hx("3a2a20"))
	rect(im, cx + 1, base, cx + 6, base + 1, hx("3a2a20"))
	body_top = base - leg - 13
	rect(im, cx - 6, body_top, cx + 6, base - leg + 1, shirt)
	rect(im, cx - 6, base - leg - 1, cx + 6, base - leg + 1, dark_shirt)
	rect(im, cx + 3, body_top + 1, cx + 6, base - leg, dark_shirt)
	if pose == "arms_up":
		rect(im, cx - 9, body_top - 9, cx - 6, body_top + 4, shirt)
		rect(im, cx + 6, body_top - 9, cx + 9, body_top + 4, dark_shirt)
		rect(im, cx - 9, body_top - 12, cx - 6, body_top - 9, skin)
		rect(im, cx + 6, body_top - 12, cx + 9, body_top - 9, skin)
	elif pose == "throw":
		rect(im, cx - 9, body_top + 1, cx - 6, body_top + 10, shirt)
		rect(im, cx + 6, body_top - 8, cx + 9, body_top + 3, dark_shirt)
		rect(im, cx + 6, body_top - 11, cx + 9, body_top - 8, skin)
		rect(im, cx - 9, body_top + 10, cx - 6, body_top + 12, skin)
	else:
		rect(im, cx - 9, body_top + 1, cx - 6, body_top + 11, shirt)
		rect(im, cx + 6, body_top + 1, cx + 9, body_top + 11, dark_shirt)
		rect(im, cx - 9, body_top + 11, cx - 6, body_top + 13, skin)
		rect(im, cx + 6, body_top + 11, cx + 9, body_top + 13, skin)
	head_top = body_top - 11
	rect(im, cx - 5, head_top, cx + 5, body_top, skin)
	rect(im, cx + 3, head_top + 1, cx + 5, body_top, dark_skin)
	if face == "front":
		rect(im, cx - 5, head_top, cx + 5, head_top + 3, hair)
		rect(im, cx - 5, head_top + 3, cx - 4, head_top + 6, hair)
		px(im, cx - 2, head_top + 5, hx("2a1a12"))
		px(im, cx + 2, head_top + 5, hx("2a1a12"))
		px(im, cx - 3, head_top + 7, hx("e8907a"))
		px(im, cx + 3, head_top + 7, hx("e8907a"))
		rect(im, cx - 1, head_top + 8, cx + 1, head_top + 9, hx("9a4a3a"))
	else:  # quay lưng
		rect(im, cx - 5, head_top, cx + 5, head_top + 7, hair)
	if hat == "nonla":
		nonla(im, cx, head_top - 6, 16)
	elif hat == "helmet":
		ell(im, cx - 6, head_top - 3, cx + 6, head_top + 5, hx("f2c12e"))
		rect(im, cx - 7, head_top + 2, cx + 7, head_top + 4, hx("d89a1c"))
		px(im, cx - 2, head_top - 1, hx("fff0a0"))
	elif hat == "khan":
		rect(im, cx - 6, head_top - 2, cx + 6, head_top + 3, hx("1e2a4a"))
		for k in range(0, 12, 2):
			px(im, cx - 6 + k, head_top - 1, hx("3a4a7a"))
		rect(im, cx - 5, head_top + 3, cx + 5, head_top + 5, hx("d8d8d0"))  # tóc bạc
	elif hat == "cap":
		rect(im, cx - 5, head_top - 1, cx + 5, head_top + 3, hx("c8402e"))
		rect(im, cx + 2, head_top + 2, cx + 8, head_top + 4, hx("a02e22"))
	return outline(im, OUTL_SOFT)


# ============================================================================ khung giao diện

def build_ui():
	"""Khung 9 mảnh (đã phóng ×3 cho lớp giao diện 1152×648): giấy da + viền gỗ, bong bóng thoại."""
	s = 3
	base = new(16, 16)
	rect(base, 0, 0, 16, 16, hx("5a2f17"))
	rect(base, 1, 1, 15, 15, hx("b66a2c"))
	rect(base, 2, 2, 14, 14, hx("dc9a46"))
	rect(base, 3, 3, 13, 13, hx("7a3e1a"))
	rect(base, 4, 4, 12, 12, hx("f7dfa6"))
	rect(base, 4, 4, 12, 5, hx("fff0c6"))
	for p in [(0, 0), (15, 0), (0, 15), (15, 15)]:
		px(base, p[0], p[1], (0, 0, 0, 0))
	px(base, 2, 2, hx("f0c070"))
	px(base, 13, 2, hx("f0c070"))
	save(base.resize((16 * s, 16 * s), Image.NEAREST), "ui", "panel")
	dark = new(16, 16)
	rect(dark, 0, 0, 16, 16, hx("2a160c"))
	rect(dark, 1, 1, 15, 15, hx("8a4f22"))
	rect(dark, 2, 2, 14, 14, hx("c98a3e"))
	rect(dark, 3, 3, 13, 13, hx("4a2612"))
	rect(dark, 4, 4, 12, 12, hx("3b2216", 235))
	for p in [(0, 0), (15, 0), (0, 15), (15, 15)]:
		px(dark, p[0], p[1], (0, 0, 0, 0))
	save(dark.resize((16 * s, 16 * s), Image.NEAREST), "ui", "panel_dark")
	bub = new(12, 12)
	rect(bub, 1, 0, 11, 12, hx("3b2618"))
	rect(bub, 0, 1, 12, 11, hx("3b2618"))
	rect(bub, 1, 1, 11, 11, hx("fffbef"))
	rect(bub, 1, 9, 11, 11, hx("eadfc8"))
	save(bub.resize((12 * s, 12 * s), Image.NEAREST), "ui", "bubble")
	# ô phím
	key = new(11, 11)
	rect(key, 1, 0, 10, 11, hx("3b2618"))
	rect(key, 0, 1, 11, 10, hx("3b2618"))
	rect(key, 1, 1, 10, 9, hx("fff3d6"))
	rect(key, 1, 8, 10, 10, hx("c9a77a"))
	save(key.resize((11 * s, 11 * s), Image.NEAREST), "ui", "key")


# ============================================================================ TRANG 1: chòi cá tra (cắt ngang ao)

WATER_Y = 104


def build_fish():
	page = "fish"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 78, SKY_WARM)
	for i, (x, y, w) in enumerate([(60, 18, 48), (170, 28, 34), (300, 14, 60), (240, 40, 22)]):
		cloud(bg, x, y, w, 10 + i)
	# rặng cây xa bờ bên kia
	tree_line(bg, 80, hx("7aa58a"), hx("5d8f6a"), 3, height=16)
	for i, x in enumerate([30, 92, 138, 226, 352]):
		palm(bg, x, 84, 30 + (i % 3) * 6, (-1) ** i * 0.6, hx("4f8656"), hx("3f6e48"), hx("7d8a6a"), hx("5e6a52"), 40 + i, 0.8)
	bamboo_clump(bg, 180, 86, 24, 7, (hx("4a7a52"), hx("5e8f62"), hx("7aa978")))
	# bờ đất xa chạm nước
	rect(bg, 0, 86, W, WATER_Y, hx("6f9a58"))
	speckle(bg, 0, 86, W, WATER_Y - 4, [hx("88b464"), hx("5d8a4a")], 300, 5)
	rect(bg, 0, WATER_Y - 5, W, WATER_Y, hx("8a6a44"))
	rect(bg, 0, WATER_Y - 2, W, WATER_Y, hx("6a5034"))
	# nước cắt ngang
	vgrad(bg, 0, WATER_Y, W, H, [hx("5fa8b8"), hx("4a93a6"), hx("3b7e93"), hx("2e687c"), hx("24546a"), hx("1d4459")], sharp=2.5)
	# vệt nắng xiên dưới nước
	rays = new(W, H)
	for i, x in enumerate([40, 120, 200, 260, 330]):
		poly(rays, [(x, WATER_Y), (x + 14, WATER_Y), (x - 30, H), (x - 56, H)], (220, 245, 240, 20 + (i % 2) * 8))
	bg.alpha_composite(rays)
	# đáy bùn + rong + đá
	rng = random.Random(9)
	pts = [(0, H)]
	for x in range(0, W + 8, 8):
		pts.append((x, 200 + math.sin(x * 0.05) * 3 + rng.uniform(-1, 1)))
	pts.append((W, H))
	poly(bg, pts, hx("3d3a2a"))
	pts2 = [(x, y + 4) for (x, y) in pts[1:-1]]
	poly(bg, [(0, H)] + pts2 + [(W, H)], hx("2e2c22"))
	speckle(bg, 0, 200, W, H, [hx("5a5238"), hx("26241c")], 200, 6)
	for i in range(26):
		x = rng.randrange(0, W)
		h = rng.randint(8, 22)
		base = 203 + rng.randint(-2, 3)
		for k in range(h):
			sway = math.sin(k * 0.45 + i) * 1.5
			px(bg, x + sway, base - k, hx("3f7a4a") if k % 3 else hx("2d5a38"))
	for i in range(8):
		x = rng.randrange(0, W)
		ell(bg, x, 202, x + rng.randint(5, 9), 208, hx("5c574a"))
		px(bg, x + 2, 203, hx("7a7464"))
	# bờ gần bên trái (đất + cỏ) và cây chuối
	bank = new(W, H)
	poly(bank, [(0, 92), (44, 92), (60, 100), (78, 128), (70, 170), (40, 216), (0, 216)], hx("7a5a38"))
	poly(bank, [(0, 92), (44, 92), (56, 98), (0, 98)], GRASS[3])
	rect(bank, 0, 90, 44, 93, GRASS[4])
	speckle(bank, 0, 99, 70, 210, [hx("8e6c46"), hx("634628"), hx("9a7a52")], 260, 11, mask=bank)
	# lớp đất xen kẽ + rễ cây + đá trong vách bờ
	rng2 = random.Random(31)
	for y in range(104, 216, 9):
		line(bank, [(0, y), (60 - (y - 104) * 0.2, y + 2)], hx("6a4c2e"))
	for i in range(7):
		x0 = rng2.randint(4, 50)
		y0 = rng2.randint(100, 180)
		pts = [(x0, y0)]
		for k in range(5):
			pts.append((pts[-1][0] + rng2.randint(-3, 4), pts[-1][1] + rng2.randint(3, 6)))
		line(bank, pts, hx("4a3220"))
	for i in range(9):
		x0 = rng2.randint(2, 58)
		y0 = rng2.randint(110, 200)
		ell(bank, x0, y0, x0 + rng2.randint(5, 9), y0 + rng2.randint(4, 6), hx("8a8478"))
		px(bank, x0 + 2, y0 + 1, hx("b0aa9c"))
	bank = outline(bank, OUTL_SOFT)
	bg.alpha_composite(bank)
	# cỏ rủ xuống mép bờ
	for x in range(0, 62, 2):
		h = rng2.randint(2, 7)
		line(bg, [(x, 97), (x + 1, 97 + h)], GRASS[2] if x % 4 else GRASS[1])
	blob(bg, 14, 82, 12, [GRASS[0], GRASS[1], GRASS[2], GRASS[3]], 21, count=6)
	for i in range(10):
		x0 = rng2.randint(0, 46)
		line(bg, [(x0, 91), (x0 + rng2.randint(-2, 2), 86)], GRASS[4])
	# chòi trên cọc (phải)
	hut = new(W, H)
	deck_y = 80
	for x in [236, 262, 292, 322, 352, 378]:
		rect(hut, x, deck_y, x + 4, H - 8, WOOD[1])
		rect(hut, x, deck_y, x + 1, H - 8, WOOD[0])
	# cầu ván dẫn tới cần vó
	for x in [150, 182, 210]:
		rect(hut, x, deck_y, x + 3, H - 10, WOOD[1])
	rect(hut, 142, deck_y - 4, 384, deck_y + 2, WOOD[3])
	for x in range(142, 384, 7):
		rect(hut, x, deck_y - 4, x + 1, deck_y + 2, WOOD[1])
	rect(hut, 142, deck_y - 4, 384, deck_y - 3, WOOD[4])
	rect(hut, 142, deck_y + 1, 384, deck_y + 3, WOOD[0])
	# lan can
	for x in range(146, 236, 12):
		rect(hut, x, deck_y - 14, x + 2, deck_y - 4, WOOD[2])
	rect(hut, 144, deck_y - 15, 236, deck_y - 13, WOOD[3])
	# vách chòi
	rect(hut, 244, 30, 384, deck_y - 4, WOOD[2])
	for x in range(244, 384, 6):
		rect(hut, x, 30, x + 1, deck_y - 4, WOOD[1])
		px(hut, x + 3, 40 + (x * 7) % 25, WOOD[1])
	rect(hut, 244, 30, 384, 33, WOOD[0])
	# cửa sổ + cửa
	rect(hut, 262, 42, 290, 62, hx("3a2216"))
	rect(hut, 264, 44, 288, 60, hx("2a1810"))
	rect(hut, 262, 52, 290, 53, WOOD[3])
	rect(hut, 275, 42, 277, 62, WOOD[3])
	rect(hut, 318, 40, 340, deck_y - 4, hx("3a2216"))
	rect(hut, 320, 42, 338, deck_y - 4, hx("553420"))
	px(hut, 334, 58, hx("e0b050"))
	hut = outline(hut, OUTL)
	bg.alpha_composite(hut)
	# mái lá dừa nước
	roof = new(W, H)
	poly(roof, [(230, 34), (264, 4), (384, 4), (384, 34)], hx("b89254"))
	for i in range(0, 160, 3):
		x = 230 + i
		line(roof, [(x, 34), (x + 30, 4)], hx("9c7a42") if i % 2 else hx("cfa866"))
	for y in range(8, 34, 6):
		line(roof, [(232 + (34 - y) * 0.94, y), (384, y)], hx("8a6a38"))
	rect(roof, 228, 33, 384, 37, hx("7c5a30"))
	roof = outline(roof, OUTL)
	bg.alpha_composite(roof)
	# giỏ, xô đỏ, lưới phơi
	ell(bg, 350, 64, 362, 76, hx("c8402e"))
	rect(bg, 350, 64, 362, 67, hx("e05a40"))
	line(bg, [(300, 34), (300, 60)], hx("6a4a2a"))
	ell(bg, 294, 58, 307, 68, hx("c49a5a"))
	# trụ cần vó (cột tre + giá)
	post = new(W, H)
	rect(post, 196, 22, 200, deck_y - 4, hx("b7a05a"))
	rect(post, 196, 22, 197, deck_y - 4, hx("8a7a3a"))
	for y in range(26, deck_y - 4, 9):
		rect(post, 196, y, 200, y + 1, hx("7a6a32"))
	line(post, [(186, deck_y - 4), (198, 34)], hx("a89048"))
	line(post, [(210, deck_y - 4), (198, 34)], hx("a89048"))
	post = outline(post, OUTL)
	bg.alpha_composite(post)
	# lục bình trôi ở mặt nước
	for (x, s) in [(30, 1), (104, 2), (222, 3)]:
		blob(bg, x, WATER_Y - 1, 5, [hx("2f6a3a"), hx("4e9a4a"), hx("7cc464")], s, count=4)
		px(bg, x, WATER_Y - 6, hx("b88ae0"))
		px(bg, x + 1, WATER_Y - 6, hx("d0a8f0"))
	save(bg, page, "bg")

	# mặt nước (dải lăn tăn trên mặt, lặp ngang) – 2 khung
	for f in range(2):
		s = new(W, 6)
		for x in range(0, W):
			y = 1 + int(round(math.sin(x * 0.18 + f * math.pi) * 1.0))
			px(s, x, y, hx("bfe8ef"))
			if (x + f * 7) % 13 < 5:
				px(s, x, y + 2, hx("8fd0dc"))
		save(s, page, f"surface_{f}")
	# cá tra nhìn ngang (đầu quay trái) – 2 khung
	fish_frames = []
	for f in range(2):
		im = new(28, 11)
		body = [(2, 5), (6, 2), (16, 2), (22, 4), (24, 5), (22, 6), (16, 8), (6, 8)]
		poly(im, body, hx("8fa3ad"))
		poly(im, [(2, 5), (6, 3), (16, 3), (22, 5), (16, 5), (6, 5)], hx("5f7480"))
		poly(im, [(6, 6), (16, 7), (20, 6), (16, 8), (6, 8)], hx("e4eef0"))
		tail = [(23, 5), (27, 1 + f), (26, 5), (27, 9 - f)]
		poly(im, tail, hx("6a7f8a"))
		poly(im, [(10, 2), (13, 0), (15, 2)], hx("5f7480"))
		px(im, 4, 4, hx("1a1a1a"))
		px(im, 5, 4, hx("ffffff"))
		line(im, [(2, 6), (0, 8)], hx("4a5860"))
		line(im, [(3, 6), (1, 9)], hx("4a5860"))
		fish_frames.append(outline(im, hx("26343c")))
	save(frames(fish_frames), page, "catfish")
	# cám
	pel = new(3, 3)
	rect(pel, 0, 0, 3, 3, hx("c89a50"))
	px(pel, 0, 0, hx("f0c878"))
	save(pel, page, "pellet")
	# cọc nối vó: cây cần tre (vẽ bằng code); giỏ cá
	basket = new(20, 14)
	poly(basket, [(1, 2), (19, 2), (16, 13), (4, 13)], hx("b8904a"))
	for y in range(3, 13, 2):
		line(basket, [(2 + (y - 2) * 0.25, y), (18 - (y - 2) * 0.25, y)], hx("8a6a30"))
	rect(basket, 0, 1, 20, 3, hx("d8b064"))
	save(outline(basket), page, "basket")


# ============================================================================ TRANG 2: ruộng lúa chín

FIELD_TOP = 64
ROW_BASE = 176   # chân hàng lúa người chơi gặt


def rice_texture(im, y0, y1, seed, x0=0, x1=W):
	"""Mảng lúa chín theo phối cảnh: càng gần càng to, bông trĩu, xen dải sáng/tối như gió lướt."""
	rng = random.Random(seed)
	# hàng lúa theo phối cảnh: khoảng cách hàng tăng dần về phía trước
	rows = []
	y = float(FIELD_TOP + 2)
	k = 0
	while y < y1:
		d = (y - FIELD_TOP) / (H - FIELD_TOP)
		step = 3 + d * 16
		rows.append((int(y), int(y + step), k))
		y += step
		k += 1
	for (ra, rb, k) in rows:
		for yy in range(max(ra, y0), min(rb, y1)):
			t = (yy - ra) / max(1, rb - ra)
			base = mix(GOLD[3], GOLD[2], t * 0.8) if k % 2 == 0 else mix(GOLD[3], GOLD[2], 0.25 + t * 0.6)
			rect(im, x0, yy, x1, yy + 1, base)
		if y0 <= rb - 1 < y1:
			rect(im, x0, rb - 1, x1, rb, GOLD[1])
	# gió lướt: vệt sáng dài
	for i in range(10):
		yy = rng.randrange(y0, y1)
		xx = rng.randrange(x0, x1)
		ww = 20 + int((yy - FIELD_TOP) * 0.5)
		rect(im, xx, yy, xx + ww, yy + 1, GOLD[4])
	for y in range(y0, y1, 1):
		d = (y - FIELD_TOP) / (H - FIELD_TOP)
		step = 1 + int(d * 4)
		hgt = 1 + int(d * 6)
		for x in range(x0 + rng.randint(0, step), x1, step + rng.randint(0, 1)):
			if rng.random() < 0.55:
				continue
			col = GOLD[4] if rng.random() < 0.35 else (GOLD[1] if rng.random() < 0.4 else GOLD[3])
			line(im, [(x, y), (x + (1 if d > 0.4 else 0), y - hgt)], col)
			if d > 0.35 and rng.random() < 0.4:
				px(im, x + 1, y - hgt, GOLD[4])


def build_farm():
	page = "farm"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, FIELD_TOP, SKY_DAY)
	for i, (x, y, w) in enumerate([(70, 14, 52), (210, 22, 30), (320, 10, 44)]):
		cloud(bg, x, y, w, 30 + i)
	tree_line(bg, FIELD_TOP - 2, hx("86ad8c"), hx("6a9a70"), 12, height=14)
	# nhà mái tôn xa
	rect(bg, 268, 44, 300, 58, hx("d9cfb8"))
	poly(bg, [(264, 46), (284, 34), (304, 46)], hx("8a9aa8"))
	rect(bg, 280, 50, 286, 58, hx("5a4030"))
	for i, x in enumerate([24, 60, 150, 236, 330, 366]):
		palm(bg, x, FIELD_TOP + 2, 26 + (i % 3) * 7, 0.5 * (-1) ** i, hx("4f8656"), hx("3f6e48"), hx("7d8a6a"), hx("5e6a52"), 60 + i, 0.8)
	rect(bg, 0, FIELD_TOP - 1, W, FIELD_TOP + 2, hx("7a9a50"))
	rice_texture(bg, FIELD_TOP + 2, H, 5)
	# bờ ruộng xéo giữa đồng (trâu đứng trên bờ)
	dike = new(W, H)
	poly(dike, [(0, 108), (W, 92), (W, 99), (0, 116)], hx("9a7a4a"))
	poly(dike, [(0, 108), (W, 92), (W, 94), (0, 110)], hx("b8945c"))
	speckle(dike, 0, 90, W, 118, [hx("6fa04a"), hx("8aba5a")], 260, 3, mask=dike)
	bg.alpha_composite(dike)
	# dải trước mặt: nước ruộng + gốc rạ (chỗ đã gặt) dưới hàng lúa của người chơi
	front = new(W, H)
	rect(front, 0, ROW_BASE - 4, W, H, hx("a98a4a"))
	vgrad(front, 0, ROW_BASE - 4, W, H, [hx("b3924e"), hx("9c7c40"), hx("8a6c38")])
	rng = random.Random(4)
	for i in range(14):
		x = rng.randrange(0, W)
		y = rng.randrange(ROW_BASE + 8, H - 4)
		w = rng.randint(16, 40)
		ell(front, x, y, x + w, y + 5, hx("8fb6b0"))
		line(front, [(x + 3, y + 1), (x + w * 0.6, y + 1)], hx("cfe6e0"))
	for i in range(240):
		x = rng.randrange(0, W)
		y = rng.randrange(ROW_BASE + 2, H)
		line(front, [(x, y), (x, y - 2)], hx("7a5a28"))
		px(front, x + 1, y - 2, hx("d8b460"))
	rect(front, 0, ROW_BASE - 5, W, ROW_BASE - 3, hx("6f5428"))
	bg.alpha_composite(front)
	# hàng lúa phía sau hàng gặt (đậm, tạo chiều sâu)
	back = new(W, H)
	for x in range(0, W, 2):
		h = 10 + int(math.sin(x * 0.3) * 2)
		line(back, [(x, ROW_BASE - 5), (x + 1, ROW_BASE - 5 - h)], GOLD[1] if x % 4 else GOLD[2])
		px(back, x + 1, ROW_BASE - 5 - h, GOLD[4])
	bg.alpha_composite(back)
	save(bg, page, "bg")

	# bụi lúa đứng (2 khung lắc) – gốc ở giữa đáy
	tufts = []
	for f in range(2):
		im = new(22, 34)
		sway = f
		for k in range(-5, 6):
			bx = 11 + k * 0.9
			h = 26 - abs(k) * 1.6
			tip = (bx + k * 0.9 + sway, 33 - h)
			line(im, [(bx, 33), tip], hx("8a7a24") if k % 2 else hx("a89030"))
			if k % 2 == 0:
				gx, gy = tip[0] + (2 if k >= 0 else -2), tip[1]
				rect(im, gx - 1, gy, gx + 2, gy + 6, GOLD[3])
				px(im, gx, gy, GOLD[4])
				px(im, gx + 1, gy + 5, GOLD[1])
		tufts.append(outline(im, hx("5a3a12")))
	save(frames(tufts), page, "tuft")
	stub = new(16, 6)
	for k in range(0, 14, 2):
		line(stub, [(1 + k, 5), (1 + k, 2 + (k % 3))], hx("8a6a28"))
		px(stub, 1 + k, 2 + (k % 3), hx("d8b460"))
	save(stub, page, "stubble")
	bundle = new(22, 11)
	poly(bundle, [(1, 7), (15, 3), (21, 4), (21, 8), (15, 9), (2, 10)], hx("e0b44a"))
	poly(bundle, [(14, 3), (21, 4), (21, 8), (15, 9)], hx("ffd870"))
	rect(bundle, 9, 3, 11, 10, hx("8a5a24"))
	line(bundle, [(2, 8), (14, 5)], hx("b88a30"))
	save(outline(bundle, hx("4a2e10")), page, "bundle")
	# liềm
	sick = new(14, 14)
	rect(sick, 1, 8, 3, 14, WOOD[2])
	for t in range(0, 12):
		a = math.pi * (0.95 - t / 12 * 0.95)
		px(sick, 6 + math.cos(a) * 5, 8 - math.sin(a) * 6, hx("d8e0e6"))
		px(sick, 6 + math.cos(a) * 4, 8 - math.sin(a) * 5, hx("8a96a0"))
	save(outline(sick), page, "sickle")
	# nông dân cúi gặt (2 khung)
	fr = []
	for f in range(2):
		im = person(hx("3e6fa8") if f < 2 else hx("a84a3a"), hx("2d2d3a"), hat="nonla", pose="bend")
		if f == 1:
			im = im.transform(im.size, Image.AFFINE, (1, 0, 0, 0, 1, -1), Image.NEAREST)
		fr.append(im)
	save(frames(fr), page, "farmer_a")
	fr = []
	for f in range(2):
		im = person(hx("b8483a"), hx("3a2d2a"), hat="nonla", pose="bend")
		if f == 1:
			im = im.transform(im.size, Image.AFFINE, (1, 0, 0, 0, 1, -1), Image.NEAREST)
		fr.append(im)
	save(frames(fr), page, "farmer_b")
	# trâu (2 khung: vẫy đuôi)
	buf = []
	for f in range(2):
		im = new(44, 28)
		ell(im, 6, 6, 34, 22, hx("4f4a4c"))
		rect(im, 9, 17, 13, 27, hx("3f3a3c"))
		rect(im, 15, 18, 19, 27, hx("4f4a4c"))
		rect(im, 25, 18, 29, 27, hx("3f3a3c"))
		rect(im, 30, 17, 34, 27, hx("4f4a4c"))
		ell(im, 30, 5, 42, 16, hx("5a5456"))
		rect(im, 36, 11, 43, 17, hx("6a6062"))
		px(im, 40, 14, hx("2a2020"))
		line(im, [(31, 6), (27, 2), (29, 1)], hx("d8ccb8"))
		line(im, [(39, 5), (43, 1), (41, 0)], hx("d8ccb8"))
		px(im, 35, 9, hx("1a1a1a"))
		ell(im, 10, 8, 28, 13, hx("6a6466"))
		if f == 0:
			line(im, [(6, 10), (3, 18), (2, 22)], hx("3f3a3c"))
		else:
			line(im, [(6, 10), (2, 16), (0, 19)], hx("3f3a3c"))
		buf.append(outline(im, hx("1e1a1a")))
	save(frames(buf), page, "buffalo")
	# cò trắng đứng / bay
	eg = new(10, 16)
	ell(eg, 2, 5, 9, 11, hx("f6f6f0"))
	line(eg, [(7, 6), (8, 2)], hx("f6f6f0"))
	ell(eg, 6, 0, 10, 3, hx("ffffff"))
	px(eg, 9, 1, hx("f0b030"))
	line(eg, [(5, 11), (5, 15)], hx("2a2a2a"))
	line(eg, [(6, 11), (7, 15)], hx("2a2a2a"))
	save(outline(eg, hx("5a6a6a")), page, "egret")
	fl = []
	for f in range(2):
		im = new(18, 10)
		ell(im, 5, 4, 13, 7, hx("f6f6f0"))
		px(im, 14, 5, hx("f6f6f0"))
		px(im, 15, 5, hx("f0b030"))
		if f == 0:
			poly(im, [(6, 5), (9, 0), (11, 5)], hx("ffffff"))
		else:
			poly(im, [(6, 5), (9, 9), (11, 5)], hx("e6e6e0"))
		fl.append(outline(im, hx("5a6a6a")))
	save(frames(fl), page, "egret_fly")


# ============================================================================ TRANG 3: công trường

SITE_GROUND = 190
PLANK_Y = 92


def bricks_wall(im, x0, y0, x1, y1, seed):
	rng = random.Random(seed)
	rect(im, x0, y0, x1, y1, hx("d9c3a5"))
	for r, y in enumerate(range(y0, y1, 5)):
		off = 0 if r % 2 == 0 else 5
		for x in range(x0 - off, x1, 10):
			c = rng.choice([hx("b5523b"), hx("c0603f"), hx("a84a34"), hx("c86a48")])
			rect(im, max(x, x0), y, min(x + 9, x1), min(y + 4, y1), c)
			if x + 1 >= x0:
				px(im, x + 1, y, hx("d88a6a"))


def build_site():
	page = "site"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 120, SKY_WARM)
	for i, (x, y, w) in enumerate([(320, 18, 50), (40, 12, 30), (200, 8, 28)]):
		cloud(bg, x, y, w, 50 + i)
	# phố xa: mái tôn, mái ngói, cây
	tree_line(bg, 128, hx("88ae90"), hx("6f9a76"), 33, height=12)
	for (x, w, h, roof) in [(4, 40, 30, "8b4a3a"), (300, 50, 36, "6a8aa0"), (350, 40, 24, "9a5a3a")]:
		rect(bg, x, 130 - h, x + w, 132, hx("e6d8bc"))
		poly(bg, [(x - 3, 132 - h), (x + w / 2, 120 - h), (x + w + 3, 132 - h)], hx(roof))
		for wx in range(x + 5, x + w - 6, 12):
			rect(bg, wx, 136 - h, wx + 6, 142 - h, hx("6a8aa8"))
	# nền phía sau: cỏ + hàng rào + bụi chuối
	rect(bg, 0, 128, W, SITE_GROUND, GRASS[2])
	speckle(bg, 0, 130, W, SITE_GROUND, [GRASS[1], GRASS[3], GRASS[4]], 500, 61)
	for i, x in enumerate([10, 26, 360, 374]):
		blob(bg, x, 150, 11, [GRASS[0], GRASS[1], GRASS[2], GRASS[3]], 62 + i, count=6)
	for x in range(0, W, 14):
		rect(bg, x, 150, x + 2, SITE_GROUND, hx("8a7a6a"))
	for y in range(152, SITE_GROUND, 6):
		for x in range(0, W, 6):
			px(bg, x + (y // 6) % 2 * 3, y, hx("a8a49a"))
	rect(bg, 0, 150, W, 152, hx("9a9488"))
	# toà nhà đang xây: khung bê tông + tường gạch tầng trệt, tầng lầu còn trống từng ô
	b = new(W, H)
	rect(b, 40, PLANK_Y - 52, 350, PLANK_Y - 46, hx("9a9a94"))  # dầm trên (đổ dở)
	bricks_wall(b, 44, PLANK_Y + 4, 346, SITE_GROUND - 6, 3)
	rect(b, 150, PLANK_Y + 30, 182, SITE_GROUND - 6, hx("4a3a30"))  # ô cửa chưa lắp
	rect(b, 250, PLANK_Y + 22, 282, PLANK_Y + 46, hx("4a3a30"))
	for x in [40, 140, 240, 340]:
		rect(b, x, PLANK_Y - 52, x + 10, SITE_GROUND - 4, hx("b4b2aa"))
		rect(b, x + 7, PLANK_Y - 52, x + 10, SITE_GROUND - 4, hx("8e8c86"))
		for y in range(PLANK_Y - 56, PLANK_Y - 52):
			for k in range(3):
				px(b, x + 2 + k * 3, y - 2, hx("7a5a3a"))  # sắt chờ
	rect(b, 36, PLANK_Y - 2, 354, PLANK_Y + 4, hx("a8a69e"))  # sàn lầu
	rect(b, 36, PLANK_Y + 3, 354, PLANK_Y + 5, hx("7e7c76"))
	# vài hàng gạch có sẵn ở tầng lầu (nền cho gạch tung lên chất thêm)
	for bay in range(3):
		bx = 50 + bay * 100
		bricks_wall(b, bx, PLANK_Y - 8, bx + 90, PLANK_Y - 2, 70 + bay)
	b = outline(b, OUTL_SOFT)
	bg.alpha_composite(b)
	# giàn giáo tre phía trước
	sc = new(W, H)
	poles = [34, 90, 140, 190, 240, 290, 352]
	for x in poles:
		rect(sc, x, PLANK_Y - 60, x + 3, SITE_GROUND, hx("c8b064"))
		rect(sc, x, PLANK_Y - 60, x + 1, SITE_GROUND, hx("9a8440"))
		for y in range(PLANK_Y - 58, SITE_GROUND, 11):
			rect(sc, x, y, x + 3, y + 1, hx("8a7434"))
	for y in [PLANK_Y - 40, PLANK_Y + 40]:
		rect(sc, 30, y, 358, y + 2, hx("c8b064"))
	for i in range(len(poles) - 1):
		line(sc, [(poles[i] + 2, SITE_GROUND - 4), (poles[i + 1], PLANK_Y + 8)], hx("b8a054"))
	# ván đứng của thợ
	rect(sc, 30, PLANK_Y + 4, 358, PLANK_Y + 9, WOOD[3])
	for x in range(30, 358, 24):
		rect(sc, x, PLANK_Y + 4, x + 1, PLANK_Y + 9, WOOD[1])
	rect(sc, 30, PLANK_Y + 8, 358, PLANK_Y + 10, WOOD[0])
	for x in poles:
		rect(sc, x - 1, PLANK_Y + 3, x + 4, PLANK_Y + 6, hx("6a4a24"))  # dây buộc
	sc = outline(sc, OUTL_SOFT)
	bg.alpha_composite(sc)
	# sân đất
	g = new(W, H)
	vgrad(g, 0, SITE_GROUND - 4, W, H, [hx("c49a62"), hx("b48a52"), hx("a07a48")])
	speckle(g, 0, SITE_GROUND - 2, W, H, [hx("8e6a3e"), hx("d8b07a"), hx("7a5a34")], 500, 8)
	bg.alpha_composite(g)
	# đống cát + đá
	ell(bg, 186, SITE_GROUND - 18, 250, SITE_GROUND + 10, hx("e6c47a"))
	ell(bg, 196, SITE_GROUND - 16, 234, SITE_GROUND, hx("f2d68e"))
	speckle(bg, 188, SITE_GROUND - 14, 248, SITE_GROUND + 6, [hx("c8a05a")], 60, 2)
	ell(bg, 250, SITE_GROUND - 8, 280, SITE_GROUND + 8, hx("8e8a84"))
	speckle(bg, 252, SITE_GROUND - 6, 278, SITE_GROUND + 6, [hx("b0aca4"), hx("6a6660")], 70, 3)
	# bao xi măng
	for i in range(3):
		rect(bg, 300 + i * 2, SITE_GROUND - 8 - i * 5, 324 + i * 2, SITE_GROUND - 2 - i * 5, hx("d8d4c8"))
		rect(bg, 300 + i * 2, SITE_GROUND - 8 - i * 5, 324 + i * 2, SITE_GROUND - 7 - i * 5, hx("f0ece0"))
		rect(bg, 308 + i * 2, SITE_GROUND - 6 - i * 5, 316 + i * 2, SITE_GROUND - 4 - i * 5, hx("3a6aa8"))
	save(bg, page, "bg")

	# máy trộn hồ (2 khung quay)
	mx = []
	for f in range(2):
		im = new(46, 40)
		rect(im, 6, 30, 40, 33, hx("5a5a5a"))
		ell(im, 4, 31, 12, 39, hx("2a2a2a"))
		ell(im, 32, 31, 40, 39, hx("2a2a2a"))
		poly(im, [(10, 10), (30, 4), (40, 14), (36, 28), (14, 28)], hx("e0702e"))
		poly(im, [(10, 10), (30, 4), (34, 8), (14, 14)], hx("f49a52"))
		ell(im, 6, 6, 16, 16, hx("4a3a30"))
		for k in range(3):
			yy = 12 + k * 5 + (f * 2)
			line(im, [(16, yy), (36, yy - 4)], hx("b84e1e"))
		rect(im, 38, 18, 44, 30, hx("6a6a6a"))
		mx.append(outline(im))
	save(frames(mx), page, "mixer")
	# xe rùa
	wb = new(34, 20)
	poly(wb, [(2, 4), (26, 4), (22, 12), (6, 12)], hx("3e7a5a"))
	rect(wb, 4, 5, 24, 7, hx("8a7a6a"))
	ell(wb, 22, 11, 30, 19, hx("2a2a2a"))
	px(wb, 26, 15, hx("8a8a8a"))
	line(wb, [(6, 12), (4, 19)], hx("5a5a5a"))
	line(wb, [(24, 8), (33, 4)], hx("6a4a2a"))
	save(outline(wb), page, "wheelbarrow")
	# chồng gạch (đống gạch bốc)
	pile = new(44, 30)
	for r in range(5):
		for c in range(4 - (r // 2)):
			x = 2 + c * 10 + (r % 2) * 4 + (r // 2) * 3
			y = 25 - r * 5
			rect(pile, x, y, x + 9, y + 4, hx("b5523b") if (r + c) % 2 else hx("c86a48"))
			rect(pile, x, y, x + 9, y + 1, hx("e08a68"))
	save(outline(pile), page, "pile")
	# một viên/cặp gạch đang bay
	br = new(12, 7)
	rect(br, 0, 2, 10, 6, hx("b5523b"))
	rect(br, 2, 0, 12, 4, hx("c86a48"))
	rect(br, 2, 0, 12, 1, hx("e8967a"))
	save(outline(br), page, "brick")
	brk = new(14, 6)
	for k in range(4):
		rect(brk, k * 3 + (k % 2), 2 + (k % 2) * 2, k * 3 + 3, 5, hx("a84a34"))
	save(outline(brk), page, "broken")
	# thợ hồ: đứng / giơ tay chờ / bắt được
	wk = [person(hx("4a78b0"), hx("4a4038"), hat="helmet", pose="stand"),
		person(hx("4a78b0"), hx("4a4038"), hat="helmet", pose="arms_up")]
	save(frames(wk), page, "worker")
	# người chơi tung gạch (giơ tay) – vẽ đè thêm lên sprite người chơi trong game


# ============================================================================ TRANG 4: quán cơm bà Lan

COUNTER_Y = 150


def build_stall():
	page = "stall"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 110, [hx("f6e2b8"), hx("f0d8a8"), hx("e8cc98")])
	# phố chợ phía sau (mờ, nhạt)
	for i, (x, w, c) in enumerate([(-10, 90, "d9b48a"), (80, 70, "c8a07c"), (150, 100, "e0c49a"), (250, 70, "cfae86"), (320, 80, "dcbc90")]):
		rect(bg, x, 30 + (i % 2) * 8, x + w, 110, hx(c))
		rect(bg, x + 6, 50, x + w - 6, 76, hx("8a6a52"))
		rect(bg, x + 6, 40 + (i % 2) * 8, x + w - 6, 48 + (i % 2) * 8, hx(["c8402e", "3a7aa8", "d89a2e", "4a8a4a", "a83a6a"][i]))
	# đường + vỉa hè
	vgrad(bg, 0, 104, W, H, [hx("b8aa94"), hx("a89a84"), hx("988a76")])
	for x in range(0, W, 24):
		line(bg, [(x, 104), (x - 12, H)], hx("9a8c78"))
	# quán: vách sau, kệ, nồi
	st = new(W, H)
	rect(st, 0, 26, 250, COUNTER_Y, hx("e6d2a8"))
	for y in range(30, COUNTER_Y, 10):
		rect(st, 0, y, 250, y + 1, hx("d6c098"))
	rect(st, 0, 26, 250, 30, hx("8a5a32"))
	# tranh lịch, bảng menu
	rect(st, 150, 36, 200, 70, hx("3a2a20"))
	rect(st, 152, 38, 198, 68, hx("2e4a36"))
	for i, w in enumerate([30, 24, 34, 20]):
		rect(st, 156, 42 + i * 6, 156 + w, 44 + i * 6, hx("f0f0e0"))
	rect(st, 210, 38, 232, 62, hx("f4f0e6"))
	rect(st, 210, 38, 232, 44, hx("d0302a"))
	rect(st, 216, 48, 226, 56, hx("d0302a"))
	# kệ + nồi bên trái
	rect(st, 6, 78, 130, 82, WOOD[2])
	rect(st, 6, 82, 130, 84, WOOD[0])
	# nồi cơm (nhôm)
	for (x, w, h) in [(10, 34, 24), (50, 30, 20), (88, 36, 22)]:
		rect(st, x, 78 - h, x + w, 78, hx("c4c8cc"))
		rect(st, x, 78 - h, x + w, 78 - h + 3, hx("e8ecee"))
		rect(st, x + w - 6, 78 - h + 2, x + w, 78, hx("9aa0a6"))
		rect(st, x - 2, 78 - h + 6, x, 78 - h + 9, hx("8a9096"))
		rect(st, x + w, 78 - h + 6, x + w + 2, 78 - h + 9, hx("8a9096"))
		ell(st, x + 4, 78 - h - 4, x + w - 4, 78 - h + 2, hx("aeb4ba"))
		rect(st, x + w / 2 - 2, 78 - h - 6, x + w / 2 + 2, 78 - h - 3, hx("5a5a5a"))
	# lò than + nồi canh lớn ở giữa
	rect(st, 60, 112, 120, COUNTER_Y, hx("8a8a86"))
	rect(st, 66, 118, 114, 128, hx("e0702e"))
	rect(st, 70, 120, 110, 126, hx("ffb84a"))
	rect(st, 58, 88, 122, 112, hx("5a4a44"))
	rect(st, 58, 88, 122, 92, hx("7a6a64"))
	rect(st, 56, 92, 58, 98, hx("3a302c"))
	rect(st, 122, 92, 124, 98, hx("3a302c"))
	st = outline(st, OUTL_SOFT)
	bg.alpha_composite(st)
	# mái che sọc + diềm lượn
	aw = new(W, H)
	rect(aw, 0, 0, 262, 22, hx("d8402e"))
	for x in range(0, 262, 20):
		poly(aw, [(x, 0), (x + 10, 0), (x + 10, 22), (x, 22)], hx("f6efe0"))
	for x in range(0, 262, 10):
		c = hx("f6efe0") if (x // 10) % 2 else hx("d8402e")
		ell(aw, x, 18, x + 10, 30, c)
	rect(aw, 0, 0, 262, 3, hx("8a2a1e"))
	rect(aw, 250, 0, 256, 150, hx("8a6a4a"))  # cột quán
	aw = outline(aw, OUTL)
	bg.alpha_composite(aw)
	# quầy trước (kính + gỗ) – mặt quầy đặt món
	ct = new(W, H)
	rect(ct, 0, COUNTER_Y, 256, H, WOOD[2])
	for x in range(0, 256, 16):
		rect(ct, x, COUNTER_Y + 8, x + 1, H, WOOD[1])
	rect(ct, 0, COUNTER_Y - 4, 258, COUNTER_Y + 6, hx("e8e4dc"))  # mặt quầy inox
	rect(ct, 0, COUNTER_Y - 4, 258, COUNTER_Y - 3, hx("ffffff"))
	rect(ct, 0, COUNTER_Y + 4, 258, COUNTER_Y + 6, hx("a8a49c"))
	rect(ct, 10, COUNTER_Y + 14, 246, COUNTER_Y + 44, hx("a8d4dc", 220))  # tủ kính
	rect(ct, 10, COUNTER_Y + 14, 246, COUNTER_Y + 16, hx("e0f4f6"))
	for x in range(30, 246, 40):
		line(ct, [(x, COUNTER_Y + 18), (x + 10, COUNTER_Y + 40)], hx("e6f6f8"))
	rect(ct, 14, COUNTER_Y + 50, 120, COUNTER_Y + 60, hx("d8402e"))
	ct = outline(ct, OUTL)
	save(ct, page, "counter")  # lớp trước: che chân người đứng sau quầy
	# xe máy đậu + chậu kiểng + thân cây me
	rect(bg, 362, 0, 372, 110, hx("6a4a32"))
	rect(bg, 362, 0, 365, 110, hx("8a6a4a"))
	blob(bg, 360, 4, 26, [GRASS[0], GRASS[1], GRASS[2], GRASS[3]], 77, count=9)
	try:
		bike = Image.open(ROOT / "game" / "art" / "bike_parked.png").convert("RGBA")
		paste(bg, bike, 270, 64)
	except OSError:
		pass
	for (x, c) in [(262, "c86a3a"), (346, "3a6aa8")]:
		poly(bg, [(x, 98), (x + 14, 98), (x + 12, 110), (x + 2, 110)], hx(c))
		blob(bg, x + 7, 92, 7, [GRASS[1], GRASS[2], GRASS[3]], x, count=5)
		px(bg, x + 5, 88, hx("f05a7a"))
		px(bg, x + 9, 90, hx("f8d84a"))
	# ghế nhựa + bàn nhỏ ngoài lề đường
	for (x, y, c) in [(330, 168, "d83a2e"), (360, 176, "3a6ad8")]:
		rect(bg, x, y, x + 14, y + 3, hx(c))
		rect(bg, x + 1, y + 3, x + 3, y + 12, hx(c))
		rect(bg, x + 11, y + 3, x + 13, y + 12, hx(c))
	save(bg, page, "bg")
	# món ăn (24×18)
	dishes = []
	# cơm tấm: dĩa trắng, cơm, sườn, trứng, dưa
	d = new(26, 16)
	ell(d, 0, 6, 26, 16, hx("f4f4f0"))
	ell(d, 2, 7, 24, 14, hx("dcdcd6"))
	ell(d, 4, 4, 16, 12, hx("fffdf4"))
	speckle(d, 5, 5, 15, 11, [hx("efe8d4")], 20, 1)
	poly(d, [(12, 6), (22, 5), (23, 9), (13, 11)], hx("a8502a"))
	line(d, [(14, 7), (21, 6)], hx("d88a4a"))
	ell(d, 5, 10, 11, 14, hx("fff8e0"))
	rect(d, 7, 11, 9, 13, hx("f8b830"))
	rect(d, 18, 10, 23, 13, hx("e88a3a"))
	dishes.append(outline(d))
	# cơm cháy
	d = new(26, 16)
	ell(d, 0, 6, 26, 16, hx("f4f4f0"))
	ell(d, 2, 7, 24, 14, hx("dcdcd6"))
	for k in range(4):
		rect(d, 4 + k * 5, 5 + (k % 2) * 2, 9 + k * 5, 10 + (k % 2) * 2, hx("e0a84a"))
		rect(d, 4 + k * 5, 5 + (k % 2) * 2, 9 + k * 5, 6 + (k % 2) * 2, hx("f6d27a"))
	speckle(d, 4, 5, 24, 12, [hx("c06a2a"), hx("4a8a3a")], 16, 2)
	dishes.append(outline(d))
	# canh chua: tô
	d = new(26, 18)
	poly(d, [(1, 6), (25, 6), (21, 15), (5, 15)], hx("f0eee6"))
	rect(d, 6, 15, 20, 17, hx("d0cec6"))
	ell(d, 1, 3, 25, 9, hx("e8783a"))
	px(d, 8, 5, hx("f8d84a"))
	px(d, 15, 5, hx("5aa83a"))
	px(d, 18, 6, hx("f04a3a"))
	px(d, 11, 6, hx("5aa83a"))
	line(d, [(4, 8), (22, 8)], hx("3a7ab0"))
	dishes.append(outline(d))
	# trà đá: ly nhựa
	d = new(16, 20)
	poly(d, [(2, 2), (14, 2), (12, 19), (4, 19)], hx("c89a4a", 230))
	rect(d, 3, 2, 13, 6, hx("e8f4f6"))
	rect(d, 5, 5, 8, 8, hx("ffffff"))
	rect(d, 9, 7, 12, 10, hx("f0f8fa"))
	line(d, [(10, 0), (8, 10)], hx("e84a3a"))
	dishes.append(outline(d))
	for i, d in enumerate(dishes):
		save(d, page, f"dish_{i}")
	# hơi nước bốc (vẽ bằng code)


# ============================================================================ TRANG 5: chở ghe (nhìn từ trên xuống)

RIVER_L, RIVER_R = 82, 302


def build_boat():
	page = "boat"
	# nước sông phù sa lặp dọc (384×216)
	water = new(W, H)
	rect(water, 0, 0, W, H, hx("6c9882"))
	rng = random.Random(3)
	for i in range(70):
		x = rng.randrange(0, W)
		y = rng.randrange(0, H)
		w = rng.randint(4, 12)
		line(water, [(x, y), (x + w, y)], hx("8ab8a0"))
		if rng.random() < 0.5:
			line(water, [(x + 2, y + 1), (x + w - 2, y + 1)], hx("5e8a74"))
	save(water, page, "water")
	# hai bờ (lặp dọc, cao 432): bùn, cỏ, dừa, nhà sàn, ghe đậu có cây bẹo
	for side in ["left", "right"]:
		bank = new(W // 2, 432)
		bw = RIVER_L if side == "left" else W - RIVER_R
		bx0 = 0 if side == "left" else W // 2 - bw
		rect(bank, bx0, 0, bx0 + bw, 432, GRASS[2])
		speckle(bank, bx0, 0, bx0 + bw, 432, [GRASS[1], GRASS[3], GRASS[4]], 900, 7 if side == "left" else 8)
		edge_x = bx0 + bw if side == "left" else bx0
		pts = []
		for y in range(0, 433, 6):
			pts.append((edge_x + (math.sin(y * 0.08) * 3 + (2 if (y // 6) % 3 == 0 else 0)) * (1 if side == "left" else -1), y))
		mud = new(W // 2, 432)
		for (x, y) in pts:
			if side == "left":
				rect(mud, x - 8, y, x, y + 6, hx("8a7048"))
				rect(mud, x - 3, y, x, y + 6, hx("6a5636"))
			else:
				rect(mud, x, y, x + 8, y + 6, hx("8a7048"))
				rect(mud, x, y, x + 3, y + 6, hx("6a5636"))
		bank.alpha_composite(mud)
		rng = random.Random(11 if side == "left" else 17)
		# nhà sàn mái tôn/lá (nhìn từ trên)
		for k in range(2):
			hy = 40 + k * 216 + rng.randint(-10, 10)
			hx0 = bx0 + (6 if side == "left" else bw - 56)
			roof = new(52, 40)
			rect(roof, 0, 0, 52, 40, hx("b89254") if k == 0 else hx("8a9aa8"))
			for yy in range(0, 40, 4):
				rect(roof, 0, yy, 52, yy + 1, hx("9c7a42") if k == 0 else hx("6a7a88"))
			rect(roof, 25, 0, 27, 40, hx("6a5030") if k == 0 else hx("5a6a78"))
			paste(bank, outline(roof), hx0, hy)
			# cầu ván ra sông
			dx = bx0 + bw - 14 if side == "left" else bx0 - 2
			for yy in range(hy + 14, hy + 26, 3):
				rect(bank, dx, yy, dx + 16, yy + 2, WOOD[3])
		# dừa (tán nhìn từ trên)
		for k in range(5):
			cx = bx0 + rng.randint(10, bw - 10)
			cy = rng.randint(0, 432)
			ell(bank, cx - 6, cy - 6 + 3, cx + 7, cy + 7 + 3, (20, 50, 20, 90))
			for a in range(10):
				ang = a / 10 * math.tau + rng.uniform(-0.2, 0.2)
				for s in range(1, 17):
					w2 = 2.5 * math.sin(s / 17 * math.pi)
					nx, ny = -math.sin(ang), math.cos(ang)
					for q in range(-int(w2), int(w2) + 1):
						px(bank, cx + math.cos(ang) * s + nx * q, cy + math.sin(ang) * s + ny * q,
							hx("5a9a4a") if q < 0 else (hx("3f7a3a") if s % 3 else hx("2f5e2a")))
			ell(bank, cx - 3, cy - 3, cx + 4, cy + 4, hx("6e7a2a"))
		bank = outline(bank, OUTL_SOFT)
		save(bank, page, f"bank_{side}")
	# ghe của mình (nhìn từ trên, mũi lên trên) 28×60
	g = new(30, 62)
	poly(g, [(15, 0), (24, 12), (26, 30), (24, 54), (15, 61), (6, 54), (4, 30), (6, 12)], hx("6a3e22"))
	poly(g, [(15, 3), (22, 13), (23, 30), (22, 52), (15, 58), (8, 52), (7, 30), (8, 13)], hx("8a5a32"))
	for y in range(16, 54, 8):
		rect(g, 8, y, 22, y + 1, hx("5a3418"))
	ell(g, 12, 4, 18, 8, hx("e04a3a"))  # mắt ghe (đỏ)
	rect(g, 13, 52, 17, 61, hx("4a2a14"))  # bánh lái
	save(outline(g, hx("2a160a")), page, "player_boat")
	sack = new(11, 9)
	rect(sack, 0, 0, 11, 9, hx("e6d6a8"))
	rect(sack, 0, 0, 11, 2, hx("f6ead0"))
	rect(sack, 4, 0, 7, 9, hx("c8b480"))
	save(outline(sack), page, "sack")
	# chướng ngại: ghe ngược chiều (mũi xuống) chở trái cây + người chèo
	o = new(30, 50)
	poly(o, [(15, 49), (24, 40), (26, 20), (24, 6), (15, 0), (6, 6), (4, 20), (6, 40)], hx("5a3a24"))
	poly(o, [(15, 46), (22, 38), (23, 20), (21, 7), (15, 3), (9, 7), (7, 20), (8, 38)], hx("7a4e2c"))
	for k in range(7):
		ell(o, 9 + (k % 3) * 4, 14 + (k // 3) * 5, 14 + (k % 3) * 4, 19 + (k // 3) * 5, [hx("f0c030"), hx("5aa83a"), hx("e8703a")][k % 3])
	ell(o, 10, 32, 20, 42, hx("f1d98a"))  # nón lá người chèo
	px(o, 15, 37, hx("b8924a"))
	save(outline(o, hx("2a160a")), page, "obs_ghe")
	o = new(54, 26)
	for k in range(9):
		blob(o, 8 + (k % 5) * 10, 8 + (k // 5) * 10, 6, [hx("2f6a3a"), hx("4e9a4a"), hx("7cc464")], 20 + k, count=4)
	for (x, y) in [(14, 6), (30, 12), (44, 8)]:
		rect(o, x, y, x + 3, y + 3, hx("b88ae0"))
		px(o, x + 1, y + 1, hx("f8e060"))
	save(outline(o, hx("1e3a1e")), page, "obs_lucbinh")
	o = new(52, 16)
	rect(o, 4, 3, 48, 13, hx("7a5a3a"))
	for x in range(6, 48, 4):
		line(o, [(x, 3), (x + 2, 13)], hx("5e4428"))
	ell(o, 0, 2, 10, 14, hx("a8885a"))
	ell(o, 2, 4, 8, 12, hx("c8a878"))
	px(o, 5, 8, hx("7a5a3a"))
	blob(o, 46, 4, 4, [hx("3f7a3a"), hx("5a9a4a")], 4, count=3)
	save(outline(o, hx("2a160a")), page, "obs_dua")
	# ghe buôn đậu ven chợ nổi có cây bẹo (treo trái cây)
	m = new(34, 64)
	poly(m, [(17, 0), (28, 12), (30, 34), (28, 54), (17, 63), (6, 54), (4, 34), (6, 12)], hx("5a3a24"))
	poly(m, [(17, 4), (26, 14), (27, 34), (25, 52), (17, 59), (9, 52), (7, 34), (8, 14)], hx("7a4e2c"))
	rect(m, 8, 20, 26, 40, hx("3a6aa8"))  # mui ghe xanh
	for y in range(20, 40, 3):
		rect(m, 8, y, 26, y + 1, hx("2a5088"))
	for k in range(6):
		ell(m, 9 + (k % 3) * 5, 44 + (k // 3) * 5, 14 + (k % 3) * 5, 49 + (k // 3) * 5, [hx("6ab04a"), hx("f0c030"), hx("d8402e")][k % 3])
	save(outline(m, hx("2a160a")), page, "moored")
	beo = new(14, 16)
	ell(beo, 2, 2, 8, 8, hx("6ab04a"))
	ell(beo, 7, 4, 13, 10, hx("f0c030"))
	ell(beo, 3, 8, 9, 14, hx("e85a2a"))
	save(outline(beo), page, "beo")


# ============================================================================ TRANG 6: lớp học

BOARD = (84, 18, 300, 118)


def build_class():
	page = "class"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 150, [hx("f4e2a6"), hx("eed69a"), hx("e6cc8e")])  # tường vàng
	rect(bg, 0, 120, W, 150, hx("d8b878"))  # chân tường
	rect(bg, 0, 120, W, 122, hx("b8985a"))
	# cửa sổ trái + phải có song sắt, nắng chiếu
	for x0 in [8, 320]:
		rect(bg, x0, 22, x0 + 56, 96, hx("6a4a2a"))
		vgrad(bg, x0 + 3, 25, x0 + 53, 93, [hx("a8dcf0"), hx("c8ecf4"), hx("e8f6e8")])
		blob(bg, x0 + 20, 80, 12, [hx("4f8656"), hx("6aa86a"), hx("8cc87a")], x0, count=5)
		for x in range(x0 + 10, x0 + 53, 9):
			rect(bg, x, 25, x + 2, 93, hx("4a6a7a"))
		rect(bg, x0 + 3, 58, x0 + 53, 60, hx("4a6a7a"))
	sun = new(W, H)
	poly(sun, [(12, 96), (62, 96), (130, 216), (60, 216)], (255, 240, 190, 40))
	bg.alpha_composite(sun)
	# bảng đen (bảng xanh) + khung gỗ + máng phấn
	x0, y0, x1, y1 = BOARD
	rect(bg, x0 - 5, y0 - 5, x1 + 5, y1 + 5, WOOD[1])
	rect(bg, x0 - 5, y0 - 5, x1 + 5, y0 - 3, WOOD[3])
	vgrad(bg, x0, y0, x1, y1, [hx("2f5a46"), hx("2b5442"), hx("284e3e")])
	speckle(bg, x0, y0, x1, y1, [hx("3a6a54"), hx("355f4c")], 220, 4)
	for i in range(5):
		line(bg, [(x0 + 10 + i * 40, y1 - 6), (x0 + 30 + i * 40, y1 - 12)], hx("4a7a64"))  # vết phấn lau
	rect(bg, x0 - 8, y1 + 4, x1 + 8, y1 + 8, WOOD[2])
	rect(bg, x0 + 20, y1 + 2, x0 + 26, y1 + 4, hx("f8f8f0"))
	rect(bg, x0 + 30, y1 + 2, x0 + 34, y1 + 4, hx("f0a8a8"))
	# băng rôn đỏ phía trên bảng (chữ do game vẽ)
	rect(bg, 96, 0, 288, 12, hx("c8302a"))
	rect(bg, 96, 0, 288, 1, hx("e85a4a"))
	rect(bg, 96, 11, 288, 12, hx("8a1e1a"))
	# đồng hồ
	ell(bg, 312, 4, 328, 20, hx("3a2a20"))
	ell(bg, 313, 5, 327, 19, hx("f8f4e8"))
	line(bg, [(320, 12), (320, 7)], hx("2a2a2a"))
	line(bg, [(320, 12), (324, 12)], hx("2a2a2a"))
	# bục giảng + bàn giáo viên (phải)
	desk = new(W, H)
	rect(desk, 300, 112, 384, 150, WOOD[2])
	rect(desk, 300, 112, 384, 116, WOOD[4])
	rect(desk, 300, 146, 384, 150, WOOD[0])
	rect(desk, 312, 104, 330, 112, hx("d84a3a"))  # sách
	rect(desk, 314, 102, 332, 106, hx("3a6ad8"))
	ell(desk, 346, 100, 358, 112, hx("e8e0d0"))  # ly nước
	desk = outline(desk, OUTL_SOFT)
	bg.alpha_composite(desk)
	# sàn gạch bông
	vgrad(bg, 0, 150, W, H, [hx("c8b090"), hx("bca482"), hx("ae9674")])
	for y in range(150, H, 12):
		rect(bg, 0, y, W, y + 1, hx("a08868"))
	for x in range(0, W, 16):
		line(bg, [(x, 150), (x + (x - 192) * 0.3, H)], hx("a08868"))
	save(bg, page, "bg")
	# dãy bàn học trước mặt (lớp phủ phía trước học sinh)
	fg = new(W, H)
	for row, (y, h) in enumerate([(176, 14), (204, 14)]):
		rect(fg, -4, y, W + 4, y + h, WOOD[3])
		rect(fg, -4, y, W + 4, y + 2, WOOD[4])
		rect(fg, -4, y + h - 2, W + 4, y + h, WOOD[1])
		for x in range(40 + row * 20, W, 96):
			rect(fg, x, y + h, x + 4, H, WOOD[0])
		for x in range(20 + row * 30, W, 70):
			rect(fg, x, y - 2, x + 14, y + 1, hx("f4f0e6"))  # vở
			rect(fg, x + 6, y - 2, x + 7, y + 1, hx("c8c0b0"))
	fg = outline(fg, OUTL_SOFT)
	save(fg, page, "desks")
	# học sinh quay lưng: áo trắng, tóc đen/ cột tóc/ khăn quàng đỏ
	kids = []
	for k in range(4):
		im = new(22, 26)
		hair = hx("1e1612") if k != 2 else hx("3a2418")
		rect(im, 3, 14, 19, 26, hx("f8f8f4"))
		rect(im, 3, 14, 19, 16, hx("e8e8e0"))
		rect(im, 15, 16, 19, 26, hx("dcdcd4"))
		ell(im, 5, 2, 17, 15, hair)
		if k == 1:
			rect(im, 9, 12, 13, 18, hair)  # tóc dài
			rect(im, 9, 4, 13, 6, hx("e84a6a"))
		if k == 3:
			poly(im, [(7, 14), (15, 14), (11, 19)], hx("d8302a"))  # khăn quàng
		px(im, 4, 9, SKIN[2])
		px(im, 17, 9, SKIN[2])
		kids.append(outline(im, OUTL_SOFT))
	save(frames(kids), page, "kids")
	# học sinh giơ tay
	im = new(22, 34)
	rect(im, 3, 22, 19, 34, hx("f8f8f4"))
	rect(im, 15, 24, 19, 34, hx("dcdcd4"))
	ell(im, 5, 10, 17, 23, hx("1e1612"))
	rect(im, 16, 0, 20, 20, hx("f8f8f4"))
	rect(im, 16, 0, 20, 4, SKIN[2])
	save(outline(im, OUTL_SOFT), page, "kid_hand")
	# quạt trần (2 khung)
	fan = []
	for f in range(2):
		im = new(48, 10)
		rect(im, 23, 0, 25, 5, hx("6a6a6a"))
		ell(im, 20, 4, 28, 9, hx("8a8a8a"))
		if f == 0:
			rect(im, 0, 6, 22, 8, hx("b8b8b0"))
			rect(im, 26, 5, 48, 7, hx("b8b8b0"))
		else:
			rect(im, 6, 5, 22, 7, hx("a8a8a0"))
			rect(im, 26, 6, 42, 8, hx("a8a8a0"))
		fan.append(outline(im))
	save(frames(fan), page, "fan")
	# thẻ đáp án (vẽ trên bảng) + phấn chọn
	card = new(100, 18)
	rect(card, 0, 0, 100, 18, hx("f6efd8"))
	rect(card, 0, 15, 100, 18, hx("d8caa0"))
	rect(card, 0, 0, 100, 1, hx("ffffff"))
	save(outline(card, hx("1e3a2e")), page, "card")
	sel = new(104, 22)
	rect(sel, 0, 0, 104, 22, hx("ffd84a"))
	rect(sel, 2, 2, 102, 20, (0, 0, 0, 0))
	save(sel, page, "card_sel")


# ============================================================================ TRANG 7: đền làng

def build_temple():
	page = "temple"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 160, [hx("3a1a14"), hx("4a2218"), hx("5a2a1c")])
	# vách gỗ có ô hoa văn
	for x in range(0, W, 32):
		rect(bg, x, 0, x + 1, 160, hx("2a120c"))
		for y in range(20, 150, 40):
			rect(bg, x + 6, y, x + 26, y + 26, hx("6a3020"))
			rect(bg, x + 8, y + 2, x + 24, y + 24, hx("4e2216"))
			ell(bg, x + 12, y + 8, x + 20, y + 16, hx("8a5a2a"))
	# hoành phi vàng + câu đối
	rect(bg, 112, 8, 272, 30, hx("6a1a12"))
	rect(bg, 114, 10, 270, 28, hx("b8302a"))
	rect(bg, 114, 10, 270, 11, hx("f0c040"))
	rect(bg, 114, 27, 270, 28, hx("f0c040"))
	for i in range(4):
		rect(bg, 132 + i * 36, 14, 148 + i * 36, 24, hx("f0c040"))
		rect(bg, 135 + i * 36, 17, 145 + i * 36, 21, hx("b8302a"))
	for x in [70, 300]:
		rect(bg, x, 36, x + 14, 130, hx("b8302a"))
		rect(bg, x, 36, x + 14, 38, hx("f0c040"))
		for y in range(44, 126, 12):
			rect(bg, x + 4, y, x + 10, y + 8, hx("f0c040"))
			px(bg, x + 6, y + 3, hx("b8302a"))
	# cột sơn son
	for x in [30, 340]:
		rect(bg, x, 0, x + 16, 172, hx("a8281e"))
		rect(bg, x + 3, 0, x + 6, 172, hx("d84a3a"))
		rect(bg, x + 12, 0, x + 16, 172, hx("6a140e"))
		for y in [30, 120]:
			rect(bg, x - 2, y, x + 18, y + 6, hx("e0a830"))
	# bàn thờ chính: khám thờ vàng + bài vị
	alt = new(W, H)
	rect(alt, 130, 40, 254, 110, hx("8a5a1a"))
	rect(alt, 134, 44, 250, 106, hx("d8a030"))
	rect(alt, 140, 50, 244, 100, hx("6a1a12"))
	poly(alt, [(126, 42), (192, 30), (258, 42)], hx("e0b040"))
	rect(alt, 176, 56, 208, 96, hx("e8c050"))
	rect(alt, 180, 60, 204, 92, hx("b8302a"))
	for y in range(64, 90, 8):
		rect(alt, 188, y, 196, y + 4, hx("f0d070"))
	# hai bên: lọng / đèn lồng
	rect(alt, 110, 110, 274, 136, hx("7a2a1a"))
	rect(alt, 110, 110, 274, 114, hx("a84a2a"))
	rect(alt, 110, 132, 274, 136, hx("4a160e"))
	for x in range(116, 270, 20):
		rect(alt, x, 118, x + 12, 128, hx("5a1e12"))
		px(alt, x + 6, 123, hx("e0a830"))
	# mâm ngũ quả + bình hoa
	ell(alt, 136, 100, 168, 112, hx("e0b040"))
	for k in range(6):
		ell(alt, 140 + k * 4, 94 - (k % 2) * 3, 148 + k * 4, 104 - (k % 2) * 3, [hx("f0c030"), hx("5aa83a"), hx("e8703a"), hx("d83a2a")][k % 4])
	rect(alt, 222, 88, 232, 110, hx("3a6aa8"))
	blob(alt, 227, 84, 6, [hx("d8302a"), hx("f05a4a"), hx("ffd0a0")], 8, count=4)
	alt = outline(alt, OUTL)
	bg.alpha_composite(alt)
	# sàn gạch tàu
	vgrad(bg, 0, 160, W, H, [hx("9a4a2e"), hx("8a4028"), hx("7a3622")])
	for y in range(160, H, 10):
		rect(bg, 0, y, W, y + 1, hx("6a2e1c"))
	for y in range(160, H, 10):
		off = 0 if (y // 10) % 2 else 10
		for x in range(off, W, 20):
			rect(bg, x, y, x + 1, y + 10, hx("6a2e1c"))
	# ánh đèn ấm
	# ánh đèn ấm: quầng sáng mềm (dither) quanh bàn thờ
	ga = np.zeros((H, W, 4), dtype=np.uint8)
	yy, xx = np.mgrid[0:H, 0:W]
	d = np.sqrt(((xx - 192) / 130.0) ** 2 + ((yy - 90) / 90.0) ** 2)
	strength = np.clip(1.0 - d, 0.0, 1.0) ** 1.5
	steps = np.floor(strength * 4 + BAYER[yy % 4, xx % 4] * 0.9) / 4.0
	ga[:, :, 0] = 255
	ga[:, :, 1] = 196
	ga[:, :, 2] = 120
	ga[:, :, 3] = (steps * 46).astype(np.uint8)
	bg.alpha_composite(Image.fromarray(ga, "RGBA"))
	save(bg, page, "bg")
	# lư hương đồng (đặt giữa, trước bàn thờ)
	urn = new(56, 46)
	ell(urn, 4, 10, 52, 40, hx("8a6a2a"))
	ell(urn, 8, 12, 48, 36, hx("b88a3a"))
	ell(urn, 14, 14, 30, 24, hx("e0b860"))
	rect(urn, 2, 8, 54, 14, hx("a07a30"))
	ell(urn, 6, 6, 50, 14, hx("4a3a20"))
	ell(urn, 8, 7, 48, 12, hx("7a6a5a"))  # tro
	rect(urn, 0, 18, 4, 26, hx("8a6a2a"))
	rect(urn, 52, 18, 56, 26, hx("8a6a2a"))
	for x in [12, 26, 40]:
		rect(urn, x, 38, x + 5, 46, hx("6a4a1a"))
	save(outline(urn, OUTL), page, "urn")
	# nến (2 khung lửa)
	cd = []
	for f in range(2):
		im = new(8, 26)
		rect(im, 2, 8, 6, 26, hx("e83a2a"))
		rect(im, 2, 8, 3, 26, hx("ff6a4a"))
		ell(im, 2, 1 + f, 6, 8, hx("ffd84a"))
		px(im, 4, 4 + f, hx("ffffff"))
		cd.append(im)
	save(frames(cd), page, "candle")
	# nhang (1 cây)
	inc = new(3, 26)
	rect(inc, 1, 2, 2, 20, hx("c8a46a"))
	rect(inc, 1, 18, 2, 26, hx("d83a2a"))
	px(inc, 1, 1, hx("ff8a3a"))
	px(inc, 1, 0, hx("ffd060"))
	save(inc, page, "incense")
	# ống xăm (ống tre + thẻ)
	cup = new(30, 52)
	for k in range(9):
		x = 6 + k * 2
		rect(cup, x, 2 + (k * 5) % 7, x + 1, 26, hx("e8c878"))
		rect(cup, x, 2 + (k * 5) % 7, x + 1, 5 + (k * 5) % 7, hx("d83a2a"))
	rect(cup, 4, 20, 26, 52, hx("b8904a"))
	rect(cup, 4, 20, 8, 52, hx("d8b06a"))
	rect(cup, 22, 20, 26, 52, hx("8a6a30"))
	for y in [24, 46]:
		rect(cup, 4, y, 26, y + 2, hx("6a4a20"))
	rect(cup, 12, 32, 18, 40, hx("d83a2a"))
	px(cup, 14, 35, hx("f0c040"))
	save(outline(cup, OUTL), page, "cup")
	stick = new(4, 26)
	rect(stick, 1, 0, 3, 26, hx("e8c878"))
	rect(stick, 1, 0, 3, 5, hx("d83a2a"))
	save(outline(stick, OUTL), page, "stick")
	# ông từ: áo dài the xanh đậm, khăn đóng, râu bạc
	keeper = person(hx("27325a"), hx("e8e4d8"), hat="khan", hair=hx("d8d8d0"))
	kd = ImageDraw.Draw(keeper)
	cx = keeper.width // 2
	kd.rectangle([cx - 2, 20, cx + 1, 24], fill=hx("eeeeea"))  # râu
	save(keeper, page, "keeper")
	# đèn lồng đỏ treo (2 khung lắc)
	ln = []
	for f in range(2):
		im = new(16, 26)
		line(im, [(8, 0), (8 + f, 6)], hx("2a1a12"))
		ell(im, 1 + f, 6, 15 + f, 20, hx("d8302a"))
		ell(im, 4 + f, 8, 9 + f, 16, hx("f86a4a"))
		rect(im, 5 + f, 5, 11 + f, 7, hx("e0a830"))
		rect(im, 5 + f, 19, 11 + f, 21, hx("e0a830"))
		line(im, [(8 + f, 21), (8 + f, 25)], hx("e0a830"))
		ln.append(outline(im, OUTL))
	save(frames(ln), page, "lantern")


# ============================================================================ TRANG 8: vé số

def build_lottery():
	page = "lottery"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 120, [hx("f8e2b0"), hx("f4d49c"), hx("eec890")])
	# vách quán cà phê + tán me
	rect(bg, 0, 20, W, 120, hx("e8d4b0"))
	for x in range(0, W, 48):
		rect(bg, x + 8, 34, x + 40, 90, hx("6a8aa8"))
		rect(bg, x + 10, 36, x + 38, 88, hx("8ab0c8"))
		rect(bg, x + 23, 36, x + 25, 88, hx("6a8aa8"))
	rect(bg, 0, 20, W, 26, hx("8a5a32"))
	for i, x in enumerate([20, 120, 240, 350]):
		blob(bg, x, 6, 20, [GRASS[0], GRASS[1], GRASS[2], GRASS[3]], 90 + i, count=8)
	# vỉa hè gạch
	vgrad(bg, 0, 118, W, H, [hx("c8b8a0"), hx("bcac94"), hx("b0a088")])
	for y in range(118, H, 10):
		rect(bg, 0, y, W, y + 1, hx("a09078"))
		off = 0 if (y // 10) % 2 else 12
		for x in range(off, W, 24):
			rect(bg, x, y, x + 1, y + 10, hx("a09078"))
	# xe đạp + bảng vé số dựng
	board = new(W, H)
	rect(board, 230, 46, 330, 136, WOOD[2])
	rect(board, 232, 48, 328, 134, hx("f4ecd8"))
	cols = ["e84a3a", "3a8ad8", "f0c030", "5ab04a", "c84ac8", "f08a3a"]
	for r in range(4):
		for c in range(5):
			x = 236 + c * 18
			y = 52 + r * 20
			rect(board, x, y, x + 15, y + 17, hx(cols[(r * 5 + c) % len(cols)]))
			rect(board, x + 2, y + 2, x + 13, y + 8, hx("ffffff"))
			rect(board, x + 6, y - 1, x + 9, y + 2, hx("9a9a9a"))
	rect(board, 240, 136, 244, 170, WOOD[1])
	rect(board, 316, 136, 320, 170, WOOD[1])
	board = outline(board, OUTL)
	bg.alpha_composite(board)
	# ghế nhựa, ly cà phê
	rect(bg, 40, 150, 70, 154, hx("3a6ad8"))
	rect(bg, 42, 154, 45, 172, hx("3a6ad8"))
	rect(bg, 65, 154, 68, 172, hx("3a6ad8"))
	save(bg, page, "bg")
	save(npc("lottery"), page, "seller")
	# vé số cầm tay (lớn) 64×36 – số do game in lên
	t = new(66, 38)
	rect(t, 0, 0, 66, 38, hx("fdf6e2"))
	rect(t, 0, 0, 66, 8, hx("d8402e"))
	rect(t, 0, 30, 66, 38, hx("f2d6a0"))
	for x in range(2, 66, 4):
		px(t, x, 37, hx("c8a870"))
	rect(t, 4, 11, 22, 27, hx("f0c040"))
	ell(t, 6, 13, 20, 25, hx("e0a020"))
	px(t, 12, 18, hx("fff0a0"))
	save(outline(t, OUTL), page, "ticket")
	# bảng kết quả (lớp bạc cào do game vẽ)
	r = new(200, 70)
	rect(r, 0, 0, 200, 70, hx("2a4a7a"))
	rect(r, 3, 3, 197, 67, hx("fdf6e2"))
	rect(r, 3, 3, 197, 16, hx("d8402e"))
	rect(r, 3, 16, 197, 18, hx("f0c040"))
	save(outline(r, OUTL), page, "result_board")
	coin = new(12, 12)
	ell(coin, 0, 0, 12, 12, hx("b8902a"))
	ell(coin, 1, 1, 11, 11, hx("f0c040"))
	ell(coin, 3, 3, 9, 9, hx("d8a830"))
	px(coin, 3, 3, hx("fff4b0"))
	save(outline(coin, OUTL), page, "coin")


# ============================================================================ TRANG 9: câu cá lóc (bờ kênh)

CANAL_Y = 118


def build_fishing():
	page = "fishing"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, CANAL_Y, SKY_WARM)
	for i, (x, y, w) in enumerate([(90, 20, 40), (260, 12, 56)]):
		cloud(bg, x, y, w, 70 + i)
	# bờ bên kia: dừa, nhà sàn, xuồng
	tree_line(bg, 100, hx("7aa58a"), hx("5d8f6a"), 41, height=14)
	rect(bg, 236, 72, 290, 96, hx("c8a878"))
	poly(bg, [(230, 74), (263, 58), (296, 74)], hx("9c7a42"))
	for x in [240, 254, 270, 284]:
		rect(bg, x, 96, x + 2, 112, WOOD[1])
	for i, x in enumerate([40, 120, 190, 330]):
		palm(bg, x, 102, 32 + (i % 2) * 8, 0.7 * (-1) ** i, hx("4f8656"), hx("3f6e48"), hx("7d8a6a"), hx("5e6a52"), 80 + i, 0.85)
	rect(bg, 0, 104, W, CANAL_Y, hx("6f9a58"))
	rect(bg, 0, CANAL_Y - 4, W, CANAL_Y, hx("6a5034"))
	# nước kênh
	vgrad(bg, 0, CANAL_Y, W, H, [hx("6aa8a8"), hx("5a9898"), hx("4a8484"), hx("3c7070")])
	rng = random.Random(5)
	for i in range(50):
		x = rng.randrange(0, W)
		y = rng.randrange(CANAL_Y + 4, H)
		line(bg, [(x, y), (x + rng.randint(4, 10), y)], hx("8cc4c0"))
	# phản chiếu dừa (mờ)
	refl = new(W, H)
	for x in [40, 120, 190, 330]:
		rect(refl, x - 1, CANAL_Y + 2, x + 2, CANAL_Y + 24, (60, 100, 70, 60))
	bg.alpha_composite(refl)
	# lá sen + lục bình trên mặt nước
	for (x, y, s) in [(150, 140, 1), (176, 150, 2), (300, 136, 3), (330, 160, 4)]:
		ell(bg, x - 9, y - 3, x + 9, y + 3, hx("3f8a3a"))
		ell(bg, x - 7, y - 3, x + 7, y + 1, hx("5aa84a"))
		poly(bg, [(x, y), (x + 9, y - 1), (x + 9, y + 2)], hx("4a8484"))
	blob(bg, 240, CANAL_Y + 30, 6, [hx("2f6a3a"), hx("4e9a4a"), hx("7cc464")], 6, count=4)
	px(bg, 240, CANAL_Y + 24, hx("b88ae0"))
	# hoa sen hồng
	poly(bg, [(160, 134), (163, 128), (166, 134)], hx("f08aa8"))
	poly(bg, [(158, 135), (163, 131), (168, 135), (163, 138)], hx("f8b8c8"))
	# bờ gần (trái, phía trước): cỏ, lau sậy, nơi người chơi ngồi
	bank = new(W, H)
	poly(bank, [(0, 150), (60, 150), (96, 164), (116, 190), (124, 216), (0, 216)], hx("6a4a2a"))
	poly(bank, [(0, 146), (64, 146), (98, 160), (92, 164), (60, 154), (0, 154)], GRASS[3])
	rect(bank, 0, 154, 70, 216, GRASS[2])
	speckle(bank, 0, 150, 120, 216, [GRASS[1], GRASS[3], GRASS[4], hx("7a5a34")], 500, 9, mask=bank)
	bank = outline(bank, OUTL_SOFT)
	bg.alpha_composite(bank)
	for i in range(22):
		x = 70 + rng.randint(0, 50)
		h = rng.randint(14, 30)
		for k in range(h):
			px(bg, x + math.sin(k * 0.2) * (k / h) * 3, 200 - k, hx("5a8a3a") if k % 4 else hx("3f6a2a"))
		if rng.random() < 0.5:
			rect(bg, x - 1, 200 - h - 4, x + 2, 200 - h, hx("a8784a"))
	# xô đựng cá + ghế đẩu
	rect(bg, 8, 170, 24, 186, hx("3a7ab0"))
	rect(bg, 8, 170, 24, 172, hx("6aa8d8"))
	rect(bg, 34, 176, 52, 180, hx("d84a3a"))
	rect(bg, 36, 180, 38, 190, hx("b83a2a"))
	rect(bg, 48, 180, 50, 190, hx("b83a2a"))
	save(bg, page, "bg")
	# phao (2 khung: nổi / chìm nửa)
	fl = []
	for f in range(2):
		im = new(6, 12)
		rect(im, 2, 0, 4, 4, hx("f8f8f0"))
		ell(im, 0, 3, 6, 9, hx("e83a2a"))
		rect(im, 0, 6, 6, 7, hx("f8f8f0"))
		if f == 1:
			rect(im, 0, 7, 6, 12, (0, 0, 0, 0))
		fl.append(outline(im))
	save(frames(fl), page, "bobber")
	# bóng cá lóc dưới nước + cá lóc bắt lên
	sh = new(36, 10)
	ell(sh, 0, 2, 30, 9, (20, 40, 40, 140))
	poly(sh, [(28, 5), (36, 1), (36, 9)], (20, 40, 40, 140))
	save(sh, page, "shadow")
	fish = new(36, 14)
	poly(fish, [(1, 7), (5, 3), (26, 3), (30, 6), (36, 2), (35, 7), (36, 12), (30, 8), (26, 11), (5, 11)], hx("4a5a3a"))
	for x in range(8, 26, 5):
		ell(fish, x, 4, x + 4, 8, hx("2e3a24"))
	poly(fish, [(5, 9), (26, 9), (26, 11), (5, 11)], hx("c8c8a8"))
	px(fish, 4, 5, hx("f0e070"))
	px(fish, 4, 6, hx("1a1a1a"))
	save(outline(fish, hx("1a2214")), page, "snakehead")
	save(npc("fisher"), page, "neighbor")


# ============================================================================ TRANG 10: thả diều trên bờ đê

DIKE_Y = 176


def build_kite():
	page = "kite"
	bg = new(W, H)
	vgrad(bg, 0, 0, W, 150, [hx("6a7ac8"), hx("9a8ad0"), hx("e8a0b0"), hx("f8c49a"), hx("fde2a8")], sharp=2.0)
	# mặt trời chiều
	ell(bg, 270, 92, 318, 140, hx("fff0b8"))
	ell(bg, 276, 98, 312, 134, hx("fff8dc"))
	for i, (x, y, w) in enumerate([(60, 30, 60), (180, 52, 44), (330, 40, 50), (120, 80, 36)]):
		cloud(bg, x, y, w, 100 + i, light=hx("ffe6d6"), mid=hx("f6c8c0"), shade=hx("c89ab0"))
	tree_line(bg, 150, hx("6a6a8a"), hx("4a5a6a"), 22, height=12)
	for i, x in enumerate([30, 100, 200, 350]):
		palm(bg, x, 152, 28 + (i % 2) * 8, 0.6 * (-1) ** i, hx("3a4a5a"), hx("2a3a4a"), hx("4a4a5a"), hx("3a3a4a"), 120 + i, 0.8)
	# ruộng xanh hai bên đê
	vgrad(bg, 0, 150, W, H, [hx("6aa84a"), hx("5a9a3e"), hx("4a8a34")])
	rng = random.Random(8)
	for y in range(152, H, 2):
		for x in range(rng.randint(0, 3), W, 3 + (y - 150) // 20):
			px(bg, x, y, hx("7cc05a") if (x + y) % 5 else hx("3f7a2e"))
	# ánh nắng chiều trên nước ruộng
	for i in range(8):
		x = rng.randrange(0, W)
		y = rng.randrange(158, 172)
		line(bg, [(x, y), (x + 12, y)], hx("f8d49a"))
	# bờ đê đất chạy ngang
	poly(bg, [(0, DIKE_Y - 6), (W, DIKE_Y - 10), (W, DIKE_Y + 10), (0, DIKE_Y + 14)], hx("b8905a"))
	poly(bg, [(0, DIKE_Y - 6), (W, DIKE_Y - 10), (W, DIKE_Y - 6), (0, DIKE_Y - 2)], hx("d8b07a"))
	speckle(bg, 0, DIKE_Y - 8, W, DIKE_Y + 12, [hx("6aa84a"), hx("8a6a3a")], 300, 12)
	save(bg, page, "bg")
	# diều sáo (thân + 2 khung)
	k = []
	for f in range(2):
		im = new(30, 26)
		poly(im, [(15, 0), (29, 10), (15, 25), (1, 10)], hx("e83a2a"))
		poly(im, [(15, 0), (29, 10), (15, 12)], hx("f86a4a"))
		poly(im, [(1, 10), (15, 12), (15, 25)], hx("b8281e"))
		line(im, [(15, 0), (15, 25)], hx("f0c040"))
		line(im, [(1, 10), (29, 10)], hx("f0c040"))
		ell(im, 11, 6 + f, 19, 14 + f, hx("f8e040"))
		k.append(outline(im, OUTL))
	save(frames(k), page, "kite")
	bird = []
	for f in range(2):
		im = new(14, 8)
		if f == 0:
			line(im, [(0, 2), (4, 5), (7, 4), (10, 5), (13, 2)], hx("2a2a3a"))
		else:
			line(im, [(0, 6), (4, 4), (7, 4), (10, 4), (13, 6)], hx("2a2a3a"))
		bird.append(im)
	save(frames(bird), page, "bird")
	# trẻ con xem thả diều
	save(npc("teo"), page, "friend")


# ============================================================================ main

PAGES = {}


def page(fn):
	PAGES[fn.__name__.replace("build_", "")] = fn
	return fn


for _fn in [build_ui, build_fish, build_farm, build_site, build_stall, build_boat, build_class, build_temple,
		build_lottery, build_fishing, build_kite]:
	page(_fn)


def preview(dirpath: Path, names):
	dirpath.mkdir(parents=True, exist_ok=True)
	for n in names:
		bgp = OUT / n / "bg.png"
		if bgp.exists():
			im = Image.open(bgp)
			im.resize((W * 2, H * 2), Image.NEAREST).save(dirpath / f"art_{n}.png")


if __name__ == "__main__":
	args = [a for a in sys.argv[1:]]
	prev = None
	if "--preview" in args:
		i = args.index("--preview")
		prev = Path(args[i + 1])
		del args[i:i + 2]
	names = args or list(PAGES.keys())
	for n in names:
		PAGES[n]()
		print("built", n)
	if prev:
		preview(prev, names)
