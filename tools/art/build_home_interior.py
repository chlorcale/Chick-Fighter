# -*- coding: utf-8 -*-
"""Đóng gói NỘI THẤT NHÀ NHÂN VẬT CHÍNH (vẽ tay: D:/GameArt/NhaTrong_NhanVatChinh.aseprite) cho game/home.

Quy trình (chạy lại được, KHÔNG BAO GIỜ ghi đè file .aseprite):
  1. Aseprite CLI + tools/art/export_home_interior.lua xuất từng layer/frame ra thư mục tạm.
  2. 00_Ground + 02_Decor_Duo (tĩnh, kể cả lớp bóng 70 % đã nhân độ mờ) → interior/ground.png (960×576).
     Lớp 02 có hoạt ảnh (ánh lửa hắt ra sàn) → dải 8 khung riêng, vẽ ngay trên nền.
  3. Mỗi layer 03_Object → một ảnh cắt sát (obj_<tên>.png) + gốc y-sort = đáy điểm ảnh đục (ghi đè trong SORT_Y:
     ngạch cửa/bậc thềm/nia… nằm sát nền). Layer có hoạt ảnh → dải khung ngang (hframes = số khung).
  4. Mỗi layer 04_Above → above_<tên>.png (vẽ trên người chơi, làm trong khi người chơi đứng dưới).
  5. 05_Collision (ẩn, mờ 110) → interior/collision.png: điểm ảnh nào có alpha > 0 là đặc (255), còn lại 0.
     Thêm/bớt bằng EXTRA_BLOCKS / OPENINGS. 06_Guide (bóng người 64×64) KHÔNG xuất – chỉ đọc kích thước để báo.
  6. Gà vẽ sẵn: ẩn gà thả/gà tập (HIDE) và 8 bội gà vẽ sẵn (bội thật do game dựng: cage_empty/cage_front lấy từ
     bội trống boi_ga_4); xoá 2 con gà mái trong cửa sổ chuồng gỗ (chép hàng điểm ảnh trên cùng của ô cửa xuống).
  7. Sinh game/home/home_interior_data.gd (const: kích thước, danh sách vật, hoạt ảnh, lớp trên, bội vẽ sẵn).

Chạy:  python tools/art/build_home_interior.py                (ghi game/art/home/interior/ + home_interior_data.gd)
       python tools/art/build_home_interior.py --preview DIR  (ghi thêm ảnh ghép xem trước + bản đồ va chạm vào DIR)
Tuỳ chọn môi trường: ASEPRITE (đường dẫn aseprite.exe), HOME_ASE (đường dẫn file .aseprite).
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "art", "home", "interior")
DATA = os.path.join(ROOT, "game", "home", "home_interior_data.gd")
LUA = os.path.join(ROOT, "tools", "art", "export_home_interior.lua")
ASEPRITE = os.environ.get("ASEPRITE", r"D:\aseprite\build\bin\aseprite.exe")
SOURCE = os.environ.get("HOME_ASE", r"D:\GameArt\NhaTrong_NhanVatChinh.aseprite")
RES = "res://game/art/home/interior/"

# Gà vẽ sẵn bị ẩn: chỉ gà thật của người chơi được hiện (gà con "con" giữ lại cho sân có sức sống – không lẫn với gà
# chiến). Bội vẽ sẵn cũng bị ẩn: game dựng lại đúng chỗ bằng bội trống + gà thật.
HIDE = {"ga_tha_1_mai", "ga_tha_4_mai", "ga_tha_6_trong", "ga_noi_tap_1", "ga_noi_tap_2"}
CAGE_LAYERS = ["boi_ga_1_trong", "boi_ga_2_mai", "boi_ga_3_trong", "boi_ga_4", "boi_ga_5_trong", "boi_ga_6",
               "boi_ga_7_mai", "boi_ga_8_trong"]
EMPTY_CAGE = "boi_ga_4"
# Vật nằm sát nền: luôn vẽ dưới người (gốc y-sort rất nhỏ). Số khác = gốc y-sort tuyệt đối.
FLOOR = -100000
SORT_Y = {
    "nguong_cua_chinh": FLOOR, "bac_tam_cap_ngoai_cua_chinh": FLOOR, "nguong_cua_hong_ra_san_ga": FLOOR,
    "nia_phoi_thoc": FLOOR, "chen_thoc": FLOOR, "hang_rao_tre_trai": FLOOR,
    "ga_tha_2_con": FLOOR, "ga_tha_3_con": FLOOR, "ga_tha_5_con": FLOOR,
    "bep_lua_chay_anim": 445,   # lửa nằm TRONG miệng lò: vẽ trên thân bếp (đáy 444)
}
# Vật chỉ hiện khi chưa đóng bội mở rộng ở chỗ đó (tên → chỉ số ô bội đầu tiên chiếm chỗ của nó).
YIELD_TO_SLOT = {"nia_phoi_thoc": 8}
# Va chạm bổ sung / mở thêm (Rect x, y, w, h – toạ độ ảnh). Kiểm bằng flood fill trong --preview.
EXTRA_BLOCKS: list[tuple[int, int, int, int]] = [
    (406, 454, 126, 64),   # mặt phản ăn cơm (layer chỉ chặn chân phản) – không cho đi lên mâm cơm
    (173, 198, 109, 25),   # gầm chuồng gỗ nhà sàn (cột chân + giằng chéo) – không ai chui xuống gầm
]
# Chuồng gỗ: art gốc vẽ thân chuồng lơ lửng trên bóng đổ (đáy ván y 197, bóng/chân thang y ~222) → vẽ thêm chân nhà
# sàn (coop_stilts): cột trước có đá kê chân, cột sau trong bóng gầm, giằng chéo, đà ngang dưới sàn, bóng gầm chuồng.
COOP_LAYER = "chuong_ga_go"
COOP_FLOOR_Y = 197         # hàng viền đáy thân chuồng (toạ độ thế giới)
COOP_GROUND_Y = 222        # chân cột trước chạm đất (ngang chân thang)
COOP_FRONT_POSTS = [173, 236, 276]   # x trái của cột trước (rộng 5 px; tránh thang x 203..220)
COOP_BACK_POSTS = [186, 265]         # cột sau (khuất trong bóng gầm, ngắn hơn, tối hơn)
OPENINGS: list[tuple[int, int, int, int]] = []


def run_export(tmp: str) -> None:
    for sub in ("coll", "guide"):
        os.makedirs(os.path.join(tmp, sub), exist_ok=True)
    cmd = [ASEPRITE, "-b", SOURCE, "--script-param", "out=" + tmp, "--script", LUA]
    subprocess.run(cmd, check=True)


def load_manifest(tmp: str):
    layers = []
    with open(os.path.join(tmp, "manifest.tsv"), encoding="utf-8") as f:
        for line in f.read().splitlines():
            if not line.strip():
                continue
            parts = line.split("\t")
            idx, group, name = int(parts[0]), parts[1], parts[3]
            frames = []
            for tok in parts[6].split(" "):
                if tok == "-1":
                    frames.append(None)
                    continue
                u, x, y, op = map(int, tok.split(":"))
                im = Image.open(os.path.join(tmp, "L%04d_%02d.png" % (idx, u))).convert("RGBA")
                if op < 255:
                    a = np.array(im)
                    a[:, :, 3] = (a[:, :, 3].astype(np.int32) * op // 255).astype(np.uint8)
                    im = Image.fromarray(a)
                frames.append((im, x, y))
            layers.append({"idx": idx, "group": group, "name": name, "frames": frames,
                           "unique": int(parts[4])})
    with open(os.path.join(tmp, "size.txt")) as f:
        w, h, n, ms = map(int, f.read().split())
    return layers, (w, h), n, ms


def full_frame(entry, size):
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    if entry is not None:
        im, x, y = entry
        canvas.alpha_composite(im, (x, y)) if x >= 0 and y >= 0 else canvas.paste(im, (x, y), im)
    return canvas


def union_bbox(images):
    box = None
    for im in images:
        b = im.getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def erase_coop_window_birds(im: Image.Image) -> Image.Image:
    """Chuồng gỗ: ô cửa sổ trên (x 11..52, y 9..22 trong ảnh layer) có 2 con gà mái vẽ sẵn – chép hàng y 9 (chỉ có
    song cửa + nền tối) xuống các hàng dưới để còn ô cửa trống."""
    a = np.array(im)
    a[10:23, 11:53] = a[9, 11:53]
    return Image.fromarray(a)


def erase_nest_eggs(im: Image.Image) -> Image.Image:
    """Ổ rơm: xoá 2 quả trứng vẽ sẵn (điểm sáng trong vùng x 6..17, y 2..8) bằng màu rơm sáng – trứng thật trong lò ấp
    (GameState.incubator) do game vẽ lên ổ."""
    a = np.array(im)
    straw = a[5, 19].copy()
    for y in range(2, 9):
        for x in range(6, 18):
            if a[y, x, 3] > 0 and int(a[y, x, :3].astype(np.int32).mean()) >= 192:
                a[y, x] = straw
    return Image.fromarray(a)


def straw_pad() -> Image.Image:
    """Ổ rơm nhỏ cho gà ở trước chuồng gỗ (ô 15–20). 22×8, màu lấy theo ổ rơm vẽ tay."""
    im = Image.new("RGBA", (22, 8), (0, 0, 0, 0))
    a = np.array(im)
    dark, mid, light = (52, 36, 44, 255), (150, 112, 70, 255), (226, 170, 52, 255)
    for y in range(8):
        for x in range(22):
            dx, dy = (x - 10.5) / 11.0, (y - 3.5) / 4.0
            r = dx * dx + dy * dy
            if r <= 1.0:
                a[y, x] = dark if r > 0.72 else (mid if y >= 5 or (x + y) % 3 == 0 else light)
    return Image.fromarray(a)


WOOD_OUT, WOOD_DARK, WOOD_MID, WOOD_LIGHT = (42, 30, 46), (100, 57, 47), (142, 86, 54), (182, 124, 70)
SHADE_CORE, SHADE_DEEP, SHADE_MID = (96, 62, 50), (119, 80, 56), (148, 108, 72)
STONE_LIGHT, STONE_MID, STONE_DARK = (166, 160, 153), (134, 133, 148), (106, 76, 74)


def coop_stilts(im: Image.Image, box) -> Image.Image:
    """Chân nhà sàn cho chuồng gỗ: vẽ một lớp LÓT dưới art gốc (art gốc – kể cả cái thang – vẽ đè lên trên), cùng bảng
    màu gỗ của chuồng. box = (x0, y0, x1, y1) thế giới của ảnh cắt. Trả ảnh cùng kích thước."""
    x0, y0 = box[0], box[1]
    w, h = im.size
    lay = np.zeros((h, w, 4), dtype=np.uint8)

    def put(x, y, c):
        lx, ly = x - x0, y - y0
        if 0 <= lx < w and 0 <= ly < h:
            lay[ly, lx] = tuple(c) + (255,)

    left, right = x0 + 1, box[2] - 2
    fy = COOP_FLOOR_Y
    gy = COOP_GROUND_Y
    # bóng gầm chuồng: đậm sát sàn, nhạt dần ra trước, mép trước lốm đốm (dither) hoà vào nền cát
    for y in range(fy + 1, gy):
        for x in range(left + 2, right - 1):
            if y < fy + 9:
                put(x, y, SHADE_CORE)
            elif y < fy + 14:
                put(x, y, SHADE_DEEP)
            elif y < fy + 18:
                put(x, y, SHADE_MID)
            elif y < fy + 20 and (x + y) % 2 == 0:
                put(x, y, SHADE_MID)
    # cột sau (ngắn, trong bóng)
    for px in COOP_BACK_POSTS:
        for y in range(fy + 1, fy + 15):
            put(px, y, WOOD_OUT)
            put(px + 1, y, WOOD_DARK)
            put(px + 2, y, WOOD_OUT)
        for x in range(px - 1, px + 4):
            put(x, fy + 15, STONE_DARK)
    # giằng chéo giữa các cột trước (mỗi khoang một thanh: khoang trái dốc xuống, khoang phải dốc lên)
    bays = [(COOP_FRONT_POSTS[0] + 5, COOP_FRONT_POSTS[1] - 1, 1), (COOP_FRONT_POSTS[1] + 5, COOP_FRONT_POSTS[2] - 1, -1)]
    for (a, b, d) in bays:
        n = b - a
        for i in range(n + 1):
            t = i / max(n, 1)
            yy = int(round(fy + 5 + t * 12)) if d > 0 else int(round(fy + 17 - t * 12))
            put(a + i, yy, WOOD_MID)
            put(a + i, yy - 1, WOOD_LIGHT)
            put(a + i, yy + 1, WOOD_OUT)
    # đà ngang dưới sàn (thấy bề dày sàn ván)
    for x in range(left, right + 1):
        put(x, fy + 1, WOOD_DARK)
        put(x, fy + 2, WOOD_DARK if x % 6 else WOOD_OUT)
        put(x, fy + 3, WOOD_OUT)
    # cột trước: viền tối, sáng bên trái, thân gỗ, có mắt gỗ; đá kê chân + bóng tiếp đất
    for px in COOP_FRONT_POSTS:
        for y in range(fy + 1, gy - 1):
            put(px, y, WOOD_OUT)
            put(px + 1, y, WOOD_LIGHT)
            put(px + 2, y, WOOD_MID)
            put(px + 3, y, WOOD_DARK if (y - fy) % 7 == 3 else WOOD_MID)
            put(px + 4, y, WOOD_OUT)
        for x in range(px - 1, px + 6):
            put(x, gy - 2, STONE_LIGHT if px <= x <= px + 4 else STONE_MID)
            put(x, gy - 1, STONE_MID)
        put(px - 1, gy - 2, WOOD_OUT)
        put(px + 5, gy - 2, WOOD_OUT)
        for x in range(px - 2, px + 7):
            put(x, gy, STONE_DARK)
            put(x, gy + 1, SHADE_DEEP)
    under = Image.fromarray(lay, "RGBA")
    under.alpha_composite(im)
    return under


def cage_door(empty: Image.Image, open_: bool) -> Image.Image:
    """Bội có cửa: ban ngày cửa nan mở (lỗ cửa tối có rơm lót, tấm cửa xoay ra bên trái); ban đêm cửa đóng (khung cửa
    + chốt tre)."""
    a = np.array(empty).copy()
    h, w = a.shape[:2]
    cx = w // 2
    dw, top, bot = 7, h - 19, h - 4          # nửa bề ngang cửa, hàng trên, hàng dưới (trên vành đáy)
    frame, dark, inner = (232, 206, 142), (42, 30, 46), (62, 43, 51)
    straw, straw2 = (204, 168, 114), (156, 122, 94)
    for y in range(top - 1, bot + 1):
        for x in range(cx - dw - 1, cx + dw + 1):
            dy = y - top
            r_arch = dw if dy >= 3 else dw - (3 - dy)            # vòm trên bo tròn
            if abs(x - cx + 0.5) > r_arch + 1:
                continue
            edge = abs(x - cx + 0.5) > r_arch or y == top - 1 or y == bot
            if open_:
                if edge:
                    a[y, x] = frame + (255,)
                elif y >= bot - 2:
                    a[y, x] = (straw if (x + y) % 3 else straw2) + (255,)
                else:
                    a[y, x] = (dark if y < top + 3 else inner) + (255,)
            elif edge:
                a[y, x] = frame + (255,)
    if open_:
        # tấm cửa nan xoay mở ra bên trái (hình bình hành hẹp nhìn nghiêng)
        for i in range(bot - top + 1):
            y = top + i
            for k in range(4):
                x = cx - dw - 6 + k
                if k in (0, 3) or i in (0, bot - top):
                    c = frame
                else:
                    c = (106, 67, 56) if (i + k) % 2 else (204, 168, 114)
                a[min(y + (1 if k < 2 else 0), h - 1), x] = c + (255,)
            a[min(y + 1, h - 1), cx - dw - 7] = dark + (255,)
    else:
        # chốt tre ngang giữa cửa
        y = top + (bot - top) // 2
        for x in range(cx - 2, cx + 3):
            a[y, x] = (232, 206, 142, 255)
            a[y + 1, x] = dark + (255,)
    return Image.fromarray(a)


def zzz_strip() -> Image.Image:
    """Chữ "z" ngủ (3 cỡ) – vẽ nổi trên bội gà ban đêm. Dải 3 khung 7×7 (z nhỏ, vừa, lớn)."""
    a = np.zeros((7, 21, 4), dtype=np.uint8)
    ink, out = (247, 237, 196, 255), (42, 30, 46, 255)
    for k, n in enumerate((3, 4, 5)):
        ox = k * 7 + (7 - n) // 2
        oy = (7 - n) // 2
        pts = [(ox + i, oy) for i in range(n)] + [(ox + i, oy + n - 1) for i in range(n)]
        pts += [(ox + n - 1 - j, oy + j) for j in range(1, n - 1)]
        for (x, y) in pts:
            if x + 1 < k * 7 + 7 and y + 1 < 7:
                a[y + 1, x + 1] = out            # bóng đổ 1 px xuống-phải cho dễ đọc trên nền tối
        for (x, y) in pts:
            a[y, x] = ink
    return Image.fromarray(a, "RGBA")


def lattice_only(im: Image.Image) -> Image.Image:
    """Bội trống → chỉ còn nan tre (bỏ các lỗ tối) để vẽ đè lên gà nằm trong bội."""
    a = np.array(im).astype(np.int32)
    lum = a[:, :, 0] * 0.3 + a[:, :, 1] * 0.59 + a[:, :, 2] * 0.11
    hole = (lum < 92) & (a[:, :, 3] > 0)
    # giữ vành đáy + viền ngoài (hai hàng dưới cùng và điểm sát mép trong suốt) để bội vẫn "kín" khi nhìn
    h, w = lum.shape
    keep = np.zeros_like(hole)
    keep[h - 4:, :] = True
    alpha = a[:, :, 3] > 0
    edge = alpha & ~(np.roll(alpha, 1, 0) & np.roll(alpha, -1, 0) & np.roll(alpha, 1, 1) & np.roll(alpha, -1, 1))
    keep |= edge
    out = a.copy()
    out[hole & ~keep, 3] = 0
    return Image.fromarray(out.astype(np.uint8))


def gd_vec(x, y) -> str:
    return "Vector2(%d, %d)" % (x, y)


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="home_interior_")
    try:
        run_export(tmp)
        layers, size, nframes, ms = load_manifest(tmp)
        W, H = size
        # dọn file cũ trong interior/ (giữ .import của file sẽ ghi lại: Godot tự cập nhật)
        os.makedirs(OUT, exist_ok=True)
        written: set[str] = set()

        def save(im: Image.Image, name: str):
            im.save(os.path.join(OUT, name))
            written.add(name)

        ground = Image.new("RGBA", size, (0, 0, 0, 255))
        objects, above, decor_anim, cages = [], [], [], {}
        for L in layers:
            name, group = L["name"], L["group"]
            frames = [full_frame(e, size) for e in L["frames"]]
            animated = L["unique"] > 1
            if group in ("00_Ground", "02_Decor_Duo") and not animated:
                ground.alpha_composite(frames[0])
                continue
            if name in HIDE:
                continue
            if name in CAGE_LAYERS:
                cages[name] = frames[0]
                continue
            box = union_bbox(frames)
            if box is None:
                continue
            crops = [f.crop(box) for f in frames]
            if name == COOP_LAYER:
                crops = [coop_stilts(erase_coop_window_birds(c), box) for c in crops]
            if name == "o_de_rom_trung":
                crops = [erase_nest_eggs(c) for c in crops]
            if animated:
                strip = Image.new("RGBA", (crops[0].width * len(crops), crops[0].height))
                for k, c in enumerate(crops):
                    strip.paste(c, (k * crops[0].width, 0))
                img = strip
            else:
                img = crops[0]
            prefix = {"03_Object": "obj_", "04_Above": "above_"}.get(group, "decor_")
            fname = prefix + name + ".png"
            save(img, fname)
            entry = {"name": name, "tex": fname, "pos": (box[0], box[1]), "size": (box[2] - box[0], box[3] - box[1]),
                     "frames": len(crops) if animated else 1}
            if group == "03_Object":
                entry["sort"] = SORT_Y.get(name, box[3])
                entry["yield"] = YIELD_TO_SLOT.get(name, -1)
                objects.append(entry)
            elif group == "04_Above":
                above.append(entry)
            else:
                decor_anim.append(entry)
        save(ground.convert("RGB"), "ground.png")

        # bội: vị trí từng bội vẽ sẵn (gốc = giữa đáy), ảnh bội trống + nan tre + bóng đổ (lấy từ lớp bóng dưới bội 4)
        cage_feet = []
        for name in CAGE_LAYERS:
            b = cages[name].getbbox()
            cage_feet.append(((b[0] + b[2]) // 2, b[3]))
        eb = cages[EMPTY_CAGE].getbbox()
        empty = cages[EMPTY_CAGE].crop(eb)
        save(empty, "cage_empty.png")
        save(lattice_only(empty), "cage_front.png")
        save(cage_door(empty, True), "cage_open.png")
        save(cage_door(empty, False), "cage_closed.png")
        save(zzz_strip(), "zzz.png")
        shadow_layer = next(L for L in layers if L["name"] == "bong_do_vat")
        sh = full_frame(shadow_layer["frames"][0], size)
        foot4 = cage_feet[CAGE_LAYERS.index(EMPTY_CAGE)]
        sbox = (foot4[0] - 30, foot4[1] - 10, foot4[0] + 30, foot4[1] + 8)
        shadow = sh.crop(sbox)
        sbb = shadow.getbbox()
        shadow = shadow.crop(sbb)
        save(shadow, "cage_shadow.png")
        save(straw_pad(), "straw_pad.png")
        shadow_off = (sbox[0] + sbb[0] - foot4[0], sbox[1] + sbb[1] - foot4[1])

        # va chạm
        coll = Image.open(os.path.join(tmp, "coll", "C01.png")).convert("RGBA")
        cc = Image.new("RGBA", size, (0, 0, 0, 0))
        cc.alpha_composite(coll, (0, 0))
        solid = np.array(cc)[:, :, 3] > 0
        for (x, y, w, h) in EXTRA_BLOCKS:
            solid[y:y + h, x:x + w] = True
        for (x, y, w, h) in OPENINGS:
            solid[y:y + h, x:x + w] = False
        save(Image.fromarray(np.where(solid, 255, 0).astype(np.uint8), "L"), "collision.png")

        # bóng người mẫu (guide) – chỉ đo
        guide_h = []
        gpath = os.path.join(tmp, "guide", "G01.png")
        if os.path.exists(gpath):
            g = np.array(Image.open(gpath).convert("RGBA"))[:, :, 3] > 0
            rows = np.nonzero(g.any(1))[0]
            # các bóng người tách nhau theo dải hàng trống
            start = rows[0]
            for i in range(1, len(rows) + 1):
                if i == len(rows) or rows[i] != rows[i - 1] + 1:
                    guide_h.append(int(rows[i - 1] - start + 1))
                    if i < len(rows):
                        start = rows[i]
        print("guide figure heights:", sorted(set(guide_h)))

        # xoá ảnh cũ không còn dùng trong interior/ (cùng .import của chúng)
        for f in os.listdir(OUT):
            if f.endswith(".png") and f not in written:
                os.remove(os.path.join(OUT, f))
                if os.path.exists(os.path.join(OUT, f + ".import")):
                    os.remove(os.path.join(OUT, f + ".import"))

        write_data(size, nframes, ms, objects, above, decor_anim, cage_feet, empty.size, shadow_off)
        print("home interior -> %s (%d files), data -> %s" % (OUT, len(written), DATA))
        if preview:
            make_preview(preview, ground, objects, above, solid)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def write_data(size, nframes, ms, objects, above, decor_anim, cage_feet, cage_size, shadow_off):
    def entry_line(e, extra=""):
        return '\t{"name": "%s", "tex": "%s", "pos": %s, "size": %s, "frames": %d%s},' % (
            e["name"], e["tex"], gd_vec(*e["pos"]), gd_vec(*e["size"]), e["frames"], extra)

    out = []
    out.append("extends RefCounted")
    out.append("")
    out.append("## TỰ SINH bởi tools/art/build_home_interior.py từ NhaTrong_NhanVatChinh.aseprite – ĐỪNG SỬA TAY.")
    out.append("## Toạ độ = px ảnh = px thế giới nhà (gốc 0,0 góc trên trái). Ảnh trong %s" % RES)
    out.append("")
    out.append('const ART: String = "%s"' % RES)
    out.append("const SIZE: Vector2i = Vector2i(%d, %d)" % size)
    out.append("const FRAMES: int = %d" % nframes)
    out.append("const FRAME_TIME: float = %.3f" % (ms / 1000.0))
    out.append("const FLOOR_SORT: int = %d" % FLOOR)
    out.append("## Đồ vật y-sort: pos = góc trên trái, sort = gốc y-sort (FLOOR_SORT = sát nền), frames > 1 = dải khung ngang,")
    out.append("## yield = chỉ số ô bội mở rộng chiếm chỗ vật này (−1 = không).")
    out.append("const OBJECTS: Array[Dictionary] = [")
    for e in objects:
        out.append(entry_line(e, ', "sort": %d, "yield": %d' % (e["sort"], e["yield"])))
    out.append("]")
    out.append("## Lớp trên (mái, tán cây, mùng, rèm, khói bếp): vẽ trên mọi thứ, làm trong khi người chơi đứng dưới.")
    out.append("const ABOVE: Array[Dictionary] = [")
    for e in above:
        out.append(entry_line(e))
    out.append("]")
    out.append("## Hoạt ảnh sát nền (ánh lửa hắt ra sàn) – vẽ ngay trên ground.png.")
    out.append("const DECOR_ANIM: Array[Dictionary] = [")
    for e in decor_anim:
        out.append(entry_line(e))
    out.append("]")
    out.append("## Chân (giữa đáy) của 8 bội vẽ sẵn boi_ga_1..8 (theo số trong tên layer).")
    out.append("const PAINTED_CAGES: Array[Vector2] = [%s]" % ", ".join(gd_vec(*f) for f in cage_feet))
    out.append("const CAGE_SIZE: Vector2i = Vector2i(%d, %d)" % cage_size)
    out.append("const CAGE_SHADOW_OFFSET: Vector2 = %s" % gd_vec(*shadow_off))
    out.append("## Chân nhà sàn vẽ thêm cho chuồng gỗ (coop_stilts): vùng gầm + x trái các cột trước (rộng 5 px).")
    out.append("const COOP_STILTS: Rect2i = Rect2i(173, %d, 109, %d)" % (COOP_FLOOR_Y + 1, COOP_GROUND_Y - COOP_FLOOR_Y + 1))
    out.append("const COOP_POSTS: Array[int] = [%s]" % ", ".join(str(x) for x in COOP_FRONT_POSTS))
    out.append("")
    with open(DATA, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def make_preview(preview, ground, objects, above, solid):
    canvas = ground.copy().convert("RGBA")
    for e in sorted(objects, key=lambda e: e["sort"]):
        im = Image.open(os.path.join(OUT, e["tex"])).convert("RGBA")
        if e["frames"] > 1:
            im = im.crop((0, 0, e["size"][0], e["size"][1]))
        canvas.alpha_composite(im, e["pos"])
    for e in above:
        im = Image.open(os.path.join(OUT, e["tex"])).convert("RGBA")
        if e["frames"] > 1:
            im = im.crop((0, 0, e["size"][0], e["size"][1]))
        canvas.alpha_composite(im, e["pos"])
    canvas.save(os.path.join(preview, "interior_composite.png"))
    a = np.array(canvas).astype(np.float32)
    a[solid] = a[solid] * 0.45 + np.array([255, 0, 0, 255]) * 0.55
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(preview, "interior_collision.png"))


if __name__ == "__main__":
    main()
