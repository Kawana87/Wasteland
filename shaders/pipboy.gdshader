shader_type canvas_item;
// Green phosphor terminal look for the world map: monochrome green from luminance, scanlines, a soft
// barrel curve, vignette, a slow rolling bright band and a little flicker.
uniform float curve = 0.0;   // flat: the markers drawn on top must line up with the map, even zoomed in at an edge
uniform vec3 tint = vec3(0.35, 1.0, 0.45);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv *= 1.0 + curve * dot(uv, uv);
	uv = uv * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.03, 0.0, 1.0);
	} else {
		vec3 c = texture(TEXTURE, uv).rgb;
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		l = pow(l, 0.85) * 1.25;
		float scan = 0.84 + 0.16 * sin(FRAGCOORD.y * 2.1);   // per screen line, so zooming in keeps them thin
		float band = 0.92 + 0.08 * smoothstep(0.0, 0.08, 0.08 - abs(fract(uv.y - TIME * 0.07) - 0.5));
		float flick = 0.97 + 0.03 * sin(TIME * 37.0);
		float vig = 1.0;
		COLOR = vec4(tint * l * scan * band * flick * vig + vec3(0.0, 0.02, 0.0), 1.0);
	}
}
