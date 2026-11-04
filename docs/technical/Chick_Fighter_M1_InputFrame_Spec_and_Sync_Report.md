# CHICK FIGHTER — GDD SYNC REPORT & M1 INPUTFRAME SPECIFICATION

**Trạng thái:** PLANNING-ONLY. Chưa có file dự án nào được tạo/sửa. Mã trong tài liệu là **bản phác (PROPOSED)** để chủ sở hữu xem xét, chưa được kiểm chứng trên Godot 4.7.2.
**Nguồn đối chiếu:** `Chick_Fighter_Game_Design_Document_v1_0_revised.docx` (đã đọc trực tiếp) và các quyết định của chủ sở hữu trong hội thoại.
**Giới hạn:** phiên làm việc này không có OpenCode/Godot MCP, nên mọi nhận định về project thực tế vẫn là UNVERIFIED (xem Phần 5).

---

## 1. QUYẾT ĐỊNH ĐÃ ĐỒNG BỘ

| # | Nội dung | Trạng thái | Đã phản ánh trong GDD revised |
|---|---|---|---|
| D1 | Gà nòi: Speed 200, Jump 600, Gravity 2000 | CONFIRMED | Có (Bảng 4.7, Bảng 5.2) |
| D2 | Gà tre: Speed 260, Jump 600, Gravity 2000 | CONFIRMED | Có |
| D3 | Công thức Jump theo cân nặng (Bảng 4.7) | **Loại bỏ** (do AI thêm, chưa duyệt) | Đã xóa khỏi Bảng 4.7 và ghi vào Change Log |
| D4 | Không chuẩn hóa mọi giống về Speed 200 | CONFIRMED | Có |
| D5 | Movement config dùng chung, chứa preset theo giống; không tùy chỉnh theo từng fighter ngoài preset | CONFIRMED | Có (mục 4.10) |
| D6 | P1/P2 trong project không được tự gán vào Gà nòi/Gà tre | CONFIRMED | Chỉ liên quan project, không ghi trong GDD |
| D7 | Online Versus 1v1 bắt buộc cho MVP, làm ở milestone riêng sau Core Combat | CONFIRMED | Có (mục 4.11, 1.9, 11) |
| D8 | Gọi tay trong: chỉ Story Mode, [SAU MVP], 60 s là giá trị playtest, thua = thua thường, không tịch thu vĩnh viễn | CONFIRMED / PROPOSED (60 s) | Có (mục 2.3, bảng thắng/thua) |
| D9 | Ngưỡng chênh lệch chỉ số kích hoạt Gọi tay trong; hậu quả Escape thất bại | OPEN | Ghi là chưa chốt |
| D10 | Mapping milestone: M14 Regression, M15 Online Versus, M16 Clash Rush/QTE, M17 Time Stop | CONFIRMED | Chưa có bảng ánh xạ trong GDD |

**Bằng chứng kiểm tra chéo cho D1–D2:** với Jump 600 và Gravity 2000, độ cao đỉnh nhảy = 600² / (2·2000) = **90 px**, thời gian bay = 2·600 / 2000 = **0,6 s**. Hai số này trùng đúng Bảng 4.2 của GDD, nên bộ thông số nhất quán.

**Đối chiếu project cũ (từ handoff, UNVERIFIED):**
- P2 = 200 / 600 / 2000 trùng đúng preset Gà nòi, nhưng **không được suy ra P2 là Gà nòi**.
- P1 = 250 / 1200 / 5000 không khớp preset nào. Với bộ này đỉnh nhảy = 1200² / (2·5000) = **144 px**, lệch xa 90 px của GDD.

---

## 2. CÁC ĐIỂM CÒN LỆCH GIỮA GDD VÀ TECHNICAL HANDOFF (cần chủ sở hữu quyết định)

| # | Lệch | Chi tiết | Đề xuất (chưa áp dụng) |
|---|---|---|---|
| G1 | **GDD không có logical input H** | GDD Bảng 4.1 chỉ có 10 điều khiển: A, D, W, S, J, K, L, U, I, O. H là bit thứ 11 theo quyết định của chủ sở hữu và handoff, nhưng không xuất hiện trong GDD | Thêm dòng H vào Bảng 4.1 khi chủ sở hữu chốt tên/chức năng |
| G2 | **Bitmask mạng trong GDD ghi 10 bit** | Mục 4.11 và Hình 4.3 nói "bitmask 10 bit". Nếu InputFrame có 11 bit thì gói INPUT cũng phải là 11 bit | Sửa chữ và vẽ lại Hình 4.3 sau khi chốt G1 |
| G3 | **Clash khác nhau hoàn toàn** | GDD mục 4.7: Clash xảy ra khi hai đòn cùng loại va hitbox trong 3 frame, minigame spam W/A/S/D 2,5 giây, ghi "Có thể bỏ". Handoff: Clash Rush bằng H, QTE 5 giây, input J/K/L | Chốt thiết kế nào là chuẩn rồi cập nhật bên còn lại |
| G4 | **Time Stop, Damage Ledger, Tech Tree không có trong GDD** | Tìm "Time Stop" trong GDD cho 0 kết quả (Cửu Kê chỉ là nhân vật). Handoff mục 7 không truy vết được về GDD | Thêm mục Act 3 vào GDD, hoặc ghi rõ handoff là nguồn duy nhất cho phần này |
| G5 | **Bảng 5.1 mô tả WEIGHT ảnh hưởng độ cao nhảy và dash** | Mâu thuẫn với D1–D2 (Jump 600 chung). Đây là nội dung gốc của GDD, mình không tự sửa | Chốt: sửa mô tả WEIGHT chỉ còn knockback và Clash |
| G6 | **Input Buffer 8 frame** | GDD mục 4.1 có Input Buffer (nhận Dash nhấn đúp, bấm sớm). Handoff cấm tạo buffer/leniency dài hạn trong M1 | Xếp Input Buffer sang M3 làm module đọc lịch sử InputFrame, không làm trong M1 |
| G7 | **"Chuộc gà bị tịch thu = Giá × 2,0"** | Công thức 6 mục 7.3 của GDD cho thấy tồn tại cơ chế tịch thu, trong khi Gọi tay trong cấm tịch thu vĩnh viễn | Làm rõ cơ chế tịch thu gắn với tình huống nào (có thể là Escape thất bại, đang OPEN) |
| G8 | **Tên mốc** | GDD dùng Phase 0/1/2, handoff dùng M0–M17 | Dùng bảng ánh xạ ở Phần 3 |

---

## 3. NỘI DUNG CẦN CẬP NHẬT TRONG TECHNICAL HANDOFF

Mình không có file handoff dạng sửa được nên liệt kê đoạn thay thế.

1. **Mục 1.2, Versus 1v1:** thay dòng *"Yêu cầu Online Versus 1v1 có thuộc điều kiện MVP release hay không vẫn là OPEN"* bằng:
   *"CONFIRMED — Online Versus 1v1 là yêu cầu của MVP release; triển khai ở milestone riêng (M15) sau Core Combat. Hoàn thành Core Combat không đồng nghĩa hoàn thành Online Versus."*
2. **Mục 2.3 và 10.1:** thêm bảng preset giống gà (Phần 1, D1–D2) và ghi *"P1/P2 trong project không được tự gán vào giống nào"*.
3. **Mục 3.1:** thay *"11 logical input bits theo định hướng GDD"* bằng bảng bit ở Phần 4.2, ghi rõ H không có trong GDD Bảng 4.1 (G1).
4. **Mục 9:** thêm bảng ánh xạ GDD ↔ milestone:

| GDD | Milestone |
|---|---|
| Phase 0 (Core Combat, prototype, playtest giữa kỳ) | M1–M14 |
| Phase 1: Online Versus 1v1 | M15 |
| Phase 1: Clash Rush / QTE | M16 |
| Act 3: Time Stop | M17 (chưa có trong GDD, xem G4) |

5. **Mục 10.4:** ghi InputFrame phải hỗ trợ nguồn local/remote về kiến trúc, không có code mạng trong M1.
6. **Mục 11 (Validation Matrix):** thêm dòng *"GDD traceability: có 8 điểm lệch đã liệt kê (G1–G8)"*.

---

## 4. M1 — INPUTFRAME TECHNICAL SPECIFICATION (PROPOSED)

### 4.1 Phân biệt ba lớp

| Lớp | Ví dụ | Ai sở hữu |
|---|---|---|
| Physical key | `A`, `Left`, gamepad button | Người chơi / thiết bị |
| Input Map action | `p1_left`, `p2_left` | `project.godot` (M1 **không sửa**) |
| Logical input bit | `MOVE_LEFT` | `InputBits` (M1) |

P1 và P2 dùng phím khác nhau nhưng phải xuất ra **cùng schema logical**. Combat FSM chỉ đọc logical bit, không đọc phím.

### 4.2 Bit layout (đối chiếu GDD Bảng 4.1)

Thứ tự bit theo đúng thứ tự dòng trong GDD: A, D, W, S, J, K, L, U, I, O, rồi H. Tên logical lấy từ cột "Hành động" của GDD, không đặt theo phím vật lý của P1.

| Bit | Tên logical (PROPOSED) | Phím P1 trong GDD | Hành động theo GDD | Action có trong Input Map baseline |
|---:|---|---|---|---|
| 0 | `MOVE_LEFT` | A | Di chuyển trái | `p1_left` / `p2_left` |
| 1 | `MOVE_RIGHT` | D | Di chuyển phải | `p1_right` / `p2_right` |
| 2 | `JUMP` | W | Nhảy | `p1_jump` / `p2_jump` |
| 3 | `CROUCH` | S | Cúi | `p1_crouch` / `p2_crouch` |
| 4 | `LIGHT` | J | Light Attack | **Chưa có** |
| 5 | `HEAVY` | K | Heavy Attack | **Chưa có** |
| 6 | `SPECIAL` | L | Special | **Chưa có** |
| 7 | `CARD_PREV` | U | Chọn thẻ trái | **Chưa có** |
| 8 | `CARD_NEXT` | I | Chọn thẻ phải | **Chưa có** |
| 9 | `CARD_USE` | O | Kích hoạt thẻ | **Chưa có** |
| 10 | `ACTION_H` | H | **GDD không định nghĩa** (xem G1) | **Chưa có** |

Ghi chú:
- Tên `ACTION_H` là tên trung tính có chủ đích, vì chức năng H (Clash Rush, Time Stop) chưa có trong GDD.
- **Không có bit** cho Dash, Roll, Block, Crouch Block, vì chúng là lệnh suy ra: Dash/Roll từ chuỗi nhấn (module Input Buffer, M3), Block từ hướng ngược đối thủ (FacingRules, M2).
- Hướng là tuyệt đối (trái/phải), không phải forward/back.
- `COUNT = 11`, `MASK = 0x7FF`.

### 4.3 InputFrame

Snapshot bất biến theo tick, gồm 4 trường: `tick`, `held`, `pressed`, `released` (ba mask 11 bit).

- Trường private, chỉ có getter (không setter), tạo qua `_init`/factory; mọi mask bị cắt bằng `MASK` khi tạo.
- Công thức cạnh (có tính các sự kiện đã chốt trong cửa sổ tick, xem 4.4):
  - `pressed  = ((current & ~previous) | latched_pressed)  & MASK`
  - `released = ((previous & ~current) | latched_released) & MASK`
- Dạng chuẩn để truyền/hash sau này: `PackedInt32Array [tick, held, pressed, released]` (int32 đủ cho khoảng 414 ngày ở 60 tick/s).
- Không chứa thời gian thực, không chứa tham chiếu Node: chỉ dữ liệu thuần.

### 4.4 Bắt sự kiện giữa hai tick (không mất cú nhấn ngắn)

**Vấn đề:** poll trạng thái giữ phím tại mỗi tick sẽ mất cú nhấn-thả nằm trọn giữa hai tick.

**Thiết kế:**
1. **Event capture:** `LocalInputSource._input(event)` đẩy từng sự kiện vào hàng đợi `pending` theo thứ tự đến, dưới dạng `(bit, is_pressed)`. Bỏ qua echo (phím lặp).
2. **Tick consumption:** `sample(tick)` duyệt hàng đợi theo thứ tự, cập nhật `held` chạy, đồng thời ghi `latched_pressed` / `latched_released`, rồi xóa hàng đợi. `held` của frame là trạng thái **cuối** cửa sổ tick.
3. **Nhiều sự kiện cùng bit trong một cửa sổ:** hợp nhất vào ba mask, thứ tự trong cùng tick **không được bảo toàn** và consumer không được phụ thuộc vào nó. Quy tắc đọc:

| Chuỗi sự kiện trong cửa sổ | held | pressed | released |
|---|---|---|---|
| Nhấn rồi thả (tap ngắn) | 0 | 1 | 1 |
| Nhấn (giữ tiếp) | 1 | 1 | 0 |
| Đang giữ, thả | 0 | 0 | 1 |
| Đang giữ, thả rồi nhấn lại | 1 | 1 | 1 |
| Không có sự kiện, vẫn giữ | 1 | 0 | 0 |

4. **Mất focus cửa sổ:** tạo sự kiện thả giả cho mọi phím đang giữ, để tránh kẹt phím (PROPOSED, cần kiểm chứng hằng số thông báo focus trong 4.7.2).
5. **Chủ ý không làm trong M1:** buffer gameplay dài hạn, leniency, nhận diện nhấn đúp (G6).

### 4.5 Interface nguồn input

`InputSource` (abstract): `sample(tick) -> InputFrame` và `is_ready(tick) -> bool`.
`is_ready` có sẵn để `RemoteInputSource` (M15) trả `false` khi chưa nhận được frame của tick đó (lockstep sẽ chờ). Local và Scripted luôn trả `true`.

| Nguồn | M1 | Ghi chú |
|---|---|---|
| `LocalInputSource` | Làm | Nhận cấu hình mapping riêng cho từng player |
| `ScriptedInputSource` | Làm | Phục vụ test và replay |
| `RemoteInputSource` | **Không làm** | M15. Cùng định dạng InputFrame, không đổi Combat FSM |
| Input delay | **Không làm** | M15, dạng wrapper bọc quanh một InputSource |

### 4.6 LocalInputSource

- `configure(mapping: Dictionary)` với `{bit_index: StringName action}`. P1 và P2 mỗi bên một cấu hình, ví dụ P1 dùng `p1_left`, `p1_right`, `p1_jump`, `p1_crouch`.
- Trước khi truy vấn, luôn kiểm tra `InputMap.has_action()`. Action không tồn tại thì:
  - Bỏ qua action đó, bit tương ứng luôn bằng 0.
  - Ghi vào danh sách `get_missing_actions()`, cảnh báo **một lần**, không crash.
  - **Không tạo action** trong Project Settings.
- Quy tắc tick (stateful):

| Tình huống | Hành vi |
|---|---|
| `sample(t)` với `t` bằng tick vừa lấy | Trả lại **đúng frame đã cache**, không tính lại cạnh |
| `t` lớn hơn tick trước | Tạo frame mới; nếu bỏ qua tick, **không** tạo frame cho tick bị bỏ, sự kiện dồn vào frame này |
| `t` nhỏ hơn tick trước | `push_error`, trả `null` |
| Tick đầu tiên | `previous` coi như 0 |

### 4.7 ScriptedInputSource

Hàm thuần theo tick (stateless), nên cùng chuỗi đầu vào luôn cho cùng InputFrame dù được lấy mẫu kiểu nào.

| Tình huống | Hành vi (đã chốt trong spec) |
|---|---|
| Tick được hỏi lặp lại | Cùng kết quả (không có trạng thái) |
| Tick bị bỏ qua | Kết quả của tick đó vẫn đúng như khi lấy mẫu đủ |
| Mask có bit ngoài `MASK` | **Từ chối nạp** (`push_error`, trả `false`, không nạp một phần). Khác với factory của InputFrame vốn cắt bằng `MASK` |
| Tick chưa có dữ liệu | Trước tick bắt đầu: `held = 0`. Sau tick cuối: theo `after_end` (mặc định `NEUTRAL`, tùy chọn `HOLD_LAST`) |
| Tick âm | `push_error`, trả `null` |
| Tap ngắn | `add_tap(tick, bit)` đặt cả `pressed` và `released` tại tick đó, `held` không đổi |

### 4.8 Candidate files (chỉ TẠO MỚI, không sửa file cũ) — thư mục là PROPOSED

| File | Nội dung |
|---|---|
| `res://core/input/input_bits.gd` | Hằng bit, tên, `MASK`, chuyển mask ↔ tên |
| `res://core/input/input_frame.gd` | Snapshot bất biến, factory, pack/unpack |
| `res://core/input/input_source.gd` | Interface trừu tượng |
| `res://core/input/local_input_source.gd` | Nguồn từ Input Map, event queue |
| `res://core/input/scripted_input_source.gd` | Nguồn theo kịch bản |
| `res://tests/m1/test_input_frame.gd` | Các test case (4.9) |
| `res://tests/m1/run_m1_tests.gd` | Trình chạy headless (`extends SceneTree`, không cần addon) |

Không đụng: `player_1.gd`, `player_2.gd`, `node_2d.gd`, `battle_system.tscn`, `project.godot`.

### 4.9 Test plan

| # | Test | Cách làm |
|---|---|---|
| 1 | Pressed đúng một tick | Scripted `[0,1,1,1,0]`: `pressed` chỉ ở tick 1 |
| 2 | Held nhiều tick | Cùng chuỗi: `held` ở tick 1–3 |
| 3 | Released đúng một tick | `released` chỉ ở tick 4 |
| 4 | Nhiều input đồng thời | Mask nhiều bit, kiểm từng bit độc lập |
| 5 | Tap ngắn không mất | `push_event` nhấn+thả trước một tick: frame có `pressed=1`, `released=1`, `held=0`. Thêm một test tích hợp với action có sẵn `p1_left` qua `Input.parse_input_event` |
| 6 | Hai player mapping khác nhau | Cấu hình P1 (`p1_*`) và P2 (`p2_*`), cùng schema logical |
| 7 | Thiếu action | Cấu hình có `p1_light` (không tồn tại): không crash, có trong `get_missing_actions()`, bit luôn 0 |
| 8 | Scripted xác định | Chạy hai lần, và theo nhiều kiểu lấy mẫu (đủ, bỏ qua, lặp), so sánh `PackedInt32Array` |
| 9 | Mask encode/decode | Round-trip cả 2048 mask; pack/unpack frame; mask lố bit bị cắt ở factory và bị từ chối ở Scripted |
| 10 | Thứ tự tick | Lặp tick → frame cache; lùi tick → lỗi; bỏ qua tick → sự kiện dồn đúng |

Tất cả test dùng `push_event` hoặc Scripted để **không sửa Input Map**.

### 4.10 Acceptance criteria

1. Test 1–10 pass khi chạy headless.
2. Không có parser error và warning mới trên Godot 4.7.2.
3. `player_1.gd`, `player_2.gd`, `node_2d.gd`, `battle_system.tscn`, `project.godot` **không đổi** (so sánh hash trước/sau).
4. Không thêm action vào Input Map; không đổi Project Settings.
5. InputFrame không phụ thuộc Node/scene; không có mã mạng; không có Combat FSM.
6. Cùng chuỗi Scripted cho cùng chuỗi frame ở mọi kiểu lấy mẫu.
7. Báo cáo ghi chính xác file tạo mới và kết quả test.

### 4.11 Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Chữ ký API khác ở 4.7.2 (`is_action_pressed`, focus notification, getter-only property) | Kiểm chứng từng API bằng MCP/runtime trước khi viết |
| Taps ngắn bị mất vì lấy mẫu trong `_physics_process` | Event queue (4.4) |
| Thứ tự tick lệch khi driver sai | Quy tắc tick ở 4.6, lỗi rõ ràng |
| Mapping chưa có action tấn công | M1 chỉ báo cáo; thêm action cần phê duyệt riêng |
| Thêm bit H sau này đổi layout | Layout cố định 11 bit từ đầu, H chiếm bit 10 |

---

## 5. TRẠNG THÁI XÁC MINH

| Hạng mục | Trạng thái |
|---|---|
| Đọc GDD revised | VERIFIED (đọc trực tiếp file) |
| Project `test-godot`, Scene Tree, Input Map, script cũ | **UNVERIFIED** (chưa truy cập) |
| Godot MCP, Godot Editor, phiên bản 4.7.2 | **UNVERIFIED** |
| API GDScript trong bản phác | **UNVERIFIED** trên 4.7.2 |

---

## 6. CÂU HỎI CẦN CHỦ SỞ HỮU QUYẾT ĐỊNH TRƯỚC KHI ĐÓNG BĂNG M1

1. **H:** tên và chức năng của logical input thứ 11; có thêm vào GDD Bảng 4.1 không (G1, G2).
2. **WEIGHT:** sửa mô tả ở Bảng 5.1 cho khớp Jump 600 chung không (G5).
3. **Clash:** theo GDD (hitbox va chạm, spam 2,5 giây) hay theo handoff (Rush bằng H, QTE 5 giây) (G3).
4. **Act 3 / Time Stop:** có đưa vào GDD không, hay chỉ nằm ở handoff (G4).
5. **Thư mục** file mới: `res://core/input/` và `res://tests/m1/` có phù hợp không.
6. **Test runner:** dùng script headless thuần (không cài addon test) có đồng ý không.
7. **Base class:** `InputSource` kế thừa `Node` (tiện cho `_input` và focus) hay tách adapter để giữ lõi thuần `RefCounted`.

---

## 7. BẢN PHÁC MÃ (chỉ để xem xét, KHÔNG ghi vào project)

```gdscript
# input_bits.gd
class_name InputBits
extends RefCounted

const MOVE_LEFT := 0
const MOVE_RIGHT := 1
const JUMP := 2
const CROUCH := 3
const LIGHT := 4
const HEAVY := 5
const SPECIAL := 6
const CARD_PREV := 7
const CARD_NEXT := 8
const CARD_USE := 9
const ACTION_H := 10
const COUNT := 11
const MASK := (1 << COUNT) - 1
const NAMES := ["MOVE_LEFT", "MOVE_RIGHT", "JUMP", "CROUCH", "LIGHT", "HEAVY",
	"SPECIAL", "CARD_PREV", "CARD_NEXT", "CARD_USE", "ACTION_H"]

static func bit(index: int) -> int:
	return 1 << index
```

```gdscript
# input_frame.gd
class_name InputFrame
extends RefCounted

var _tick: int
var _held: int
var _pressed: int
var _released: int

var tick: int:
	get: return _tick
var held: int:
	get: return _held
var pressed: int:
	get: return _pressed
var released: int:
	get: return _released

func _init(p_tick: int, p_held: int, p_pressed: int, p_released: int) -> void:
	_tick = p_tick
	_held = p_held & InputBits.MASK
	_pressed = p_pressed & InputBits.MASK
	_released = p_released & InputBits.MASK

static func from_states(p_tick: int, p_current: int, p_previous: int,
		p_latched_pressed: int = 0, p_latched_released: int = 0) -> InputFrame:
	var cur := p_current & InputBits.MASK
	var prev := p_previous & InputBits.MASK
	var pressed := ((cur & ~prev) | p_latched_pressed) & InputBits.MASK
	var released := ((prev & ~cur) | p_latched_released) & InputBits.MASK
	return InputFrame.new(p_tick, cur, pressed, released)

func is_held(p_bit: int) -> bool:
	return ((_held >> p_bit) & 1) == 1

func to_packed() -> PackedInt32Array:
	return PackedInt32Array([_tick, _held, _pressed, _released])

static func from_packed(p_data: PackedInt32Array) -> InputFrame:
	return InputFrame.new(p_data[0], p_data[1], p_data[2], p_data[3])
```

```gdscript
# input_source.gd
class_name InputSource
extends Node

func is_ready(_tick: int) -> bool:
	return true

func sample(_tick: int) -> InputFrame:
	push_error("InputSource.sample() is abstract")
	return null
```

```gdscript
# local_input_source.gd
class_name LocalInputSource
extends InputSource

var _mapping: Dictionary = {}
var _pending: Array = []
var _held := 0
var _last_tick := -1
var _last_frame: InputFrame = null
var _missing: Array[StringName] = []

func configure(p_mapping: Dictionary) -> void:
	_mapping = p_mapping
	_missing.clear()
	for bit in _mapping:
		var action: StringName = _mapping[bit]
		if not InputMap.has_action(action):
			_missing.append(action)
			push_warning("LocalInputSource: missing action %s" % action)

func get_missing_actions() -> Array[StringName]:
	return _missing

func _input(event: InputEvent) -> void:
	feed_event(event)

func feed_event(event: InputEvent) -> void:
	if event.is_echo():
		return
	for bit in _mapping:
		var action: StringName = _mapping[bit]
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			push_event(bit, true)
		elif event.is_action_released(action):
			push_event(bit, false)

func push_event(p_bit: int, p_is_pressed: bool) -> void:
	_pending.append([p_bit, p_is_pressed])

func sample(p_tick: int) -> InputFrame:
	if p_tick == _last_tick:
		return _last_frame
	if p_tick < _last_tick:
		push_error("LocalInputSource: tick went backwards")
		return null
	var cur := _held
	var latched_p := 0
	var latched_r := 0
	for ev in _pending:
		var m := InputBits.bit(ev[0])
		if ev[1]:
			cur |= m
			latched_p |= m
		else:
			cur &= ~m
			latched_r |= m
	_pending.clear()
	_last_frame = InputFrame.from_states(p_tick, cur, _held, latched_p, latched_r)
	_held = cur
	_last_tick = p_tick
	return _last_frame
```

```gdscript
# scripted_input_source.gd
class_name ScriptedInputSource
extends InputSource

enum AfterEnd { NEUTRAL, HOLD_LAST }

var _start := 0
var _masks: Array[int] = []
var _after_end := AfterEnd.NEUTRAL
var _tap_pressed := {}
var _tap_released := {}

func load_masks(p_start_tick: int, p_masks: Array[int],
		p_after_end: AfterEnd = AfterEnd.NEUTRAL) -> bool:
	for m in p_masks:
		if (m & ~InputBits.MASK) != 0:
			push_error("ScriptedInputSource: mask has bits outside MASK")
			return false
	_start = p_start_tick
	_masks = p_masks.duplicate()
	_after_end = p_after_end
	return true

func add_tap(p_tick: int, p_bit: int) -> void:
	var m := InputBits.bit(p_bit)
	_tap_pressed[p_tick] = _tap_pressed.get(p_tick, 0) | m
	_tap_released[p_tick] = _tap_released.get(p_tick, 0) | m

func _held_at(t: int) -> int:
	if t < _start or _masks.is_empty():
		return 0
	var i := t - _start
	if i < _masks.size():
		return _masks[i]
	return _masks[-1] if _after_end == AfterEnd.HOLD_LAST else 0

func sample(p_tick: int) -> InputFrame:
	if p_tick < 0:
		push_error("ScriptedInputSource: negative tick")
		return null
	return InputFrame.from_states(p_tick, _held_at(p_tick), _held_at(p_tick - 1),
		_tap_pressed.get(p_tick, 0), _tap_released.get(p_tick, 0))
```

---

**Ranh giới phê duyệt:** tài liệu này là đặc tả và báo cáo đồng bộ. Chưa có phê duyệt triển khai M1, nên chưa tạo hay sửa bất kỳ file project nào.
