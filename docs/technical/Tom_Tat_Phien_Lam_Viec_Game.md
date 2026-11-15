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

