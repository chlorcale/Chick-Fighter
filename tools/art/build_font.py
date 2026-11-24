# -*- coding: utf-8 -*-
"""Dựng font pixel riêng của game (hỗ trợ đủ tiếng Việt) – không dùng tài sản của ai.

Hai mặt chữ vẽ tay bằng lưới điểm:
  * body  – chữ thường dùng: hoa cao 7 px, x-height 5 px, nét 1 px, chân 2 px.
  * bold  – chữ đậm / tiêu đề: hoa cao 9 px, x-height 6 px, nét dọc 2 px, chân 3 px.
Chữ có dấu tiếng Việt được GHÉP từ chữ gốc + bảng dấu (mũ ^, trăng ˘, móc ơ/ư, 5 dấu thanh), nên khoảng cách
và cách xếp dấu đồng nhất; phần ascent chừa đủ chỗ để dấu chồng (Ẫ, Ặ, Ẳ…) không đụng dòng trên.

Đầu ra (game/fonts/):
  * chick_body.ttf, chick_bold.ttf – glyph pixel dạng vector (mỗi pixel một ô vuông 100 đơn vị, UPM 1100).
    DialogBox.make_font đặt fixed_size = 11 + FIXED_SIZE_SCALE_INTEGER_ONLY: Godot dựng chữ đúng 1 pixel thiết kế =
    1 px rồi phóng NGUYÊN lần (cỡ 11–16 → ×1, 17–27 → ×2, 28–38 → ×3, …); viền chữ (outline) vẫn vẽ được.
  * (--bmfont, hoặc khi thiếu fontTools) chick_body.fnt/.png, chick_bold.fnt/.png – BMFont text, không có viền.
Chạy:  python tools/art/build_font.py [--specimen <file.png>] [--bmfont]
"""
from __future__ import annotations

import os
import sys
import unicodedata

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "fonts")


def G(top: int, rows: str):
	"""Một glyph: top = hàng đầu tiên (0 = đỉnh chữ hoa, âm = vùng dấu, > cao chữ hoa = chân)."""
	lines = [ln.strip() for ln in rows.strip().splitlines()]
	return (top, lines)


# =====================================================================================================
# MẶT CHỮ BODY (hoa 7, x 5): hàng 0..6 là thân, đường chân chữ dưới hàng 6; hàng 7..8 phần đuôi (g p q y j).
# =====================================================================================================
BODY = {
	"A": G(0, """
.###.
#...#
#...#
#####
#...#
#...#
#...#"""),
	"B": G(0, """
####.
#...#
#...#
####.
#...#
#...#
####."""),
	"C": G(0, """
.###.
#...#
#....
#....
#....
#...#
.###."""),
	"D": G(0, """
####.
#...#
#...#
#...#
#...#
#...#
####."""),
	"E": G(0, """
#####
#....
#....
####.
#....
#....
#####"""),
	"F": G(0, """
#####
#....
#....
####.
#....
#....
#...."""),
	"G": G(0, """
.###.
#...#
#....
#.###
#...#
#...#
.####"""),
	"H": G(0, """
#...#
#...#
#...#
#####
#...#
#...#
#...#"""),
	"I": G(0, """
###
.#.
.#.
.#.
.#.
.#.
###"""),
	"J": G(0, """
....#
....#
....#
....#
#...#
#...#
.###."""),
	"K": G(0, """
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#"""),
	"L": G(0, """
#....
#....
#....
#....
#....
#....
#####"""),
	"M": G(0, """
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#"""),
	"N": G(0, """
#...#
##..#
#.#.#
#.#.#
#..##
#...#
#...#"""),
	"O": G(0, """
.###.
#...#
#...#
#...#
#...#
#...#
.###."""),
	"P": G(0, """
####.
#...#
#...#
####.
#....
#....
#...."""),
	"Q": G(0, """
.###.
#...#
#...#
#...#
#.#.#
#..#.
.##.#"""),
	"R": G(0, """
####.
#...#
#...#
####.
#.#..
#..#.
#...#"""),
	"S": G(0, """
.###.
#...#
#....
.###.
....#
#...#
.###."""),
	"T": G(0, """
#####
..#..
..#..
..#..
..#..
..#..
..#.."""),
	"U": G(0, """
#...#
#...#
#...#
#...#
#...#
#...#
.###."""),
	"V": G(0, """
#...#
#...#
#...#
#...#
.#.#.
.#.#.
..#.."""),
	"W": G(0, """
#...#
#...#
#...#
#.#.#
#.#.#
##.##
#...#"""),
	"X": G(0, """
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#"""),
	"Y": G(0, """
#...#
#...#
.#.#.
..#..
..#..
..#..
..#.."""),
	"Z": G(0, """
#####
....#
...#.
..#..
.#...
#....
#####"""),
	"Đ": G(0, """
.####.
.#...#
.#...#
###..#
.#...#
.#...#
.####."""),
	# ---------------------------------------------------------------- chữ thường
	"a": G(2, """
.###.
....#
.####
#...#
.####"""),
	"b": G(0, """
#....
#....
####.
#...#
#...#
#...#
####."""),
	"c": G(2, """
.###.
#...#
#....
#...#
.###."""),
	"d": G(0, """
....#
....#
.####
#...#
#...#
#...#
.####"""),
	"e": G(2, """
.###.
#...#
#####
#....
.###."""),
	"f": G(0, """
..##
.#..
###.
.#..
.#..
.#..
.#.."""),
	"g": G(2, """
.####
#...#
#...#
#...#
.####
....#
.###."""),
	"h": G(0, """
#....
#....
####.
#...#
#...#
#...#
#...#"""),
	"i": G(0, """
#
.
#
#
#
#
#"""),
	"ı": G(2, """
#
#
#
#
#"""),
	"j": G(0, """
..#
...
..#
..#
..#
..#
..#
#.#
.#."""),
	"k": G(0, """
#...
#...
#..#
#.#.
##..
#.#.
#..#"""),
	"l": G(0, """
#.
#.
#.
#.
#.
#.
.#"""),
	"m": G(2, """
####.
#.#.#
#.#.#
#.#.#
#.#.#"""),
	"n": G(2, """
####.
#...#
#...#
#...#
#...#"""),
	"o": G(2, """
.###.
#...#
#...#
#...#
.###."""),
	"p": G(2, """
####.
#...#
#...#
#...#
####.
#....
#...."""),
	"q": G(2, """
.####
#...#
#...#
#...#
.####
....#
....#"""),
	"r": G(2, """
#.##
##..
#...
#...
#..."""),
	"s": G(2, """
.####
#....
.###.
....#
####."""),
	"t": G(1, """
.#..
####
.#..
.#..
.#..
..##"""),
	"u": G(2, """
#...#
#...#
#...#
#...#
.####"""),
	"v": G(2, """
#...#
#...#
#...#
.#.#.
..#.."""),
	"w": G(2, """
#...#
#...#
#.#.#
#.#.#
.#.#."""),
	"x": G(2, """
#...#
.#.#.
..#..
.#.#.
#...#"""),
	"y": G(2, """
#...#
#...#
#...#
#...#
.####
....#
.###."""),
	"y_dot": G(2, """
#...#
#...#
#...#
#...#
.####
....#
...#."""),
	"z": G(2, """
#####
...#.
..#..
.#...
#####"""),
	"đ": G(0, """
....#.
..####
.####.
#...#.
#...#.
#...#.
.####."""),
	# ---------------------------------------------------------------- số
	"0": G(0, """
.###.
#...#
#..##
#.#.#
##..#
#...#
.###."""),
	"1": G(0, """
..#..
.##..
..#..
..#..
..#..
..#..
.###."""),
	"2": G(0, """
.###.
#...#
....#
...#.
..#..
.#...
#####"""),
	"3": G(0, """
.###.
#...#
....#
..##.
....#
#...#
.###."""),
	"4": G(0, """
...#.
..##.
.#.#.
#..#.
#####
...#.
...#."""),
	"5": G(0, """
#####
#....
####.
....#
....#
#...#
.###."""),
	"6": G(0, """
.###.
#....
#....
####.
#...#
#...#
.###."""),
	"7": G(0, """
#####
....#
...#.
..#..
..#..
..#..
..#.."""),
	"8": G(0, """
.###.
#...#
#...#
.###.
#...#
#...#
.###."""),
	"9": G(0, """
.###.
#...#
#...#
.####
....#
....#
.###."""),
	# ---------------------------------------------------------------- dấu câu, ký hiệu
	".": G(6, "#"),
	",": G(6, """
.#
#."""),
	":": G(2, """
#
.
.
.
#"""),
	";": G(2, """
.#
..
..
..
.#
#."""),
	"!": G(0, """
#
#
#
#
#
.
#"""),
	"?": G(0, """
.###.
#...#
....#
...#.
..#..
.....
..#.."""),
	"'": G(0, """
#
#"""),
	"\"": G(0, """
#.#
#.#"""),
	"`": G(0, """
#.
.#"""),
	"‘": G(0, """
.#
#.
##"""),
	"’": G(0, """
##
.#
#."""),
	"“": G(0, """
.#..#
#..#.
##.##"""),
	"”": G(0, """
##.##
.#..#
#..#."""),
	"-": G(4, "###"),
	"–": G(4, "#####"),
	"—": G(4, "#######"),
	"−": G(3, "#####"),
	"_": G(8, "#####"),
	"+": G(1, """
..#..
..#..
#####
..#..
..#.."""),
	"=": G(2, """
#####
.....
#####"""),
	"×": G(2, """
#...#
.#.#.
..#..
.#.#.
#...#"""),
	"÷": G(1, """
..#..
.....
#####
.....
..#.."""),
	"±": G(1, """
..#..
..#..
#####
..#..
..#..
.....
#####"""),
	"<": G(1, """
...#
..#.
.#..
#...
.#..
..#.
...#"""),
	">": G(1, """
#...
.#..
..#.
...#
..#.
.#..
#..."""),
	"≤": G(0, """
...#
..#.
.#..
#...
.#..
..#.
...#
....
####"""),
	"≥": G(0, """
#...
.#..
..#.
...#
..#.
.#..
#...
....
####"""),
	"≈": G(1, """
.#..#
#.##.
.....
.#..#
#.##."""),
	"≠": G(1, """
...#.
#####
..#..
#####
.#..."""),
	"%": G(0, """
##..#
##.#.
...#.
..#..
.#...
.#.##
#..##"""),
	"/": G(0, """
....#
...#.
...#.
..#..
.#...
.#...
#...."""),
	"\\": G(0, """
#....
.#...
.#...
..#..
...#.
...#.
....#"""),
	"|": G(0, """
#
#
#
#
#
#
#
#"""),
	"(": G(0, """
.#
#.
#.
#.
#.
#.
.#"""),
	")": G(0, """
#.
.#
.#
.#
.#
.#
#."""),
	"[": G(0, """
##
#.
#.
#.
#.
#.
##"""),
	"]": G(0, """
##
.#
.#
.#
.#
.#
##"""),
	"{": G(0, """
.##
.#.
.#.
#..
.#.
.#.
.##"""),
	"}": G(0, """
##.
.#.
.#.
..#
.#.
.#.
##."""),
	"«": G(2, """
..#.#
.#.#.
#.#..
.#.#.
..#.#"""),
	"»": G(2, """
#.#..
.#.#.
..#.#
.#.#.
#.#.."""),
	"·": G(3, "#"),
	"•": G(2, """
.##.
####
####
.##."""),
	"…": G(6, "#.#.#"),
	"#": G(1, """
.#.#.
#####
.#.#.
#####
.#.#."""),
	"&": G(0, """
.##..
#..#.
#.#..
.#...
#.#.#
#..#.
.##.#"""),
	"@": G(0, """
.###.
#...#
#.###
#.#.#
#.###
#....
.###."""),
	"*": G(1, """
..#..
#.#.#
.###.
#.#.#
..#.."""),
	"^": G(0, """
.#.
#.#"""),
	"~": G(2, """
.#..#
#.##."""),
	"$": G(0, """
..#..
.####
#.#..
.###.
..#.#
####.
..#.."""),
	"°": G(0, """
.#.
#.#
.#."""),
	"²": G(0, """
##.
..#
.#.
###"""),
	"√": G(0, """
....###
....#..
....#..
#..#...
.#.#...
.#.#...
..#...."""),
	"∞": G(2, """
.#.#.
#.#.#
#.#.#
.#.#."""),
	"⌊": G(0, """
#.
#.
#.
#.
#.
#.
##"""),
	"⌋": G(0, """
.#
.#
.#
.#
.#
.#
##"""),
	"Π": G(0, """
#####
#...#
#...#
#...#
#...#
#...#
#...#"""),
	"Σ": G(0, """
#####
#....
.#...
..#..
.#...
#....
#####"""),
	"⏱": G(0, """
.###.
..#..
.###.
#.#.#
#.###
#...#
.###."""),
	# mũi tên
	"→": G(1, """
..#..
...#.
#####
...#.
..#.."""),
	"←": G(1, """
..#..
.#...
#####
.#...
..#.."""),
	"↑": G(0, """
..#..
.###.
#.#.#
..#..
..#..
..#..
..#.."""),
	"↓": G(0, """
..#..
..#..
..#..
..#..
#.#.#
.###.
..#.."""),
	"↔": G(1, """
.#...#.
#.....#
#######
#.....#
.#...#."""),
	"↘": G(1, """
#....
.#...
..#.#
...##
..###"""),
	"↗": G(1, """
..###
...##
..#.#
.#...
#...."""),
	"↖": G(1, """
###..
##...
#.#..
...#.
....#"""),
	"↙": G(1, """
....#
...#.
#.#..
##...
###.."""),
	"▶": G(1, """
#..
##.
###
##.
#.."""),
	"◀": G(1, """
..#
.##
###
.##
..#"""),
	"◄": G(1, """
..#
.##
###
.##
..#"""),
	"➤": G(1, """
#...
###.
.###
###.
#..."""),
	"▲": G(2, """
..#..
.###.
#####"""),
	"▼": G(2, """
#####
.###.
..#.."""),
	"★": G(0, """
...#...
..###..
#######
.#####.
..###..
.##.##.
.#...#."""),
	"✦": G(1, """
..#..
.###.
#####
.###.
..#.."""),
	"♥": G(1, """
.#.#.
#####
#####
.###.
..#.."""),
	"♡": G(1, """
.#.#.
#.#.#
#...#
.#.#.
..#.."""),
	"●": G(1, """
.###.
#####
#####
#####
.###."""),
	"○": G(1, """
.###.
#...#
#...#
#...#
.###."""),
	"□": G(1, """
#####
#...#
#...#
#...#
#####"""),
	"✓": G(1, """
....#
...#.
#.#..
.#...
....."""),
	"✗": G(1, """
#...#
.#.#.
..#..
.##..
#..##"""),
	"∩": G(1, """
.###.
#...#
#...#
#...#
#...#"""),
	"✔": G(1, """
...##
..##.
##.#.
.##..
..#.."""),
}

# Dấu (body). Mỗi dấu: danh sách hàng, gốc trái ở cột 0.
BODY_MARKS = {
	"acute": [".#", "#."],
	"grave": ["#.", ".#"],
	"hook": ["##", ".#", "#."],
	"tilde": [".#.#", "#.#."],
	"dot": ["#"],
	"circ": [".#.", "#.#"],
	"breve": ["#..#", ".##."],
}

BODY_METRICS = {
	"cap": 7, "xtop": 2, "ascent": 12, "descent": 3, "space": 3, "spacing": 1, "dot_row": 8,
	"fixed_size": 11, "name": "Chick Body",
}

# =====================================================================================================
# MẶT CHỮ BOLD (hoa 9, x 6, nét dọc 2 px): hàng 0..8 là thân, 9..11 phần đuôi.
# =====================================================================================================
BOLD = {
	"A": G(0, """
.####.
##..##
##..##
##..##
######
##..##
##..##
##..##
##..##"""),
	"B": G(0, """
#####.
##..##
##..##
##..##
#####.
##..##
##..##
##..##
#####."""),
	"C": G(0, """
.####.
##..##
##....
##....
##....
##....
##....
##..##
.####."""),
	"D": G(0, """
#####.
##..##
##..##
##..##
##..##
##..##
##..##
##..##
#####."""),
	"E": G(0, """
######
##....
##....
##....
#####.
##....
##....
##....
######"""),
	"F": G(0, """
######
##....
##....
##....
#####.
##....
##....
##....
##...."""),
	"G": G(0, """
.####.
##..##
##....
##....
##.###
##..##
##..##
##..##
.#####"""),
	"H": G(0, """
##..##
##..##
##..##
##..##
######
##..##
##..##
##..##
##..##"""),
	"I": G(0, """
####
.##.
.##.
.##.
.##.
.##.
.##.
.##.
####"""),
	"J": G(0, """
....##
....##
....##
....##
....##
....##
##..##
##..##
.####."""),
	"K": G(0, """
##...##
##..##.
##.##..
####...
###....
####...
##.##..
##..##.
##...##"""),
	"L": G(0, """
##....
##....
##....
##....
##....
##....
##....
##....
######"""),
	"M": G(0, """
##....##
###..###
########
##.##.##
##....##
##....##
##....##
##....##
##....##"""),
	"N": G(0, """
##...##
###..##
###..##
####.##
##.####
##..###
##..###
##...##
##...##"""),
	"O": G(0, """
.####.
##..##
##..##
##..##
##..##
##..##
##..##
##..##
.####."""),
	"P": G(0, """
#####.
##..##
##..##
##..##
#####.
##....
##....
##....
##...."""),
	"Q": G(0, """
.####.
##..##
##..##
##..##
##..##
##..##
##.###
##..##
.####.
....##"""),
	"R": G(0, """
#####.
##..##
##..##
##..##
#####.
##.##.
##..##
##..##
##..##"""),
	"S": G(0, """
.####.
##..##
##....
##....
.####.
....##
....##
##..##
.####."""),
	"T": G(0, """
######
..##..
..##..
..##..
..##..
..##..
..##..
..##..
..##.."""),
	"U": G(0, """
##..##
##..##
##..##
##..##
##..##
##..##
##..##
##..##
.####."""),
	"V": G(0, """
##..##
##..##
##..##
##..##
##..##
##..##
.####.
.####.
..##.."""),
	"W": G(0, """
##....##
##....##
##....##
##....##
##.##.##
##.##.##
########
###..###
##....##"""),
	"X": G(0, """
##..##
##..##
.####.
..##..
..##..
..##..
.####.
##..##
##..##"""),
	"Y": G(0, """
##..##
##..##
##..##
.####.
..##..
..##..
..##..
..##..
..##.."""),
	"Z": G(0, """
######
....##
...##.
...##.
..##..
.##...
.##...
##....
######"""),
	"Đ": G(0, """
.#####.
.##..##
.##..##
.##..##
####.##
.##..##
.##..##
.##..##
.#####."""),
	# ---------------------------------------------------------------- chữ thường (x-height 6: hàng 3..8)
	"a": G(3, """
.####.
....##
.#####
##..##
##..##
.#####"""),
	"b": G(0, """
##....
##....
##....
#####.
##..##
##..##
##..##
##..##
#####."""),
	"c": G(3, """
.####.
##..##
##....
##....
##..##
.####."""),
	"d": G(0, """
....##
....##
....##
.#####
##..##
##..##
##..##
##..##
.#####"""),
	"e": G(3, """
.####.
##..##
######
##....
##..##
.####."""),
	"f": G(0, """
..###
.##..
.##..
####.
.##..
.##..
.##..
.##..
.##.."""),
	"g": G(3, """
.#####
##..##
##..##
##..##
##..##
.#####
....##
##..##
.####."""),
	"h": G(0, """
##....
##....
##....
#####.
##..##
##..##
##..##
##..##
##..##"""),
	"i": G(0, """
##
##
..
##
##
##
##
##
##"""),
	"ı": G(3, """
##
##
##
##
##
##"""),
	"j": G(0, """
..##
..##
....
..##
..##
..##
..##
..##
..##
..##
..##
###."""),
	"k": G(0, """
##....
##....
##....
##..##
##.##.
####..
####..
##.##.
##..##"""),
	"l": G(0, """
##.
##.
##.
##.
##.
##.
##.
##.
.##"""),
	"m": G(3, """
#######.
##.##.##
##.##.##
##.##.##
##.##.##
##.##.##"""),
	"n": G(3, """
#####.
##..##
##..##
##..##
##..##
##..##"""),
	"o": G(3, """
.####.
##..##
##..##
##..##
##..##
.####."""),
	"p": G(3, """
#####.
##..##
##..##
##..##
##..##
#####.
##....
##....
##...."""),
	"q": G(3, """
.#####
##..##
##..##
##..##
##..##
.#####
....##
....##
....##"""),
	"r": G(3, """
##.###
####..
###...
##....
##....
##...."""),
	"s": G(3, """
.#####
##....
.####.
....##
....##
#####."""),
	"t": G(1, """
.##..
.##..
#####
.##..
.##..
.##..
.##..
..###"""),
	"u": G(3, """
##..##
##..##
##..##
##..##
##..##
.#####"""),
	"v": G(3, """
##..##
##..##
##..##
##..##
.####.
..##.."""),
	"w": G(3, """
##....##
##....##
##.##.##
##.##.##
########
.##..##."""),
	"x": G(3, """
##..##
.####.
..##..
..##..
.####.
##..##"""),
	"y": G(3, """
##..##
##..##
##..##
##..##
##..##
.#####
....##
##..##
.####."""),
	"y_dot": G(3, """
##..##
##..##
##..##
##..##
##..##
.#####
....##
....##
...##."""),
	"z": G(3, """
######
...##.
..##..
.##...
##....
######"""),
	"đ": G(0, """
....##.
..######
....##.
.#####.
##..##.
##..##.
##..##.
##..##.
.#####."""),
	# ---------------------------------------------------------------- số
	"0": G(0, """
.####.
##..##
##..##
##.###
###.##
##..##
##..##
##..##
.####."""),
	"1": G(0, """
..##..
.###..
####..
..##..
..##..
..##..
..##..
..##..
######"""),
	"2": G(0, """
.####.
##..##
....##
....##
...##.
..##..
.##...
##....
######"""),
	"3": G(0, """
.####.
##..##
....##
....##
..###.
....##
....##
##..##
.####."""),
	"4": G(0, """
...###
..####
.##.##
##..##
##..##
######
....##
....##
....##"""),
	"5": G(0, """
######
##....
##....
#####.
....##
....##
....##
##..##
.####."""),
	"6": G(0, """
.####.
##..##
##....
##....
#####.
##..##
##..##
##..##
.####."""),
	"7": G(0, """
######
....##
....##
...##.
..##..
..##..
..##..
..##..
..##.."""),
	"8": G(0, """
.####.
##..##
##..##
##..##
.####.
##..##
##..##
##..##
.####."""),
	"9": G(0, """
.####.
##..##
##..##
##..##
.#####
....##
....##
##..##
.####."""),
	".": G(7, """
##
##"""),
	",": G(7, """
.##
.##
##."""),
	":": G(3, """
##
##
..
..
##
##"""),
	";": G(3, """
.##
.##
...
...
.##
.##
##."""),
	"!": G(0, """
##
##
##
##
##
##
..
##
##"""),
	"?": G(0, """
.####.
##..##
....##
...##.
..##..
..##..
......
..##..
..##.."""),
	"-": G(5, "####"),
	"–": G(5, "######"),
	"—": G(5, "#########"),
	"−": G(4, "######"),
	"'": G(0, """
##
##
#."""),
	"\"": G(0, """
##.##
##.##
#..#."""),
	"“": G(0, """
.#..#.
##.##.
##.##."""),
	"”": G(0, """
.##.##
.##.##
.#..#."""),
	"(": G(0, """
.##
##.
##.
##.
##.
##.
##.
##.
.##"""),
	")": G(0, """
##.
.##
.##
.##
.##
.##
.##
.##
##."""),
	"[": G(0, """
###
##.
##.
##.
##.
##.
##.
##.
###"""),
	"]": G(0, """
###
.##
.##
.##
.##
.##
.##
.##
###"""),
	"/": G(0, """
....##
....##
...##.
...##.
..##..
.##...
.##...
##....
##...."""),
	"%": G(0, """
##...##
##..##.
...##..
...##..
..##...
..##...
.##....
##..##.
#...##."""),
	"+": G(2, """
..##..
..##..
######
######
..##..
..##.."""),
	"=": G(3, """
######
......
......
######"""),
	"×": G(2, """
##..##
.####.
..##..
.####.
##..##"""),
	"·": G(4, """
##
##"""),
	"…": G(7, """
##.##.##
##.##.##"""),
	"«": G(3, """
..##.##
.##.##.
##.##..
.##.##.
..##.##"""),
	"»": G(3, """
##.##..
.##.##.
..##.##
.##.##.
##.##.."""),
	"→": G(2, """
...##..
....##.
#######
#######
....##.
...##.."""),
	"←": G(2, """
..##...
.##....
#######
#######
.##....
..##..."""),
	"↑": G(0, """
..##..
.####.
######
..##..
..##..
..##..
..##..
..##..
..##.."""),
	"↓": G(0, """
..##..
..##..
..##..
..##..
..##..
..##..
######
.####.
..##.."""),
	"▶": G(1, """
##...
###..
####.
#####
####.
###..
##..."""),
	"◀": G(1, """
...##
..###
.####
#####
.####
..###
...##"""),
	"▲": G(2, """
...#...
..###..
.#####.
#######"""),
	"▼": G(2, """
#######
.#####.
..###..
...#..."""),
	"★": G(0, """
...#...
..###..
..###..
#######
.#####.
..###..
.##.##.
.#...#."""),
	"♥": G(1, """
.##.##.
#######
#######
.#####.
..###..
...#..."""),
}

BOLD_MARKS = {
	"acute": [".##", "##."],
	"grave": ["##.", ".##"],
	"hook": ["###", "..#", ".#."],
	"tilde": [".##..#", "#..##."],
	"dot": ["##", "##"],
	"circ": [".##.", "#..#"],
	"breve": ["#..#", ".##."],
}

BOLD_METRICS = {
	"cap": 9, "xtop": 3, "ascent": 14, "descent": 3, "space": 4, "spacing": 1, "dot_row": 10,
	"fixed_size": 11, "name": "Chick Bold",
}

# Dấu thanh tiếng Việt (mã tổ hợp) → tên dấu trong bảng.
TONES = {"": None, "̀": "grave", "́": "acute", "̉": "hook", "̃": "tilde", "̣": "dot"}
# Nguyên âm gốc: chữ → (chữ cơ sở, dấu phụ 1 (circ/breve/horn hoặc None)).
VOWELS = {
	"a": ("a", None), "ă": ("a", "breve"), "â": ("a", "circ"), "e": ("e", None), "ê": ("e", "circ"),
	"i": ("i", None), "o": ("o", None), "ô": ("o", "circ"), "ơ": ("o", "horn"), "u": ("u", None),
	"ư": ("u", "horn"), "y": ("y", None),
}
COMBINING = {"breve": "̆", "circ": "̂", "horn": "̛"}

# Bộ ký tự bổ sung luôn có (ký hiệu bàn phím ASCII đầy đủ).
ASCII = "".join(chr(c) for c in range(0x20, 0x7F))


# =====================================================================================================
# Ghép glyph
# =====================================================================================================

class Glyph:
	def __init__(self, pixels: set[tuple[int, int]], width: int, advance: int):
		self.pixels = pixels  # (x, row) – row tương đối đỉnh chữ hoa
		self.width = width
		self.advance = advance


def to_pixels(g) -> tuple[set[tuple[int, int]], int]:
	top, rows = g
	px = set()
	w = 0
	for r, line in enumerate(rows):
		w = max(w, len(line))
		for x, ch in enumerate(line):
			if ch == "#":
				px.add((x, top + r))
	return px, w


def stamp(px: set, mark: list[str], x0: int, bottom_row: int) -> None:
	"""Đặt dấu sao cho hàng cuối của dấu nằm ở bottom_row."""
	h = len(mark)
	for r, line in enumerate(mark):
		for x, ch in enumerate(line):
			if ch == "#":
				px.add((x0 + x, bottom_row - (h - 1) + r))


def mark_w(mark: list[str]) -> int:
	return max(len(r) for r in mark)


def add_horn(px: set, w: int, upper: bool, bold: bool, cap: int) -> int:
	"""Thêm móc ơ/ư bên phải phía trên thân; trả về bề rộng mới."""
	# Tìm điểm phải-trên của thân: hàng trên cùng có pixel ở cột phải nhất.
	rows = sorted({r for (_, r) in px})
	top = rows[0]
	right = max(x for (x, r) in px)
	# hàng có pixel ở cột phải nhất, cao nhất
	rr = min(r for (x, r) in px if x == right)
	if bold:
		hx, hy = right + 1, rr - 1
		px.update({(hx, hy), (hx + 1, hy), (hx + 1, hy - 1)})
		return max(w, hx + 2)
	hx, hy = right + 1, rr - 1
	px.update({(hx, hy), (hx, hy - 1)})
	return max(w, hx + 1)


def compose(face: dict, marks: dict, met: dict, base: str, upper: bool, mark1: str | None, tone: str | None) -> Glyph:
	key = base.upper() if upper else base
	if not upper and base == "i" and tone not in (None, "dot"):
		key = "ı"  # i không chấm khi có dấu thanh phía trên
	if not upper and base == "y" and tone == "dot":
		key = "y_dot"
	px, w = to_pixels(face[key])
	px = set(px)
	bold = met is BOLD_METRICS
	top = 0 if upper else met["xtop"]
	if not upper and base == "i" and tone == "dot":
		top = met["xtop"]
	body_w = w
	if mark1 == "horn":
		w = add_horn(px, w, upper, bold, met["cap"])
	center = body_w / 2.0
	bottom = top - 2  # 1 hàng trống phía trên thân
	tone_mark = marks.get(tone) if tone and tone != "dot" else None
	if mark1 in ("circ", "breve"):
		m = marks[mark1]
		mw = mark_w(m)
		# Dấu thanh đứng bên phải mũ (â ê ô, trừ dấu ngã) hoặc bên phải trăng của chữ HOA khi là dấu hỏi (cao 3 hàng);
		# còn lại chồng lên trên.
		side = tone_mark is not None and ((mark1 == "circ" and tone != "tilde") or (mark1 == "breve" and upper and tone == "hook"))
		x0 = int(round(center - mw / 2.0))
		if side:
			x0 = max(0, x0 - 1)
		stamp(px, m, x0, bottom)
		mtop = bottom - len(m) + 1
		if tone_mark is not None:
			tw = mark_w(tone_mark)
			if side:
				# dấu thanh đứng bên phải mũ, nhô lên một hàng
				# (chỉ nhô ra khoảng cách chữ, không nới bước tiến)
				stamp(px, tone_mark, x0 + mw, mtop)
			else:
				stamp(px, tone_mark, int(round(center - tw / 2.0)), mtop - 1)
	elif tone_mark is not None:
		tw = mark_w(tone_mark)
		x0 = int(round(center - tw / 2.0))
		if mark1 == "horn" and not upper:
			x0 = int(round(center - tw / 2.0))
		stamp(px, tone_mark, x0, bottom)
	if tone == "dot":
		d = marks["dot"]
		dw = mark_w(d)
		if not upper and base == "y":
			x0 = 0 if bold else 1
		else:
			x0 = int(round(center - dw / 2.0))
		stamp(px, d, x0, met["dot_row"] + len(d) - 1)
	return Glyph(px, w, w + met["spacing"])


def build_face(face: dict, marks: dict, met: dict) -> dict[str, Glyph]:
	out: dict[str, Glyph] = {}
	for ch, g in face.items():
		if len(ch) != 1:
			continue
		px, w = to_pixels(g)
		adv = w + met["spacing"]
		if ch in "·":
			# chấm giữa: chừa 1 px hai bên
			px = {(x + 1, r) for (x, r) in px}
			w += 2
			adv = w + met["spacing"]
		out[ch] = Glyph(px, w, adv)
	out[" "] = Glyph(set(), 0, met["space"])
	out[" "] = out[" "]
	# Chữ Việt có dấu: ghép.
	for vowel, (base, m1) in VOWELS.items():
		for comb, tone in TONES.items():
			for upper in (False, True):
				seq = base + (COMBINING[m1] if m1 else "") + comb
				ch = unicodedata.normalize("NFC", seq)
				if upper:
					ch = unicodedata.normalize("NFC", seq.upper()) if base != "i" else unicodedata.normalize("NFC", "I" + (COMBINING[m1] if m1 else "") + comb)
				if len(ch) != 1:
					continue
				if m1 is None and tone is None:
					continue  # chữ gốc đã có
				out[ch] = compose(face, marks, met, base, upper, m1, tone)
	# Ký tự thiếu ở mặt đậm: mượn từ mặt thường (phóng to không đẹp nên chỉ dời dọc cho cân).
	return out


def borrow_missing(bold: dict[str, Glyph], body: dict[str, Glyph]) -> None:
	"""Ký hiệu hiếm chỉ vẽ ở body: chép sang bold, làm đậm ngang 1 px và hạ xuống cho khớp đường chân chữ."""
	shift = BOLD_METRICS["cap"] - BODY_METRICS["cap"]
	for ch, g in body.items():
		if ch in bold:
			continue
		px = set()
		for (x, r) in g.pixels:
			px.add((x, r + shift))
			px.add((x + 1, r + shift))
		w = g.width + (1 if g.width > 0 else 0)
		bold[ch] = Glyph(px, w, w + BOLD_METRICS["spacing"] if g.width > 0 else g.advance + 1)


# =====================================================================================================
# Xuất BMFont + TTF
# =====================================================================================================

def export_bmfont(glyphs: dict[str, Glyph], met: dict, stem: str) -> None:
	cap = met["cap"]
	ascent = met["ascent"]
	base_y = ascent  # đường chân chữ tính từ đỉnh dòng
	line_h = ascent + met["descent"]
	items = sorted(glyphs.items(), key=lambda kv: ord(kv[0]))
	# xếp ô: mỗi glyph một ô cao line_h, rộng width+1
	page_w = 256
	x = y = 1
	row_h = line_h + 1
	placed = []
	for ch, g in items:
		cw = max(g.width, 1) + 2
		if x + cw > page_w:
			x = 1
			y += row_h
		placed.append((ch, g, x, y))
		x += cw
	page_h = 1
	while page_h < y + row_h + 1:
		page_h *= 2
	img = Image.new("RGBA", (page_w, page_h), (255, 255, 255, 0))
	lines = []
	for ch, g, gx, gy in placed:
		if not g.pixels:
			lines.append((ord(ch), 0, 0, 0, 0, 0, 0, g.advance))
			continue
		min_r = min(r for (_, r) in g.pixels)
		max_r = max(r for (_, r) in g.pixels)
		min_x = min(xx for (xx, _) in g.pixels)
		max_x = max(xx for (xx, _) in g.pixels)
		h = max_r - min_r + 1
		w = max_x - min_x + 1
		for (px, r) in g.pixels:
			img.putpixel((gx + px - min_x, gy + r - min_r), (255, 255, 255, 255))
		yoff = base_y - cap + min_r
		lines.append((ord(ch), gx, gy, w, h, min_x, yoff, g.advance))
	png_name = stem + "_0.png"
	img.save(os.path.join(OUT_DIR, png_name))
	with open(os.path.join(OUT_DIR, stem + ".fnt"), "w", encoding="utf-8", newline="\n") as f:
		f.write('info face="%s" size=%d bold=%d italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n'
			% (met["name"], met["fixed_size"], 1 if "Bold" in met["name"] else 0))
		f.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4\n"
			% (line_h, base_y, page_w, page_h))
		f.write('page id=0 file="%s"\n' % png_name)
		f.write("chars count=%d\n" % len(lines))
		for (cid, gx, gy, w, h, xo, yo, adv) in lines:
			f.write("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15\n"
				% (cid, gx, gy, w, h, xo, yo, adv))


def export_ttf(glyphs: dict[str, Glyph], met: dict, stem: str) -> bool:
	"""Font vector: mỗi pixel là một ô vuông (gộp theo đoạn ngang), 1 pixel = 100 đơn vị, UPM = fixed_size × 100.
	Godot dựng ở fixed_size px (1 pixel thiết kế = 1 px màn hình) rồi phóng nguyên lần."""
	try:
		from fontTools.fontBuilder import FontBuilder
		from fontTools.pens.ttGlyphPen import TTGlyphPen
	except ImportError:
		print("fontTools chưa cài – bỏ qua .ttf")
		return False
	U = 100
	upm = met["fixed_size"] * U
	cap = met["cap"]
	names = [".notdef"]
	cmap = {}
	glyph_objs = {}
	metrics = {}
	pen = TTGlyphPen(None)
	# .notdef: khung chữ nhật
	pen.moveTo((0, 0)); pen.lineTo((0, cap * U)); pen.lineTo((4 * U, cap * U)); pen.lineTo((4 * U, 0)); pen.closePath()
	pen.moveTo((U, U)); pen.lineTo((3 * U, U)); pen.lineTo((3 * U, (cap - 1) * U)); pen.lineTo((U, (cap - 1) * U)); pen.closePath()
	glyph_objs[".notdef"] = pen.glyph()
	metrics[".notdef"] = (5 * U, 0)
	for ch, g in sorted(glyphs.items(), key=lambda kv: ord(kv[0])):
		name = "uni%04X" % ord(ch)
		names.append(name)
		cmap[ord(ch)] = name
		pen = TTGlyphPen(None)
		rows: dict[int, list[int]] = {}
		for (x, r) in g.pixels:
			rows.setdefault(r, []).append(x)
		for r, xs in rows.items():
			xs.sort()
			start = prev = xs[0]
			runs = []
			for xx in xs[1:]:
				if xx == prev + 1:
					prev = xx
					continue
				runs.append((start, prev))
				start = prev = xx
			runs.append((start, prev))
			y_top = (cap - r) * U  # hàng r: từ (cap - r) xuống (cap - r - 1)
			for (a, b) in runs:
				x0, x1 = a * U, (b + 1) * U
				# chiều kim đồng hồ (TrueType: đường bao ngoài theo chiều kim đồng hồ)
				pen.moveTo((x0, y_top - U)); pen.lineTo((x0, y_top)); pen.lineTo((x1, y_top)); pen.lineTo((x1, y_top - U)); pen.closePath()
		glyph_objs[name] = pen.glyph()
		lsb = min((x for (x, _) in g.pixels), default=0) * U
		metrics[name] = (g.advance * U, lsb)
	fb = FontBuilder(upm, isTTF=True)
	fb.setupGlyphOrder(names)
	fb.setupCharacterMap(cmap)
	fb.setupGlyf(glyph_objs)
	fb.setupHorizontalMetrics(metrics)
	asc = met["ascent"] * U
	desc = met["descent"] * U
	fb.setupHorizontalHeader(ascent=asc, descent=-desc, lineGap=0)
	fb.setupNameTable({"familyName": met["name"], "styleName": "Regular"})
	fb.setupOS2(version=4, sTypoAscender=asc, sTypoDescender=-desc, sTypoLineGap=0, usWinAscent=asc, usWinDescent=desc,
		sxHeight=(cap - met["xtop"]) * U, sCapHeight=cap * U, fsSelection=0x40 | 0x80)
	fb.setupPost()
	fb.save(os.path.join(OUT_DIR, stem + ".ttf"))
	return True


# =====================================================================================================
# Bảng mẫu chữ
# =====================================================================================================

SAMPLES = [
	"Huyền Thoại Đá Gà", "Nguyễn Thị Ánh Tuyết", "Ừ, để mẹ dò bài", "Mỗi ngày", "ĐẤU TRƯỜNG",
	"Lão Gà Khô – khô gà lá chanh", "Chú Tư: “Gà hay là gà biết đọc đối thủ!”", "Tiền thưởng: +300.000đ · Lv12 → 13",
	"ẤẦẨẪẬ ẮẰẲẴẶ ẾỀỂỄỆ ỐỒỔỖỘ ỚỜỞỠỢ ỨỪỬỮỰ ỲÝỶỸỴ", "ấầẩẫậ ắằẳẵặ ếềểễệ ốồổỗộ ớờởỡợ ứừửữự ỳýỷỹỵ ìíỉĩị",
	"[W/S] chọn ▶ [E] xác nhận ▼ ★ ♥ % × ← → ↑ ↓ ↘ … «Ao Làng» (90%) ≥ ≈",
]


def render_specimen(faces: dict[str, dict[str, Glyph]], mets: dict[str, dict], chars: str, out_path: str) -> None:
	def draw_text(img, x, y, text, glyphs, met, scale, color):
		cx = x
		for ch in text:
			g = glyphs.get(ch)
			if g is None:
				# thiếu glyph: ô đỏ
				ImageDraw.Draw(img).rectangle([cx, y, cx + 4 * scale, y + met["cap"] * scale], outline=(255, 0, 0))
				cx += 6 * scale
				continue
			for (px, r) in g.pixels:
				yy = y + (met["ascent"] - met["cap"] + r) * scale
				ImageDraw.Draw(img).rectangle([cx + px * scale, yy, cx + px * scale + scale - 1, yy + scale - 1], fill=color)
			cx += g.advance * scale
		return cx

	width = 1800
	blocks = []
	y = 10
	plan = []
	for face in ("body", "bold"):
		met = mets[face]
		lh = met["ascent"] + met["descent"]
		for scale in (1, 2, 3):
			for s in SAMPLES:
				plan.append((face, scale, s))
			# toàn bộ ký tự
			per = max(20, (width - 20) // (8 * scale + 1 * scale))
			cs = list(chars)
			for i in range(0, len(cs), per):
				plan.append((face, scale, "".join(cs[i:i + per])))
	total_h = 10
	for face, scale, s in plan:
		met = mets[face]
		total_h += (met["ascent"] + met["descent"]) * scale + 2
	img = Image.new("RGB", (width, total_h + 10), (40, 30, 24))
	# nền giấy cho một nửa để kiểm tra chữ tối trên nền sáng
	for face, scale, s in plan:
		met = mets[face]
		lh = (met["ascent"] + met["descent"]) * scale
		paper = scale == 2
		if paper:
			ImageDraw.Draw(img).rectangle([0, y, width, y + lh + 1], fill=(240, 222, 186))
		draw_text(img, 10, y, s, faces[face], met, scale, (62, 39, 24) if paper else (250, 244, 228))
		y += lh + 2
	img.save(out_path)


def main() -> None:
	os.makedirs(OUT_DIR, exist_ok=True)
	body = build_face(BODY, BODY_MARKS, BODY_METRICS)
	bold = build_face(BOLD, BOLD_MARKS, BOLD_METRICS)
	borrow_missing(bold, body)
	for g in (body, bold):
		g.pop("y_dot", None)
	if not export_ttf(body, BODY_METRICS, "chick_body") or not export_ttf(bold, BOLD_METRICS, "chick_bold") 			or "--bmfont" in sys.argv:
		# Không có fontTools (hoặc yêu cầu riêng): xuất BMFont – Godot đọc được nhưng KHÔNG vẽ được viền chữ.
		export_bmfont(body, BODY_METRICS, "chick_body")
		export_bmfont(bold, BOLD_METRICS, "chick_bold")
	print("body glyphs:", len(body), "bold glyphs:", len(bold))
	# Kiểm tra: ký tự nào trong mã game (.gd/.json) chưa có glyph → báo để vẽ thêm.
	missing = set()
	for folder, _dirs, files in os.walk(os.path.join(ROOT, "game")):
		for fn in files:
			if fn.endswith((".gd", ".json")):
				with open(os.path.join(folder, fn), encoding="utf-8", errors="ignore") as f:
					for ch in f.read():
						if ord(ch) >= 32 and ch not in body and not (0x300 <= ord(ch) <= 0x36F) and ord(ch) != 0xFE0F:
							missing.add(ch)
	print("ký tự trong game chưa có glyph:", "".join(sorted(missing)) if missing else "(không)")
	if "--specimen" in sys.argv:
		out = sys.argv[sys.argv.index("--specimen") + 1]
		chars = "".join(sorted(body.keys(), key=ord))
		render_specimen({"body": body, "bold": bold}, {"body": BODY_METRICS, "bold": BOLD_METRICS}, chars, out)
		print("specimen:", out)


if __name__ == "__main__":
	main()
