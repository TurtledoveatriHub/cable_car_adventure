shader_type canvas_item;
// 背景大气透视 / 轻微景深：对背景层做低强度模糊、去饱和、雾化和压暗。
// 只作用于 SkyBackdrop 所在的 CanvasLayer，不会影响缆车、障碍和 UI。

// ## 屏幕纹理：由 BackBufferCopy 捕获的背景层内容，供模糊采样使用。
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// ## 背景模糊半径（像素，0~8）：0 表示关闭景深模糊；越大背景越虚化。
uniform float blur_radius : hint_range(0.0, 8.0) = 1.12;
// ## 背景去饱和比例（0~1）：0 保持原色；越大越灰，用于拉开背景与实体障碍的层次。
uniform float desaturation : hint_range(0.0, 1.0) = 0.14;
// ## 雾化颜色（RGB，alpha 不参与计算）：建议取关卡天空的浅灰蓝，模拟大气透视。
uniform vec4 haze_color : source_color = vec4(0.70, 0.80, 0.88, 1.0);
// ## 雾化强度（0~0.5）：0 不雾化；过大背景会发白、失去细节。
uniform float haze_strength : hint_range(0.0, 0.5) = 0.10;
// ## 背景压暗比例（0~0.5）：0 不压暗；越大背景越暗，实体与缆车越突出。
uniform float darken : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	vec4 color;
	if (blur_radius > 0.01) {
		vec2 texel = SCREEN_PIXEL_SIZE * blur_radius;
		color = texture(screen_texture, SCREEN_UV) * 0.40;
		color += texture(screen_texture, SCREEN_UV + vec2(texel.x, 0.0)) * 0.15;
		color += texture(screen_texture, SCREEN_UV - vec2(texel.x, 0.0)) * 0.15;
		color += texture(screen_texture, SCREEN_UV + vec2(0.0, texel.y)) * 0.15;
		color += texture(screen_texture, SCREEN_UV - vec2(0.0, texel.y)) * 0.15;
	} else {
		color = texture(screen_texture, SCREEN_UV);
	}
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(color.rgb, vec3(gray), desaturation);
	color.rgb = mix(color.rgb, haze_color.rgb, haze_strength);
	color.rgb *= 1.0 - darken;
	COLOR = color;
}
