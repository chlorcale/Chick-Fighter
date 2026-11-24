Font pixel riêng của game (vẽ tay, đủ tiếng Việt) – dựng bằng: python tools/art/build_font.py --specimen <file.png>
  chick_body.ttf  chữ thường: hoa 7 px, x-height 5 px, nét 1 px
  chick_bold.ttf  chữ đậm / tiêu đề: hoa 9 px, nét dọc 2 px
DialogBox.make_font(bold) nạp hai file này với fixed_size = 11 + phóng NGUYÊN lần:
  cỡ 11–16 → ×1, 17–27 → ×2, 28–38 → ×3, 39–49 → ×4 … (dùng UISkin.FS_SMALL 11 / FS_BODY 22 / FS_BIG 33 / FS_HUGE 44).
Gốc giao diện nên đặt texture_filter = NEAREST (UISkin.pixel(node)) để chữ ×2 trở lên không nhoè.
Font khác (.ttf/.otf, vd. KVN-97) thả vào đây chỉ được dùng khi thiếu hai file chick_*.ttf; thiếu hết thì dùng font hệ thống.
