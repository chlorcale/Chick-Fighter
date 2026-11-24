# Tóm tắt phiên làm việc – Hiện thực game Chick Fighter (Godot)

**Dự án:** Huyền Thoại Đá Gà – Chick Fighter
**Thư mục:** `D:\Chick_Fighter\Chick-Fighter`
**Engine chạy thử:** Godot 4.5.1 (máy hiện có); `project.godot` ghi `4.5`
**Trạng thái:** đã cài đặt và test tự động, **chưa commit**, **chưa có người chơi thử bằng bàn phím từ đầu đến cuối**.

---

## 1. Tài liệu đầu vào

| Tài liệu | Vai trò |
|---|---|
| `CHICK_FIGHTER_Technical_Audit_and_Design_Baseline.md` | Baseline quyết định của Owner (Special 5 vạch, đỡ theo hướng, 11 bit input, mốc M0–M17…) |
| `D:\Chick_Fighter_GDD_v4.docx` (GDD v1.2) | Cốt truyện, bối cảnh, frame data, gauge, 5 trận MVP, kinh tế, công thức cân bằng |
| `D:\GameArt\truongcon.aseprite` | Nhân vật chính 64×64, 22 frame, tag idle/walk_down/up/left/right, layer viền `Vien` |
| `D:\GameArt\BoiCanh_MienTay_NhanVat.aseprite` | Bản đồ 1280×1080, 96 frame × 80 ms, 6 màn, layer 00–06 |
| `D:\GameArt\rooster fight.aseprite` | Gà đá 128×112, 47 frame (idle, run, jump, light_kick, heavy_kick) – dùng ở vòng 2 |
| `D:\GameArt\rooster_fight_combo.aseprite` + `rooster_fight_movelist.md` | Gà đá 153 frame, 21 tag, bảng chiêu & combo – dùng ở vòng 3 |
| `D:\CLAUDE.md`, `AGENTS.md` | Quy tắc làm việc (thay đổi tối thiểu, không sửa `.godot/`, báo cáo PASS/FAIL trung thực) |

---

## 2. Diễn tiến theo từng yêu cầu

### Vòng 1 – "Hiện thực game theo GDD & MD; xóa viền trắng; chỉ đi lên/xuống/trái/phải"
- Xuất nhân vật từ `truongcon.aseprite` **tắt layer `Vien`** → hết viền trắng.
- Nhân vật khám phá chỉ đi 4 hướng, không đi chéo (phím nhấn sau cùng thắng), có va chạm theo layer `05_Collision` + ô chặn bổ sung.
- Dựng luồng MVP: hội thoại → Chú Tư → trận hướng dẫn → giao hữu Tèo → tiệm Cô Ba → giải Ao Làng 3 vòng.
- Trận đấu ban đầu chạy trên `battle_system.tscn` cũ.
- Vấn đề còn lại (người dùng phản hồi): bản đồ chỉ dùng 24/96 frame nên xe, ghe bị giật; nhân vật trông nhỏ.

### Vòng 2 – "Frame còn lag, xe/ghe giật, nhân vật nhỏ; làm lại cốt truyện và phần đấu thật chỉn chu (tham khảo Street Fighter, Bleach vs Naruto)"
- **Pipeline art mới** (`tools/art/`): xuất **từng layer** của bản đồ, gộp layer tĩnh, giữ layer động đủ **96 frame × 80 ms**, đóng gói atlas + `map_layers.json`; layer `03_Object` Y-sort với nhân vật.
- Camera khám phá ×3.
- **Phần đấu viết lại** (`BattleDirector`), dùng sprite `rooster fight.aseprite`: mô phỏng 60 Hz cố định, hitbox/hurtbox theo rect, hitstop, combo cancel, đỡ đứng/đỡ cúi theo tầng đòn, vỡ thủ, va chạm đòn, siêu chiêu dừng hình + cắt cảnh, K.O. quay chậm, camera bám trung điểm + rung, âm thanh sinh bằng code, sân Ao Làng vẽ pixel (khán giả lấy từ NPC bản đồ), AI theo Tier.
- **Cốt truyện viết lại theo GDD:** màn tiêu đề + nhập tên, hồi ức ông nội (cắt cảnh tối, tiếng dế), trận hướng dẫn có nhiệm vụ, màn Pre-battle (gắn đồ, xem đối thủ), màn kết quả (tiền, EXP, lên cấp), ngủ = lưu game, kết Act 1.

### Vòng 3 – "Thêm loạt combo từ file mới; nút vẫn ASWDHJKLUIO; thanh máu có chiều sâu; nhân vật ngoài cốt truyện nhỏ ngang NPC; thêm xe máy; cho qua sông"
- **Gán nút:** J = L (nhẹ) · K = M (vừa) · L = H (mạnh) · H = S (đặc biệt).
- **Toàn bộ bảng chiêu** từ `rooster_fight_combo.aseprite`, thời lượng frame lấy đúng từ file art.
- **Thanh máu nhiều lớp:** khung kim loại, 4 dải sáng–tối, lớp máu vừa mất chớp trắng → cam rút dần, vệt sáng, vạch 10%, rung + văng mảnh vụn khi trúng, nhấp nháy khi máu thấp.
- **Khám phá:** nhân vật thu nhỏ ×0,8 (≈42 px, ngang NPC); xe máy (E lên/xuống, 210 px/s so với 80 px/s đi bộ); đò ngang qua sông; mở rộng bản đồ ra cả bờ nam; mở lối đi trên hai cây cầu qua kênh.

---

## 3. Trạng thái hiện tại của game

### 3.1 Điều khiển
| Phím | Khám phá | Trong trận |
|---|---|---|
| W A S D | Đi 4 hướng | Nhảy / trái / cúi / phải; bấm đúp trái/phải = lướt |
| E | Tương tác, lên/xuống xe máy | – |
| J / K / L / H | – | L nhẹ / M vừa / H mạnh / S đặc biệt |
| U / I / O | – | Chọn thẻ trái / phải / tung thẻ |
| Esc | – | Tạm dừng + bảng chiêu |
| F1 | – | Hiện hitbox/hurtbox (debug) |

### 3.2 Bảng chiêu
| Chiêu | Lệnh | Ghi chú |
|---|---|---|
| Mổ Nhanh | J | Nối sang L, M, đặc biệt |
| Đá Nhẹ | → + J, hoặc J thứ hai trong chuỗi | |
| Tát Cánh | K | Nối sang H, đặc biệt, siêu chiêu |
| Đá Cựa Bay | L | Đánh ngã (TE_NgaNgua) |
| Cựa Hất | ↓ + L | Hất tung, chống nhảy; trúng thì nhảy hủy để tung hứng |
| Mổ Thấp / Quét Cánh | ↓ + J / ↓ + K | Đòn thấp; Quét Cánh đánh ngã |
| Đòn trên không | J / K / L khi nhảy | Đòn cao |
| Mổ Liên Hoàn | H hoặc → ↓ ↘ + H | 1 vạch, bấm H liên tục lặp tối đa 3 vòng |
| Phun Lông | ↓ + H hoặc ↓ ↘ → + H | Đạn 5 lông, không tốn nộ, 1 viên trên sân |
| Lốc Xoáy Cánh | ← + H hoặc ↓ ↘ → ↓ ↘ → + H | 2 vạch, hút rồi nổ văng, không đỡ được |
| Gáy Thị Uy | H + L cùng lúc | +25% thanh nộ, có thể bị đánh |
| Đỡ bằng cánh | Giữ lùi (cúi + lùi để đỡ đòn thấp) | Không chặn siêu chiêu |

**Combo đã kiểm chứng:** J J K L · K → ↓L → nhảy → J · J → K → H (bấm liên tục) · J → K → ← + H.
**Rush đối đầu:** hai Mổ Liên Hoàn chạm nhau → ai bấm H nhiều hơn trong 1,5 s thắng.

### 3.3 Luật trận (GDD chương 4 + baseline)
- Mô phỏng 60 Hz cố định; đồng hồ 99 s, hiệp phụ 15 s (trúng đòn trước thắng), hòa thì bên nhận ít sát thương hơn thắng.
- Sát thương công thức 1, knockback theo WEIGHT công thức 2, hitstop, tường 0–1000 px.
- Block Gauge 100, hồi 15/s sau 1,5 s, chip 1 HP khi đỡ; cạn thì vỡ thủ + ngã, gauge về 50.
- Special Gauge 5 vạch (Owner); Card Gauge bắt đầu 2, hồi +1/4 s (GDD).
- Giảm sát thương theo độ dài combo: −5%/nhịp, tối thiểu 50% (thêm mới, không có trong GDD).

### 3.4 Cốt truyện Act 1 – Ao Làng
Tiêu đề → nhập tên (mặc định "Tư Gà") → hồi ức ông nội → Mẹ nhắc ra sân đình → Chú Tư trao Gà nòi (đặt tên, mặc định "Ô Mun") → trận hướng dẫn 4 bước (đánh trúng J/K, đỡ 2 đòn, combo 3 nhịp, Mổ Liên Hoàn) → nhận Cuồng Nộ + Mai Rùa → giao hữu Tèo (+50.000đ, Gió Sông) → tiệm Cô Ba (Mào sắt, Dao chân, Cám tăng lực) → đăng ký giải → Vòng 1 Lửa Đỏ, Vòng 2 Mun Sông, Chung kết Tia Chớp (+300.000đ) → về nhà → cắt cảnh kết Act 1. Mũi tên vàng chỉ mục tiêu; thua thì đấu lại; ngủ ở nhà để lưu.

### 3.5 Khám phá
- Bản đồ đủ hai bờ sông, 96 frame động, Y-sort với nhân vật.
- Xe máy đậu trước cổng nhà; đò ngang ở bến cầu ván.
- Bờ nam có điểm tương tác: trường học, công trường, ruộng lúa, đền làng, chòi nuôi cá, cô bán vé số.

---

## 4. Cấu trúc file

| Đường dẫn | Nội dung |
|---|---|
| `game/main.gd`, `game/main.tscn` | Điểm vào, toàn bộ luồng cốt truyện (scene chính mới trong `project.godot`) |
| `game/game_state.gd` | Tiến trình, chỉ số giống, công thức EXP/tiền, đối thủ, lưu/tải |
| `game/world/world.gd`, `map_view.gd`, `player.gd` | Khám phá, bản đồ theo layer, nhân vật + xe máy + đò |
| `game/battle/battle_director.gd` | Lõi trận đấu |
| `game/battle/moves.gd` | Bảng chiêu, frame data từ file art |
| `game/battle/enemy_ai.gd` | AI theo Tier |
| `game/battle/battle_hud.gd`, `battle_fx.gd`, `battle_arena.gd`, `fighter_view.gd`, `sfx.gd`, `rooster.gdshader` | HUD, hiệu ứng, sân đấu, hình gà, âm thanh, shader đổi màu |
| `game/ui/*.gd` | Hộp thoại, tiêu đề, cắt cảnh, Pre-battle, màn kết quả |
| `game/art/` | Atlas bản đồ, sheet gà, NPC, xe máy, mask va chạm (sinh ra từ pipeline) |
| `tools/art/` | Script Lua xuất từ Aseprite + `build_assets.py` đóng gói |
| `tests/game/run_game_smoke.gd`, `run_flow_smoke.gd` | Test khám phá, chiêu, AI, luồng cốt truyện |

**Thay đổi ngoài thư mục `game/`:**
- `project.godot`: đổi `run/main_scene` sang `res://game/main.tscn` (Input Map không sửa; phím J/K/L/H/U/I/O đăng ký lúc chạy).
- `core/fighter/fighter_controller.gd`: thêm `movement_locked`, `apply_knockback()`, `apply_launch()`, `get_input_source()`.
- `battle_system.tscn` và các file `.tres` của M5 **không sửa**.

---

## 5. Kiểm thử (lần chạy cuối)

| Bộ test | Kết quả |
|---|---|
| `tests/game/run_game_smoke.gd` | PASS (bản đồ, 4 hướng, xe máy, đò, combo J J K L, Cựa Hất, rush, đạn, siêu chiêu, đỡ/tầng đòn, va chạm đòn, trận AI-vs-AI) |
| `tests/game/run_flow_smoke.gd` | PASS (tên mặc định → Chú Tư → hướng dẫn → Tèo → thưởng, mũi tên chỉ tiệm) |
| `tests/m1` … `tests/m11_1` (13 bộ) | Tất cả PASS, không lỗi hồi quy |

Lệnh chạy:
```bash
godot --headless --path . --fixed-fps 60 -s res://tests/game/run_game_smoke.gd
```

**Chưa kiểm chứng:** chơi tay trọn 5 trận bằng bàn phím; cảm giác cân bằng thực tế.

---

## 6. Quyết định & lệch so với tài liệu (cần Owner xác nhận)

| Mục | Đang làm | Nguồn / lý do |
|---|---|---|
| Nút H | Dùng làm nút S (đặc biệt) | Người dùng yêu cầu; baseline cũ giữ H cho Clash Rush |
| Motion input | Có lệnh vẽ tay + lối tắt một nút | Bảng chiêu dùng motion; GDD ghi "không có motion input" |
| Đỡ cúi, tầng đòn cao/thấp | Bật (`USE_HIGH_LOW_GUARD`) | GDD Bảng 4.5; baseline cũ không có |
| Vỡ thủ | Ngã thay vì choáng 1,2 s | GDD Bảng 4.8 |
| Card Gauge đầu trận | 2 | GDD 4.7; baseline ghi 5 |
| Chiêu Cước Sấm | Thay bằng bộ chiêu mới | File combo mới |
| Hitstun nối combo | Nhẹ 20, nặng 34 tick | PLACEHOLDER để combo trong bảng chiêu nối được |
| Cửa sổ nối đòn | 8 tick (GDD: 3 frame) | Frame trong art dài hơn |
| Nạp nộ | Đòn thường 4 + sát thương; chiêu đặc biệt 1 | PLACEHOLDER; Owner chưa chốt kinh tế Special |
| Chi phí Block Gauge | L 10 · M 18 · H 25 · rush 8/nhịp · đạn 6/lông | PLACEHOLDER |
| Launch | `apply_launch()` – kênh vận tốc dọc ngoài MovementController | Cần cho hất tung/tung hứng |
| Dash | Bật trên mặt đất | GDD 4.2; baseline từng để tắt chờ Owner |

---

## 7. Việc còn lại
- Versus Online 1v1 (mốc M15).
- Passive "Lanh Lẹ" của Gà tre (dash hồi nhanh 30%).
- Âm thanh thật thay âm thanh sinh bằng code.
- Chơi thử tay và cân bằng lại các giá trị PLACEHOLDER.
- Ba file `core/cards/` (`card_catalog.gd`, `card_collection.gd`, `card_deck_rules.gd`) có thay đổi chỉ về thụt lề, nhiều khả năng do editor Godot đang mở tự định dạng – chưa đụng tới.
- Commit khi Owner đồng ý.

---

## 8. Vòng 4 – Xe Dream, viền nhân vật, đò, hoạt động bờ nam, gà Đông Tảo, trận 3 hiệp, AI, âm thanh (13/11/2026)

### 8.1 Thay đổi
| Mục | Nội dung | File chính |
|---|---|---|
| Xe Dream | Xe to ngang xe NPC (68×42), 3 hướng, nan hoa quay, khói ống xả; xe đỗ riêng (không có chân người) | `tools/art/build_dream_bike.py`, `game/world/player.gd`, `exhaust_smoke.gd`, `game/art/bike_*.png` |
| Viền nhân vật | Viền 1 px màu (42,30,46) như NPC, bằng shader | `game/world/outline.gdshader` |
| Đò ngang | Ẩn đò mặc định của bản đồ; World giữ một chiếc đò neo ở bến phía người chơi, chở qua sông | `game/world/world.gd`, `map_view.gd`, `game/art/world/ferry_rowing.png` |
| Tiệm Cô Ba | Danh sách lựa chọn dạng cửa sổ cuộn (5 dòng, ▲/▼), dòng mô tả riêng | `game/ui/dialog_box.gd`, `game/main.gd` |
| Hoạt động bờ nam | Cầu cá tra (đi trên cầu ván, cho cá ăn, kéo vó), gặt lúa, câu đố ở trường, bốc gạch, thắp nhang xin xăm, vé số | `game/world/activities.gd`, `activity_runner.gd`, `minigames/*.gd`, `world_fx.gd` |
| Gà Đông Tảo | Kit thứ hai theo `D:/GameArt/dongtao_fight_movelist.md` (119 frame, 18 tag); đối thủ Vòng 2 "Mun Sông" | `game/battle/kit_dongtao.gd`, `moves.gd`, `fighter_view.gd`, `tools/art/build_fighter_sheet.py` |
| Gà đổi màu | Shader đổi màu theo mặt nạ bộ phận (thân, cổ, đuôi; giữ mào/chân/mắt) | `game/battle/rooster.gdshader`, `game/art/*_mask.png` |
| Trận đấu | 3 hiệp thắng 2 (trừ trận hướng dẫn), mở màn có VS, camera động, quay chậm khi K.O., khán giả reo | `game/battle/battle_director.gd`, `battle_hud.gd`, `battle_fx.gd`, `battle_arena.gd` |
| AI | Viết lại: 3 tier, đọc tầm đòn từ bảng chiêu, trừng phạt, chống nhảy, học thói quen người chơi | `game/battle/enemy_ai.gd` |
| Âm thanh | 41 file WAV tổng hợp bằng code (nhạc ngũ cung, âm nền, xe, tiếng động) + bộ phát | `tools/audio/*.py`, `game/audio/*`, hook trong `main.gd`, `world.gd`, `player.gd` |

### 8.2 Lệch so với tài liệu (Owner yêu cầu ở vòng này; giá trị là PLACEHOLDER)
| Mục | Đang làm |
|---|---|
| Giống gà thứ ba | Gà Đông Tảo chỉ làm đối thủ: HP 130, tốc độ 140 px/s (preset mới trong `core/movement/movement_config.gd`), weight 12 (bị đẩy lùi ~50%), không nhảy/cúi/lướt |
| Đỡ của Đông Tảo | "Thiết Giáp" đỡ mọi tầng đòn, tốn Block Gauge ×1,5; chip vẫn 1 HP (không áp dụng "nhận 20% sát thương" của movelist) |
| Chiêu Đông Tảo | Húc Trâu, Địa Chấn, Phản Đòn tốn 0 vạch; Thái Sơn Áp Đỉnh 2 vạch, né bằng cách nhảy |
| Số hiệp | Thắng 2 hiệp; mỗi hiệp 99 s; Special/Card Gauge giữ qua hiệp; HP, Block Gauge hồi đầy |
| Máu trong trận | `HEALTH_SCALE = 1.6` cho trận không phải hướng dẫn (hiệp trung bình ~44 s giữa hai AI ngang tier) |
| Bảy Ghe | Bỏ Mào sắt (đã có máu tank) |
| Tier AI | chu_tu T1, teo_1 T1, ut_map T1+, bay_ghe T2, teo_2 T3 |
| Kinh tế | Việc làm thêm bờ nam mỗi ngày một lượt (ngủ = sang ngày): tối đa ~135.000đ/ngày; lưu ở `user://chick_fighter_world.cfg` |

### 8.3 Kiểm thử
Lệnh: `godot --headless --path . --fixed-fps 60 -s res://tests/game/<file>.gd`
- `run_game_smoke.gd` (~2 phút 45 s, gồm 19 trận AI), `run_flow_smoke.gd`, `run_world_smoke.gd`, `run_audio_smoke.gd`, `run_ai_batch.gd -- seeds=10`.
- **Chưa kiểm chứng:** chơi tay bằng bàn phím (cân bằng trận, độ khó mini-game); chưa ai nghe thử âm thanh.

---

## 9. Vòng 5 – Dáng ngồi xe, font, đua xe ẩn, nhạc sáo, sới đá mới (13/11/2026)

| Mục | Nội dung | File chính |
|---|---|---|
| Dáng ngồi xe | Vẽ lại người ngồi xe 4 hướng (ảnh ghép người + xe 68×60 / 30×60), chân ngắn lại, tay cầm ghi-đông; `WorldPlayer.make_rider_visual()` cho game đua | `tools/art/build_dream_bike.py`, `game/world/player.gd`, `game/art/bike_ride_*.png` |
| Font | `DialogBox.make_font()` tự dùng file `.ttf/.otf` đầu tiên trong `game/fonts/` cho toàn bộ chữ (không khử răng cưa), thiếu ký tự thì lấy font hệ thống; `ThemeDB.fallback_font` đặt trong `main.gd`. **Chưa có file font** (trang s99.vn cần đăng nhập để tải) | `game/ui/dialog_box.gd`, `game/main.gd`, `game/fonts/` |
| Đua xe ẩn | Chạy xe cùng chiều, kèm một xe NPC ≥ 0,8 s rồi vượt lên → bị thách đua; đua 3 làn ~40–50 s, 4 đối thủ; thắng trận đầu trong ngày +30.000đ, danh hiệu "Thần Gió Đường Làng" | `game/world/race/*.gd`, `game/world/world.gd` (`race_challenge`), `game/main.gd`, `game/world/activities.gd` |
| Nhạc | `music_village`, `music_title`, `music_memory` viết lại với sáo trúc làm giai điệu chính (giai điệu mới, chỉ lấy không khí nhạc quê hương Nam Bộ); mức mặc định: nhạc −9 dB, âm nền −6 dB, tiếng động −4 dB | `tools/audio/music.py`, `instruments.py`, `game/audio/audio_director.gd` |
| Sới đá | Sửa lỗi khán giả nhảy loạn (pha dao động nhân với thời gian trận); dựng lại sới Ao Làng nhiều lớp (trời, sông, đình, đèn lồng, khán đài 103 người, rào tre, nền cát); biến thể buổi tối cho đối thủ tier ≥ 3 (suy đoán, chưa được Owner chốt) | `game/battle/battle_arena.gd`, `tools/art/build_arena.py`, `game/art/arena/*` |

Test mới: `tests/game/run_race_smoke.gd`. **Chưa kiểm chứng:** chơi tay game đua, nghe thử nhạc mới.

---

## 10. Vòng 6 – Mở rộng theo GDD v5 (17–18/11/2026)

| Mục | Nội dung | File chính |
|---|---|---|
| Dữ liệu & thời gian | Đàn gà, kho đồ, 6 ô trang bị, trứng/ấp, Biotech, đột biến, Khô Gà, thể trạng; thứ trong tuần, 5 buổi, ngày/đêm, đồng hồ; đối thủ Liên tỉnh/Olympic | `game/game_state.gd`, `game/data/*.gd`, `game/world/day_night.gd`, `game/ui/clock_hud.gd` |
| Bản đồ 5120×2160 | Xuất từ `Chick_Fighter_World_Map_Expanded.aseprite` (không sửa file gốc), chợ đông, Lão Gà Khô (trước đây: Tiệm Mèo), sới Liên tỉnh, nhà thi đấu Olympic, mũi tên mép màn hình, bản đồ M, minimap N, biển chỉ đường | `tools/art/build_world_map.py`, `game/art/world_map/`, `game/world/world.gd`, `map_view.gd`, `market_crowd.gd`, `world_map_overlay.gd` |
| Nhà & chuồng gà | Nội thất, sân sau có bội gà, bảng chăm gà/gắn đồ/đột biến, kệ ấp trứng, bàn học | `game/home/**`, `tools/art/build_home.py` |
| Trận đấu | 3 vũ khí, lớp trang bị trên gà, chỉ số/nội tại/đột biến có tác dụng, màn chuẩn bị, chế độ công an 30 s, AI T4, Hell Mode, 2 sân mới | `game/battle/**`, `game/ui/prebattle.gd`, `result_screen.gd`, `tools/art/build_gear.py`, `build_arena_venues.py` |
| Escape | Chạy bộ + bơi vượt chướng ngại, cảnh rửa bát | `game/escape/**`, `tools/art/build_escape.py` |
| Đời sống & cốt truyện | Lịch tuần, lớp THPT, thư viện, việc làm (bốc gạch, bán cơm, chở ghe), hàng xóm + thân thiết + 5 quest, cửa hàng (Cô Ba, 4 sạp chợ, Lão Gà Khô (trước đây: Tiệm Mèo)), giải Liên tỉnh/Olympic, luồng báo công an → Escape | `game/main.gd`, `game/story/**`, `game/sim/life_state.gd`, `game/world/minigames/*` |

**PLACEHOLDER / cần Owner chốt:** chỉ số Đông Tảo (game: ATK 10/DEF 2/SPD 140/WEIGHT 12; GDD v5: 11/4/150/4,5); "Heavy" của GDD = đòn K; SPD từ trang bị chỉ hiển thị (tốc độ trong trận theo preset giống); DEF cộng dồn làm hiệp hay hết giờ; chung kết Ao Làng còn dễ; mọi giá, thưởng, giờ mở cửa, ngưỡng báo công an 1,35; biến thể sân buổi tối; `tools/balance/economy_sim.gd` chưa được chuyển sang API mới.

Test mới: `run_state_smoke`, `run_home_smoke`, `run_escape_smoke`, `run_life_smoke`. **Chưa kiểm chứng:** chơi tay bất kỳ phần nào của vòng này.

---

## 11. Vòng 7 – Sửa lỗi Godot, nhà mới, Lão Gà Khô (20/11/2026)

| Mục | Nội dung | File chính |
|---|---|---|
| Lỗi parse | `tools/balance/economy_sim.gd` chuyển sang API GameState mới (hết lỗi đỏ ở editor, `run_economy_report.gd` chạy lại được) | `tools/balance/economy_sim.gd` |
| Lỗi Rect2 âm | Làm mờ tán cây với vật < 5 px, mũi tên mép màn hình, minimap: chặn kích thước âm | `game/world/map_view.gd`, `world.gd`, `world_map_overlay.gd` |
| Ảnh trang bị lỗi import | `dongtao_cua_dong.png` có `.import` hỏng (valid=false) → tạo lại | `game/art/gear/dongtao_cua_dong.png.import` |
| Nhà mới | Nội thất từ `NhaTrong_NhanVatChinh.aseprite` (960×576, 8 frame): phòng khách, buồng, bếp, sân gà; 8 bội vẽ tay = ô chuồng 1–8 (ô 9–14 bội chép thêm, 15–20 ổ rơm); người chơi ×1,0 trong nhà theo layer guide | `tools/art/build_home_interior.py`, `game/home/**`, `game/escape/escape_cutscene.gd` |
| Lão Gà Khô | Xe khô gà lá chanh (8 frame, thu ×½) thay kiosk Tiệm Mèo ở góc đông bắc chợ; cơ chế giữ nguyên (id `cat_shop`, shop `&"meo"`) | `tools/art/world_map_extras.py`, `game/story/story_shops.gd`, `game/world/world.gd` |

Còn mở: báo cáo kinh tế cho thấy người chơi giả lập đăng ký Liên tỉnh nhưng không vào trận nào trong 12 tuần (chưa điều tra).

---

## 12. Vòng 8 – Map cập nhật, nhân vật mới, xe/vỏ lãi chạy thật, lái vỏ lãi (23/11/2026)

| Mục | Nội dung | File chính |
|---|---|---|
| Map | Dựng lại từ `Chick_Fighter_World_Map_Expanded.aseprite` (23/11). Dùng 2 sân của Owner (Sân gà Liên tỉnh cổng (4508,1080), Sân gà Olympia (4938,1413)) và xe Lão Gà Khô của Owner ((2912,922), [E] (2968,1044)); bỏ bản do mình vẽ. 4 sạp đặc biệt dời chỗ. | `tools/art/build_world_map.py`, `world_map_extras.py`, `world_map_traffic.py`, `game/art/world_map/*` |
| Xe & vỏ lãi | 71 layer giao thông tách khỏi map → `traffic.json` (8 kiểu, 17 tuyến, 37 spawn, 8 bến, 18 cầu) + `water.png`, `roads.png`. Runtime: 39 xe/vỏ lãi chạy theo tuyến, giữ khoảng cách, nhường người chơi/người đi bộ, bóp còi, âm thanh theo vị trí. | `game/world/traffic.gd`, `vehicle_actor.gd` |
| Lái vỏ lãi | Lên ở 8 bến ("[E] Lái vỏ lãi"), W ga, S lùi, A/D bẻ lái 16 hướng, va bờ/cầu thấp, lên bờ ở bến hoặc bờ đi được. | `game/world/player_boat.gd`, `world.gd` |
| Người đi bộ | 79 người có lịch trình theo vai (đi chợ, đi học, thăm xóm), A* tránh đường xe, chờ xe, tránh người chơi, tụ 2 người nói chuyện, tối về nhà. | `game/world/pedestrians.gd` |
| Camera | Làng: ×2,0/2,5/3,0/4,0, mặc định ×2,5, con lăn chuột hoặc `-`/`=`, lưu `user://view_settings.cfg`. Nhà: ×2,0–4,0, mặc định ×2,5. | `game/world/view_settings.gd`, `game/home/home_scene.gd` |
| Nhân vật chính | `truongcon_stardew.aseprite` (20 frame) ở ×1,0 ngoài làng, ×4/3 trong nhà; dáng ngồi xe, chân dung, Escape vẽ lại theo nhân vật mới. | `tools/art/build_player.py`, `game/world/player.gd`, `build_dream_bike.py`, `build_escape.py` |
| Người nhà | Mẹ, Ba, em trai dựng từ khung hình nhân vật mới; đi lại theo buổi (A* trong nhà), nói chuyện được khi đang đi. | `tools/art/build_family.py`, `game/home/family_npc.gd`, `home_nav.gd` |

Test mới: `run_traffic_smoke`. Còn mở: vỏ lãi hướng Bắc/Nam là thân tàu vẽ bằng code (Owner có thể vẽ lại); chỉ 4 xe "race_rider" mới thách đua; nhân vật mới chỉ có tư thế đứng quay xuống.

---

## 13. Vòng 9 – Sửa crash, font pixel, sổ V, xe đa dạng, minigame màn riêng (24/11/2026)

| Mục | Nội dung | File chính |
|---|---|---|
| Crash | Game sập khi khởi động do driver D3D12 trên Intel Iris Xe → `project.godot`: `rendering_device/driver.windows="vulkan"` | `project.godot` |
| Font | Hai font pixel tự vẽ (`chick_body.ttf`, `chick_bold.ttf`), đủ dấu tiếng Việt, phóng theo bậc nguyên (11–16 ×1, 17–27 ×2, 28–38 ×3…); viền chữ vẽ lại bằng `UISkin.draw_string_crisp` | `tools/art/build_font.py`, `game/fonts/`, `game/ui/ui_skin.gd` |
| Giao diện | Khung gỗ + giấy (Stardew-inspired): hội thoại, đồng hồ, tiêu đề, chuẩn bị trận, kết quả, HUD trận, bảng nhà, minigame, đua, Escape; toàn game lọc NEAREST | `tools/art/build_ui_skin.py`, `game/art/ui/`, `game/ui/**` |
| Bản đồ | Minimap tắt mặc định (N), M mở bản đồ giấy cũ có xe máy/vỏ lãi | `game/world/world_map_overlay.gd` |
| Sổ V | Hướng dẫn 8 mục, cây 71 thành tựu 5 nhánh (bí mật = "?"), sổ tay | `game/ui/guidebook.gd`, `game/sim/achievements.gd`, `achievement_toast.gd` |
| Thế giới | Vỏ lãi bốc đầu nằm trên nước; ông câu cá quay ra sông; vỏ lãi đi hết sông (1 vòng liền, chui mọi cầu); xe máy qua 17 cầu; dấu vị trí xe/vỏ lãi; 8 mẫu xe NPC mới (20 kiểu); đua xe: 10 tay đua có tên + dấu "!"; cảnh đua mới; `World.achievement_event` | `game/world/**`, `tools/art/build_vehicles.py`, `world_map_fixes.py` |
| Minigame | 13 trò thành màn riêng vẽ lại; thêm Câu cá lóc (345,252) và Thả diều (480,842) | `game/world/minigames/**`, `activity_runner.gd`, `tools/art/build_minigames.py` |
| Nhà | Gà đi lại trong sân (hình nhỏ vẽ đúng cỡ, màu + đồ theo từng con, tối vào bội), chuồng gỗ có chân sàn | `game/home/yard_chicken*.gd`, `tools/art/build_rooster_walk.py`, `build_home_interior.py` |

Còn mở: rạch nhỏ phía đông quá hẹp cho vỏ lãi; xe Dream của nhân vật giữ hình cũ; một số chữ ×1 còn nhỏ (tab sổ V, tên địa điểm trên bản đồ M); `run_game_smoke` mất ~10 phút.

