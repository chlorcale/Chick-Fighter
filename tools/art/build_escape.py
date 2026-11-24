# -*- coding: utf-8 -*-
"""Sinh ảnh cho mini-game TẨU THOÁT (gọi tay trong) + cắt cảnh rửa chén.

Chạy:  python tools/art/build_escape.py [thư_mục_xem_trước]
Ra:    game/art/escape/hero_noi.png, hero_dongtao.png  – nhân vật chính nhìn ngang (chạy/nhảy/trượt/té/lặn/bơi)
                                                         ôm gà dưới nách (bơi: gà ngồi trên đầu)
       game/art/escape/hero_back.png                   – nhìn sau lưng: rửa chén (3 khung), chỉ tay, đứng
       game/art/escape/police.png                      – hai chú công an (cao gầy / thấp mập), kiểu NPC của game
       game/art/escape/rooster_small.png               – gà nhỏ (nòi/tre, Đông Tảo): ngồi, chớp mắt, kêu
       game/art/escape/props.png                       – đồ vật cắt từ bản đồ (game/art/map/map_atlas_*.png)
       game/escape/escape_sheets.gd                    – bảng toạ độ khung hình (TỰ SINH, đừng sửa tay)

Nguồn: game/art/player_sheet_v2.png (nhân vật chính bản mới, khung 64×64: walk_right chụm chân = 17, walk_up chụm
chân = 9 – chạy tools/art/build_player.py trước), rooster_sheet.png / dongtao_sheet.png (ô 128×112, khung 0 = idle),
bản đồ cũ map_layers.json (chỉ đọc).
Art mới đã đúng cỡ NPC (~43 px) nên dựng thẳng ở ×1 (không thu nhỏ), giữ viền của art; công an/gà viền màu viền bản
đồ (42,30,46) như NPC → trong game vẽ ×1, đúng lưới pixel.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_player as bp  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "game", "art")
OUT = os.path.join(ART, "escape")
SHEETS_GD = os.path.join(ROOT, "game", "escape", "escape_sheets.gd")
OUTLINE = (42, 30, 46, 255)
CLEAR = (0, 0, 0, 0)

# Bảng màu nhân vật chính (lấy từ player_sheet_v2.png).
SKIN = bp.PAL["skin"]
SKIN_D = bp.PAL["skin_d"]
SHIRT = bp.PAL["sh"]
SHIRT_D = bp.PAL["sh_d"]
SHIRT_DD = (58, 18, 32, 255)
SHIRT_M = bp.PAL["sh_m"]
JEAN = bp.PAL["jean"]
JEAN_D = bp.PAL["jean_m"]
JEAN_DD = bp.PAL["jean_d"]
JEAN_L = bp.PAL["jean_l"]
SANDAL = bp.PAL["shoe"]
SANDAL_L = bp.PAL["shoe_l"]

HERO_CELL = 56
HERO_FOOT_Y = 54
HERO_FOOT_X = 28


# ============================================================ tiện ích

def outline(img, color=OUTLINE):
	"""Viền 1 px (4 hướng) quanh pixel đục; giữ nguyên kích thước."""
	src = img.load()
	out = img.copy()
	dst = out.load()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			if src[x, y][3] >= 128:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, ny = x + dx, y + dy
				if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] >= 128 and src[nx, ny] != color:
					dst[x, y] = color
					break
	return out


def put(img, x, y, color):
	if 0 <= x < img.width and 0 <= y < img.height:
		img.putpixel((int(x), int(y)), color)


def rect(img, x0, y0, w, h, color):
	for y in range(int(y0), int(y0 + h)):
		for x in range(int(x0), int(x0 + w)):
			put(img, x, y, color)


def line(img, a, b, color, width=1):
	"""Đường thẳng pixel (Bresenham) dày `width` (thêm pixel về phía dưới/phải)."""
	(x0, y0), (x1, y1) = a, b
	dx, dy = abs(x1 - x0), -abs(y1 - y0)
	sx = 1 if x0 < x1 else -1
	sy = 1 if y0 < y1 else -1
	err = dx + dy
	while True:
		for k in range(width):
			for j in range(width):
				put(img, x0 + k, y0 + j, color)
		if x0 == x1 and y0 == y1:
			break
		e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


def bbox_bottom(img):
	box = img.getbbox()
	return box[3] if box else img.height


def strip(frames):
	w = sum(f.width for f in frames)
	h = max(f.height for f in frames)
	out = Image.new("RGBA", (w, h), CLEAR)
	x = 0
	for f in frames:
		out.alpha_composite(f, (x, 0))
		x += f.width
	return out


def save(img, name):
	os.makedirs(OUT, exist_ok=True)
	path = os.path.join(OUT, name)
	img.save(path)
	return path


# ============================================================ gà nhỏ (vẽ tay theo bảng màu gà đá trong game)

## Gà trống quay phải, 14×12. Ký hiệu: T/t đuôi (đậm/ánh), B/b thân (sáng/tối), w cánh, N/n bờm cổ (cam/kem),
## H đầu, C mào, E mắt, K mỏ, W tích (yếm), L chân. Bảng màu lấy từ rooster_sheet.png / dongtao_sheet.png.
## Đuôi: lông đuôi đen ánh xanh có MỘT vệt bóng cong liền (t) – bản cũ xen kẽ T/t thành ô cờ, nhìn ở 1× như đuôi bị
## vỡ/lủng lỗ.
ROOSTER_MAP = [
	".T........C.C.",
	"TtT......CCCC.",
	"TttT....NHHHH.",
	".TttT..NNHEHKK",
	"..TtTBBNNHHW..",
	"..TTBBBBNnNW..",
	"..TBBwwwBNn...",
	"...BBwwwwBB...",
	"....BbbbbB....",
	".....bbbb.....",
	".....L..L.....",
	"....LL.LL.....",
]
ROOSTER_PALETTES = {
	"noi": {"T": (27, 44, 66), "t": (62, 112, 140), "B": (194, 54, 54), "b": (136, 33, 52), "w": (90, 29, 49),
		"N": (232, 112, 51), "n": (252, 217, 175), "H": (194, 54, 54), "C": (230, 52, 52), "E": (9, 7, 12),
		"K": (246, 200, 80), "W": (220, 44, 50), "L": (237, 167, 97)},
	"dongtao": {"T": (52, 36, 30), "t": (110, 70, 44), "B": (206, 122, 70), "b": (150, 82, 52), "w": (120, 62, 40),
		"N": (232, 150, 80), "n": (248, 206, 150), "H": (214, 84, 70), "C": (226, 48, 52), "E": (9, 7, 12),
		"K": (246, 200, 80), "W": (220, 44, 50), "L": (236, 150, 140)},
}


def draw_rooster(palette, blink=False):
	h = len(ROOSTER_MAP)
	w = len(ROOSTER_MAP[0])
	img = Image.new("RGBA", (w, h), CLEAR)
	for y, row in enumerate(ROOSTER_MAP):
		for x, ch in enumerate(row):
			if ch == ".":
				continue
			if ch == "E" and blink:
				ch = "H"
			img.putpixel((x, y), palette[ch] + (255,))
	if palette is ROOSTER_PALETTES["dongtao"]:
		# Đông Tảo: chân to xù (đặc sản), đuôi ngắn hơn.
		for x in (4, 5, 7, 8):
			img.putpixel((x, 10), palette["L"] + (255,))
		img.putpixel((0, 2), CLEAR)
		img.putpixel((0, 3), CLEAR)
	return img


def rooster_variants():
	"""{biến thể: {"sit": ảnh, "blink": ảnh}} – ảnh chưa viền, quay phải."""
	res = {}
	for key, pal in ROOSTER_PALETTES.items():
		res[key] = {"sit": draw_rooster(pal), "blink": draw_rooster(pal, True)}
	return res


# ============================================================ nhân vật chính

## Nhân vật chính bản mới (player_sheet_v2.png) đã đúng cỡ NPC → dựng thẳng ở độ phân giải gốc (×1, không thu nhỏ),
## giữ viền của art (HERO_OL). Thân trên cắt từ khung đi bộ, chân chạy/nhảy vẽ lại bằng bảng màu art.
HERO_OL = bp.PAL["outline"]
F_SIDE = 17          # walk_right chụm chân (nhìn phải)
F_BACK = 9           # walk_up chụm chân (nhìn sau)
HIP_Y = 45           # hàng thắt lưng / đầu quần trong khung 64
BODY_X = 31          # x giữa thân (khung nhìn ngang) → đặt vào HERO_FOOT_X của ô
BOTTLE_COLORS = {bp.PAL[k][:3] for k in ("bottle", "bottle_l", "bottle_d", "bottle_y", "bottle_g", "sh_y2")}
SHIRT_COLORS = {bp.PAL[k][:3] for k in ("sh_l", "sh", "sh_m", "sh_d", "sh_y", "sh_w")}


def hero_outline(img, color=None):
	"""Viền lại sau khi sửa: bỏ điểm viền mồ côi, thêm viền quanh điểm đục KHÔNG phải viền (không viền chồng 2 lớp)."""
	color = color or HERO_OL
	w, h = img.size
	px = img.load()

	def ol(c):
		return c[3] > 0 and c[:3] == color[:3]

	def solid(x, y):
		return 0 <= x < w and 0 <= y < h and px[x, y][3] > 0 and not ol(px[x, y])

	drop = [(x, y) for y in range(h) for x in range(w) if ol(px[x, y])
		and not any(solid(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)]
	for p in drop:
		px[p] = CLEAR
	add = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0
		and any(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
	for p in add:
		px[p] = color
	return img


def player_frame(index):
	frames, _sh, _meta = bp.load_frames()
	return frames[index].copy()


def cloth_at(frame, x, y):
	"""Vải áo caro lấy mẫu từ lưng áo (khung nhìn sau) – lặp theo ô 12×8."""
	back = player_frame(F_BACK)
	return back.getpixel((25 + x % 12, 34 + y % 8))


def hero_upper():
	"""Đầu + thân (hàng 0..HIP_Y) của khung nhìn phải, bỏ chai nước đỏ + bàn tay cầm chai (thay bằng vải áo)."""
	f = player_frame(F_SIDE)
	up = Image.new("RGBA", (64, 64), CLEAR)
	up.alpha_composite(f.crop((0, 0, 64, HIP_Y)), (0, 0))
	px = up.load()
	# thân áo (không tính chai) – cột trái nhất..phải nhất của vải áo ở mỗi hàng
	for y in range(31, HIP_Y):
		row = [x for x in range(64) if px[x, y][3] > 0 and px[x, y][:3] in SHIRT_COLORS]
		for x in range(64):
			c = px[x, y]
			if c[3] > 0 and (c[:3] in BOTTLE_COLORS or (c[:3] in (bp.PAL["skin"][:3], bp.PAL["skin_d"][:3], bp.PAL["skin_l"][:3]) and y > 34)):
				px[x, y] = CLEAR
		row = [x for x in range(64) if px[x, y][3] > 0 and not (px[x, y][:3] == HERO_OL[:3])]
		if row:
			x0, x1 = min(row), max(row)
			for x in range(x0, min(x1 + 1, 36)):
				if px[x, y][3] == 0 or px[x, y][:3] == HERO_OL[:3]:
					px[x, y] = cloth_at(f, x, y)
	# vạt áo dưới cùng sẫm như đường thắt lưng
	for x in range(26, 36):
		if px[x, HIP_Y - 1][3] > 0:
			px[x, HIP_Y - 1] = SHIRT_D
	# bỏ hết viền cũ ở phía trước thân (cột > 33, hàng thân) để viền lại gọn
	for y in range(33, HIP_Y):
		for x in range(34, 64):
			if px[x, y][3] > 0 and px[x, y][:3] == HERO_OL[:3]:
				px[x, y] = CLEAR
	return up


def draw_leg(img, hip, knee, foot, near):
	main, shade = (JEAN, JEAN_D) if near else (JEAN_D, JEAN_DD)
	line(img, hip, knee, main, 3)
	line(img, knee, foot, main, 3)
	line(img, (hip[0] + 1, hip[1] + 1), (knee[0] + 1, knee[1] + 1), shade, 1)
	# bàn chân mang dép (như art): mu bàn chân da + đế tối, mũi chân quay phải
	fx, fy = foot
	rect(img, fx - 1, fy, 5, 1, SKIN_D)
	rect(img, fx - 1, fy + 1, 6, 1, SANDAL if near else SANDAL_L)


def hero_body(pose):
	"""pose: (knee_near, foot_near, knee_far, foot_far, back_hand | None, body_dy) – toạ độ khung 64 gốc."""
	kn, fn, kf, ff, hand, dy = pose
	img = Image.new("RGBA", (64, 64), CLEAR)
	if hand is not None:
		line(img, (29, 35 + dy), (hand[0], hand[1] + dy), SHIRT_D, 3)
		rect(img, hand[0] - 1, hand[1] + dy, 2, 2, SKIN_D)
	draw_leg(img, (29, HIP_Y + dy), (kf[0], kf[1] + dy), (ff[0], ff[1]), False)
	up = hero_upper()
	img.alpha_composite(up, (0, dy)) if dy >= 0 else img.paste(up.crop((0, -dy, 64, 64)), (0, 0), up.crop((0, -dy, 64, 64)))
	rect(img, 27, HIP_Y + dy, 9, 2, JEAN)          # đũng quần
	rect(img, 27, HIP_Y + dy, 9, 1, JEAN_D)        # lưng quần
	draw_leg(img, (32, HIP_Y + 1 + dy), (kn[0], kn[1] + dy), (fn[0], fn[1]), True)
	return hero_outline(img)


HERO_POSES = {
	"run0": ((37, 50), (40, 55), (27, 51), (23, 54), (23, 40), 0),
	"run1": ((33, 51), (33, 56), (36, 49), (35, 53), (25, 41), 0),
	"run2": ((29, 51), (25, 55), (36, 50), (40, 55), None, 0),
	"run3": ((36, 49), (35, 53), (31, 51), (31, 56), None, 0),
	"jump": ((37, 48), (34, 52), (35, 49), (31, 53), (24, 36), 0),
	"fall": ((35, 50), (36, 55), (30, 51), (28, 55), (25, 38), 0),
	"stand": ((33, 51), (33, 56), (30, 51), (29, 56), None, 0),
}


def shrink(img):
	"""Art mới đã cùng cỡ NPC: không thu nhỏ nữa (giữ tên hàm cho các bước sau)."""
	return img


def tuck_rooster(small, rooster, dy):
	"""Gà ôm trước bụng: cẳng tay đỡ dưới bụng gà (vẽ trước), gà nằm trên tay, đầu thò ra phía trước."""
	ox = 25
	oy = 33 + dy
	rw, rh = rooster.size
	arm = Image.new("RGBA", small.size, CLEAR)
	belly = oy + rh - 2                      # ngang bụng/chân gà
	line(arm, (30, 35 + dy), (30, belly), SHIRT_D, 3)
	line(arm, (30, belly), (ox + rw - 3, belly), SHIRT, 3)
	line(arm, (31, belly + 1), (ox + rw - 3, belly + 1), SHIRT_D, 1)
	rect(arm, ox + rw - 2, belly - 1, 2, 3, SKIN)
	put(arm, ox + rw - 1, belly + 1, SKIN_D)
	small.alpha_composite(arm)
	small = hero_outline(small)
	pad = Image.new("RGBA", (rw + 2, rh + 2), CLEAR)
	pad.alpha_composite(rooster, (1, 1))
	small.alpha_composite(outline(pad, HERO_OL), (ox - 1, oy - 1))
	return small


def place(img, bottom):
	cell = Image.new("RGBA", (HERO_CELL, HERO_CELL), CLEAR)
	cell.alpha_composite(img, (HERO_FOOT_X - BODY_X, HERO_FOOT_Y - bottom))
	return cell


def hero_frames(rooster):
	frames = {}
	for key in ("run0", "run1", "run2", "run3", "jump", "fall", "stand"):
		body = hero_body(HERO_POSES[key])
		dy = HERO_POSES[key][5]
		frames[key] = tuck_rooster(shrink(body), rooster, dy)
	cells = {}
	# Khung chạm đất: chân thấp nhất ở HERO_FOOT_Y. Khung trên không: theo thân như khung đứng.
	stand_bottom = bbox_bottom(frames["stand"])
	for key, small in frames.items():
		bottom = stand_bottom if key in ("jump", "fall") else bbox_bottom(small)
		cells[key] = place(small, bottom)
	# Trượt (nằm ngửa, chân trước) / lặn: xoay khung đứng 90°.
	base = place(frames["stand"], stand_bottom)
	for key, angle in (("slide", 90), ("dive", -90)):
		rot = base.rotate(angle, resample=Image.NEAREST, expand=False)
		box = rot.getbbox()
		cell = Image.new("RGBA", (HERO_CELL, HERO_CELL), CLEAR)
		content = rot.crop(box)
		cell.alpha_composite(content, (HERO_FOOT_X - content.width // 2, HERO_FOOT_Y - content.height))
		cells[key] = cell
	# Té: nghiêng tới trước ~25°.
	run2 = place(frames["run2"], bbox_bottom(frames["run2"]))
	rot = run2.rotate(-26, resample=Image.NEAREST, center=(HERO_FOOT_X, HERO_FOOT_Y))
	box = rot.getbbox()
	cell = Image.new("RGBA", (HERO_CELL, HERO_CELL), CLEAR)
	cell.alpha_composite(rot.crop(box), (box[0], HERO_FOOT_Y - (box[3] - box[1])))
	cells["stumble"] = hero_outline(cell)
	return cells


def swim_frames(rooster):
	"""Bơi: đầu + vai trên mặt nước (mép dưới ảnh = mặt nước ở HERO_FOOT_Y), gà ngồi chễm chệ trên đầu."""
	up = hero_upper()
	box = up.getbbox()
	head_top = box[1]
	water = 38                         # mặt nước cắt ngang ngực (vai ở hàng ~33)
	cells = []
	arms = [((29, 35), (37, 29)), ((29, 35), (39, 38)), None, ((29, 35), (19, 30))]
	for k, arm in enumerate(arms):
		img = Image.new("RGBA", (64, 64), CLEAR)
		if arm is not None and k == 3:
			line(img, arm[0], arm[1], SHIRT_D, 3)
			rect(img, arm[1][0] - 1, arm[1][1] - 1, 2, 2, SKIN_D)
		img.alpha_composite(up.crop((0, 0, 64, water)), (0, 0))
		if arm is not None and k != 3:
			line(img, arm[0], arm[1], SHIRT, 3)
			line(img, (arm[0][0], arm[0][1] + 1), (arm[1][0], arm[1][1] + 1), SHIRT_D, 1)
			rect(img, arm[1][0], arm[1][1] - 1, 2, 2, SKIN)
		img = img.crop((0, 0, 64, water))
		body = Image.new("RGBA", (64, water + 1), CLEAR)
		body.alpha_composite(img)
		body = hero_outline(body)
		body = body.crop((0, 0, 64, water))
		rw, rh = rooster.size
		bob = 1 if k % 2 == 1 else 0
		cell = Image.new("RGBA", (HERO_CELL, HERO_CELL), CLEAR)
		cell.alpha_composite(body, (HERO_FOOT_X - BODY_X, HERO_FOOT_Y - water))
		top = HERO_FOOT_Y - water + head_top
		cell.alpha_composite(outline(rooster, HERO_OL), (HERO_FOOT_X - rw // 2 - 1, top - rh + 3 + bob))
		cells.append(cell)
	return cells


def hero_back_frames():
	"""Nhìn sau lưng (walk_up chụm chân): bỏ chai nước; khuỷu tay rửa chén (3 khung), chỉ tay, đứng."""
	f = player_frame(F_BACK)
	base = f.copy()
	px = base.load()
	jean = {bp.PAL[k][:3] for k in ("jean", "jean_m")}
	for y in range(30, 58):
		for x in range(64):
			c = px[x, y]
			if c[3] > 0 and c[:3] in BOTTLE_COLORS:
				px[x, y] = CLEAR
	# tay phải (bên phải ảnh) đang cầm chai: vá lại bằng vải áo / bàn tay buông
	hero_outline(base)
	bx = base.getbbox()
	cx = (bx[0] + bx[2]) // 2
	frames = {}
	poses = {"wash0": (0, 0), "wash1": (-2, 1), "wash2": (1, -2), "stand": None, "point": "point"}
	l_x, r_x = bx[0] + 1, bx[2] - 2     # mép ngoài hai tay áo
	for key, pose in poses.items():
		img = base.copy()
		if pose == "point":
			# tay phải duỗi ngang chỉ ra cửa sau (bên phải), không quay lại
			rect(img, r_x, 36, 10, 3, SHIRT)
			rect(img, r_x, 38, 10, 1, SHIRT_D)
			rect(img, r_x + 3, 36, 1, 3, SHIRT_D)
			rect(img, r_x + 10, 36, 3, 2, SKIN)
			rect(img, r_x + 13, 36, 2, 1, SKIN)
			rect(img, r_x + 10, 37, 3, 1, SKIN_D)
		elif pose is not None:
			ly, ry = pose
			# khuỷu tay chìa ra hai bên, nhúc nhích lên xuống khi kỳ cọ
			rect(img, l_x - 2, 38 + ly, 3, 3, SHIRT_D)
			rect(img, l_x - 3, 39 + ly, 2, 2, SHIRT_DD)
			rect(img, r_x, 38 + ry, 3, 3, SHIRT_D)
			rect(img, r_x + 2, 39 + ry, 2, 2, SHIRT_DD)
		img = hero_outline(img)
		cell = Image.new("RGBA", (HERO_CELL, HERO_CELL), CLEAR)
		cell.alpha_composite(img, (HERO_FOOT_X - cx, HERO_FOOT_Y - bbox_bottom(img)))
		frames[key] = cell
	return frames


# ============================================================ công an (kiểu NPC của game)

POL = {
	"green": (104, 126, 70, 255), "green_d": (78, 96, 54, 255), "green_l": (132, 154, 88, 255),
	"pants": (66, 80, 50, 255), "pants_d": (50, 60, 40, 255),
	"cap": (98, 120, 66, 255), "cap_d": (64, 80, 46, 255), "visor": (30, 22, 38, 255), "pipe": (214, 186, 92, 255),
	"skin": (220, 170, 104, 255), "skin_d": (182, 124, 70, 255), "eye": (30, 22, 38, 255), "mouth": (142, 86, 54, 255),
	"hair": (42, 30, 46, 255), "whistle": (206, 210, 220, 255), "whistle_d": (140, 146, 160, 255),
	"cord": (230, 200, 80, 255), "belt": (59, 42, 58, 255), "buckle": (246, 212, 74, 255), "shoe": (30, 22, 38, 255),
	"paper": (247, 237, 196, 255), "book": (70, 92, 150, 255), "stache": (59, 42, 58, 255), "blush": (226, 120, 100, 255),
}
POL_CELL_W = 32
POL_CELL_H = 52
POL_FOOT_Y = 50


def police_front(tall, talk=False, scratch=False):
	c = POL
	img = Image.new("RGBA", (POL_CELL_W, POL_CELL_H), CLEAR)
	if tall:
		hw, x0, top, body_w, leg_len, head_h = 13, 9, 2, 13, 14, 13
	else:
		hw, x0, top, body_w, leg_len, head_h = 15, 8, 10, 17, 9, 13
	cx = 16
	hx = cx - hw // 2
	# Mũ kê-pi: chóp rộng hơn đầu, đai, lưỡi trai đen.
	rect(img, hx - 1, top, hw + 2, 4, c["cap"])
	rect(img, hx - 1, top, hw + 2, 1, c["green_l"])
	rect(img, hx, top + 4, hw, 1, c["cap_d"])
	rect(img, hx, top + 5, hw, 1, c["pipe"])
	rect(img, hx - 1, top + 6, hw + 2, 1, c["visor"])
	# Đầu.
	hy = top + 7
	rect(img, hx, hy, hw, head_h - 2, c["skin"])
	rect(img, hx, hy, hw, 1, c["hair"])
	rect(img, hx - 1, hy + 2, 1, 3, c["skin_d"])
	rect(img, hx + hw, hy + 2, 1, 3, c["skin_d"])
	ey = hy + 3
	put(img, cx - 3, ey, c["eye"])
	put(img, cx + 3, ey, c["eye"])
	put(img, cx - 3, ey - 1, c["hair"]) if not tall else None
	if tall:
		# Ria mép cong.
		rect(img, cx - 2, ey + 4, 5, 1, c["stache"])
		put(img, cx - 3, ey + 5, c["stache"])
		put(img, cx + 3, ey + 5, c["stache"])
	else:
		put(img, cx - 5, ey + 2, c["blush"])
		put(img, cx + 5, ey + 2, c["blush"])
	if talk:
		rect(img, cx - 1, ey + 5 + (0 if tall else 0), 3, 2, c["mouth"])
	else:
		# Còi ngậm miệng + dây đeo.
		rect(img, cx, ey + 5, 3, 2, c["whistle"])
		put(img, cx + 2, ey + 6, c["whistle_d"])
	# Thân áo.
	by = hy + head_h - 2
	bx = cx - body_w // 2
	body_h = 14 if tall else 13
	rect(img, bx, by, body_w, body_h, c["green"])
	rect(img, bx, by, body_w, 1, c["green_d"])
	rect(img, cx - 1, by, 3, 2, c["skin"])          # cổ áo chữ V
	put(img, cx, by + 2, c["skin"])
	rect(img, bx + 2, by + 3, 3, 2, c["green_d"])     # nắp túi
	rect(img, bx + body_w - 5, by + 3, 3, 2, c["green_d"])
	for k in range(3, body_h - 2, 3):
		put(img, cx, by + k, c["green_d"])
	if not talk:
		line(img, (cx - 3, by), (cx, by + 4), c["cord"], 1)
	rect(img, bx, by + body_h - 2, body_w, 2, c["belt"])
	rect(img, cx - 1, by + body_h - 2, 3, 2, c["buckle"])
	# Tay.
	arm_h = body_h - 2
	rect(img, bx - 3, by + 1, 3, arm_h, c["green_d"])
	rect(img, bx - 3, by + 1 + arm_h, 3, 2, c["skin"])
	if scratch:
		# Tay phải gãi đầu (bối rối).
		rect(img, bx + body_w, by - 6, 3, 8, c["green_d"])
		rect(img, bx + body_w - 1, by - 8, 3, 3, c["skin"])
	else:
		rect(img, bx + body_w, by + 1, 3, arm_h, c["green_d"])
		rect(img, bx + body_w, by + 1 + arm_h, 3, 2, c["skin"])
	# Quần + giày.
	ly = by + body_h
	lw = (body_w - 1) // 2
	rect(img, bx, ly, lw, leg_len, c["pants"])
	rect(img, bx + body_w - lw, ly, lw, leg_len, c["pants"])
	rect(img, bx + lw, ly, body_w - 2 * lw, 3, c["pants"])
	rect(img, bx + lw - 1, ly + 3, 1, leg_len - 3, c["pants_d"])
	rect(img, bx - 1, ly + leg_len, lw + 1, 2, c["shoe"])
	rect(img, bx + body_w - lw, ly + leg_len, lw + 1, 2, c["shoe"])
	bottom = ly + leg_len + 2
	cell = Image.new("RGBA", (POL_CELL_W, POL_CELL_H), CLEAR)
	cell.alpha_composite(img, (0, POL_FOOT_Y - bottom))
	return outline(cell)


def police_side(tall, frame, notebook=False):
	"""Nhìn ngang quay phải. frame 0..3 = chạy, 4 = đứng (cầm sổ biên bản nếu notebook)."""
	c = POL
	img = Image.new("RGBA", (POL_CELL_W, POL_CELL_H), CLEAR)
	if tall:
		hw, top, body_w, body_h, leg, head_h = 11, 2, 8, 14, 14, 12
	else:
		hw, top, body_w, body_h, leg, head_h = 12, 10, 12, 13, 9, 12
	cx = 15
	hx = cx - hw // 2
	running = frame < 4
	bob = -1 if running and frame % 2 == 1 else 0
	top += bob
	# Tay sau (khuất sau thân).
	by = top + 7 + head_h - 2
	bx = cx - body_w // 2
	swing = [(-5, 6), (-2, 9), (4, 7), (1, 9)][frame] if running else (0, 10)
	shoulder = (cx - 1, by + 2)
	if running:
		line(img, shoulder, (shoulder[0] - swing[0], shoulder[1] + swing[1] - 2), c["green_d"], 2)
	# Chân (sau trước, trước sau).
	hip_y = by + body_h
	legs = {
		0: (((cx + 4, hip_y + leg // 2), (cx + 6, hip_y + leg)), ((cx - 3, hip_y + leg // 2 + 1), (cx - 7, hip_y + leg - 1))),
		1: (((cx + 1, hip_y + leg // 2 + 1), (cx, hip_y + leg)), ((cx - 1, hip_y + leg // 2), (cx - 4, hip_y + leg - 3))),
		2: (((cx - 3, hip_y + leg // 2 + 1), (cx - 7, hip_y + leg - 1)), ((cx + 4, hip_y + leg // 2), (cx + 6, hip_y + leg))),
		3: (((cx - 1, hip_y + leg // 2), (cx - 3, hip_y + leg - 3)), ((cx + 1, hip_y + leg // 2 + 1), (cx, hip_y + leg))),
		4: (((cx + 1, hip_y + leg // 2), (cx + 1, hip_y + leg)), ((cx - 2, hip_y + leg // 2), (cx - 2, hip_y + leg))),
	}
	near, far = legs[frame if running else 4]
	for (knee, foot), col, shoe in ((far, c["pants_d"], c["shoe"]), (near, c["pants"], c["shoe"])):
		line(img, (cx - 1, hip_y), knee, col, 3)
		line(img, knee, foot, col, 3)
		rect(img, foot[0], foot[1] + 2, 4, 2, shoe)
	# Thân.
	rect(img, bx, by, body_w, body_h, c["green"])
	rect(img, bx, by, 2, body_h, c["green_d"])
	rect(img, bx + body_w - 3, by + 3, 2, 2, c["green_d"])
	rect(img, bx, by + body_h - 2, body_w, 2, c["belt"])
	put(img, bx + body_w - 2, by + body_h - 2, c["buckle"])
	# Đầu (nhìn nghiêng phải) + mũ có lưỡi trai chìa ra trước.
	hy = top + 7
	rect(img, hx - 1, top, hw + 1, 4, c["cap"])
	rect(img, hx - 1, top, hw + 1, 1, c["green_l"])
	rect(img, hx - 1, top + 4, hw + 1, 1, c["cap_d"])
	rect(img, hx - 1, top + 5, hw + 1, 1, c["pipe"])
	rect(img, hx + hw - 2, top + 6, 5, 1, c["visor"])
	rect(img, hx - 1, top + 6, hw - 1, 1, c["cap_d"])
	rect(img, hx, hy, hw, head_h - 2, c["skin"])
	rect(img, hx, hy, 4, 3, c["hair"])
	rect(img, hx + 2, hy + 3, 2, 2, c["skin_d"])          # tai
	put(img, hx + hw - 3, hy + 2, c["eye"])
	put(img, hx + hw, hy + 4, c["skin"])                     # mũi
	if tall:
		rect(img, hx + hw - 4, hy + 6, 4, 1, c["stache"])
	else:
		put(img, hx + hw - 4, hy + 5, c["blush"])
	if running or not notebook:
		# Còi ngậm miệng (má phồng khi thổi).
		rect(img, hx + hw, hy + 6, 3, 2, c["whistle"])
		put(img, hx + hw + 2, hy + 7, c["whistle_d"])
		if running and frame % 2 == 0:
			put(img, hx + hw - 2, hy + 6, c["blush"])
	else:
		put(img, hx + hw - 1, hy + 7, c["mouth"])
	# Tay trước.
	if running:
		line(img, shoulder, (shoulder[0] + swing[0], shoulder[1] + swing[1] - 2), c["green_d"], 2)
		rect(img, shoulder[0] + swing[0], shoulder[1] + swing[1] - 1, 2, 2, c["skin"])
	elif notebook:
		# Cầm sổ biên bản trước ngực, tay kia cầm bút.
		rect(img, cx + 2, by + 3, 6, 7, c["book"])
		rect(img, cx + 3, by + 4, 4, 5, c["paper"])
		rect(img, cx + 4, by + 5, 3, 1, c["green_d"])
		rect(img, cx + 4, by + 7, 2, 1, c["green_d"])
		line(img, shoulder, (cx + 2, by + 8), c["green_d"], 2)
		rect(img, cx + 8, by + 6, 1, 3, c["eye"])
	else:
		rect(img, cx - 1, by + 2, 3, body_h - 4, c["green_d"])
		rect(img, cx - 1, by + body_h - 2, 3, 2, c["skin"])
	bottom = hip_y + leg + 4 - bob
	cell = Image.new("RGBA", (POL_CELL_W, POL_CELL_H), CLEAR)
	cell.alpha_composite(img, (0, POL_FOOT_Y - bottom))
	return outline(cell)


def police_sheet():
	rows = []
	for tall in (True, False):
		frames = [police_side(tall, k) for k in range(4)]
		frames += [police_front(tall), police_front(tall, talk=True), police_front(tall, scratch=True),
			police_side(tall, 4, notebook=True)]
		rows.append(strip(frames))
	out = Image.new("RGBA", (rows[0].width, POL_CELL_H * 2), CLEAR)
	out.alpha_composite(rows[0], (0, 0))
	out.alpha_composite(rows[1], (0, POL_CELL_H))
	return out


# ============================================================ đồ vật từ bản đồ

def map_nodes():
	path = os.path.join(ART, "map", "map_layers.json")
	data = json.load(open(path, encoding="utf-8"))
	atlases = [Image.open(os.path.join(ART, "map", a)).convert("RGBA") for a in data["atlases"]]
	by = {}
	for layer in ("below", "object", "above"):
		for n in data[layer]:
			if n.get("name"):
				by[n["name"]] = n
	return by, atlases


def node_images(by, atlases, name):
	out = []
	for r in by[name]["regions"]:
		out.append(atlases[r[0]].crop((r[1], r[2], r[1] + r[3], r[2] + r[4])))
	return out


def node_pos(node, region_index):
	if "static_frame" in node:
		return node["static_frame"][1], node["static_frame"][2]
	for fr in node.get("frames", []):
		if fr and fr[0] == region_index:
			return fr[1], fr[2]
	fr = node["frames"][0]
	return fr[1], fr[2]


def compose_tree(by, atlases, base, crown):
	"""Thân (tĩnh) + tán (nhiều khung) ghép đúng vị trí trên bản đồ; mọi khung chung một khung bao."""
	trunk = node_images(by, atlases, base)[0]
	tx, ty = node_pos(by[base], 0)
	crowns = node_images(by, atlases, crown)
	parts = []
	for i, im in enumerate(crowns):
		cx, cy = node_pos(by[crown], i)
		parts.append((im, cx - tx, cy - ty))
	x0 = min([0] + [p[1] for p in parts])
	y0 = min([0] + [p[2] for p in parts])
	x1 = max([trunk.width] + [p[1] + p[0].width for p in parts])
	y1 = max([trunk.height] + [p[2] + p[0].height for p in parts])
	frames = []
	for im, ox, oy in parts:
		f = Image.new("RGBA", (x1 - x0, y1 - y0), CLEAR)
		f.alpha_composite(trunk, (-x0, -y0))
		f.alpha_composite(im, (ox - x0, oy - y0))
		frames.append(f)
	return frames


def unify(frames):
	w = max(f.width for f in frames)
	h = max(f.height for f in frames)
	out = []
	for f in frames:
		c = Image.new("RGBA", (w, h), CLEAR)
		c.alpha_composite(f, ((w - f.width) // 2, h - f.height))
		out.append(c)
	return out


def build_props():
	by, atlases = map_nodes()
	props = {}
	props["coconut_a"] = compose_tree(by, atlases, "C_dua_04_than", "C_dua_04_tan")
	props["coconut_b"] = compose_tree(by, atlases, "D_dua_02_than", "D_dua_02_tan")
	props["coconut_c"] = compose_tree(by, atlases, "B_dua_04_than", "B_dua_04_tan")
	props["mango"] = compose_tree(by, atlases, "C_cay_xoai_01_goc", "C_cay_xoai_01_tan")
	props["jackfruit"] = compose_tree(by, atlases, "C_cay_mit_01_goc", "C_cay_mit_01_tan")
	props["bamboo"] = compose_tree(by, atlases, "E_tre_01_goc", "E_tre_01_ngon")
	simple = {
		"banana": "B_chuoi_01", "banana_b": "C_chuoi_02", "nipa": "C_dua_nuoc_01", "nipa_b": "B_dua_nuoc_02",
		"house_thatch": "C_nha_la_tuong", "house_garden": "B_nha_vuon_1_tuong", "house_home": "F_nha_la_vuon_tuong",
		"jar": "A_khap_01", "jar_b": "B_khap_2", "dog_sleep": "NV_cho_muc_ngu", "rack": "C_gian_phoi_kho",
		"hens": "B_ga_nha_01", "ducks": "E_vit_01", "hyacinth_a": "C_luc_binh_01", "hyacinth_b": "C_luc_binh_02",
		"hyacinth_c": "C_luc_binh_03", "hyacinth_d": "A_luc_binh_02", "lotus": "B_sen_02",
		"fruit_boat": "C_ghe_ban_trai_cay_cho_noi_1", "boat_two": "song_vo_lai_2", "tour_boat": "D_ghe_du_lich_1",
		"fisher": "NV_ong_cau_ca", "buffalo": "E_trau_gam_co", "sign_ferry": "C_bien_ben_do", "smoke": "C_khoi_bep",
		"stake": "C_coc_buoc_do", "bush": "B_bui_17",
	}
	for key, name in simple.items():
		props[key] = unify(node_images(by, atlases, name))
	# Rào tre: cắt một khúc ~24 px (chừa nguyên cọc hai đầu) từ hàng rào dài.
	fence = node_images(by, atlases, "B_rao_tre_bac_trai")[0]
	props["fence"] = [fence.crop((0, 0, 26, fence.height))]
	return props


def pack_props(props):
	"""Xếp từng prop (các khung nằm ngang) thành hàng trong một atlas rộng 1024. Trả (ảnh, bảng)."""
	width = 1024
	x = y = row_h = 0
	table = {}
	placed = []
	for key in sorted(props.keys(), key=lambda k: -props[k][0].height):
		frames = props[key]
		fw, fh = frames[0].width, frames[0].height
		total = fw * len(frames)
		if x + total > width:
			x = 0
			y += row_h + 1
			row_h = 0
		table[key] = [x, y, fw, fh, len(frames)]
		placed.append((frames, x, y))
		x += total + 1
		row_h = max(row_h, fh)
	out = Image.new("RGBA", (width, y + row_h + 1), CLEAR)
	for frames, px, py in placed:
		for i, f in enumerate(frames):
			out.alpha_composite(f, (px + i * f.width, py))
	return out, table


# ============================================================ xuất

def write_sheets_gd(hero_keys, back_keys, prop_table, rooster_info):
	lines = [
		"extends RefCounted",
		"",
		"## TỰ SINH bởi tools/art/build_escape.py – đừng sửa tay (chạy lại script để cập nhật).",
		"## Bảng khung hình cho game/art/escape/*.png. Mọi khung nhân vật: ô HERO_CELL, gốc (chân / mặt nước) ở HERO_FOOT.",
		"",
		"const HERO_CELL: int = %d" % HERO_CELL,
		"const HERO_FOOT: Vector2i = Vector2i(%d, %d)" % (HERO_FOOT_X, HERO_FOOT_Y),
		"## Tên khung → chỉ số ô trong hero_noi.png / hero_dongtao.png.",
		"const HERO: Dictionary = {%s}" % ", ".join('"%s": %d' % (k, i) for i, k in enumerate(hero_keys)),
		"## Tên khung → chỉ số ô trong hero_back.png (nhìn sau lưng, không có gà).",
		"const HERO_BACK: Dictionary = {%s}" % ", ".join('"%s": %d' % (k, i) for i, k in enumerate(back_keys)),
		"const POLICE_CELL: Vector2i = Vector2i(%d, %d)" % (POL_CELL_W, POL_CELL_H),
		"const POLICE_FOOT: Vector2i = Vector2i(16, %d)" % POL_FOOT_Y,
		"## Hàng 0 = chú cao gầy (ria mép), hàng 1 = chú thấp mập. Cột: chạy 0–3, đứng trước 4, nói 5, gãi đầu 6,",
		"## đứng nghiêng cầm sổ biên bản 7.",
		"const POLICE: Dictionary = {\"run\": [0, 1, 2, 3], \"front\": 4, \"talk\": 5, \"scratch\": 6, \"notebook\": 7}",
		"## Gà nhỏ: hàng 0 = nòi/tre, hàng 1 = Đông Tảo; cột 0 ngồi, 1 chớp mắt. Ô ROOSTER_CELL, quay phải.",
		"const ROOSTER_CELL: Vector2i = Vector2i(%d, %d)" % rooster_info,
		"## Prop: [x, y, w, h, số khung] trong props.png (các khung nằm ngang liền nhau, gốc = giữa-dưới).",
		"const PROPS: Dictionary = {",
	]
	for key in sorted(prop_table.keys()):
		lines.append('\t"%s": [%s],' % (key, ", ".join(str(v) for v in prop_table[key])))
	lines.append("}")
	lines.append("")
	with open(SHEETS_GD, "w", encoding="utf-8", newline="\n") as fh:
		fh.write("\n".join(lines))


def main():
	preview = sys.argv[1] if len(sys.argv) > 1 else None
	roosters = rooster_variants()
	hero_keys = ["run0", "run1", "run2", "run3", "jump", "fall", "slide", "stumble", "dive", "stand",
		"swim0", "swim1", "swim2", "swim3"]
	for variant, info in roosters.items():
		cells = hero_frames(info["sit"])
		swims = swim_frames(info["sit"])
		for i, s in enumerate(swims):
			cells["swim%d" % i] = s
		save(strip([cells[k] for k in hero_keys]), "hero_%s.png" % variant)
	back = hero_back_frames()
	back_keys = ["wash0", "wash1", "wash2", "point", "stand"]
	save(strip([back[k] for k in back_keys]), "hero_back.png")
	save(police_sheet(), "police.png")
	# Gà nhỏ: ô chung kích thước cho cả hai biến thể.
	rw = max(i["sit"].width for i in roosters.values()) + 2
	rh = max(i["sit"].height for i in roosters.values()) + 2
	rows = []
	for variant in ("noi", "dongtao"):
		info = roosters[variant]
		cells = []
		for key in ("sit", "blink"):
			cell = Image.new("RGBA", (rw, rh), CLEAR)
			cell.alpha_composite(info[key], (1 + (rw - 2 - info[key].width) // 2, rh - 1 - info[key].height))
			cells.append(outline(cell))
		rows.append(strip(cells))
	rsheet = Image.new("RGBA", (rows[0].width, rh * 2), CLEAR)
	rsheet.alpha_composite(rows[0], (0, 0))
	rsheet.alpha_composite(rows[1], (0, rh))
	save(rsheet, "rooster_small.png")
	props_img, table = pack_props(build_props())
	save(props_img, "props.png")
	write_sheets_gd(hero_keys, back_keys, table, (rw, rh))
	if preview:
		os.makedirs(preview, exist_ok=True)
		for name in ("hero_noi.png", "hero_dongtao.png", "hero_back.png", "police.png", "rooster_small.png", "props.png"):
			im = Image.open(os.path.join(OUT, name))
			bg = Image.new("RGBA", im.size, (120, 160, 110, 255))
			bg.alpha_composite(im)
			k = 4 if im.width < 900 else 2
			bg.resize((im.width * k, im.height * k), Image.NEAREST).save(os.path.join(preview, "pv_" + name))
	print("OK:", OUT)


if __name__ == "__main__":
	main()
