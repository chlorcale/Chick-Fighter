# -*- coding: utf-8 -*-
"""Nhân vật chính bản mới (kiểu Stardew) từ D:/GameArt/truongcon_stardew.aseprite → sheet cho Godot.

Chạy:  python tools/art/build_player.py [--aseprite EXE] [--source FILE.aseprite] [--preview DIR]
Ra:    game/art/player_sheet_v2.png          – 20 khung 64×64 nằm ngang, CHỈ layer "Nhan vat" (đã có viền sẵn)
       game/art/player_sheet_v2_shadow.png   – 20 khung 64×64, CHỈ layer "Bong" (bóng đổ, vẽ dưới nhân vật)
       game/art/player_sheet_v2.json         – tag (idle, walk_down, walk_up, walk_left, walk_right) + thời lượng khung
       game/art/player_sheet_v2_portrait.png – chân dung bán thân (khung idle nhìn thẳng) phóng ×4 NEAREST cho DialogBox

File .aseprite chỉ ĐỌC (Aseprite chạy -b, script Lua nhúng bên dưới ghi ra thư mục tạm). Nếu không có Aseprite
mà sheet đã có sẵn thì vẫn sinh lại được chân dung (--from-sheet).

Thư viện cho các script khác (build_dream_bike.py, build_family.py, build_escape.py):
  load_frames()  → (list 20 ảnh RGBA 64×64 nhân vật, list 20 ảnh bóng, meta dict)
  PAL            → bảng màu tên → RGBA của nhân vật (lấy từ file art)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "game", "art")
SHEET = os.path.join(ART, "player_sheet_v2.png")
SHADOW = os.path.join(ART, "player_sheet_v2_shadow.png")
META = os.path.join(ART, "player_sheet_v2.json")
PORTRAIT = os.path.join(ART, "player_sheet_v2_portrait.png")
DEFAULT_ASEPRITE = r"D:\aseprite\build\bin\aseprite.exe"
DEFAULT_SOURCE = r"D:\GameArt\truongcon_stardew.aseprite"
FRAME = 64
CHAR_LAYER = "Nhan vat"
SHADOW_LAYER = "Bong"
## Gốc toạ độ của WorldPlayer trong ô 64×64: giữa hai bàn chân, ngay dưới hàng viền chân thấp nhất (hàng 57).
FOOT = (32, 58)

## Bảng màu nhân vật (đọc từ art – dùng để tô lại người nhà / vẽ tư thế ngồi xe / tẩu thoát).
PAL = {
	"outline": (58, 34, 40, 255),
	"cap": (46, 42, 56, 255), "cap_l": (74, 70, 88, 255), "cap_d": (30, 26, 38, 255),
	"brim": (200, 50, 58, 255), "brim_l": (224, 72, 74, 255), "brim_d": (142, 30, 44, 255), "badge": (242, 194, 74, 255),
	"hair": (44, 32, 40, 255), "hair_l": (74, 58, 64, 255),
	"skin_l": (255, 217, 168, 255), "skin": (242, 180, 126, 255), "skin_d": (208, 138, 92, 255),
	"skin_dd": (165, 96, 63, 255), "blush": (246, 168, 138, 255), "mouth": (232, 148, 120, 255),
	"nose": (184, 106, 90, 255), "eye": (42, 26, 36, 255), "eye_w": (255, 246, 238, 255),
	"sh_l": (226, 88, 74, 255), "sh": (184, 48, 58, 255), "sh_m": (134, 32, 46, 255), "sh_d": (86, 26, 44, 255),
	"sh_y": (232, 176, 74, 255), "sh_w": (255, 244, 224, 255), "sh_y2": (240, 184, 48, 255),
	"bottle_d": (154, 18, 34, 255), "bottle_l": (255, 122, 106, 255), "bottle": (224, 36, 46, 255),
	"bottle_y": (246, 212, 96, 255), "bottle_g": (244, 204, 58, 255),
	"jean": (90, 134, 200, 255), "jean_l": (142, 180, 226, 255), "jean_d": (44, 68, 120, 255),
	"jean_m": (62, 98, 162, 255), "jean_w": (232, 238, 246, 255),
	"shoe": (42, 42, 52, 255), "shoe_l": (74, 74, 86, 255),
}

LUA = r"""
local spr = app.activeSprite
local out = app.params.out
local function only(name)
  for _, l in ipairs(spr.layers) do l.isVisible = (l.name == name) end
end
local meta = {}
for i = 1, #spr.frames do
  only("%CHAR%")
  local a = Image(spr.spec); a:drawSprite(spr, i); a:saveAs(string.format("%s/char_%02d.png", out, i))
  only("%SHADOW%")
  local b = Image(spr.spec); b:drawSprite(spr, i); b:saveAs(string.format("%s/shadow_%02d.png", out, i))
  meta[#meta + 1] = string.format("frame\t%d\t%d", i, math.floor(spr.frames[i].duration * 1000 + 0.5))
end
for _, t in ipairs(spr.tags) do
  meta[#meta + 1] = string.format("tag\t%s\t%d\t%d", t.name, t.fromFrame.frameNumber, t.toFrame.frameNumber)
end
for _, l in ipairs(spr.layers) do meta[#meta + 1] = "layer\t" .. l.name end
meta[#meta + 1] = string.format("size\t%d\t%d", spr.width, spr.height)
local f = io.open(out .. "/meta.txt", "w")
f:write(table.concat(meta, "\n"))
f:close()
"""


def export(aseprite: str, source: str, tmp: str) -> None:
	"""Chạy Aseprite -b với script Lua nhúng; không bao giờ ghi lên file nguồn."""
	lua = os.path.join(tmp, "export_player.lua")
	with open(lua, "w", encoding="utf-8") as fh:
		fh.write(LUA.replace("%CHAR%", CHAR_LAYER).replace("%SHADOW%", SHADOW_LAYER))
	out = os.path.join(tmp, "frames")
	os.makedirs(out, exist_ok=True)
	subprocess.run([aseprite, "-b", source, "--script-param", "out=" + out, "--script", lua], check=True)


def read_meta(path: str) -> dict:
	frames, tags, layers = [], {}, []
	size = (FRAME, FRAME)
	with open(path, encoding="utf-8") as fh:
		for raw in fh.read().splitlines():
			p = raw.split("\t")
			if p[0] == "frame":
				frames.append(int(p[2]))
			elif p[0] == "tag":
				tags[p[1]] = [int(p[2]) - 1, int(p[3]) - 1]   # chỉ số khung bắt đầu từ 0, gồm cả 2 đầu
			elif p[0] == "layer":
				layers.append(p[1])
			elif p[0] == "size":
				size = (int(p[1]), int(p[2]))
	return {"durations_ms": frames, "tags": tags, "layers": layers, "size": size}


def strip(frames: list) -> Image.Image:
	out = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		out.alpha_composite(f, (i * FRAME, 0))
	return out


def load_frames():
	"""(khung nhân vật, khung bóng, meta) đọc từ sheet đã sinh trong game/art."""
	sheet = Image.open(SHEET).convert("RGBA")
	shadow = Image.open(SHADOW).convert("RGBA")
	n = sheet.width // FRAME
	chars = [sheet.crop((i * FRAME, 0, i * FRAME + FRAME, FRAME)) for i in range(n)]
	shads = [shadow.crop((i * FRAME, 0, i * FRAME + FRAME, FRAME)) for i in range(n)]
	with open(META, encoding="utf-8") as fh:
		meta = json.load(fh)
	return chars, shads, meta


def frames_of(meta: dict, tag: str) -> list:
	a, b = meta["tags"][tag]
	return list(range(a, b + 1))


def build_portrait(front: Image.Image) -> Image.Image:
	"""Bán thân nhìn thẳng: đầu + vai (hàng 14..41 của khung idle 1), lề 2 px, phóng ×4 NEAREST."""
	box = front.getbbox()
	x0 = max(0, box[0] - 2)
	x1 = min(FRAME, box[2] + 2)
	crop = front.crop((x0, max(0, box[1] - 2), x1, 42))
	k = 4
	return crop.resize((crop.width * k, crop.height * k), Image.NEAREST)


def main(argv: list) -> None:
	aseprite = DEFAULT_ASEPRITE
	source = DEFAULT_SOURCE
	preview = None
	from_sheet = False
	i = 0
	while i < len(argv):
		a = argv[i]
		if a == "--aseprite":
			aseprite = argv[i + 1]; i += 1
		elif a == "--source":
			source = argv[i + 1]; i += 1
		elif a == "--preview":
			preview = argv[i + 1]; i += 1
		elif a == "--from-sheet":
			from_sheet = True
		i += 1
	if not from_sheet:
		tmp = tempfile.mkdtemp(prefix="cf_player_")
		try:
			export(aseprite, source, tmp)
			meta = read_meta(os.path.join(tmp, "frames", "meta.txt"))
			n = len(meta["durations_ms"])
			chars = [Image.open(os.path.join(tmp, "frames", "char_%02d.png" % (k + 1))).convert("RGBA") for k in range(n)]
			shads = [Image.open(os.path.join(tmp, "frames", "shadow_%02d.png" % (k + 1))).convert("RGBA") for k in range(n)]
		finally:
			shutil.rmtree(tmp, ignore_errors=True)
		assert meta["size"] == (FRAME, FRAME), meta["size"]
		strip(chars).save(SHEET)
		strip(shads).save(SHADOW)
		meta_out = {
			"source": os.path.basename(source),
			"frame_size": FRAME,
			"frames": len(chars),
			"foot": list(FOOT),
			"durations_ms": meta["durations_ms"],
			"tags": meta["tags"],
		}
		with open(META, "w", encoding="utf-8", newline="\n") as fh:
			json.dump(meta_out, fh, ensure_ascii=False, indent="\t")
			fh.write("\n")
	chars, shads, meta = load_frames()
	build_portrait(chars[frames_of(meta, "idle")[0]]).save(PORTRAIT)
	print("player v2: %d khung, tag %s" % (len(chars), ", ".join("%s=%s" % (k, v) for k, v in meta["tags"].items())))
	if preview:
		os.makedirs(preview, exist_ok=True)
		bg = (110, 150, 100, 255)
		k = 6
		out = Image.new("RGBA", (FRAME * len(chars), FRAME), bg)
		for j, (c, s) in enumerate(zip(chars, shads)):
			out.alpha_composite(s, (j * FRAME, 0))
			out.alpha_composite(c, (j * FRAME, 0))
		out.resize((out.width * 3, out.height * 3), Image.NEAREST).save(os.path.join(preview, "pv_player_v2.png"))
		p = Image.open(PORTRAIT).convert("RGBA")
		b = Image.new("RGBA", p.size, (82, 128, 92, 255))
		b.alpha_composite(p)
		b.save(os.path.join(preview, "pv_player_portrait.png"))


if __name__ == "__main__":
	main(sys.argv[1:])
