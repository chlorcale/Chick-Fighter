# -*- coding: utf-8 -*-
"""Người nhà (Mẹ, Ba, em trai) cùng kiểu vẽ với nhân vật chính bản mới – sửa/tô lại từng khung của player_sheet_v2.

Chạy:  python tools/art/build_player.py            (trước, nếu art nhân vật chính đổi)
       python tools/art/build_family.py [--preview DIR]
Ra:    game/art/home/family_me.png, family_cha.png, family_em.png – 20 khung 64×64 nằm ngang, cùng thứ tự/tag/thời
       lượng với player_sheet_v2 (idle 0–3, walk_down 4–7, walk_up 8–11, walk_left 12–15, walk_right 16–19), gốc chân
       (32, 58) như nhân vật chính; bóng dùng chung player_sheet_v2_shadow.png.
       game/art/home/family_*_portrait.png – chân dung bán thân ×4 cho DialogBox.

Cách làm (giữ nguyên tỉ lệ, viền, cách đổ bóng của art gốc – chỉ đổi người):
  * nón lưỡi trai → tóc (hạ đỉnh 1 px, cắt lưỡi trai chìa ra ở khung nhìn ngang, vẽ lại viền);
  * áo caro → áo của từng người (ánh xạ 4 sắc độ của caro sang dải màu mới nên nếp áo/tay áo vẫn đọc được);
  * quần jean (miếng vá) → quần mới; chai nước đỏ cầm tay → vật cầm tay của từng người;
  * chi tiết riêng: Mẹ búi tóc + xấp bài kiểm tra; Ba ria mép, tóc muối tiêu, khăn rằn vắt vai, bình trà;
    em trai thấp hơn (bớt hàng thân + chân), kính cận, khăn quàng đỏ, sách giáo khoa.
Tất định (không ngẫu nhiên).
"""
from __future__ import annotations

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_player as bp  # noqa: E402

ROOT = bp.ROOT
OUT = os.path.join(ROOT, "game", "art", "home")
P = bp.PAL
OL = P["outline"]
CLEAR = (0, 0, 0, 0)
FRAME = bp.FRAME

FRONT = list(range(0, 8))
BACK = list(range(8, 12))
LEFT = list(range(12, 16))
RIGHT = list(range(16, 20))


def facing(i: int) -> str:
	if i in BACK:
		return "back"
	if i in LEFT:
		return "left"
	if i in RIGHT:
		return "right"
	return "front"


def rgb(c):
	return tuple(c[:3])


CAP = {rgb(P[k]) for k in ("cap", "cap_l", "cap_d", "brim", "brim_l", "brim_d")}
SHIRT_KEYS = ("sh_l", "sh", "sh_m", "sh_d", "sh_y", "sh_w")
JEAN_KEYS = ("jean", "jean_l", "jean_m", "jean_d", "jean_w")
BOTTLE_KEYS = ("bottle", "bottle_l", "bottle_d", "bottle_y", "bottle_g", "sh_y2")
SKIN = {rgb(P[k]) for k in ("skin", "skin_l", "skin_d")}


# ============================================================ tiện ích điểm ảnh

def opaque(px, x, y):
	return 0 <= x < FRAME and 0 <= y < FRAME and px[x, y][3] > 0


def is_ol(c):
	return c[3] > 0 and rgb(c) == rgb(OL)


def fix_outline(img):
	"""Bỏ điểm viền mồ côi (không kề điểm đục nào khác viền) rồi viền lại mép lộ ra (chỉ quanh điểm không phải viền)."""
	px = img.load()
	drop = []
	for y in range(FRAME):
		for x in range(FRAME):
			if not is_ol(px[x, y]):
				continue
			keep = False
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if (dx or dy) and opaque(px, nx, ny) and not is_ol(px[nx, ny]):
						keep = True
			if not keep:
				drop.append((x, y))
	for p in drop:
		px[p] = CLEAR
	add = []
	for y in range(FRAME):
		for x in range(FRAME):
			if px[x, y][3] > 0:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if opaque(px, nx, ny) and not is_ol(px[nx, ny]):
					add.append((x, y))
					break
	for p in add:
		px[p] = OL
	return img


def delete_rows(img, rows):
	"""Bớt các hàng (giữ chân đứng yên): phần phía trên mỗi hàng bị bớt dịch xuống 1 px."""
	keep = [y for y in range(FRAME) if y not in set(rows)]
	out = Image.new("RGBA", (FRAME, FRAME), CLEAR)
	pad = FRAME - len(keep)
	for i, y in enumerate(keep):
		out.paste(img.crop((0, y, FRAME, y + 1)), (0, pad + i))
	return out


def shirt_row(img):
	"""Hàng đầu tiên có vải áo (dưới cằm)."""
	px = img.load()
	shirt = {rgb(P[k]) for k in SHIRT_KEYS}
	for y in range(26, FRAME):
		for x in range(FRAME):
			if px[x, y][3] > 0 and rgb(px[x, y]) in shirt:
				return y
	return 33


def neck_span(img):
	"""(x trái, x phải) của da cổ ngay trên hàng áo."""
	px = img.load()
	y = shirt_row(img) - 1
	xs = [x for x in range(FRAME) if px[x, y][3] > 0 and rgb(px[x, y]) in SKIN]
	if not xs:
		return 29, 34
	return min(xs), max(xs)


def body_span(img, y):
	px = img.load()
	xs = [x for x in range(FRAME) if px[x, y][3] > 0]
	return (min(xs), max(xs)) if xs else (24, 40)


def recolor(img, mapping, y0=0, y1=FRAME):
	px = img.load()
	for y in range(y0, y1):
		for x in range(FRAME):
			c = px[x, y]
			if c[3] == 0:
				continue
			n = mapping.get(rgb(c))
			if n is not None:
				px[x, y] = (n[0], n[1], n[2], 255)


def put(img, x, y, c):
	if 0 <= x < FRAME and 0 <= y < FRAME:
		img.putpixel((x, y), (c[0], c[1], c[2], 255))


def rect(img, x0, y0, w, h, c):
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			put(img, x, y, c)


# ============================================================ tóc (thay nón)

def cap_to_hair(img, face, hair, hair_l, hair_d):
	"""Nón → tóc: tô lại màu, cắt lưỡi trai chìa ra (khung ngang), hạ đỉnh đầu 1 px."""
	px = img.load()
	# 1) cắt lưỡi trai chìa ra phía trước mặt ở khung nhìn ngang
	if face in ("left", "right"):
		skin_x = [x for y in range(23, 31) for x in range(FRAME) if px[x, y][3] > 0 and rgb(px[x, y]) in SKIN]
		if skin_x:
			front = max(skin_x) if face == "right" else min(skin_x)
			for y in range(12, 24):
				for x in range(FRAME):
					beyond = x > front if face == "right" else x < front
					if beyond and px[x, y][3] > 0 and (rgb(px[x, y]) in CAP or is_ol(px[x, y])):
						px[x, y] = CLEAR
	# 2) tô màu: thân nón → tóc, gờ sáng → ánh tóc, lưỡi trai (khung thẳng) → mái tóc
	# (gờ sáng của nón thành vệt ngang trên tóc trông như băng đô → tô cùng màu tóc; ánh tóc chỉ giữ ở mái + tóc mai)
	m = {rgb(P["cap"]): hair, rgb(P["cap_l"]): hair, rgb(P["cap_d"]): hair_d, rgb(P["brim"]): hair,
		rgb(P["brim_l"]): hair, rgb(P["brim_d"]): hair, rgb(P["badge"]): hair,
		rgb(P["hair"]): hair, rgb(P["hair_l"]): hair_l}
	brows = [(x, y) for y in range(22, 31) for x in range(FRAME) if px[x, y][3] > 0 and rgb(px[x, y]) == rgb(P["hair_l"])
		and any(opaque(px, x + dx, y + dy) and rgb(px[x + dx, y + dy]) in SKIN for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
	recolor(img, m, 0, 31)
	for p in brows:   # lông mày (ánh tóc sát da mặt) luôn đậm
		px[p] = (hair[0], hair[1], hair[2], 255)
	# 3) hạ đỉnh đầu 1 px (nón cao hơn tóc): xoá điểm đục trên cùng mỗi cột trong vùng đầu
	for x in range(FRAME):
		for y in range(10, 24):
			if px[x, y][3] > 0:
				px[x, y] = CLEAR
				break
	fix_outline(img)


def bun(img, face, hair, hair_l):
	"""Búi tóc của Mẹ: sau gáy (nhìn sau), chỏm sau đầu (nhìn ngang), nhô trên đỉnh (nhìn thẳng)."""
	px = img.load()
	top = min(y for y in range(FRAME) for x in range(FRAME) if px[x, y][3] > 0)
	x0, x1 = body_span(img, top + 3)
	cx = (x0 + x1) // 2
	if face == "front":
		rect(img, cx - 2, top - 2, 5, 3, hair)
		put(img, cx - 1, top - 2, hair_l)
	elif face == "back":
		rect(img, cx - 3, top + 7, 7, 5, hair)
		rect(img, cx - 2, top + 6, 5, 7, hair)
		put(img, cx - 1, top + 7, hair_l)
		put(img, cx, top + 7, hair_l)
		rect(img, cx - 3, top + 9, 7, 1, (hair[0] + 30, hair[1] + 20, hair[2] + 26))   # dây buộc tóc
	else:
		hx0, hx1 = body_span(img, top + 5)
		bx = hx0 - 2 if face == "right" else hx1 - 2
		rect(img, bx, top + 4, 5, 5, hair)
		rect(img, bx + 1, top + 3, 3, 7, hair)
		put(img, bx + 2, top + 4, hair_l)
	fix_outline(img)


# ============================================================ mặt

def mouth_pixels(img):
	px = img.load()
	return [(x, y) for y in range(24, 33) for x in range(FRAME)
		if px[x, y][3] > 0 and rgb(px[x, y]) == rgb(P["nose"])]


def mustache(img, color):
	for x, y in mouth_pixels(img):
		put(img, x, y - 1, color)
		put(img, x - 1, y - 1, color) if img.getpixel((x - 1, y - 1))[3] > 0 and rgb(img.getpixel((x - 1, y - 1))) in SKIN else None
		put(img, x + 1, y - 1, color) if img.getpixel((x + 1, y - 1))[3] > 0 and rgb(img.getpixel((x + 1, y - 1))) in SKIN else None


def glasses(img, face, frame_c):
	"""Kính cận: gọng mảnh ôm từng mắt (lòng kính giữ nguyên mặt/mắt), cầu kính; nhìn ngang thêm càng kính về tai."""
	px = img.load()
	eye = rgb(P["eye"])
	pts = [(x, y) for y in range(23, 31) for x in range(FRAME) if px[x, y][3] > 0 and rgb(px[x, y]) == eye]
	if not pts:
		return
	cols = sorted({x for x, _y in pts})
	groups = []
	for x in cols:
		if groups and x - groups[-1][-1] <= 1:
			groups[-1].append(x)
		else:
			groups.append([x])
	ys = [y for _x, y in pts]
	top, bot = min(ys) - 1, max(ys) + 1
	boxes = []
	for g in groups:
		bx0, bx1 = min(g) - 1, max(g) + 1
		boxes.append((bx0, bx1))
		# gọng bo góc (góc để trống) cho nhẹ mặt – không thành kính râm
		for x in range(bx0 + 1, bx1):
			put(img, x, top, frame_c)
			put(img, x, bot, frame_c)
		for y in range(top + 1, bot):
			put(img, bx0, y, frame_c)
			put(img, bx1, y, frame_c)
	if len(boxes) >= 2:
		for x in range(boxes[0][1] + 1, boxes[1][0]):
			put(img, x, top + 1, frame_c)
	if face in ("left", "right"):
		bx0, bx1 = boxes[0]
		step = -1 if face == "right" else 1
		x = bx0 - 1 if face == "right" else bx1 + 1
		for _k in range(6):
			c = px[x, top + 1] if 0 <= x < FRAME else CLEAR
			if c[3] == 0 or rgb(c) not in SKIN:
				break
			put(img, x, top + 1, frame_c)
			x += step


# ============================================================ áo / quần / vật cầm tay

def mix(a, b, t):
	return tuple(int(round(a[k] + (b[k] - a[k]) * t)) for k in range(3))


def shirt_map(base, light, shade, dark, button, check=0.35):
	"""4 sắc độ caro → dải màu mới, nén tương phản ô caro (sh_m chỉ đậm hơn nền một chút = vải trơn có nếp) còn
	sh_d (đường tách tay áo/thân/nếp) giữ đậm; chỉ vàng của caro hoà vào nền, chỉ trắng → màu nút áo."""
	return {
		rgb(P["sh_l"]): light, rgb(P["sh"]): base, rgb(P["sh_m"]): mix(base, shade, check), rgb(P["sh_d"]): shade,
		rgb(P["sh_y"]): base, rgb(P["sh_w"]): button,
	}


def pants_map(base, light, mid, dark):
	return {rgb(P["jean"]): base, rgb(P["jean_l"]): light, rgb(P["jean_m"]): mid, rgb(P["jean_d"]): dark,
		rgb(P["jean_w"]): base, rgb(P["bottle_g"]): base, rgb(P["badge"]): base}


def item_map(body, light, dark, cap):
	return {rgb(P["bottle"]): body, rgb(P["bottle_l"]): light, rgb(P["bottle_d"]): dark,
		rgb(P["bottle_y"]): cap, rgb(P["bottle_g"]): cap, rgb(P["sh_y2"]): cap}


def recolor_clothes(img, shirt, pants, item):
	px = img.load()
	jean = {rgb(P[k]) for k in JEAN_KEYS}
	for y in range(FRAME):
		for x in range(FRAME):
			c = px[x, y]
			if c[3] == 0:
				continue
			k = rgb(c)
			n = None
			# miếng vá vàng của quần trùng màu nắp chai → phân biệt theo điểm kề là vải jean
			patch = k in (rgb(P["bottle_g"]), rgb(P["badge"])) and y >= 44 and any(
				opaque(px, x + dx, y + dy) and rgb(px[x + dx, y + dy]) in jean for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
			if patch or (k in jean and y >= 44):
				n = pants.get(k)
			elif k in item:
				n = item[k]
			elif y >= 31 and k in shirt:
				n = shirt[k]
			if n is not None:
				px[x, y] = (n[0], n[1], n[2], 255)


# ============================================================ phụ kiện

def scarf_red(img, face):
	"""Khăn quàng đỏ (học sinh): nút thắt dưới cổ + hai vạt (nhìn thẳng), tam giác sau lưng (nhìn sau)."""
	red, red_d, red_l = (214, 44, 44), (150, 26, 34), (240, 96, 84)
	y = shirt_row(img)
	nx0, nx1 = neck_span(img)
	cx = (nx0 + nx1) // 2
	if face == "front":
		rect(img, nx0 - 1, y, nx1 - nx0 + 3, 1, red)
		rect(img, cx - 1, y + 1, 3, 1, red_d)
		put(img, cx, y + 1, red_l)
		put(img, cx - 1, y + 2, red)
		put(img, cx + 1, y + 2, red)
		put(img, cx - 2, y + 3, red_d)
		put(img, cx + 2, y + 3, red_d)
	elif face == "back":
		rect(img, nx0 - 1, y, nx1 - nx0 + 3, 1, red)
		rect(img, cx - 2, y + 1, 5, 1, red)
		rect(img, cx - 1, y + 2, 3, 1, red_d)
		put(img, cx, y + 3, red_d)
	else:
		rect(img, nx0, y, nx1 - nx0 + 1, 1, red)
		fx = nx1 + 1 if face == "right" else nx0 - 1
		put(img, fx, y, red)
		put(img, fx, y + 1, red_d)
		put(img, fx, y + 2, red_d)


def khan_ran(img, face):
	"""Khăn rằn (ca rô đen trắng) quàng cổ, một vạt thả trước ngực bên trái."""
	k, w = (40, 36, 46), (226, 222, 208)
	y = shirt_row(img)
	nx0, nx1 = neck_span(img)

	def chk(x, yy):
		return k if (x + yy) % 2 == 0 else w

	if face in ("front", "back"):
		for x in range(nx0 - 2, nx1 + 3):
			put(img, x, y, chk(x, y))
			put(img, x, y - 1, chk(x, y - 1)) if x in (nx0 - 2, nx1 + 2) else None
		if face == "front":
			hx = nx0 - 2
			for yy in range(y + 1, y + 7):
				put(img, hx, yy, chk(hx, yy))
				put(img, hx + 1, yy, chk(hx + 1, yy))
			put(img, hx, y + 7, w)
			put(img, hx + 1, y + 7, k)
	else:
		for x in range(nx0 - 1, nx1 + 2):
			put(img, x, y, chk(x, y))
		fx = nx1 + 1 if face == "right" else nx0 - 2
		for yy in range(y + 1, y + 6):
			put(img, fx, yy, chk(fx, yy))
			put(img, fx + 1, yy, chk(fx + 1, yy))


# ============================================================ từng người

MEMBERS = {
	"me": {
		"name": "Mẹ",
		"hair": ((34, 26, 32), (70, 56, 64), (22, 16, 22)),
		# áo bà ba tím hoa cà
		"shirt": shirt_map((176, 134, 200), (206, 172, 224), (140, 100, 170), (104, 70, 134), (246, 236, 250)),
		# quần lãnh đen
		"pants": pants_map((52, 48, 64), (88, 84, 106), (40, 36, 50), (28, 24, 36)),
		# xấp bài kiểm tra (giấy trắng, lề đỏ)
		"item": item_map((238, 232, 214), (255, 252, 240), (190, 182, 164), (214, 60, 56)),
		"rows": [40, 50],
	},
	"cha": {
		"name": "Ba",
		"hair": ((40, 34, 36), (128, 122, 126), (26, 22, 26)),     # tóc muối tiêu (ánh xám)
		# áo sơ mi xanh lá cũ, mặc thoải mái
		"shirt": shirt_map((104, 150, 92), (140, 184, 118), (76, 116, 70), (52, 84, 54), (226, 220, 196)),
		# quần tây kaki
		"pants": pants_map((150, 120, 86), (186, 158, 116), (120, 94, 66), (88, 66, 46)),
		# bình trà giữ nhiệt
		"item": item_map((70, 120, 150), (120, 170, 196), (44, 80, 108), (200, 200, 206)),
		"rows": [],
	},
	"em": {
		"name": "Em trai",
		"hair": ((30, 22, 28), (66, 52, 60), (18, 12, 18)),
		# áo sơ mi trắng đồng phục
		"shirt": shirt_map((236, 236, 232), (252, 252, 250), (206, 210, 220), (164, 170, 190), (200, 204, 216)),
		# quần xanh đen đồng phục
		"pants": pants_map((52, 66, 112), (84, 102, 156), (40, 50, 90), (28, 36, 66)),
		# sách giáo khoa bìa xanh
		"item": item_map((70, 120, 196), (130, 172, 232), (40, 70, 130), (240, 236, 220)),
		"rows": [37, 41, 47, 49, 51],
	},
}


def make_member(who, frames):
	cfg = MEMBERS[who]
	out = []
	for i, src in enumerate(frames):
		f = facing(i)
		img = src.copy()
		hair, hair_l, hair_d = cfg["hair"]
		recolor_clothes(img, cfg["shirt"], cfg["pants"], cfg["item"])
		cap_to_hair(img, f, hair, hair_l, hair_d)
		if who == "me":
			bun(img, f, hair, hair_l)
		elif who == "cha":
			if f != "back":
				mustache(img, hair)
			khan_ran(img, f)
		elif who == "em":
			if f != "back":
				glasses(img, f, (92, 90, 112))
			scarf_red(img, f)
		if cfg["rows"]:
			img = delete_rows(img, cfg["rows"])
		fix_outline(img)
		out.append(img)
	return out


def strip(frames):
	return bp.strip(frames)


def main(argv):
	preview = None
	if "--preview" in argv:
		preview = argv[argv.index("--preview") + 1]
	frames, shadows, meta = bp.load_frames()
	os.makedirs(OUT, exist_ok=True)
	sheets = {}
	for who in MEMBERS:
		fr = make_member(who, frames)
		sheets[who] = fr
		strip(fr).save(os.path.join(OUT, "family_%s.png" % who))
		bp.build_portrait(fr[0]).save(os.path.join(OUT, "family_%s_portrait.png" % who))
	print("family: %s (20 frames 64x64 each)" % ", ".join("family_%s.png" % w for w in MEMBERS))
	if preview:
		os.makedirs(preview, exist_ok=True)
		bg = (110, 150, 100, 255)
		rows = [("hero", frames)] + [(w, sheets[w]) for w in MEMBERS]
		sheet = Image.new("RGBA", (FRAME * 20, FRAME * len(rows)), bg)
		for r, (_w, fr) in enumerate(rows):
			for j, f in enumerate(fr):
				sheet.alpha_composite(shadows[j], (j * FRAME, r * FRAME))
				sheet.alpha_composite(f, (j * FRAME, r * FRAME))
		sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(preview, "pv_family_all.png"))
		# ×6: cả nhà đứng cạnh nhau (nhìn thẳng, nhìn ngang, nhìn sau)
		line = Image.new("RGBA", (34 * 12, 50), bg)
		x = 0
		for j in (0, 17, 9):
			for _w, fr in rows:
				cell = Image.new("RGBA", (FRAME, FRAME), CLEAR)
				cell.alpha_composite(shadows[j])
				cell.alpha_composite(fr[j])
				line.alpha_composite(cell.crop((15, 10, 49, 60)), (x, 0))
				x += 34
		line.resize((line.width * 6, line.height * 6), Image.NEAREST).save(os.path.join(preview, "pv_family_x6.png"))


if __name__ == "__main__":
	main(sys.argv[1:])
