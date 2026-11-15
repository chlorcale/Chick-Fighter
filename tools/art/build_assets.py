"""Đóng gói art xuất từ Aseprite thành atlas + JSON cho Godot.

Bước 1 (Aseprite, chạy trong D:/GameArt):
  aseprite -b BoiCanh_MienTay_NhanVat.aseprite --script-param out=<tmp>/layers --script export_map_layers.lua
  aseprite -b BoiCanh_MienTay_NhanVat.aseprite --script-param out=<tmp>/coll_full.png --script export_collision.lua
  aseprite -b rooster_fight_combo.aseprite     --script-param out=<tmp>/rooster --script export_rooster.lua
  aseprite -b truongcon.aseprite (layer "Vien" tắt) -> player_sheet.png  (xem build cũ)
Bước 2:
  python -I build_assets.py <tmp> <project_root>

Bản đồ: mỗi layer lá được phân loại
  - tĩnh (một ảnh, cùng vị trí, có ở cả 96 frame) -> gộp các layer tĩnh liền nhau thành một ảnh;
  - động (đổi ảnh hoặc đổi vị trí: nước, xe, ghe, cây lắc, khói...) -> giữ riêng, đủ 96 frame 80 ms.
Layer 03_Object không gộp để Godot Y-sort từng vật với nhân vật (GDD Bảng 8.2).
"""
import json
import os
import sys

from PIL import Image

FRAME_COUNT = 96
MAP_W = 1280
CROP_H = 1080         # cả hai bờ sông (Màn A–F)
ATLAS_W = 2048
ATLAS_MAX_H = 2048

GROUP_ROLE = {"00_Ground": "below", "01_Water": "below", "02_Decor_Duoi": "below",
              "03_Object": "object", "04_Above": "above"}


class AtlasPacker:
    def __init__(self, prefix):
        self.prefix = prefix
        self.pages = []
        self._new_page()

    def _new_page(self):
        self.pages.append({"img": Image.new("RGBA", (ATLAS_W, ATLAS_MAX_H), (0, 0, 0, 0)),
                           "x": 0, "y": 0, "row_h": 0})

    def add(self, img):
        w, h = img.size
        page = self.pages[-1]
        if page["x"] + w + 1 > ATLAS_W:
            page["x"] = 0
            page["y"] += page["row_h"] + 1
            page["row_h"] = 0
        if page["y"] + h + 1 > ATLAS_MAX_H:
            self._new_page()
            page = self.pages[-1]
        x, y = page["x"], page["y"]
        page["img"].paste(img, (x, y))
        page["x"] += w + 1
        page["row_h"] = max(page["row_h"], h)
        return [len(self.pages) - 1, x, y, w, h]

    def save(self, out_dir):
        names = []
        for i, page in enumerate(self.pages):
            used_h = page["y"] + page["row_h"] + 1
            name = "%s_%d.png" % (self.prefix, i)
            page["img"].crop((0, 0, ATLAS_W, used_h)).save(os.path.join(out_dir, name), optimize=True)
            names.append(name)
        return names


def with_opacity(img, op):
    if op >= 255:
        return img
    r, g, b, a = img.split()
    a = a.point(lambda v: v * op // 255)
    return Image.merge("RGBA", (r, g, b, a))


def build_map(src, out_dir):
    rows = []
    with open(os.path.join(src, "manifest.tsv"), encoding="utf8") as f:
        for line in f:
            idx, top, parent, name, nuniq, frames = line.rstrip("\n").split("\t")
            parsed = []
            for token in frames.split(" "):
                if token == "-1":
                    parsed.append(None)
                else:
                    u, x, y, op = (int(v) for v in token.split(":"))
                    parsed.append((u, x, y, op))
            rows.append({"idx": int(idx), "top": top, "name": name, "frames": parsed})

    cache = {}

    def image(row, u):
        key = (row["idx"], u)
        if key not in cache:
            cache[key] = Image.open(os.path.join(src, "L%03d_%02d.png" % key)).convert("RGBA")
        return cache[key]

    def is_static(row):
        first = row["frames"][0]
        return first is not None and all(fr == first for fr in row["frames"])

    def in_crop(row):
        for fr in row["frames"]:
            if fr is not None and fr[2] < CROP_H:
                return True
        return False

    packer = AtlasPacker("map_atlas")
    nodes = {"below": [], "object": [], "above": []}
    pending = {"below": None, "above": None}   # canvas gộp layer tĩnh đang mở

    def flush(role):
        canvas = pending[role]
        pending[role] = None
        if canvas is None:
            return
        bbox = canvas.getbbox()
        if bbox is None:
            return
        region = packer.add(canvas.crop(bbox))
        nodes[role].append({"static": region, "pos": [bbox[0], bbox[1]]})

    for row in rows:
        role = GROUP_ROLE.get(row["top"])
        if role is None or not in_crop(row):
            continue
        if role != "object" and is_static(row):
            u, x, y, op = row["frames"][0]
            if pending[role] is None:
                pending[role] = Image.new("RGBA", (MAP_W, CROP_H), (0, 0, 0, 0))
            layer_img = with_opacity(image(row, u), op)
            tmp = Image.new("RGBA", (MAP_W, CROP_H), (0, 0, 0, 0))
            tmp.paste(layer_img, (x, y))
            pending[role].alpha_composite(tmp)
            continue
        if role != "object":
            flush(role)
        # Layer động (hoặc vật thể 03_Object): mỗi ảnh duy nhất vào atlas một lần.
        regions = []
        region_index = {}
        frames = []
        for fr in row["frames"]:
            if fr is None:
                frames.append(None)
                continue
            u, x, y, op = fr
            key = (u, op)
            if key not in region_index:
                region_index[key] = len(regions)
                regions.append(packer.add(with_opacity(image(row, u), op)))
            frames.append([region_index[key], x, y])
        node = {"name": row["name"], "regions": regions}
        if all(f == frames[0] for f in frames):
            node["static_frame"] = frames[0]
        else:
            node["frames"] = frames
        nodes[role].append(node)
    flush("below")
    flush("above")

    atlases = packer.save(out_dir)
    manifest = {"frame_ms": 80, "frame_count": FRAME_COUNT, "size": [MAP_W, CROP_H],
                "atlases": atlases, "below": nodes["below"], "object": nodes["object"],
                "above": nodes["above"]}
    with open(os.path.join(out_dir, "map_layers.json"), "w", encoding="utf8") as f:
        json.dump(manifest, f, separators=(",", ":"), ensure_ascii=False)
    print("map: atlases=%d below=%d object=%d above=%d" % (
        len(atlases), len(nodes["below"]), len(nodes["object"]), len(nodes["above"])))

    # Sprite NPC (dùng làm khán giả trên sới và chân dung hội thoại).
    npc_dir = os.path.join(out_dir, "..", "npc")
    os.makedirs(npc_dir, exist_ok=True)
    wanted = {"NV_khan_gia_1": "crowd_1", "NV_khan_gia_2": "crowd_2", "NV_khan_gia_3": "crowd_3",
              "NV_khan_gia_4": "crowd_4", "NV_rapper_mc_dau_truong": "mc",
              "NV_ao_ngua_o_san_dinh": "chu_tu", "NV_ba_lo_canh_cong_dau_truong": "teo",
              "NV_xam_tay_nhay_o_quan": "shop", "NV_dam_trang_o_nha_vuon": "lady",
              "NV_non_den_jean_goi_dien": "crowd_5", "NV_ong_cau_ca": "fisher", "song_do_ngang": "ferry",
              "NV_co_ban_ve_so": "lottery", "NV_vest_ca_vat_do_o_san_den": "temple_man"}
    for row in rows:
        if row["name"] in wanted and row["frames"][0] is not None:
            image(row, row["frames"][0][0]).save(os.path.join(npc_dir, wanted[row["name"]] + ".png"))


def build_rooster(src, out_dir):
    """rooster_fight_combo.aseprite: 153 frame, 21 tag (xem D:/GameArt/rooster_fight_movelist.md)."""
    cell_w, cell_h = 128, 112
    durations = []
    tags = {}
    with open(os.path.join(src, "meta.txt"), encoding="utf8") as f:
        for line in f:
            parts = line.rstrip(chr(10)).split(chr(9))
            if parts[0] == "frame":
                durations.append(int(parts[2]))
            elif parts[0] == "tag":
                tags[parts[1]] = [int(parts[2]), int(parts[3])]
    count = len(durations)
    cols = 12
    sheet = Image.new("RGBA", (cols * cell_w, ((count + cols - 1) // cols) * cell_h), (0, 0, 0, 0))
    bottoms = []
    boxes = []
    for i in range(count):
        frame = Image.open(os.path.join(src, "body_%03d.png" % (i + 1))).convert("RGBA")
        sheet.paste(frame, ((i % cols) * cell_w, (i // cols) * cell_h))
        bbox = frame.getbbox() or (0, 0, cell_w, cell_h)
        bottoms.append(bbox[3])
        boxes.append(list(bbox))
    sheet.save(os.path.join(out_dir, "rooster_sheet.png"), optimize=True)
    with open(os.path.join(out_dir, "rooster.json"), "w", encoding="utf8") as f:
        json.dump({"cell": [cell_w, cell_h], "cols": cols, "count": count, "durations": durations,
                   "tags": tags, "bottoms": bottoms, "boxes": boxes}, f)
    print("rooster: %d frames, %d tags" % (count, len(tags)))


def build_bike(out_dir):
    """Xe máy pixel art 3 hướng (vẽ bằng code): ngang (nhìn phải), trước (đi xuống), sau (đi lên)."""
    K = (34, 30, 32, 255)      # bánh xe / viền
    G = (150, 150, 158, 255)   # kim loại
    R = (196, 52, 40, 255)     # thân đỏ
    D = (130, 30, 26, 255)     # đỏ tối
    B = (28, 24, 26, 255)      # yên
    Y = (255, 222, 90, 255)    # đèn
    W = (240, 240, 235, 255)
    def canvas(w, h):
        return Image.new("RGBA", (w, h), (0, 0, 0, 0))
    def rect(img, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < img.width and 0 <= y < img.height:
                    img.putpixel((x, y), c)
    def wheel(img, cx, cy):
        for y in range(-5, 6):
            for x in range(-5, 6):
                d = x * x + y * y
                if d <= 26:
                    img.putpixel((cx + x, cy + y), K if d > 6 else G)
    side = canvas(38, 24)
    wheel(side, 7, 18)
    wheel(side, 30, 18)
    rect(side, 9, 11, 27, 15, R)
    rect(side, 9, 15, 25, 15, D)
    rect(side, 11, 8, 22, 10, B)
    rect(side, 3, 13, 9, 14, G)          # ống xả
    rect(side, 26, 7, 27, 17, G)         # phuộc
    rect(side, 25, 5, 30, 5, G)          # tay lái
    rect(side, 28, 7, 30, 9, Y)          # đèn
    rect(side, 22, 10, 26, 12, D)
    side.save(os.path.join(out_dir, "bike_side.png"))
    O = (255, 150, 40, 255)
    def handlebar(img):
        rect(img, 2, 6, 19, 6, G)
        rect(img, 0, 6, 1, 7, K); rect(img, 20, 6, 21, 7, K)
        rect(img, 3, 2, 3, 5, G); rect(img, 18, 2, 18, 5, G)
        rect(img, 2, 0, 4, 2, K); rect(img, 17, 0, 19, 2, K)
    front = canvas(22, 26)
    rect(front, 9, 16, 12, 25, K)
    rect(front, 10, 19, 11, 19, G); rect(front, 10, 22, 11, 22, G)
    rect(front, 8, 15, 13, 16, D)
    rect(front, 6, 7, 15, 14, R)
    rect(front, 5, 8, 16, 13, R)
    rect(front, 6, 13, 15, 14, D)
    rect(front, 8, 9, 13, 12, Y)
    rect(front, 9, 9, 10, 10, W)
    rect(front, 4, 10, 4, 11, O); rect(front, 17, 10, 17, 11, O)
    handlebar(front)
    front.save(os.path.join(out_dir, "bike_front.png"))
    back = canvas(22, 26)
    rect(back, 9, 18, 12, 25, K)
    rect(back, 10, 21, 11, 21, G); rect(back, 10, 24, 11, 24, G)
    rect(back, 6, 4, 15, 8, B)
    rect(back, 5, 8, 16, 15, R)
    rect(back, 5, 14, 16, 15, D)
    rect(back, 8, 10, 13, 11, (255, 60, 50, 255))
    rect(back, 4, 10, 4, 11, O); rect(back, 17, 10, 17, 11, O)
    rect(back, 8, 16, 13, 18, W)
    handlebar(back)
    back.save(os.path.join(out_dir, "bike_back.png"))


if __name__ == "__main__":
    tmp, project = sys.argv[1], sys.argv[2]
    art = os.path.join(project, "game", "art")
    map_out = os.path.join(art, "map")
    os.makedirs(map_out, exist_ok=True)
    for name in os.listdir(map_out):
        if name.endswith(".png") or name.endswith(".import") or name.endswith(".json"):
            os.remove(os.path.join(map_out, name))
    build_map(os.path.join(tmp, "layers"), map_out)
    build_rooster(os.path.join(tmp, "rooster"), art)
    build_bike(art)
    coll = Image.open(os.path.join(tmp, "coll_full.png")).convert("RGBA")
    mask = Image.new("L", coll.size, 0)
    mask.putdata([255 if px[3] > 0 else 0 for px in coll.getdata()])
    mask.save(os.path.join(art, "collision.png"))
