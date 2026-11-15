shader_type canvas_item;

// Đổi màu lông cho gà đối thủ + chớp màu khi trúng/đỡ đòn.
//
// Có mặt nạ bộ phận (part_mask, cùng bố cục với sheet; kênh R = mã * 32 – xem
// tools/art/export_fighter_mask.lua): chỉ đổi màu lông, giữ nguyên mào, mặt, mỏ, mắt, chân, hiệu ứng.
//   1 đầu (mào/mặt giữ nguyên; lông bờm màu cam trên đầu đổi theo "neck")  2 cổ (bờm)
//   3 thân + cánh  4 đuôi  5 chân  6 hiệu ứng  7 bóng mờ (theo thân)
// Mỗi nhóm có (lệch hue, nhân saturation, nhân value). hue_shift/saturation cũ áp lên mọi nhóm lông.
// Không có mặt nạ: hue_shift/saturation áp lên toàn bộ hình như trước.
uniform float hue_shift = 0.0;
uniform float saturation = 1.0;
uniform bool use_mask = false;
uniform sampler2D part_mask : filter_nearest, repeat_disable;
uniform vec3 body_hsv = vec3(0.0, 1.0, 1.0);
uniform vec3 neck_hsv = vec3(0.0, 1.0, 1.0);
uniform vec3 tail_hsv = vec3(0.0, 1.0, 1.0);
uniform vec3 legs_hsv = vec3(0.0, 1.0, 1.0);
uniform vec3 comb_hsv = vec3(0.0, 1.0, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 shift(vec3 hsv, vec3 p) {
	// Viền đen (value rất thấp) giữ nguyên để nét pixel không bị nhòe.
	if (hsv.z < 0.09) {
		return hsv;
	}
	return vec3(fract(hsv.x + p.x), clamp(hsv.y * p.y, 0.0, 1.0), clamp(hsv.z * p.z, 0.0, 1.0));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 hsv = rgb2hsv(c.rgb);
	vec3 legacy = vec3(hue_shift, saturation, 1.0);
	if (use_mask) {
		int role = int(texture(part_mask, UV).r * 255.0 / 32.0 + 0.5);
		vec3 p = vec3(0.0, 1.0, 1.0);
		bool feather = false;
		if (role == 3 || role == 7) {
			p = body_hsv;
			feather = true;
		} else if (role == 2) {
			p = neck_hsv;
			feather = true;
		} else if (role == 4) {
			p = tail_hsv;
			feather = true;
		} else if (role == 5) {
			p = legs_hsv;
		} else if (role == 1) {
			bool hackle = hsv.x > 0.035 && hsv.x < 0.115 && hsv.y > 0.2 && hsv.z > 0.45;
			bool comb = (hsv.x > 0.9 || hsv.x < 0.035) && hsv.y > 0.45;
			if (hackle) {
				p = neck_hsv;
				feather = true;
			} else if (comb) {
				p = comb_hsv;
			}
		}
		if (feather) {
			p = vec3(p.x + legacy.x, p.y * legacy.y, p.z);
		}
		hsv = shift(hsv, p);
	} else {
		hsv.x = fract(hsv.x + hue_shift);
		hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	}
	vec3 rgb = hsv2rgb(hsv);
	COLOR = vec4(mix(rgb, flash_color.rgb, clamp(flash, 0.0, 1.0)), c.a);
}
