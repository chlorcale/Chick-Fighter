extends RefCounted

## TỰ SINH bởi tools/art/build_home_interior.py từ NhaTrong_NhanVatChinh.aseprite – ĐỪNG SỬA TAY.
## Toạ độ = px ảnh = px thế giới nhà (gốc 0,0 góc trên trái). Ảnh trong res://game/art/home/interior/

const ART: String = "res://game/art/home/interior/"
const SIZE: Vector2i = Vector2i(960, 576)
const FRAMES: int = 8
const FRAME_TIME: float = 0.110
const FLOOR_SORT: int = -100000
## Đồ vật y-sort: pos = góc trên trái, sort = gốc y-sort (FLOOR_SORT = sát nền), frames > 1 = dải khung ngang,
## yield = chỉ số ô bội mở rộng chiếm chỗ vật này (−1 = không).
const OBJECTS: Array[Dictionary] = [
	{"name": "hang_rao_tre_tren", "tex": "obj_hang_rao_tre_tren.png", "pos": Vector2(22, 92), "size": Vector2(294, 36), "frames": 1, "sort": 128, "yield": -1},
	{"name": "ke_tivi_go_kham", "tex": "obj_ke_tivi_go_kham.png", "pos": Vector2(546, 64), "size": Vector2(86, 88), "frames": 1, "sort": 152, "yield": -1},
	{"name": "tu_tho_trung_bay_kham", "tex": "obj_tu_tho_trung_bay_kham.png", "pos": Vector2(864, 32), "size": Vector2(70, 122), "frames": 1, "sort": 154, "yield": -1},
	{"name": "tu_ao_go", "tex": "obj_tu_ao_go.png", "pos": Vector2(454, 32), "size": Vector2(64, 122), "frames": 1, "sort": 154, "yield": -1},
	{"name": "ban_tho_go_kham", "tex": "obj_ban_tho_go_kham.png", "pos": Vector2(673, 46), "size": Vector2(126, 114), "frames": 1, "sort": 160, "yield": -1},
	{"name": "than_cay_man", "tex": "obj_than_cay_man.png", "pos": Vector2(63, 148), "size": Vector2(18, 50), "frames": 1, "sort": 198, "yield": -1},
	{"name": "dong_rom", "tex": "obj_dong_rom.png", "pos": Vector2(99, 171), "size": Vector2(70, 43), "frames": 1, "sort": 214, "yield": -1},
	{"name": "giuong_go", "tex": "obj_giuong_go.png", "pos": Vector2(332, 104), "size": Vector2(98, 114), "frames": 1, "sort": 218, "yield": -1},
	{"name": "quat_dung", "tex": "obj_quat_dung.png", "pos": Vector2(447, 170), "size": Vector2(26, 50), "frames": 1, "sort": 220, "yield": -1},
	{"name": "chuong_ga_go", "tex": "obj_chuong_ga_go.png", "pos": Vector2(172, 122), "size": Vector2(110, 102), "frames": 1, "sort": 224, "yield": -1},
	{"name": "bao_lua_thoc", "tex": "obj_bao_lua_thoc.png", "pos": Vector2(106, 215), "size": Vector2(62, 33), "frames": 1, "sort": 248, "yield": -1},
	{"name": "o_de_rom_trung", "tex": "obj_o_de_rom_trung.png", "pos": Vector2(183, 233), "size": Vector2(28, 16), "frames": 1, "sort": 249, "yield": -1},
	{"name": "ga_tha_3_con", "tex": "obj_ga_tha_3_con.png", "pos": Vector2(269, 246), "size": Vector2(7, 7), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "ga_tha_2_con", "tex": "obj_ga_tha_2_con.png", "pos": Vector2(258, 254), "size": Vector2(7, 7), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "ban_tra_giua_kham", "tex": "obj_ban_tra_giua_kham.png", "pos": Vector2(689, 182), "size": Vector2(94, 90), "frames": 1, "sort": 272, "yield": -1},
	{"name": "lu_hung_nuoc_mua", "tex": "obj_lu_hung_nuoc_mua.png", "pos": Vector2(255, 251), "size": Vector2(38, 41), "frames": 1, "sort": 292, "yield": -1},
	{"name": "truong_ky_trai_kham_xa_cu", "tex": "obj_truong_ky_trai_kham_xa_cu.png", "pos": Vector2(630, 178), "size": Vector2(50, 126), "frames": 1, "sort": 304, "yield": -1},
	{"name": "truong_ky_phai_kham_xa_cu", "tex": "obj_truong_ky_phai_kham_xa_cu.png", "pos": Vector2(792, 178), "size": Vector2(50, 126), "frames": 1, "sort": 304, "yield": -1},
	{"name": "don_go_kham", "tex": "obj_don_go_kham.png", "pos": Vector2(748, 268), "size": Vector2(32, 38), "frames": 1, "sort": 306, "yield": -1},
	{"name": "cai_phan_go_gian_tho", "tex": "obj_cai_phan_go_gian_tho.png", "pos": Vector2(856, 178), "size": Vector2(78, 128), "frames": 1, "sort": 306, "yield": -1},
	{"name": "ruong_go_dai_dong", "tex": "obj_ruong_go_dai_dong.png", "pos": Vector2(332, 274), "size": Vector2(58, 40), "frames": 1, "sort": 314, "yield": -1},
	{"name": "ghe_go_ban_hoc", "tex": "obj_ghe_go_ban_hoc.png", "pos": Vector2(412, 280), "size": Vector2(28, 38), "frames": 1, "sort": 318, "yield": -1},
	{"name": "chau_van_nien_thanh", "tex": "obj_chau_van_nien_thanh.png", "pos": Vector2(542, 281), "size": Vector2(29, 39), "frames": 1, "sort": 320, "yield": -1},
	{"name": "ban_hoc_den_radio", "tex": "obj_ban_hoc_den_radio.png", "pos": Vector2(446, 256), "size": Vector2(72, 66), "frames": 1, "sort": 322, "yield": -1},
	{"name": "chau_quat_canh_cua_chinh", "tex": "obj_chau_quat_canh_cua_chinh.png", "pos": Vector2(667, 281), "size": Vector2(26, 41), "frames": 1, "sort": 322, "yield": -1},
	{"name": "nguong_cua_chinh", "tex": "obj_nguong_cua_chinh.png", "pos": Vector2(704, 328), "size": Vector2(64, 8), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "choi_cha_dung_vach", "tex": "obj_choi_cha_dung_vach.png", "pos": Vector2(287, 300), "size": Vector2(17, 50), "frames": 1, "sort": 350, "yield": -1},
	{"name": "bac_tam_cap_ngoai_cua_chinh", "tex": "obj_bac_tam_cap_ngoai_cua_chinh.png", "pos": Vector2(699, 336), "size": Vector2(74, 24), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "nia_phoi_thoc", "tex": "obj_nia_phoi_thoc.png", "pos": Vector2(151, 382), "size": Vector2(52, 34), "frames": 1, "sort": -100000, "yield": 8},
	{"name": "ga_tha_5_con", "tex": "obj_ga_tha_5_con.png", "pos": Vector2(97, 412), "size": Vector2(7, 7), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "bep_cui_ong_tao", "tex": "obj_bep_cui_ong_tao.png", "pos": Vector2(334, 371), "size": Vector2(106, 73), "frames": 1, "sort": 444, "yield": -1},
	{"name": "bep_lua_chay_anim", "tex": "obj_bep_lua_chay_anim.png", "pos": Vector2(353, 400), "size": Vector2(69, 40), "frames": 8, "sort": 445, "yield": -1},
	{"name": "dong_cui", "tex": "obj_dong_cui.png", "pos": Vector2(442, 408), "size": Vector2(44, 36), "frames": 1, "sort": 444, "yield": -1},
	{"name": "chan_chen_chan_ngam_nuoc", "tex": "obj_chan_chen_chan_ngam_nuoc.png", "pos": Vector2(518, 346), "size": Vector2(56, 100), "frames": 1, "sort": 446, "yield": -1},
	{"name": "mang_nuoc_ong_tre", "tex": "obj_mang_nuoc_ong_tre.png", "pos": Vector2(96, 439), "size": Vector2(48, 11), "frames": 1, "sort": 450, "yield": -1},
	{"name": "chen_thoc", "tex": "obj_chen_thoc.png", "pos": Vector2(150, 440), "size": Vector2(22, 12), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "khap_gao", "tex": "obj_khap_gao.png", "pos": Vector2(543, 452), "size": Vector2(26, 31), "frames": 1, "sort": 483, "yield": -1},
	{"name": "than_bui_chuoi", "tex": "obj_than_bui_chuoi.png", "pos": Vector2(28, 458), "size": Vector2(20, 42), "frames": 1, "sort": 500, "yield": -1},
	{"name": "hu_mam", "tex": "obj_hu_mam.png", "pos": Vector2(547, 487), "size": Vector2(14, 18), "frames": 1, "sort": 505, "yield": -1},
	{"name": "nguong_cua_hong_ra_san_ga", "tex": "obj_nguong_cua_hong_ra_san_ga.png", "pos": Vector2(320, 448), "size": Vector2(8, 64), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "phan_an_com_mam_com", "tex": "obj_phan_an_com_mam_com.png", "pos": Vector2(404, 452), "size": Vector2(130, 86), "frames": 1, "sort": 538, "yield": -1},
	{"name": "thau_nhom", "tex": "obj_thau_nhom.png", "pos": Vector2(347, 527), "size": Vector2(28, 16), "frames": 1, "sort": 543, "yield": -1},
	{"name": "lu_nuoc_bep_1", "tex": "obj_lu_nuoc_bep_1.png", "pos": Vector2(605, 502), "size": Vector2(38, 44), "frames": 1, "sort": 546, "yield": -1},
	{"name": "lu_nuoc_bep_2", "tex": "obj_lu_nuoc_bep_2.png", "pos": Vector2(565, 507), "size": Vector2(38, 43), "frames": 1, "sort": 550, "yield": -1},
	{"name": "hang_rao_tre_trai", "tex": "obj_hang_rao_tre_trai.png", "pos": Vector2(15, 118), "size": Vector2(14, 440), "frames": 1, "sort": -100000, "yield": -1},
	{"name": "hang_rao_tre_duoi_trai", "tex": "obj_hang_rao_tre_duoi_trai.png", "pos": Vector2(22, 524), "size": Vector2(218, 36), "frames": 1, "sort": 560, "yield": -1},
	{"name": "hang_rao_tre_duoi_phai", "tex": "obj_hang_rao_tre_duoi_phai.png", "pos": Vector2(292, 524), "size": Vector2(24, 36), "frames": 1, "sort": 560, "yield": -1},
	{"name": "cong_tre_ra_dong", "tex": "obj_cong_tre_ra_dong.png", "pos": Vector2(238, 518), "size": Vector2(54, 42), "frames": 1, "sort": 560, "yield": -1},
	{"name": "canh_cua_hong_mo", "tex": "obj_canh_cua_hong_mo.png", "pos": Vector2(328, 514), "size": Vector2(16, 52), "frames": 1, "sort": 566, "yield": -1},
]
## Lớp trên (mái, tán cây, mùng, rèm, khói bếp): vẽ trên mọi thứ, làm trong khi người chơi đứng dưới.
const ABOVE: Array[Dictionary] = [
	{"name": "mung_che_giuong", "tex": "above_mung_che_giuong.png", "pos": Vector2(327, 98), "size": Vector2(104, 122), "frames": 1},
	{"name": "ren_cua_buong", "tex": "above_ren_cua_buong.png", "pos": Vector2(520, 194), "size": Vector2(18, 67), "frames": 1},
	{"name": "bep_khoi_hoi_nuoc_anim", "tex": "above_bep_khoi_hoi_nuoc_anim.png", "pos": Vector2(353, 338), "size": Vector2(88, 34), "frames": 8},
	{"name": "mai_hien_ton_xanh", "tex": "above_mai_hien_ton_xanh.png", "pos": Vector2(295, 93), "size": Vector2(26, 470), "frames": 1},
	{"name": "mai_che_cua_hong", "tex": "above_mai_che_cua_hong.png", "pos": Vector2(279, 434), "size": Vector2(42, 90), "frames": 1},
	{"name": "mai_ton_chuong_ga", "tex": "above_mai_ton_chuong_ga.png", "pos": Vector2(166, 100), "size": Vector2(126, 48), "frames": 1},
	{"name": "tan_cay_man_trai_do", "tex": "above_tan_cay_man_trai_do.png", "pos": Vector2(23, 104), "size": Vector2(104, 72), "frames": 1},
	{"name": "la_bui_chuoi", "tex": "above_la_bui_chuoi.png", "pos": Vector2(2, 428), "size": Vector2(92, 37), "frames": 1},
]
## Hoạt ảnh sát nền (ánh lửa hắt ra sàn) – vẽ ngay trên ground.png.
const DECOR_ANIM: Array[Dictionary] = [
	{"name": "bep_anh_lua_hat_ra_san_anim", "tex": "decor_bep_anh_lua_hat_ra_san_anim.png", "pos": Vector2(349, 439), "size": Vector2(77, 13), "frames": 8},
]
## Chân (giữa đáy) của 8 bội vẽ sẵn boi_ga_1..8 (theo số trong tên layer).
const PAINTED_CAGES: Array[Vector2] = [Vector2(72, 269), Vector2(72, 317), Vector2(72, 365), Vector2(72, 413), Vector2(128, 523), Vector2(182, 527), Vector2(234, 523), Vector2(268, 437)]
const CAGE_SIZE: Vector2i = Vector2i(50, 41)
const CAGE_SHADOW_OFFSET: Vector2 = Vector2(-24, -5)
## Chân nhà sàn vẽ thêm cho chuồng gỗ (coop_stilts): vùng gầm + x trái các cột trước (rộng 5 px).
const COOP_STILTS: Rect2i = Rect2i(173, 198, 109, 26)
const COOP_POSTS: Array[int] = [173, 236, 276]

