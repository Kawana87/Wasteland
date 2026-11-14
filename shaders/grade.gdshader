shader_type canvas_item;
// Post-war colour grade applied to the game world (not the UI): desaturated, warm olive/sepia,
// soft vignette. Brightness and tint follow the time of day.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 tint = vec3(1.03, 1.0, 0.86);
uniform float bright = 1.0;
uniform float sat = 0.74;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, sat);
	c = c * tint * bright + vec3(0.015, 0.01, 0.0);
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * 0.55;
	COLOR = vec4(c, 1.0);
}
