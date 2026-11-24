shader_type canvas_item;
// Viền 1 px bản đồ (= 1,25 texel khi sprite thu nhỏ ×0,8) quanh hình dạng sprite.
// region_min/region_max: vùng đang vẽ trong texture (UV 0..1); ngoài vùng coi như trong suốt.

uniform vec4 outline_color : source_color = vec4(0.1647, 0.1176, 0.1804, 1.0);
uniform float outline_texels = 1.25;
uniform vec2 region_min = vec2(0.0, 0.0);
uniform vec2 region_max = vec2(1.0, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		vec2 o = TEXTURE_PIXEL_SIZE * outline_texels;
		vec2 u0 = UV + vec2(o.x, 0.0);
		vec2 u1 = UV - vec2(o.x, 0.0);
		vec2 u2 = UV + vec2(0.0, o.y);
		vec2 u3 = UV - vec2(0.0, o.y);
		float n = 0.0;
		n = max(n, texture(TEXTURE, u0).a * step(u0.x, region_max.x));
		n = max(n, texture(TEXTURE, u1).a * step(region_min.x, u1.x));
		n = max(n, texture(TEXTURE, u2).a * step(u2.y, region_max.y));
		n = max(n, texture(TEXTURE, u3).a * step(region_min.y, u3.y));
		if (n > 0.5) {
			c = outline_color;
		}
	}
	COLOR = c;
}
