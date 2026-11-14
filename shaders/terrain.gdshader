shader_type canvas_item;
render_mode unshaded;
// Terrain is a mesh of sloped triangles. Each vertex carries:
//   COLOR.rgb = material mid-tone, COLOR.a = how lit the slope is (0..1)
//   UV.x = world x + material id * 1000, UV.y = world y
// The fragment shader quantises lighting into 4 shades with an ordered (Bayer) dither,
// anchored to world pixels so the pattern doesn't swim as the camera moves.

const float BAYER[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};

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

void fragment() {
	vec2 cell = floor(pix);
	float n = hash(cell);
	vec3 base = COLOR.rgb;
	float extra = 0.0;
	if (mat < 3.5) { if (n < 0.05) { extra = -1.0; } else if (n < 0.09) { extra = 1.0; } }
	if (mat == 5.0 || mat == 12.0 || mat == 13.0) { if (n < 0.04) { extra = 1.0; } }
	if (mat == 12.0 && abs(sin(wpos.x * 9.1 + sin(wpos.y * 5.3) * 1.7)) < 0.06) { extra = 2.0; }
	if (mat == 13.0) {
		vec2 f = fract(wpos) - 0.5;
		float d = dot(f, f);
		if (d < 0.07) { base *= 0.55; extra = 1.0; } else if (d < 0.09) { extra = -1.0; }
	}
	if (mat == 6.0) { vec2 f = fract(wpos); if (f.x < 0.06 || f.y < 0.06) { extra = 2.0; } }
	if (mat == 7.0) { if (fract(wpos.y * 3.0) < 0.12) { extra = 2.0; } }
	if (mat == 8.0) {
		float c = mod(floor(wpos.x * 2.0) + floor(wpos.y * 2.0), 2.0);
		base = c > 0.5 ? vec3(0.741, 0.706, 0.612) : vec3(0.541, 0.518, 0.463);
	}
	if (mat == 9.0) { if (mod(cell.x + cell.y * 2.0, 7.0) < 1.0) { extra = -1.0; } }
	if (mat == 4.0) { if (mod(floor((wpos.x + wpos.y) * 6.0), 5.0) < 1.0) { extra = 1.0; } }
	float v = 0.5 + (lit - 0.80) * 3.0 + (n - 0.5) * 0.18;
	float lv = v * 3.2;
	int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float th = (BAYER[bi] + 0.5) / 16.0;
	float k = floor(lv) + ((fract(lv) > th) ? 1.0 : 0.0);
	k = 3.0 - clamp(k, 0.0, 3.0);
	k = clamp(k + extra, 0.0, 3.0);
	float f = k < 0.5 ? 1.14 : (k < 1.5 ? 1.0 : (k < 2.5 ? 0.85 : 0.71));
	COLOR = vec4(base * f, 1.0);
}
