extends RefCounted

## Bộ chiêu (kit) Gà Đông Tảo – tank. Nguồn: D:/GameArt/dongtao_fight_movelist.md và
## dongtao_fight_combo.aseprite (119 frame, 18 tag; xuất bằng tools/art/build_fighter_sheet.py).
## Thời lượng frame lấy từ file art (ms → tick 60 Hz) như kit gà đá mặc định; sát thương và phản ứng
## theo mục 4 "Gợi ý thông số" của movelist. Hộp va chạm đo từ khung bao của frame active (gốc chân
## (57, 105), ×2), gà nhìn sang PHẢI, y âm là hướng lên.
##
## Định dạng một đòn giống Moves.TABLE, thêm các khóa riêng của kit này:
##  armor        [từ, đến]  frame có giáp (chịu đúng 1 đòn không bị ngắt, vẫn mất máu)
##  run          {frames: [từ, đến], speed: px/tick, max_loops, stop_dist}  lao tới, lặp đoạn chạy
##  counter      [từ, đến]  cửa sổ phản đòn; "active": frame quạt cánh; "whiff_hold": tick hồi thêm khi hụt
##  invuln       [từ, đến]  frame bất tử (bay lên của siêu chiêu)
##  ground_only  (trong hit) không trúng đối thủ đang ở trên không
##  counter_only (trong hit) nhịp đánh chỉ có hiệu lực khi đã bắt được đòn
##  freeze_text  dừng hình + cắt cảnh khi ra chiêu
##
## PLACEHOLDER: chi phí 0 vạch cho Húc Trâu / Địa Chấn / Phản Đòn (movelist chỉ ghi giá siêu chiêu),
## số vòng chạy tối đa của Húc Trâu, hộp va chạm, knockback, thời gian hồi thêm khi Phản Đòn hụt.

enum Level { MID, HIGH, LOW }

const TABLE: Dictionary = {
	&"huc_dau": {"name": "Húc Đầu", "tag": "L_HucDau", "cat": "L",
		"hits": [{"frames": [2], "dmg": 6, "react": &"nhe", "level": Level.MID, "kb": 8.0, "hitstop": 4,
			"box": Rect2(36, -118, 86, 58)}],
		"cancel": ["L", "M", "H"]},
	&"dam_chan": {"name": "Dậm Chân", "tag": "M_DamChan", "cat": "M",
		"hits": [{"frames": [2, 3], "dmg": 9, "react": &"nang", "level": Level.LOW, "kb": 16.0, "hitstop": 6,
			"box": Rect2(20, -40, 112, 40), "fx": "shock"}],
		"cancel": ["H", "SP", "SUPER"]},
	&"da_tru": {"name": "Đá Trụ", "tag": "H_DaTru", "cat": "H",
		"hits": [{"frames": [2, 3], "dmg": 14, "react": &"vang", "level": Level.MID, "kb": 100.0, "hitstop": 9,
			"launch": 300.0, "box": Rect2(40, -104, 108, 72)}],
		"cancel": []},
	&"phan_don": {"name": "Phản Đòn", "tag": "SP_PhanDon", "cat": "SP",
		"counter": [0, 1], "active": 3, "whiff_hold": 22,
		"hits": [{"frames": [3], "dmg": 12, "react": &"nang", "level": Level.MID, "kb": 45.0, "hitstop": 10,
			"box": Rect2(24, -128, 130, 124), "counter_only": true}],
		"cancel": []},
	&"huc_trau": {"name": "Húc Trâu", "tag": "SP_HucTrau", "cat": "SP", "freeze_text": "HÚC TRÂU!",
		"armor": [1, 6], "run": {"frames": [2, 5], "speed": 6.0, "max_loops": 3, "stop_dist": 120.0},
		"hits": [{"frames": [6], "dmg": 13, "react": &"nang", "level": Level.MID, "kb": 50.0, "hitstop": 8,
			"box": Rect2(30, -112, 118, 104)}],
		"cancel": []},
	&"dia_chan": {"name": "Địa Chấn", "tag": "SP_DiaChan", "cat": "SP",
		"hits": [{"frames": [4, 5], "dmg": 15, "react": &"te", "level": Level.LOW, "kb": 40.0, "hitstop": 8,
			"box": Rect2(-150, -46, 300, 46), "ground_only": true, "fx": "quake"}],
		"cancel": []},
	&"thai_son": {"name": "Thái Sơn Áp Đỉnh", "tag": "SUP_ThaiSonApDinh", "cat": "SUPER", "cost": 2,
		"unblockable": true, "invuln": [2, 5], "freeze_text": "THÁI SƠN ÁP ĐỈNH!",
		"hits": [{"frames": [6, 7], "dmg": 35, "react": &"vang", "level": Level.MID, "kb": 165.0, "hitstop": 14,
			"launch": 420.0, "box": Rect2(-1100, -60, 2200, 60), "ground_only": true, "fx": "quake"}],
		"cancel": []},
	&"dam_nguc": {"name": "Đấm Ngực Thị Uy", "tag": "TAUNT_DamNguc", "cat": "TAUNT", "gain_frame": 4,
		"hits": [], "cancel": []},
}

const MOVE_LIST: Array = [
	["Húc Đầu", "J"], ["Dậm Chân (đòn thấp, sóng chấn ngắn)", "K"], ["Đá Trụ (đẩy văng)", "L"],
	["Húc Trâu – lao có giáp (chịu 1 đòn)", "H   hoặc  → → + H"],
	["Địa Chấn – sóng chấn 2 phía (không trúng khi nhảy)", "↓ + H   hoặc  ↓ ↓ + H"],
	["Phản Đòn – bắt đòn rồi quạt lại", "← + H  (đúng lúc đòn tới)"],
	["THÁI SƠN ÁP ĐỈNH – 2 vạch, không đỡ được", "→ + H   hoặc  ↓ ↘ → ↓ ↘ → + H"],
	["Đấm Ngực Thị Uy (+25% thanh nộ)", "H + L cùng lúc"],
	["Thiết Giáp: đỡ mọi tầng, không bị đẩy lùi", "giữ lùi (tốn Block Gauge ×1,5)"],
	["Không nhảy, không cúi, không lướt", "gà nặng"],
]

const COMBOS: String = "Combo: J K L · J K → H (2 vạch) · đỡ → ←H → K → ↓H · H (Húc Trâu) → J → L"

## Hoạt ảnh theo trạng thái.
const ANIMS: Dictionary = {
	"idle": "idle", "walk_f": "walk", "walk_b": "walk", "guard": "GUARD_ThietGiap",
	"guard_hit": "GUARD_TrungDon", "nhe": "HIT_Nhe", "nang": "HIT_Nang", "te": "TE_NgaNgua",
	"nam": "NAM_Dat", "vang": "VANG_RaXa", "dung": "DUNG_Day", "taunt": "TAUNT_DamNguc",
}
