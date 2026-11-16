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
uniform sampler2D path_map : filter_linear, repeat_disable;
uniform float shadow_strength = 1.0;
uniform vec2 origin = vec2(0.0);     // chunk origin in tiles (UV holds tile position within the chunk)
uniform float city = 0.0;

varying vec2 lpos;
varying float mat;
varying float lit;
varying vec2 pix;

void vertex() {
	mat = floor(UV.x / 1000.0 + 0.001);
	lpos = vec2(UV.x - mat * 1000.0, UV.y);   // tile position within the chunk
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
	vec2 uv = lpos / 32.0;
	vec2 wpos = lpos + origin;
	float lt = lit;
	bool floor_mat = (m >= 6.5 && m <= 10.5) || (m > 13.5 && m < 14.5);
	bool water = m > 14.5 && m < 15.5;
	bool is_city = city > 0.5;
	if (!floor_mat && !water) {
		float rough = (vnoise(wpos * 4.0) - 0.5) * 0.4 + (vnoise(wpos * 11.0) - 0.5) * 0.2;   // ragged edges
		float rd = texture(road_map, uv).r + rough * 0.6;
		float sd = texture(side_map, uv).r;
		float dd = texture(dirt_map, uv).r + rough;
		float pd = texture(path_map, uv).r + rough;
		sd += rough * 0.6;
		float edge = 0.5 + (th - 0.5) * 0.3;
		if (rd > 0.8) {
			base = vec3(0.78, 0.66, 0.32); m = 5.0;            // faded centre paint
		} else if (rd > edge * 0.5) {
			base = vec3(0.29, 0.28, 0.30); m = 5.0;            // asphalt
			// dust blown onto the road near its edges, and drifts across it
			float drift = clamp((0.5 - rd) * 2.2 + (vnoise(wpos * 0.6 + 3.0) - 0.62) * 2.5, 0.0, 1.0);
			if (drift > th) { base = mix(vec3(0.46, 0.40, 0.31), vec3(0.36, 0.33, 0.30), 0.3); m = 11.0; }
			float cr = vnoise(wpos * 3.0);
			if (abs(cr - 0.5) < 0.02) { extra = 1.0; }          // cracks
			float ph = hash(floor(wpos * 1.5));
			vec2 f = fract(wpos * 1.5) - 0.5;
			if (ph < 0.05 && dot(f, f) < 0.06) { base *= 0.6; }
			if (vnoise(wpos * 0.7) > 0.72) { base = mix(base, vec3(0.42, 0.40, 0.36), 0.5); }
			if (vnoise(wpos * 1.3 + 7.0) > 0.78 && n < 0.25) { base = vec3(0.42, 0.48, 0.28); }   // weeds pushing through
		} else if (sd > edge) {
			if (is_city) {
				base = vec3(0.56, 0.54, 0.50); m = 6.0;        // concrete sidewalk slabs
				vec2 f = fract(wpos);
				if (f.x < 0.04 || f.y < 0.04) { extra = 1.0; }
				if (hash(floor(wpos)) < 0.12) { base *= 0.9; }
			} else {
				base = vec3(0.50, 0.46, 0.38); m = 3.0;        // gravel shoulder
			}
		} else if (pd > edge) {
			base = vec3(0.58, 0.52, 0.41); m = 11.0;            // worn foot trail
			if (hash(floor(wpos * 6.0)) < 0.06) { extra = 1.0; }
		} else if (dd > edge) {
			base = vec3(0.50, 0.42, 0.30); m = 11.0;            // dirt track with ruts
			if (abs(fract(wpos.x * 1.7 + wpos.y * 1.7) - 0.5) < 0.06) { extra = 1.0; }
		}
	}
	if (m < 3.5) {
		float g = vnoise(wpos * 2.3);
		if (n < 0.05) { extra = -1.0; } else if (n < 0.09) { extra = 1.0; }
		if (g > 0.7) { base = mix(base, vec3(0.55, 0.52, 0.32), 0.35); }
		if (g < 0.22) { base = mix(base, vec3(0.38, 0.39, 0.25), 0.35); }
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
	if (m == 16.0) { if (abs(vnoise(wpos * 1.7) - 0.5) < 0.03) { extra = 1.0; } if (n < 0.06) { extra = -1.0; } }   // salt crust polygons
	if (m == 17.0 || m == 24.0) { float st = fract((wpos.x + wpos.y) * 0.9 + vnoise(wpos * 0.5) * 2.0); if (st < 0.12) { extra = 1.0; } base = mix(base, vec3(0.62, 0.38, 0.26), vnoise(wpos * 0.3) * 0.3); }
	if (m == 18.0) { float g = vnoise(wpos * 1.6); if (g > 0.66) { base = vec3(0.29, 0.36, 0.33); } if (g < 0.25) { base = mix(base, vec3(0.36, 0.42, 0.24), 0.6); } if (n < 0.08) { extra = -1.0; } }
	if (m == 19.0) { if (n < 0.07) { extra = -2.0; } if (abs(vnoise(wpos * 2.5) - 0.5) < 0.03) { extra = 1.0; } }
	if (m == 20.0) { float row = fract((wpos.x * 0.9 + wpos.y * 0.15) * 1.0); if (row < 0.3) { extra = 1.0; } if (vnoise(wpos * 0.4) > 0.6 && row > 0.5 && n < 0.4) { base = vec3(0.44, 0.48, 0.24); } }
	if (m == 21.0) { if (fract(wpos.x * 0.7 + sin(wpos.y * 0.9) * 0.6) < 0.08) { extra = 1.0; } }
	if (m == 22.0) { if (n < 0.08) { extra = -1.0; } if (vnoise(wpos * 3.0) > 0.7) { base = mix(base, vec3(0.42, 0.33, 0.2), 0.5); } }
	if (m == 23.0) { vec2 f = fract(wpos * 0.5); if (f.x < 0.03 || f.y < 0.03) { extra = 1.0; } if (abs(vnoise(wpos * 2.0) - 0.5) < 0.025) { extra = 1.0; } if (vnoise(wpos * 1.1 + 4.0) > 0.75 && n < 0.3) { base = vec3(0.42, 0.46, 0.28); } }
	if (water) {
		float t = TIME * 0.6;
		float wv = vnoise(wpos * 1.3 + vec2(t, t * 0.6)) + vnoise(wpos * 3.1 - vec2(t * 0.8, 0.0)) * 0.5;
		base = mix(vec3(0.17, 0.30, 0.34), vec3(0.23, 0.40, 0.42), clamp(wv - 0.4, 0.0, 1.0));
		if (wv > 1.18 && n > 0.4) { base = vec3(0.55, 0.66, 0.62); }   // glints
		lt = 0.9;
	}
	float v = 0.5 + (lt - 0.80) * 3.0 + (n - 0.5) * 0.14;
	float lv = v * 3.2;
	float k = floor(lv) + ((fract(lv) > th) ? 1.0 : 0.0);
	k = 3.0 - clamp(k, 0.0, 3.0);
	k = clamp(k + extra, 0.0, 3.0);
	float f = k < 0.5 ? 1.12 : (k < 1.5 ? 1.0 : (k < 2.5 ? 0.86 : 0.73));
	vec3 col = base * f;
	// cast + contact shadows, dithered at the edges, slightly blue
	float s = texture(shade_map, uv).r;
	// cliff faces (steep rock) don't take the flat cast shadows: stamped in world xy they would smear
	// into tall dark wedges down the slope
	if (!floor_mat && mat != 4.0 && s > th * 0.96 + 0.02) {
		col *= mix(vec3(1.0), vec3(0.6, 0.63, 0.74), shadow_strength * (s > 0.7 ? 1.0 : 0.75));
	}
	COLOR = vec4(col, 1.0);
}
