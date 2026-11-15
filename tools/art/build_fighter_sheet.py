"""Đóng gói sheet chiến kê cho một bộ chiêu (kit) mới, độc lập với build_assets.py.

    python tools/art/build_fighter_sheet.py <file.aseprite> <tên> [thư_mục_ra] [--mask-only]

Ví dụ:  python tools/art/build_fighter_sheet.py D:/GameArt/dongtao_fight_combo.aseprite dongtao
-> game/art/dongtao_sheet.png + game/art/dongtao.json (cùng định dạng rooster_sheet.png / rooster.json:
   cell, cols, count, durations (ms), tags (1-based, gồm cả hai đầu), bottoms, boxes).
Kèm theo <tên>_mask.png (cùng bố cục): kênh R = mã bộ phận * 32 (xem export_fighter_mask.lua),
shader rooster.gdshader dùng để đổi màu lông mà không làm hỏng mào, chân, mắt, hiệu ứng.
--mask-only: chỉ tạo mặt nạ (dùng cho rooster: sheet rooster_sheet.png do build_assets.py tạo).
File .aseprite chỉ được đọc, không bị sửa.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ASEPRITE = os.environ.get("ASEPRITE", r"D:\aseprite\build\bin\aseprite.exe")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def export_frames(src_file, tmp):
    subprocess.run([ASEPRITE, "-b", src_file, "--script-param", "out=" + tmp,
                    "--script", os.path.join(HERE, "export_fighter.lua")], check=True)


def export_mask(src_file, tmp):
    subprocess.run([ASEPRITE, "-b", src_file, "--script-param", "out=" + tmp,
                    "--script", os.path.join(HERE, "export_fighter_mask.lua")], check=True)


def pack_mask(tmp, name, out_dir, count, cell_w=128, cell_h=112, cols=12):
    sheet = Image.new("RGBA", (cols * cell_w, ((count + cols - 1) // cols) * cell_h), (0, 0, 0, 0))
    for i in range(count):
        frame = Image.open(os.path.join(tmp, "mask_%03d.png" % (i + 1))).convert("RGBA")
        sheet.paste(frame, ((i % cols) * cell_w, (i // cols) * cell_h))
    sheet.save(os.path.join(out_dir, name + "_mask.png"), optimize=True)
    print("%s_mask.png: %d frames" % (name, count))


def pack(tmp, name, out_dir, cell_w=128, cell_h=112, cols=12):
    durations, tags, layers = [], {}, []
    with open(os.path.join(tmp, "meta.txt"), encoding="utf8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if parts[0] == "frame":
                durations.append(int(parts[2]))
            elif parts[0] == "tag":
                tags[parts[1]] = [int(parts[2]), int(parts[3])]
            elif parts[0] == "layer":
                layers.append(parts[1])
    count = len(durations)
    sheet = Image.new("RGBA", (cols * cell_w, ((count + cols - 1) // cols) * cell_h), (0, 0, 0, 0))
    bottoms, boxes = [], []
    for i in range(count):
        frame = Image.open(os.path.join(tmp, "body_%03d.png" % (i + 1))).convert("RGBA")
        sheet.paste(frame, ((i % cols) * cell_w, (i // cols) * cell_h))
        bbox = frame.getbbox() or (0, 0, cell_w, cell_h)
        bottoms.append(bbox[3])
        boxes.append(list(bbox))
    sheet.save(os.path.join(out_dir, name + "_sheet.png"), optimize=True)
    with open(os.path.join(out_dir, name + ".json"), "w", encoding="utf8") as f:
        json.dump({"cell": [cell_w, cell_h], "cols": cols, "count": count, "durations": durations,
                   "tags": tags, "bottoms": bottoms, "boxes": boxes}, f)
    print("%s: %d frames, %d tags, layers=%s" % (name, count, len(tags), layers))
    return count


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mask_only = "--mask-only" in sys.argv
    src_file, name = args[0], args[1]
    out_dir = args[2] if len(args) > 2 else os.path.join(ROOT, "game", "art")
    tmp = tempfile.mkdtemp(prefix="fighter_")
    try:
        export_frames(src_file, tmp)
        if mask_only:
            count = len([f for f in os.listdir(tmp) if f.startswith("body_")])
        else:
            count = pack(tmp, name, out_dir)
        export_mask(src_file, tmp)
        pack_mask(tmp, name, out_dir, count)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
