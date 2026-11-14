shader_type canvas_item;
// Optional old-TV look: scanlines, RGB mask, slight curve, vignette and glow.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float lines = 216.0;       // one dark line per game pixel row
uniform float curve = 0.06;
uniform float strength = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + curve * dot(c, c));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec3 col = texture(screen_tex, uv).rgb;
		vec3 glow = (texture(screen_tex, uv + vec2(0.002, 0.0)).rgb + texture(screen_tex, uv - vec2(0.002, 0.0)).rgb) * 0.5;
		col = mix(col, max(col, glow), 0.35);
		float sl = 0.78 + 0.22 * sin(uv.y * lines * 6.28318);
		col *= mix(1.0, sl, strength);
		float m = mod(FRAGCOORD.x, 3.0);
		vec3 mask = m < 1.0 ? vec3(1.06, 0.95, 0.95) : (m < 2.0 ? vec3(0.95, 1.06, 0.95) : vec3(0.95, 0.95, 1.06));
		col *= mix(vec3(1.0), mask, strength);
		float vig = smoothstep(0.85, 0.35, length(c));
		col *= mix(1.0, 0.55 + 0.45 * vig, strength);
		col = pow(col, vec3(0.95)) * 1.08;
		COLOR = vec4(col, 1.0);
	}
}
