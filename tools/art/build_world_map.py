# -*- coding: utf-8 -*-
"""Dựng dữ liệu bản đồ thế giới mở rộng (5120×2160) cho MapView – chạy lại được, độc lập với build_assets.py.

Chạy (từ thư mục gốc dự án):
    python -I tools/art/build_world_map.py                 # xuất bằng Aseprite rồi dựng
    python -I tools/art/build_world_map.py --skip-export --export-dir <thư_mục_đã_xuất>
Tuỳ chọn: --aseprite <exe> --art <file.aseprite> --export-dir <tmp> --project <gốc dự án>

Nguồn: D:/GameArt/Chick_Fighter_World_Map_Expanded.aseprite (CHỈ ĐỌC). Bước xuất dùng
tools/art/export_world_layers.lua. Kết quả (ghi đè, PNG thừa của lần dựng trước bị xoá kèm .import):
    game/art/map/map_atlas_*.png   trang atlas ≤ 4096×4096
    game/art/map/map_layers.json   manifest (định dạng v2, xem đầu game/world/map_view.gd)
    game/art/map/map_preview.png   ảnh thu nhỏ 1/4 (màn hình bản đồ, phím M)
    game/art/collision.png         mặt nạ va chạm đủ cỡ (mọi layer lá của 05_Collision)

Quy tắc dựng:
  - below (00_Ground, 01_Water, 02_Decor_Duoi) / above (04_Above):
      * layer tĩnh gộp thành "đợt" (run) theo thứ tự vẽ; một layer tĩnh được gộp vào đợt sớm hơn nếu nó
        không chồng pixel lên bất cứ thứ gì vẽ sau đợt đó (giữ đúng thứ tự vẽ, bớt số đợt);
        mỗi đợt cắt thành ô ≤ 512 (chia tư tới 128 khi ô thưa), bỏ ô trống;
      * layer động nhỏ giữ nguyên dạng node có tên (regions + frames, như v1);
      * layer động lớn (nước, cụm lục bình, cụm tán cây) thành "sparse": các mảnh nhỏ theo thành phần liên thông
        cho từng trạng thái + chuỗi trạng thái 96 frame → không có ảnh khổng lồ trong atlas.
  - object (03_Object): mỗi layer một node có tên (Y-sort). Cụm cây mới (N_ trong NEW_VEGETATION, ô lưới
    ~640×360) được tách theo thành phần liên thông (trên hợp mọi frame) thành từng cây "<tên>#k" để Y-sort đúng.
  - Vật chạy vòng (xe máy, ghe, chim) của bản đồ cũ biến mất ở x≈1280 giữa bản đồ mới → thêm "fade" để mờ dần.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DEFAULT = os.path.abspath(os.path.join(HERE, "..", ".."))
ART_DEFAULT = "D:/GameArt/Chick_Fighter_World_Map_Expanded.aseprite"
ASEPRITE_DEFAULT = "D:/aseprite/build/bin/aseprite.exe"

ATLAS_W = 4096
ATLAS_MAX_H = 4096
TILE = 512
MIN_TILE = 128
SPARSE_MIN = 256          # layer động below/above có khung hợp > 256×256 → sparse
GROUP_ROLE = {"00_Ground": "below", "01_Water": "below", "02_Decor_Duoi": "below",
              "03_Object": "object", "04_Above": "above"}
## Tên node mà code/công cụ khác tra theo tên (MapView API, race, arena, minigame): luôn giữ dạng node có tên.
REQUIRED_NAMES = [
    "A_cau_van_ben_ghe", "A_cau_van_noi_dai", "A_ghe_nhua_01", "A_quan_tap_hoa_tuong", "A_xe_may_cho_ga",
    "A_xe_may_con_tay_do", "B_cay_da_01_goc", "B_cay_da_01_tan", "B_chuoi_01", "B_co_dau_truong_01",
    "B_co_hoi_dinh", "B_cot_co_dinh", "B_cot_dien_01", "B_den_long_01", "B_den_long_02", "B_dinh_bac_tam_cap",
    "B_dinh_tuong_cot", "B_dua_01_tan", "B_dua_01_than", "B_dua_03_tan", "B_dua_03_than", "B_dua_04_tan",
    "B_dua_04_than", "B_dua_05_tan", "B_dua_05_than", "B_dua_nuoc_02", "B_ga_nha_01", "B_ga_nha_02",
    "B_khoi_nhang", "B_nha_vuon_1_tuong", "C_ca_tra_cau_van", "C_ca_tra_con_01", "C_cau_tau_ben_do",
    "C_chuoi_02", "C_cot_dien_01", "C_dua_04_tan", "C_dua_04_than", "C_dua_nuoc_01", "C_khoi_bep",
    "C_nha_la_tuong", "C_xe_may_cho_dua", "C_xe_may_con_tay_den", "D_dua_02_tan", "D_dua_02_than", "E_vit_01",
    "F_co_to_quoc", "F_day_co_hoi_01", "F_day_co_hoi_02", "NV_ao_ngua_o_san_dinh",
    "NV_ba_lo_canh_cong_dau_truong", "NV_cho_vang", "NV_co_ban_ve_so", "NV_dam_trang_o_nha_vuon",
    "NV_khan_gia_1", "NV_khan_gia_2", "NV_khan_gia_3", "NV_khan_gia_4", "NV_non_den_jean_goi_dien",
    "NV_ong_cau_ca", "NV_rapper_mc_dau_truong", "NV_vest_ca_vat_do_o_san_den", "NV_xam_tay_nhay_o_quan",
    "song_do_ngang", "song_do_ngang_gon", "song_vo_lai_1_boc_dau", "song_vo_lai_2",
]


def log(*a):
    try:
        print(*a, flush=True)
    except UnicodeEncodeError:
        print(*(str(v).encode("ascii", "replace").decode() for v in a), flush=True)


# ------------------------------------------------------------------ xuất từ Aseprite

def export(aseprite, art, out):
    for sub in ("", "coll", "guide"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for name in os.listdir(out):
        if name.endswith(".png") or name.endswith(".tsv"):
            os.remove(os.path.join(out, name))
    lua = os.path.join(HERE, "export_world_layers.lua")
    t = time.time()
    subprocess.run([aseprite, "-b", art, "--script-param", "out=" + out.replace("\\", "/"), "--script", lua], check=True)
    log("export: %.1fs" % (time.time() - t))


def read_rows(src):
    rows = []
    with open(os.path.join(src, "manifest.tsv"), encoding="utf8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            idx, top, gp, name, n, frames = line.split("\t")
            parsed = []
            for token in frames.split(" "):
                parsed.append(None if token == "-1" else tuple(int(v) for v in token.split(":")))
            rows.append({"idx": int(idx), "top": top, "gp": gp, "name": name, "n": int(n), "frames": parsed})
    with open(os.path.join(src, "size.txt")) as f:
        w, h, count, ms = (int(v) for v in f.read().split())
    return rows, (w, h, count, ms)


# ------------------------------------------------------------------ atlas

class Packer:
    """Gom mọi ảnh rồi xếp kệ (cao giảm dần) vào các trang ≤ ATLAS_W×ATLAS_MAX_H. Ảnh trùng byte dùng chung."""

    def __init__(self):
        self.items = []      # [img, ref(list sẽ được điền [page,x,y,w,h])]
        self.by_hash = {}

    def add(self, img):
        key = hashlib.md5(img.tobytes() + bytes(str(img.size), "ascii")).hexdigest()
        if key in self.by_hash:
            return self.by_hash[key]
        ref = [0, 0, 0, img.width, img.height]
        self.items.append((img, ref))
        self.by_hash[key] = ref
        return ref

    def pack(self, out_dir, prefix="map_atlas"):
        order = sorted(range(len(self.items)), key=lambda i: (-self.items[i][0].height, -self.items[i][0].width))
        pages = [[]]
        x = y = row_h = 0
        for i in order:
            img, ref = self.items[i]
            w, h = img.size
            if x + w > ATLAS_W:
                x = 0
                y += row_h + 1
                row_h = 0
            if y + h > ATLAS_MAX_H:
                pages.append([])
                x = y = row_h = 0
            ref[0], ref[1], ref[2] = len(pages) - 1, x, y
            pages[-1].append((img, x, y))
            x += w + 1
            row_h = max(row_h, h)
        names = []
        for p, content in enumerate(pages):
            used_h = max(yy + img.height for img, _, yy in content)
            used_w = max(xx + img.width for img, xx, _ in content)
            page = Image.new("RGBA", (used_w, used_h), (0, 0, 0, 0))
            for img, xx, yy in content:
                page.paste(img, (xx, yy))
            name = "%s_%d.png" % (prefix, p)
            page.save(os.path.join(out_dir, name), optimize=True)
            names.append(name)
            log("  %s %dx%d (%d ảnh)" % (name, used_w, used_h, len(content)))
        return names


# ------------------------------------------------------------------ tiện ích ảnh

class Layers:
    def __init__(self, src, size):
        self.src = src
        self.W, self.H = size
        self.cache = {}

    def image(self, row, u, op=255):
        key = (row["idx"], u, op)
        if key not in self.cache:
            img = Image.open(os.path.join(self.src, "L%04d_%02d.png" % (row["idx"], u))).convert("RGBA")
            if op < 255:
                a = np.asarray(img).copy()
                a[..., 3] = (a[..., 3].astype(np.int32) * op // 255).astype(np.uint8)
                img = Image.fromarray(a, "RGBA")
            if len(self.cache) > 400:
                self.cache.clear()
            self.cache[key] = img
        return self.cache[key]

    def clip(self, img, x, y):
        """Cắt ảnh theo khung bản đồ → (ảnh, x, y) hoặc None."""
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + img.width, self.W), min(y + img.height, self.H)
        if x1 <= x0 or y1 <= y0:
            return None
        if (x0, y0, x1, y1) != (x, y, x + img.width, y + img.height):
            img = img.crop((x0 - x, y0 - y, x1 - x, y1 - y))
        return img, x0, y0


def alpha_mask(img):
    return np.asarray(img)[..., 3] > 0


def is_static(row):
    first = row["frames"][0]
    return first is not None and all(fr == first for fr in row["frames"])


def union_box(row, L):
    box = None
    for fr in row["frames"]:
        if fr is None:
            continue
        img = L.image(row, fr[0])
        b = (fr[1], fr[2], fr[1] + img.width, fr[2] + img.height)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


# ------------------------------------------------------------------ below / above

class Run:
    def __init__(self, W, H):
        self.canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.after = np.zeros((H, W), bool)   # mọi pixel được vẽ SAU đợt này
        self.layers = 0


def build_flat_role(rows, L, packer, role, report):
    W, H = L.W, L.H
    order = []          # ("run", Run) | ("anim", row)
    runs = []

    def mark_after(mask, x, y, upto):
        h, w = mask.shape
        for r in runs[:upto]:
            r.after[y:y + h, x:x + w] |= mask

    for row in rows:
        if GROUP_ROLE.get(row["top"]) != role:
            continue
        if is_static(row):
            u, x, y, op = row["frames"][0]
            clipped = L.clip(L.image(row, u, op), x, y)
            if clipped is None:
                continue
            img, x, y = clipped
            mask = alpha_mask(img)
            h, w = mask.shape
            target = None
            for i in range(len(runs) - 1, -1, -1):
                if runs[i].after[y:y + h, x:x + w][mask].any():
                    break
                target = i
            if target is None:
                runs.append(Run(W, H))
                order.append(("run", runs[-1]))
                target = len(runs) - 1
            run = runs[target]
            run.canvas.alpha_composite(img, (x, y))
            run.layers += 1
            mark_after(mask, x, y, target)
        else:
            order.append(("anim", row))
            seen = set()
            for fr in row["frames"]:
                if fr is None or (fr[0], fr[1], fr[2]) in seen:
                    continue
                seen.add((fr[0], fr[1], fr[2]))
                clipped = L.clip(L.image(row, fr[0]), fr[1], fr[2])
                if clipped is None:
                    continue
                img, x, y = clipped
                mark_after(alpha_mask(img), x, y, len(runs))
    nodes = []
    stats = {"runs": len(runs), "tiles": 0, "named": 0, "sparse": 0, "pieces": 0}
    for kind, value in order:
        if kind == "run":
            tiles = []
            for ty in range(0, H, TILE):
                for tx in range(0, W, TILE):
                    quad_tiles(value.canvas, tx, ty, TILE, tiles)
            for img, x, y in tiles:
                nodes.append({"static": packer.add(img), "pos": [x, y]})
            stats["tiles"] += len(tiles)
            value.canvas = None
            value.after = None
        else:
            row = value
            box = union_box(row, L)
            if box is None:
                continue
            big = (box[2] - box[0]) > SPARSE_MIN and (box[3] - box[1]) > SPARSE_MIN
            if big and row["name"] not in REQUIRED_NAMES:
                node = sparse_node(row, L, packer)
                stats["sparse"] += 1
                stats["pieces"] += len(node["sparse"])
            else:
                node = named_node(row, L, packer)
                stats["named"] += 1
            if node is not None:
                nodes.append(node)
    report[role] = stats
    return nodes


def quad_tiles(canvas, x, y, size, out):
    W, H = canvas.size
    crop = canvas.crop((x, y, min(x + size, W), min(y + size, H)))
    bbox = crop.getbbox()
    if bbox is None:
        return
    part = crop.crop(bbox)
    area = part.width * part.height
    filled = int((np.asarray(part)[..., 3] > 0).sum())
    if size > MIN_TILE and filled < 0.4 * area:
        half = size // 2
        for dy in (0, half):
            for dx in (0, half):
                if x + dx < W and y + dy < H:
                    quad_tiles(canvas, x + dx, y + dy, half, out)
        return
    out.append((part, x + bbox[0], y + bbox[1]))


def named_node(row, L, packer, add_fade=True):
    regions = []
    index = {}
    frames = []
    for fr in row["frames"]:
        if fr is None:
            frames.append(None)
            continue
        u, x, y, op = fr
        key = (u, op)
        if key not in index:
            index[key] = len(regions)
            regions.append(packer.add(L.image(row, u, op)))
        frames.append([index[key], x, y])
    if not regions:
        return None
    node = {"name": row["name"], "regions": regions}
    if all(f == frames[0] for f in frames):
        node["static_frame"] = frames[0]
    else:
        node["frames"] = frames
        if add_fade:
            fade = fade_for(row, L)
            if fade is not None:
                node["fade"] = fade
    return node


def fade_for(row, L):
    """Vật chạy vòng của bản đồ cũ: biến mất ở mép phải cũ (x≈1280) giữa bản đồ mới → khoảng mờ dần."""
    vis = [fr for fr in row["frames"] if fr is not None]
    xs = [fr[1] for fr in vis]
    if max(xs) - min(xs) < 300:
        return None
    right = max(fr[1] + L.image(row, fr[0]).width for fr in vis)
    if right >= L.W - 16:
        return None
    return [right - 90, right - 10]


def sparse_node(row, L, packer):
    """Layer động lớn → các mảnh theo thành phần liên thông cho mỗi trạng thái (u,x,y,op) khác nhau."""
    states = {}
    seq = []
    pieces = []
    for fr in row["frames"]:
        if fr is None:
            seq.append(-1)
            continue
        if fr not in states:
            sid = len(states)
            states[fr] = sid
            u, x, y, op = fr
            clipped = L.clip(L.image(row, u, op), x, y)
            if clipped is not None:
                img, x0, y0 = clipped
                arr = np.asarray(img)
                mask = arr[..., 3] > 0
                grown = ndimage.binary_dilation(mask, iterations=3)
                lab, n = ndimage.label(grown, structure=np.ones((3, 3), bool))
                lab = np.where(mask, lab, 0)
                for k, sl in enumerate(ndimage.find_objects(lab), start=1):
                    if sl is None:
                        continue
                    sub = arr[sl].copy()
                    sub[lab[sl] != k] = 0
                    ref = packer.add(Image.fromarray(sub, "RGBA"))
                    pieces.append([sid, ref, x0 + sl[1].start, y0 + sl[0].start])
        seq.append(states[fr])
    # mảnh: [trạng thái, trang, ax, ay, w, h, x, y] – tham chiếu ref còn được điền khi pack, nên giữ list ref
    return {"name": row["name"], "sparse": pieces, "seq": seq, "_sparse_refs": True}


# ------------------------------------------------------------------ object

def split_candidates(row, L):
    n = row["name"]
    return n.startswith("N_") and row["gp"].endswith("NEW_VEGETATION")


def build_objects(rows, L, packer, report):
    nodes = []
    split_count = 0
    parts_total = 0
    for row in rows:
        if GROUP_ROLE.get(row["top"]) != "object":
            continue
        if split_candidates(row, L):
            parts = split_node(row, L, packer)
            if parts:
                nodes.extend(parts)
                split_count += 1
                parts_total += len(parts)
                continue
        node = named_node(row, L, packer)
        if node is not None:
            nodes.append(node)
    report["object"] = {"nodes": len(nodes), "split_layers": split_count, "split_parts": parts_total}
    return nodes


def split_node(row, L, packer):
    box = union_box(row, L)
    if box is None:
        return None
    x0, y0, x1, y1 = box
    union = np.zeros((y1 - y0, x1 - x0), bool)
    entries = {}
    for fr in row["frames"]:
        if fr is None or fr in entries:
            continue
        img = L.image(row, fr[0], fr[3])
        entries[fr] = img
        m = alpha_mask(img)
        union[fr[2] - y0:fr[2] - y0 + m.shape[0], fr[1] - x0:fr[1] - x0 + m.shape[1]] |= m
    lab, n = ndimage.label(ndimage.binary_dilation(union, iterations=1), structure=np.ones((3, 3), bool))
    lab = np.where(union, lab, 0)
    if n < 2:
        return None
    parts = []
    for k, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        cx0, cy0 = x0 + sl[1].start, y0 + sl[0].start
        cw, ch = sl[1].stop - sl[1].start, sl[0].stop - sl[0].start
        comp = lab[sl] == k
        regions = []
        index = {}
        frames = []
        for fr in row["frames"]:
            if fr is None:
                frames.append(None)
                continue
            img = entries[fr]
            cell = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            cell.paste(img, (fr[1] - cx0, fr[2] - cy0))
            arr = np.asarray(cell).copy()
            arr[~comp] = 0
            if not (arr[..., 3] > 0).any():
                frames.append(None)
                continue
            key = arr.tobytes()
            if key not in index:
                index[key] = len(regions)
                regions.append(packer.add(Image.fromarray(arr, "RGBA")))
            frames.append([index[key], cx0, cy0])
        if not regions:
            continue
        node = {"name": "%s#%d" % (row["name"], len(parts)), "part_of": row["name"], "regions": regions}
        if all(f == frames[0] for f in frames):
            node["static_frame"] = frames[0]
        else:
            node["frames"] = frames
        parts.append(node)
    return parts


# ------------------------------------------------------------------ va chạm + ảnh xem trước

def build_collision(src, size, out_path):
    W, H = size
    mask = np.zeros((H, W), bool)
    names = []
    with open(os.path.join(src, "coll.tsv"), encoding="utf8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5 or parts[3] == "-1":
                continue
            idx, x, y = int(parts[0]), int(parts[3]), int(parts[4])
            img = Image.open(os.path.join(src, "coll", "C%02d.png" % idx)).convert("RGBA")
            a = np.asarray(img)[..., 3] > 0
            h, w = a.shape
            xa, ya = max(x, 0), max(y, 0)
            xb, yb = min(x + w, W), min(y + h, H)
            mask[ya:yb, xa:xb] |= a[ya - y:yb - y, xa - x:xb - x]
            names.append(parts[2])
    Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L").save(out_path, optimize=True)
    log("collision: %s (%d layer: %s) blocked=%d" % (out_path, len(names), ", ".join(names), int(mask.sum())))


def build_preview(rows, L, out_path, scale=4):
    canvas = Image.new("RGBA", (L.W, L.H), (0, 0, 0, 255))
    for row in rows:
        if row["top"] not in GROUP_ROLE:
            continue
        fr = row["frames"][0]
        if fr is None:
            continue
        clipped = L.clip(L.image(row, fr[0], fr[3]), fr[1], fr[2])
        if clipped is None:
            continue
        img, x, y = clipped
        canvas.alpha_composite(img, (x, y))
    canvas.convert("RGB").resize((L.W // scale, L.H // scale), Image.BOX).save(out_path, optimize=True)
    log("preview: %s" % out_path)


# ------------------------------------------------------------------ chính

def finalize_refs(nodes):
    """Đổi các tham chiếu sparse [sid, ref, x, y] thành [sid, trang, ax, ay, w, h, x, y]."""
    for node in nodes:
        if node.pop("_sparse_refs", False):
            node["sparse"] = [[sid] + list(ref) + [x, y] for sid, ref, x, y in node["sparse"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aseprite", default=ASEPRITE_DEFAULT)
    ap.add_argument("--art", default=ART_DEFAULT)
    ap.add_argument("--export-dir", default=os.path.join(tempfile.gettempdir(), "chick_world_export"))
    ap.add_argument("--skip-export", action="store_true")
    ap.add_argument("--project", default=ROOT_DEFAULT)
    args = ap.parse_args()
    t0 = time.time()
    if not args.skip_export:
        export(args.aseprite, args.art, args.export_dir)
    rows, (W, H, count, ms) = read_rows(args.export_dir)
    log("layers: %d, size %dx%d, %d frame × %d ms" % (len(rows), W, H, count, ms))
    L = Layers(args.export_dir, (W, H))
    packer = Packer()
    report = {}
    below = build_flat_role(rows, L, packer, "below", report)
    log("below: %s (%.1fs)" % (report["below"], time.time() - t0))
    objects = build_objects(rows, L, packer, report)
    log("object: %s (%.1fs)" % (report["object"], time.time() - t0))
    above = build_flat_role(rows, L, packer, "above", report)
    log("above: %s (%.1fs)" % (report["above"], time.time() - t0))

    map_out = os.path.join(args.project, "game", "art", "map")
    os.makedirs(map_out, exist_ok=True)
    tmp_out = os.path.join(args.export_dir, "_atlas")
    os.makedirs(tmp_out, exist_ok=True)
    for name in os.listdir(tmp_out):
        os.remove(os.path.join(tmp_out, name))
    atlases = packer.pack(tmp_out)
    for section in (below, objects, above):
        finalize_refs(section)
    names = {n.get("name") for n in below + objects + above if n.get("name") and "regions" in n}
    missing = [n for n in REQUIRED_NAMES if n not in names]
    if missing:
        raise SystemExit("THIẾU node có tên mà code cần: %s" % missing)

    # Ghi ra dự án: xoá PNG atlas cũ (kèm .import) không còn dùng, giữ mọi .uid.
    keep = set(atlases) | {"map_layers.json", "map_preview.png"}
    for name in os.listdir(map_out):
        base = name[:-7] if name.endswith(".import") else name
        if base.endswith(".png") and base not in keep:
            os.remove(os.path.join(map_out, name))
    for name in atlases:
        os.replace(os.path.join(tmp_out, name), os.path.join(map_out, name))
    manifest = {"version": 2, "frame_ms": ms, "frame_count": count, "size": [W, H], "cell": TILE,
                "atlases": atlases, "below": below, "object": objects, "above": above}
    with open(os.path.join(map_out, "map_layers.json"), "w", encoding="utf8") as f:
        json.dump(manifest, f, separators=(",", ":"), ensure_ascii=False)
    build_collision(args.export_dir, (W, H), os.path.join(args.project, "game", "art", "collision.png"))
    build_preview(rows, L, os.path.join(map_out, "map_preview.png"))
    total = sum(os.path.getsize(os.path.join(map_out, n)) for n in os.listdir(map_out))
    log("game/art/map: %.1f MB, atlases=%d, below=%d object=%d above=%d, %.1fs" % (
        total / 1e6, len(atlases), len(below), len(objects), len(above), time.time() - t0))


if __name__ == "__main__":
    main()
