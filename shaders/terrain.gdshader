shader_type canvas_item;
render_mode unshaded;
// Terrain is a mesh of sloped triangles. Each vertex carries:
//   COLOR.rgb = material mid-tone, COLOR.a = how lit the slope is (0..1)
//   UV.x = world x + material id * 1000, UV.y = world y
// Roads, sidewalks, dirt tracks and cast shadows come from world-space masks (GroundMaps),
// so road edges curve smoothly instead of stepping tile by tile.
// Lighting is quantised into 4 shades with an ordered (Bayer) dither anchored to screen pixels.

const float BAYER[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};

uniform sampler2D road_map : filter_linear, repeat_disable;
uniform sampler2D side_map : filter_linear, repeat_disable;
uniform sampler2D dirt_map : filter_linear, repeat_disable;
uniform sampler2D shade_map : filter_linear, repeat_disable;
uniform float shadow_strength = 1.0;

varying vec2 wpos;
varying float mat;
varying float lit;
varying vec2 pix;

void vertex() {
	mat = floor(UV.x / 1000.0 + 0.001);
	wpos = vec2(UV.x - mat * 1000.0, UV.y);
	lit = COLOR.a;
	pix = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 cell = floor(pix);
	float n = hash(cell);
	int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float th = (BAYER[bi] + 0.5) / 16.0;
	vec3 base = COLOR.rgb;
	float extra = 0.0;
	float m = mat;
	vec2 uv = wpos / 64.0;
	bool floor_mat = (m >= 6.5 && m <= 10.5) || m > 13.5;
	bool city = wpos.x >= 24.0 && wpos.y >= 24.0;
	if (!floor_mat) {
		float rd = texture(road_map, uv).r;
		float sd = texture(side_map, uv).r;
		float dd = texture(dirt_map, uv).r;
		float edge = 0.5 + (th - 0.5) * 0.3;
		if (rd > 0.8) {
			base = vec3(0.78, 0.66, 0.32); m = 5.0;            // faded centre paint
		} else if (rd > edge * 0.5) {
			base = vec3(0.29, 0.28, 0.30); m = 5.0;            // asphalt
			float cr = vnoise(wpos * 3.0);
			if (abs(cr - 0.5) < 0.02) { extra = 1.0; }          // cracks
			float ph = hash(floor(wpos * 1.5));
			vec2 f = fract(wpos * 1.5) - 0.5;
			if (ph < 0.05 && dot(f, f) < 0.06) { base *= 0.6; }
			if (vnoise(wpos * 0.7) > 0.72) { base = mix(base, vec3(0.42, 0.40, 0.36), 0.5); }
			if (vnoise(wpos * 1.3 + 7.0) > 0.78 && n < 0.25) { base = vec3(0.42, 0.48, 0.28); }   // weeds pushing through
		} else if (sd > edge) {
			if (city) {
				base = vec3(0.56, 0.54, 0.50); m = 6.0;        // concrete sidewalk slabs
				vec2 f = fract(wpos);
				if (f.x < 0.04 || f.y < 0.04) { extra = 1.0; }
				if (hash(floor(wpos)) < 0.12) { base *= 0.9; }
			} else {
				base = vec3(0.50, 0.46, 0.38); m = 3.0;        // gravel shoulder
			}
		} else if (dd > edge) {
			base = vec3(0.50, 0.42, 0.30); m = 11.0;            // dirt track with ruts
			if (abs(fract(wpos.x * 1.7 + wpos.y * 1.7) - 0.5) < 0.06) { extra = 1.0; }
		}
	}
	if (m < 3.5) {
		float g = vnoise(wpos * 2.3);
		if (n < 0.05) { extra = -1.0; } else if (n < 0.09) { extra = 1.0; }
		if (g > 0.7) { base = mix(base, vec3(0.55, 0.52, 0.32), 0.35); }
		if (g < 0.22) { base = mix(base, vec3(0.36, 0.40, 0.24), 0.35); }
		// short grass strokes
		if (mod(cell.x + floor(cell.y * 0.5) * 3.0, 7.0) < 1.0 && hash(cell * 0.37) < 0.35) { extra = -1.0; }
	}
	if (m == 7.0) { if (fract(wpos.y * 3.0) < 0.12) { extra = 2.0; } }
	if (m == 8.0) {
		float c = mod(floor(wpos.x * 2.0) + floor(wpos.y * 2.0), 2.0);
		base = c > 0.5 ? vec3(0.86, 0.83, 0.76) : vec3(0.2, 0.19, 0.2);
	}
	if (m == 14.0) {
		float c = mod(floor(wpos.x * 3.0) + floor(wpos.y * 3.0), 2.0);
		base = c > 0.5 ? vec3(0.6, 0.72, 0.66) : vec3(0.84, 0.81, 0.72);
	}
	if (m == 9.0) { if (mod(cell.x + cell.y * 2.0, 7.0) < 1.0) { extra = -1.0; } }
	if (m == 10.0) { vec2 f = fract(wpos * 2.0); if (f.x < 0.03 || f.y < 0.03) { extra = 1.0; } }
	if (m == 4.0) { if (mod(floor((wpos.x + wpos.y) * 6.0), 5.0) < 1.0) { extra = 1.0; } }
	float v = 0.5 + (lit - 0.80) * 3.0 + (n - 0.5) * 0.14;
	float lv = v * 3.2;
	float k = floor(lv) + ((fract(lv) > th) ? 1.0 : 0.0);
	k = 3.0 - clamp(k, 0.0, 3.0);
	k = clamp(k + extra, 0.0, 3.0);
	float f = k < 0.5 ? 1.12 : (k < 1.5 ? 1.0 : (k < 2.5 ? 0.86 : 0.73));
	vec3 col = base * f;
	// cast + contact shadows, dithered at the edges, slightly blue
	float s = texture(shade_map, uv).r;
	if (!floor_mat && s > th * 0.96 + 0.02) {
		col *= mix(vec3(1.0), vec3(0.6, 0.63, 0.74), shadow_strength * (s > 0.7 ? 1.0 : 0.75));
	}
	COLOR = vec4(col, 1.0);
}
