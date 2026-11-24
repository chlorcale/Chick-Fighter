# -*- coding: utf-8 -*-
"""Xuất `rooster fight.aseprite` cho game + dựng SHEET GÀ NHỎ cho sân nhà (game/home/yard_chicken.gd).

1. Sheet đầy đủ (cùng định dạng sheet trận, dùng lại tools/art/build_fighter_sheet.py):
     game/art/rooster_walk_sheet.png + rooster_walk.json + rooster_walk_mask.png   (47 khung, ô 128×112)
   Sheet trận (rooster_sheet.png / dongtao_sheet.png) KHÔNG bị đụng tới.
2. Sheet gà nhỏ cho sân nhà – vẽ lại ở đúng mật độ điểm ảnh của nét vẽ nhà (1 px art = 1 px thế giới):
     game/art/home/yard/<v>_sheet.png, <v>_mask.png, <v>.json, gear/<v>_<món>.png   (v = noi, tre, dongtao)
   Vì sao: thu nhỏ ×0,3 bằng lọc "nearest" lúc chạy làm rơi mất 2/3 hàng/cột điểm ảnh → gà bị "vỡ", đứt viền, chân
   rời thân. Ở đây mỗi điểm ảnh nhỏ được tính theo DIỆN TÍCH phủ của các điểm ảnh gốc (box filter chính xác, kể cả tỉ lệ
   lẻ), màu bám lại bảng màu gốc của khung, viền ngoài lấy màu tối nhất trong ô (giữ nét viền), chân/mắt có ngưỡng
   phủ thấp hơn (không mất chân mảnh). Mặt nạ bộ phận (đổi màu lông bằng rooster.gdshader) chọn bộ phận phủ nhiều
   nhất; lớp trang bị (game/art/gear/*.png của trận, cùng bố cục ô) thu nhỏ y như vậy → shader dùng đúng UV.
   Khung lấy từ bản xuất "sạch" (ẩn 00_Shadow, 01_Afterimage, 09_FX – không vệt tốc độ, tia sáng).
   Tag: idle, walk (run_right), scratch (run_left = bước lùi cào đất), flap (jump: vỗ cánh nhảy), crow (gáy thị uy),
   peck (CÚI MỔ – dựng từ idle khung 1 xoay quanh chân 14°/28°/38°, cả mặt nạ + đồ).
   Đông Tảo (dongtao_fight_combo.aseprite): idle, walk, scratch (= walk), flap (= TAUNT_DamNguc), crow, peck.
File .aseprite chỉ được đọc, không bao giờ bị sửa.

Chạy:  python tools/art/build_rooster_walk.py              (ghi cả hai phần)
       python tools/art/build_rooster_walk.py --preview DIR (ghi thêm ảnh xem trước phóng to vào DIR)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_fighter_sheet as bfs  # noqa: E402

ASEPRITE = os.environ.get("ASEPRITE", r"D:\aseprite\build\bin\aseprite.exe")
GAME_ART = r"D:\GameArt"
SRC_WALK = os.path.join(GAME_ART, "rooster fight.aseprite")
SRC_ROOSTER_COMBO = os.path.join(GAME_ART, "rooster_fight_combo.aseprite")
SRC_DONGTAO_COMBO = os.path.join(GAME_ART, "dongtao_fight_combo.aseprite")
ART = os.path.join(ROOT, "game", "art")
GEAR = os.path.join(ART, "gear")
YARD = os.path.join(ART, "home", "yard")
CW, CH, COLS = 128, 112, 12
FOOT = {"rooster": (56, 105), "dongtao": (57, 105)}
## Tỉ lệ thu nhỏ: gà nòi cao ~62 px art → ~23 px (ngang gối–hông người cao 57 px); gà tre ×0,9 như trong trận.
SCALES = {"noi": 0.375, "tre": 0.375 * 0.9, "dongtao": 0.375}
HIDE_LAYERS = ("00_Shadow", "01_Afterimage", "09_FX")
OUTLINE_LUMA = 60
## Màu mắt trong art gốc (màu, sai số) → 1 điểm mắt tối ở bản nhỏ.
EYE = {"rooster": ((255, 255, 255), 10), "dongtao": ((240, 196, 92), 6)}
PECK_ANGLES = (12.0, 24.0, 34.0)
## Viền sel-out: độ tối của viền so với màu mảng bên trong.
SELOUT = 0.5


# ------------------------------------------------------------------ xuất từ Aseprite

def export_clean(src: str, tmp: str) -> None:
    """Xuất khung + mặt nạ với các lớp hiệu ứng bị ẩn (ghép script ẩn lớp + export_fighter + export_fighter_mask)."""
    hide = "local __spr = app.activeSprite\nfor _, l in ipairs(__spr.layers) do\n"
    hide += "".join('  if l.name == "%s" then l.isVisible = false end\n' % n for n in HIDE_LAYERS) + "end\n"
    parts = [hide]
    for f in ("export_fighter.lua", "export_fighter_mask.lua"):
        with open(os.path.join(HERE, f), encoding="utf-8") as fh:
            parts.append("do\n" + fh.read() + "\nend\n")
    lua = os.path.join(tmp, "export_clean.lua")
    with open(lua, "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))
    subprocess.run([ASEPRITE, "-b", src, "--script-param", "out=" + tmp, "--script", lua], check=True)


def read_meta(tmp: str):
    durations, tags = [], {}
    with open(os.path.join(tmp, "meta.txt"), encoding="utf8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "frame":
                durations.append(int(p[2]))
            elif p[0] == "tag":
                tags[p[1]] = (int(p[2]), int(p[3]))
    return durations, tags


def load_frame(tmp: str, f: int):
    rgba = np.array(Image.open(os.path.join(tmp, "body_%03d.png" % f)).convert("RGBA"))
    m = np.array(Image.open(os.path.join(tmp, "mask_%03d.png" % f)).convert("RGBA")).astype(np.int32)
    roles = (m[:, :, 0] + 16) // 32
    roles[m[:, :, 3] == 0] = 0
    roles[rgba[:, :, 3] == 0] = 0
    return rgba, roles


def gear_cell(kit: str, item: str, f: int):
    path = os.path.join(GEAR, "%s_%s.png" % (kit, item))
    im = Image.open(path).convert("RGBA")
    i = f - 1
    return np.array(im.crop(((i % COLS) * CW, (i // COLS) * CH, (i % COLS + 1) * CW, (i // COLS + 1) * CH)))


def gear_items(kit: str):
    out = []
    for fn in sorted(os.listdir(GEAR)):
        if fn.startswith(kit + "_") and fn.endswith(".png"):
            out.append(fn[len(kit) + 1:-4])
    return out


# ------------------------------------------------------------------ xoay (cúi mổ)

def rotate(arr: np.ndarray, angle: float, pivot) -> np.ndarray:
    """Xoay một ô (RGBA hoặc mã bộ phận) quanh pivot, góc dương = cúi về phía trước (gà nhìn phải), lấy mẫu gần nhất."""
    if arr.ndim == 2:
        im = Image.fromarray(arr.astype(np.uint8), "L")
    else:
        im = Image.fromarray(arr.astype(np.uint8), "RGBA")
    r = im.rotate(-angle, resample=Image.NEAREST, center=pivot)
    return np.array(r).astype(arr.dtype)


def leg_zone(roles: np.ndarray, grow: int = 3) -> np.ndarray:
    """Vùng chân (mã 5) nở thêm vài px – phần đứng yên khi gà cúi mổ (cựa, dao chân đi theo chân)."""
    z = roles == 5
    for _ in range(grow):
        p = np.pad(z, 1)
        z = z | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return z


def hip_of(roles: np.ndarray):
    ys, xs = np.nonzero(roles == 5)
    return (float(xs.mean()), float(ys.min()) + 2.0)


def bend(rgba: np.ndarray, roles: np.ndarray, angle: float, zone: np.ndarray, hip):
    """Cúi mổ: chân đứng yên, phần trên (thân, đầu, đuôi, cánh) xoay quanh hông."""
    legs = rgba.copy()
    legs[~zone] = 0
    upper = rgba.copy()
    upper[zone] = 0
    up = rotate(upper, angle, hip)
    out = legs.copy()
    on = up[:, :, 3] > 0
    out[on] = up[on]
    if roles is None:
        return out, None
    lr = np.where(zone, roles, 0)
    ur = rotate(np.where(zone, 0, roles), angle, hip)
    return out, np.where(on, ur, lr)


# ------------------------------------------------------------------ thu nhỏ giữ nét

def weights(n_src: int, n_out: int, s: float, off: float) -> np.ndarray:
    """Ma trận phủ 1 chiều: W[i, x] = độ dài giao giữa điểm ảnh nguồn x (đã đổi sang toạ độ đích) và ô đích i."""
    w = np.zeros((n_out, n_src), dtype=np.float64)
    for x in range(n_src):
        a, b = x * s + off, (x + 1) * s + off
        i0, i1 = int(np.floor(a)), int(np.ceil(b))
        for i in range(max(i0, 0), min(i1, n_out)):
            ov = min(b, i + 1) - max(a, i)
            if ov > 0:
                w[i, x] = ov
    return w


def owner(n_src: int, n_out: int, s: float, off: float) -> np.ndarray:
    """Ô đích chứa tâm điểm ảnh nguồn (dùng chọn màu tối nhất / phát hiện nét)."""
    return np.clip(np.floor((np.arange(n_src) + 0.5) * s + off).astype(int), 0, n_out - 1)


class Shrinker:
    def __init__(self, s: float, foot):
        self.s = s
        fx, fy = foot
        self.off_x = float(np.round(fx * s)) - fx * s
        self.off_y = float(np.ceil(fy * s - 1e-6)) - fy * s
        self.w = int(np.ceil(CW * s + self.off_x))
        self.h = int(np.ceil(CH * s + self.off_y))
        self.foot = (int(round(fx * s + self.off_x)), int(round(fy * s + self.off_y)))
        self.wx = weights(CW, self.w, s, self.off_x)
        self.wy = weights(CH, self.h, s, self.off_y)
        self.ox = owner(CW, self.w, s, self.off_x)
        self.oy = owner(CH, self.h, s, self.off_y)

    def area(self, a: np.ndarray) -> np.ndarray:
        return self.wy @ a @ self.wx.T

    def shrink(self, rgba: np.ndarray, roles: np.ndarray | None, thr: float = 0.5, leg_thr: float = 0.2,
               outline: bool = True, eye=None, selout: bool = False):
        """→ (rgba nhỏ uint8, mã bộ phận nhỏ hoặc None)."""
        a = rgba[:, :, 3].astype(np.float64) / 255.0
        cov = self.area(a)
        rgb = rgba[:, :, :3].astype(np.float64)
        sums = np.stack([self.area(rgb[:, :, k] * a) for k in range(3)], axis=2)
        out = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        small_roles = np.zeros((self.h, self.w), dtype=np.int32) if roles is not None else None
        opaque = cov >= thr
        leg_only = np.zeros_like(opaque)
        if roles is not None:
            covs = {}
            for r in range(1, 8):
                sel = (roles == r).astype(np.float64) * a
                if sel.any():
                    covs[r] = self.area(sel)
            best = np.zeros((self.h, self.w), dtype=np.int32)
            best_c = np.zeros((self.h, self.w))
            for r, c in covs.items():
                upd = c > best_c
                best[upd] = r
                best_c[upd] = c[upd]
            # chân mảnh (5) + đầu (1: mắt, mỏ, mào) giữ ở ngưỡng phủ thấp hơn
            for r, t in ((5, leg_thr), (1, 0.34)):
                if r in covs:
                    extra = (covs[r] >= t) & ~opaque
                    leg_only |= extra
                    best[extra] = r
            opaque |= leg_only
            small_roles = np.where(opaque, best, 0)
        # màu trung bình (pixel thêm vì chân: chỉ lấy màu của bộ phận đó)
        col = np.zeros((self.h, self.w, 3))
        nz = cov > 1e-9
        col[nz] = sums[nz] / cov[nz][:, None]
        if roles is not None and leg_only.any():
            for r in (5, 1):
                sel = (roles == r).astype(np.float64) * a
                c_r = self.area(sel)
                s_r = np.stack([self.area(rgb[:, :, k] * sel) for k in range(3)], axis=2)
                pick = leg_only & (small_roles == r) & (c_r > 1e-9)
                col[pick] = s_r[pick] / c_r[pick][:, None]
        # bám bảng màu gốc
        vis = rgba[:, :, 3] > 0
        palette = np.unique(rgba[vis][:, :3].reshape(-1, 3), axis=0).astype(np.float64)
        if len(palette) == 0:
            return out, small_roles
        ys, xs = np.nonzero(opaque)
        if len(ys):
            q = col[ys, xs]
            d = ((q[:, None, :] - palette[None, :, :]) ** 2).sum(2)
            out[ys, xs, :3] = palette[d.argmin(1)].astype(np.uint8)
            out[ys, xs, 3] = 255
        if outline:
            # viền ngoài: điểm ảnh rìa bóng → màu tối nhất (viền gốc) trong các điểm ảnh nguồn thuộc ô đó
            alpha = opaque
            pad = np.pad(alpha, 1)
            edge = alpha & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
            luma = rgb[:, :, 0] * 0.3 + rgb[:, :, 1] * 0.59 + rgb[:, :, 2] * 0.11
            dark = vis & (luma < OUTLINE_LUMA)
            dys, dxs = np.nonzero(dark)
            best_l = np.full((self.h, self.w), 1e9)
            best_c = np.zeros((self.h, self.w, 3), dtype=np.uint8)
            for y, x in zip(dys, dxs):
                oy, ox = self.oy[y], self.ox[x]
                if luma[y, x] < best_l[oy, ox]:
                    best_l[oy, ox] = luma[y, x]
                    best_c[oy, ox] = rgba[y, x, :3]
            fix = edge & (best_l < 1e8)
            out[fix, :3] = best_c[fix]
            if selout and roles is not None:
                # "sel-out" kiểu Stardew: viền là sắc tối của chính mảng màu bên trong (không đen kịt) → gà nhỏ không
                # bị tối thui; chân / mỏ / mào vẫn có viền rõ. Màu bám bảng màu gốc (shader vẫn đổi màu theo bộ phận).
                fy, fx = np.nonzero(fix)
                if len(fy):
                    q = col[fy, fx] * SELOUT
                    d = ((q[:, None, :] - palette[None, :, :]) ** 2).sum(2)
                    out[fy, fx, :3] = palette[d.argmin(1)].astype(np.uint8)
            # mắt: ô chứa lòng trắng mắt (rooster) / mắt vàng (Đông Tảo) trên đầu → 1 điểm mắt tối (kiểu Stardew)
            if eye is not None and roles is not None:
                er = np.abs(rgba[:, :, :3].astype(np.int32) - np.array(eye[0])).max(2) <= eye[1]
                er &= (roles == 1) & vis
                eys, exs = np.nonzero(er)
                if len(eys):
                    oy, ox = int(np.round(np.mean(self.oy[eys]))), int(np.round(np.mean(self.ox[exs])))
                    if opaque[oy, ox]:
                        out[oy, ox, :3] = best_c[oy, ox] if best_l[oy, ox] < 1e8 else (24, 18, 28)
                        if best_l[oy, ox] >= 1e8:
                            out[oy, ox, :3] = (24, 18, 28)
        return out, small_roles


# ------------------------------------------------------------------ dựng sheet nhỏ

def plan_rooster(walk_tmp: str, combo_tmp: str):
    """Danh sách khung: (tag, [(nguồn tmp, khung nguồn, góc cúi, khung đồ trên sheet trận, ms)])."""
    d_walk, t_walk = read_meta(walk_tmp)
    d_combo, t_combo = read_meta(combo_tmp)

    def rng(tags, durs, tmp, name, gear_base=0):
        a, b = tags[name]
        return [(tmp, f, 0.0, f + gear_base, durs[f - 1]) for f in range(a, b + 1)]
    plan = [
        ("idle", rng(t_walk, d_walk, walk_tmp, "idle")),
        ("walk", rng(t_walk, d_walk, walk_tmp, "run_right")),
        ("scratch", rng(t_walk, d_walk, walk_tmp, "run_left")),
        ("flap", rng(t_walk, d_walk, walk_tmp, "jump")),
        ("crow", rng(t_combo, d_combo, combo_tmp, "TAUNT_GayThiUy")),
        ("peck", [(walk_tmp, 1, ang, 1, 90) for ang in PECK_ANGLES]),
    ]
    return plan


def plan_dongtao(combo_tmp: str):
    d, t = read_meta(combo_tmp)

    def rng(name):
        a, b = t[name]
        return [(combo_tmp, f, 0.0, f, d[f - 1]) for f in range(a, b + 1)]
    return [
        ("idle", rng("idle")),
        ("walk", rng("walk")),
        ("scratch", rng("walk")),
        ("flap", rng("TAUNT_DamNguc")),
        ("crow", rng("TAUNT_DamNguc")),
        ("peck", [(combo_tmp, 1, ang, 1, 90) for ang in PECK_ANGLES]),
    ]


def build_variant(v: str, kit: str, plan, preview: str | None):
    sh = Shrinker(SCALES[v], FOOT[kit])
    frames = [fr for _, lst in plan for fr in lst]
    n = len(frames)
    rows = (n + COLS - 1) // COLS
    sheet = np.zeros((rows * sh.h, COLS * sh.w, 4), dtype=np.uint8)
    mask = np.zeros_like(sheet)
    tags, durations, bottoms, tops = {}, [], [], []
    k = 0
    for name, lst in plan:
        tags[name] = [k + 1, k + len(lst)]
        for (tmp, f, ang, _g, ms) in lst:
            rgba, roles = load_frame(tmp, f)
            if ang:
                zone = leg_zone(roles)
                rgba, roles = bend(rgba, roles, ang, zone, hip_of(roles))
            small, sroles = sh.shrink(rgba, roles, eye=EYE[kit], selout=True)
            x, y = (k % COLS) * sh.w, (k // COLS) * sh.h
            sheet[y:y + sh.h, x:x + sh.w] = small
            m = np.zeros((sh.h, sh.w, 4), dtype=np.uint8)
            m[:, :, 0] = (sroles * 32).clip(0, 255)
            m[:, :, 3] = np.where(sroles > 0, 255, 0)
            mask[y:y + sh.h, x:x + sh.w] = m
            durations.append(int(ms))
            ys = np.nonzero(small[:, :, 3])[0]
            bottoms.append(int(ys.max()) + 1 if len(ys) else sh.foot[1])
            tops.append(int(ys.min()) if len(ys) else 0)
            k += 1
    os.makedirs(os.path.join(YARD, "gear"), exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(YARD, v + "_sheet.png"), optimize=True)
    Image.fromarray(mask, "RGBA").save(os.path.join(YARD, v + "_mask.png"), optimize=True)
    items = gear_items(kit)
    for item in items:
        g = np.zeros_like(sheet)
        cache = {}
        for k, (tmp, f, ang, gf, ms) in enumerate(frames):
            key = (gf, ang)
            if key not in cache:
                cell = gear_cell(kit, item, gf)
                if ang:
                    _, r0 = load_frame(tmp, f)
                    cell = bend(cell, None, ang, leg_zone(r0), hip_of(r0))[0]
                cache[key] = sh.shrink(cell, None, thr=0.4, outline=True)[0] if cell[:, :, 3].any() \
                    else np.zeros((sh.h, sh.w, 4), dtype=np.uint8)
            x, y = (k % COLS) * sh.w, (k // COLS) * sh.h
            g[y:y + sh.h, x:x + sh.w] = cache[key]
        Image.fromarray(g, "RGBA").save(os.path.join(YARD, "gear", "%s_%s.png" % (v, item)), optimize=True)
    meta = {"cell": [sh.w, sh.h], "cols": COLS, "count": n, "foot": list(sh.foot), "scale": SCALES[v], "kit": kit,
            "durations": durations, "tags": tags, "bottoms": bottoms, "tops": tops, "gear": items}
    with open(os.path.join(YARD, v + ".json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh)
    print("%s: %d frames, cell %dx%d, foot %s, %d gear layers" % (v, n, sh.w, sh.h, sh.foot, len(items)))
    if preview:
        big = Image.fromarray(sheet, "RGBA")
        bg = Image.new("RGBA", big.size, (196, 160, 110, 255))
        bg.alpha_composite(big)
        bg.resize((bg.width * 4, bg.height * 4), Image.NEAREST).save(os.path.join(preview, "yard_%s.png" % v))


def crown_small() -> Image.Image:
    """Vương miện nhỏ (9×7) đội trên gà chiến ở sân – cỡ vừa con gà nhỏ (vương miện 13×11 cũ to gần bằng đầu gà)."""
    shape = ["Y..Y..Y",
             "YY.Y.YY",
             "YYLRLYY",
             "YYYYYYY",
             "DDDDDDD"]
    pal = {"Y": (247, 196, 58), "L": (255, 238, 150), "R": (206, 46, 52), "D": (176, 112, 30)}
    a = np.zeros((7, 9, 4), dtype=np.uint8)
    for y, row in enumerate(shape):
        for x, ch in enumerate(row):
            if ch != ".":
                a[y + 1, x + 1] = pal[ch] + (255,)
    solid = a[:, :, 3] > 0
    pad = np.pad(solid, 1)
    ring = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]) & ~solid
    a[ring] = (74, 40, 26, 255)
    return Image.fromarray(a, "RGBA")


def main():
    os.makedirs(YARD, exist_ok=True)
    crown_small().save(os.path.join(YARD, "crown_small.png"))
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)
    # 1) sheet đầy đủ rooster_walk_* (cùng định dạng sheet trận)
    tmp = tempfile.mkdtemp(prefix="rooster_walk_")
    try:
        bfs.export_frames(SRC_WALK, tmp)
        count = bfs.pack(tmp, "rooster_walk", ART)
        bfs.export_mask(SRC_WALK, tmp)
        bfs.pack_mask(tmp, "rooster_walk", ART, count)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # 2) sheet gà nhỏ cho sân nhà
    walk_tmp = tempfile.mkdtemp(prefix="rw_walk_")
    rcombo_tmp = tempfile.mkdtemp(prefix="rw_rcombo_")
    dcombo_tmp = tempfile.mkdtemp(prefix="rw_dcombo_")
    try:
        export_clean(SRC_WALK, walk_tmp)
        export_clean(SRC_ROOSTER_COMBO, rcombo_tmp)
        export_clean(SRC_DONGTAO_COMBO, dcombo_tmp)
        rplan = plan_rooster(walk_tmp, rcombo_tmp)
        build_variant("noi", "rooster", rplan, preview)
        build_variant("tre", "rooster", rplan, preview)
        build_variant("dongtao", "dongtao", plan_dongtao(dcombo_tmp), preview)
    finally:
        for t in (walk_tmp, rcombo_tmp, dcombo_tmp):
            shutil.rmtree(t, ignore_errors=True)


if __name__ == "__main__":
    main()
