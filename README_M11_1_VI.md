# Chick Fighter — M11.1 Extensible Card System

## 1. Mục tiêu và phạm vi

Đây là bản thay thế cho gói M11 nháp trước đó. Không cài đồng thời gói M11 cũ và M11.1. M11.1 xây dựng phần lõi để:

- Đăng ký thêm CardData Resource mới mà không phải sửa CardController.
- Quản lý danh sách thẻ đã mở khóa và lưu nguồn mở khóa.
- Xây deck từ các card ID người chơi lựa chọn, đồng thời kiểm tra deck size và quyền sở hữu.
- Dùng profile MVP (3 thẻ, tay 3) hoặc Phase 1 (deck 8–10 thẻ, tay tối đa 5).
- Khi dùng hết tay, chờ thời gian xáo rồi xáo toàn bộ deck và rút tay mới, giới hạn tay luôn không quá 5.
- Tách Card Gauge khỏi M10 SpecialGauge.
- Mô tả một thẻ bằng một hoặc nhiều CardEffectData, có effect ID, trigger, magnitude, duration và parameters.

Không sửa FighterController, CombatResolutionController, MovementController, scene, Input Map, project.godot hoặc các file M1–M10.

## 2. Cấu trúc

```text
core/cards/
  card_data.gd
  card_effect_data.gd
  card_database.gd
  card_catalog.gd             # compatibility facade for MVP cards
  card_collection.gd
  card_deck_rules.gd
  card_deck_builder.gd
  card_gauge_component.gd
  card_controller.gd
  data/
    cuong_no.tres
    mai_rua.tres
    gio_song.tres
    phong_thu.tres
    mau_chien.tres
    cung_dau.tres
    chop_thoi_co.tres
    nuoc_lon.tres
    mua_chieu.tres
    gay_sang.tres

tests/m11_1/
  test_card_system.gd
  run_m11_1_tests.gd
```

## 3. Hai profile deck theo GDD

| Profile | Số thẻ trong deck | Số thẻ tối đa trên tay |
|---|---:|---:|
| MVP | Chính xác 3 | 3 |
| Phase 1 | 8–10 | 5 |

CardDatabase đăng ký sẵn 10 card resources: 3 thẻ MVP và 7 thẻ Phase 1. CardCollection chỉ mở khóa mặc định 3 thẻ MVP. Các thẻ Phase 1 còn lại phải được mở khóa thông qua nguồn `tournament`, `npc` hoặc `achievement` trước khi DeckBuilder chấp nhận chúng.

Các thẻ Phase 1 có dữ liệu:

| Thẻ | Cost | Dữ liệu hiệu ứng |
|---|---:|---|
| Phòng Thủ | 1 | +40% Block Gauge; giảm 20% sát thương nhận vào; 5s |
| Máu Chiến | 2 | Khi HP dưới 30%, +60% ATK; 6s |
| Cứng Đầu | 1 | Block Gauge không giảm; 2s |
| Chớp Thời Cơ | 1 | Né thành công → đòn tiếp theo +100% sát thương; cửa sổ 4s |
| Nước Lớn | 3 | +20 Special Gauge ngay; **PROPOSED** |
| Mưa Chiều | 2 | Đối thủ −20% SPD; 5s; **PROPOSED** |
| Gáy Sáng | 0 | Sau 3s +1 Card Gauge; **PROPOSED** |

Các thẻ `Nước Lớn`, `Mưa Chiều`, `Gáy Sáng` được đánh dấu `is_proposed = true`; chúng được đưa vào database để chuẩn bị dữ liệu, không được coi là quyết định đã chốt.

## 4. Cách khởi tạo hệ thống

```gdscript
var database: CardDatabase = CardDatabase.create_default_database()
var collection := CardCollection.new()
collection.configure(database)
collection.unlock_mvp_defaults()

var rules: CardDeckRules = CardDeckRules.create_mvp_rules()
var deck_builder := CardDeckBuilder.new()
deck_builder.configure(database, collection, rules)

var selected_ids: Array[StringName] = [
    &"cuong_no",
    &"mai_rua",
    &"gio_song",
]
var battle_deck: Array[CardData] = deck_builder.build_deck(selected_ids)

var card_gauge := CardGaugeComponent.new()
card_gauge.configure() # 5 / 5

var cards := CardController.new()
var configured: bool = cards.configure(
    battle_deck,
    card_gauge,
    deck_builder.get_hand_size(),
    2026, # deterministic shuffle seed for test/replay
    180  # PROVISIONAL: 3 seconds at 60 ticks/second
)
```

Với Phase 1:

```gdscript
var phase1_rules: CardDeckRules = CardDeckRules.create_phase1_rules()
var phase1_builder := CardDeckBuilder.new()
phase1_builder.configure(database, collection, phase1_rules)
# selected_ids cần có 8–10 ID đã mở khóa.
var phase1_deck: Array[CardData] = phase1_builder.build_deck(selected_ids)
# Truyền phase1_builder.get_hand_size() (5) vào CardController.configure().
```

Luôn kiểm tra `configured` và `deck_builder.get_last_result()` trước khi bắt đầu trận.

## 5. Thêm một thẻ mới

1. Tạo một Resource mới trong `core/cards/data/`, dùng `CardData` làm resource chính và một hoặc nhiều `CardEffectData` làm subresource.
2. Đặt `card_id` duy nhất, `cost` trong khoảng 0–3, tên, mô tả và `content_group` phù hợp.
3. Thêm đường dẫn `.tres` mới vào `CardDatabase.DEFAULT_CARD_PATHS` (hoặc tự gọi `database.register_card(new_card)` khi khởi tạo).
4. Gọi `collection.unlock_card(card_id, &"tournament" / &"npc" / &"achievement", source_id)` khi người chơi nhận được thẻ.
5. DeckBuilder tự nhận card ID mới; không phải thêm nhánh `match`, sửa CardController hoặc viết lại logic rút tay.

`CardData.effects` là mảng, nên một thẻ có thể chứa nhiều hiệu ứng. `effect_id` là định danh mở rộng; hệ thống combat sẽ đăng ký/xử lý các ID này ở milestone tích hợp.

## 6. Deck, hand và vòng rút

- Khi khởi tạo: xáo toàn bộ deck, rút `hand_size` lá đầu tiên.
- MVP rút 3/3; Phase 1 rút 5 lá từ deck 8–10.
- Không có trạng thái nào cho phép `hand_count > 5`.
- Khi dùng hết tay: bắt đầu thời gian xáo; khi hết thời gian, xáo lại toàn bộ deck và rút một tay mới.
- Thời gian xáo 180 ticks / 3 giây đang được coi là **PROVISIONAL**.
- Seed được truyền vào để test/replay có thể tái lập thứ tự xáo.

## 7. Chính sách duplicate card

GDD hiện cung cấp kích thước deck nhưng không chốt một lá có được xuất hiện nhiều lần trong deck hay không. Vì vậy `CardDeckRules.duplicate_policy` có ba lựa chọn:

- `OWNER_DECISION_REQUIRED`: nếu deck có ID trùng, DeckBuilder trả `DUPLICATE_POLICY_UNSET`.
- `DISALLOW`: từ chối deck có ID trùng.
- `ALLOW`: cho phép nhiều bản sao.

Không có luật duplicate mặc định bị áp đặt ngầm. Deck chỉ gồm các ID duy nhất vẫn hợp lệ với mọi policy.

## 8. Card Gauge

- Tối đa 5 điểm, mặc định bắt đầu 5.
- Hồi 1 điểm mỗi 240 simulation ticks (4 giây ở 60Hz).
- Cost 0–3 được trừ ngay khi dùng thẻ.
- `add_gauge(amount)` cho phép effect như Gáy Sáng hồi Card Gauge, luôn clamp về tối đa 5.
- Card Gauge không dùng chung với M10 SpecialGauge.

## 9. Effect data và giới hạn tích hợp

CardController phát `effect_requested(card_id, effect)` cho từng effect của thẻ. Effect có `trigger_id = on_activate` và `duration_ticks > 0` được theo dõi theo simulation tick. Effect có trigger có điều kiện (ví dụ `owner_hp_below_ratio`, `on_successful_evade`) **không tự bật ngay khi dùng thẻ**; M12 phải xác nhận trigger rồi gọi `apply_timed_effect(card_id, effect)`. Effect tức thời / trì hoãn có `duration_ticks = 0` được gửi qua `effect_requested` để M12 xử lý. Các effect đang active được truy vấn bằng `has_active_effect()`, `get_effect_magnitude()` và `get_active_effect_remaining_ticks()`.

Ba getter tương thích MVP vẫn có:

- `get_attack_damage_multiplier()`
- `get_incoming_damage_multiplier()`
- `get_heavy_knockback_multiplier()`

**Quan trọng:** M11.1 chưa tự áp dụng các effect vào damage thực tế, HP, Block Gauge, SpecialGauge hoặc tốc độ đối thủ. `trigger_id` và `parameters` là dữ liệu/hợp đồng phát sự kiện để M12 tích hợp xử lý. Ví dụ `owner_hp_below_ratio`, `on_successful_evade`, `after_delay` hiện được lưu và phát ra chứ chưa tự chạy điều kiện gameplay. Không được coi Phase 1 effect là đã playable chỉ vì resource đã tồn tại.

CardCollection có `export_save_data()` / `import_save_data()` để tích hợp với hệ thống save sau này, nhưng M11.1 chưa tự ghi file save.

DeckBuilder là API logic; màn hình UI chọn deck/preparation screen chưa được tạo trong milestone này.

## 10. Cài đặt an toàn vào project

1. Đảm bảo đang ở branch dành riêng cho M11.1, ví dụ:

   ```powershell
   git switch -c feature/m11-1-extensible-card-system
   ```

2. Giải nén ZIP vào thư mục tạm.
3. Copy `core/cards` vào `test-godot/core/`.
4. Copy `tests/m11_1` vào `test-godot/tests/`.
5. Không copy đè bất kỳ file M1–M10 nào; bundle không chứa file thay thế của các milestone đó.

Nếu branch đã tồn tại thì chuyển sang branch đó, không tạo lại.

## 11. Kiểm thử trên Windows / PowerShell 5.1

Chạy từ thư mục gốc `test-godot`:

```powershell
& $godot --headless --editor --path (Get-Location).Path --quit
if ($LASTEXITCODE -ne 0) { throw "Godot editor import failed: $LASTEXITCODE" }

& $godot --headless --path (Get-Location).Path --script "res://tests/m11_1/run_m11_1_tests.gd"
if ($LASTEXITCODE -ne 0) { throw "M11.1 tests failed: $LASTEXITCODE" }
```

Sau khi M11.1 pass, chạy regression:

```powershell
& $godot --headless --path (Get-Location).Path --script "res://tests/m4/run_m4_tests.gd"
& $godot --headless --path (Get-Location).Path --script "res://tests/m8/run_m8_tests.gd"
& $godot --headless --path (Get-Location).Path --script "res://tests/m9/run_m9_tests.gd"
& $godot --headless --path (Get-Location).Path --script "res://tests/m10/run_m10_tests.gd"
```

M11.1 chỉ được đánh dấu PASS sau khi có output thật từ Godot 4.7.2. Chưa có runtime từ máy project trong lúc đóng gói này; test suite cần được chạy trên workspace của bạn.
