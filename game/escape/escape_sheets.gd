extends RefCounted

## TỰ SINH bởi tools/art/build_escape.py – đừng sửa tay (chạy lại script để cập nhật).
## Bảng khung hình cho game/art/escape/*.png. Mọi khung nhân vật: ô HERO_CELL, gốc (chân / mặt nước) ở HERO_FOOT.

const HERO_CELL: int = 56
const HERO_FOOT: Vector2i = Vector2i(28, 54)
## Tên khung → chỉ số ô trong hero_noi.png / hero_dongtao.png.
const HERO: Dictionary = {"run0": 0, "run1": 1, "run2": 2, "run3": 3, "jump": 4, "fall": 5, "slide": 6, "stumble": 7, "dive": 8, "stand": 9, "swim0": 10, "swim1": 11, "swim2": 12, "swim3": 13}
## Tên khung → chỉ số ô trong hero_back.png (nhìn sau lưng, không có gà).
const HERO_BACK: Dictionary = {"wash0": 0, "wash1": 1, "wash2": 2, "point": 3, "stand": 4}
const POLICE_CELL: Vector2i = Vector2i(32, 52)
const POLICE_FOOT: Vector2i = Vector2i(16, 50)
## Hàng 0 = chú cao gầy (ria mép), hàng 1 = chú thấp mập. Cột: chạy 0–3, đứng trước 4, nói 5, gãi đầu 6,
## đứng nghiêng cầm sổ biên bản 7.
const POLICE: Dictionary = {"run": [0, 1, 2, 3], "front": 4, "talk": 5, "scratch": 6, "notebook": 7}
## Gà nhỏ: hàng 0 = nòi/tre, hàng 1 = Đông Tảo; cột 0 ngồi, 1 chớp mắt. Ô ROOSTER_CELL, quay phải.
const ROOSTER_CELL: Vector2i = Vector2i(16, 14)
## Prop: [x, y, w, h, số khung] trong props.png (các khung nằm ngang liền nhau, gốc = giữa-dưới).
const PROPS: Dictionary = {
	"bamboo": [0, 0, 104, 127, 3],
	"banana": [195, 213, 65, 52, 4],
	"banana_b": [456, 213, 65, 52, 4],
	"boat_two": [0, 213, 194, 55, 1],
	"buffalo": [153, 317, 62, 36, 2],
	"bush": [384, 317, 40, 24, 1],
	"coconut_a": [638, 128, 95, 71, 4],
	"coconut_b": [249, 128, 97, 72, 4],
	"coconut_c": [313, 0, 107, 91, 4],
	"dog_sleep": [799, 317, 29, 13, 2],
	"ducks": [858, 317, 15, 11, 4],
	"fence": [526, 317, 26, 20, 1],
	"fisher": [530, 269, 53, 43, 2],
	"fruit_boat": [165, 128, 83, 77, 1],
	"hens": [738, 317, 15, 14, 4],
	"house_garden": [790, 269, 112, 40, 1],
	"house_home": [903, 269, 112, 40, 1],
	"house_thatch": [637, 269, 152, 40, 1],
	"hyacinth_a": [562, 317, 26, 16, 2],
	"hyacinth_b": [615, 317, 25, 16, 2],
	"hyacinth_c": [666, 317, 23, 16, 2],
	"hyacinth_d": [713, 317, 24, 16, 1],
	"jackfruit": [0, 128, 82, 84, 2],
	"jar": [447, 317, 21, 22, 1],
	"jar_b": [425, 317, 21, 23, 1],
	"lotus": [469, 317, 28, 21, 2],
	"mango": [742, 0, 72, 86, 2],
	"nipa": [265, 269, 66, 45, 4],
	"nipa_b": [0, 269, 66, 47, 4],
	"rack": [321, 317, 62, 31, 1],
	"sign_ferry": [278, 317, 42, 33, 1],
	"smoke": [0, 317, 19, 40, 8],
	"stake": [553, 317, 8, 19, 1],
	"tour_boat": [717, 213, 153, 50, 1],
}
