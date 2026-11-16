class_name GroundMaps
## Builds the textures the terrain shader samples for one chunk (8 texels per tile):
##   road  : asphalt (128) and dashed centre paint (255), smooth curves instead of tile steps
##   side  : sidewalks / shoulders
##   dirt  : dirt tracks
##   shade : cast shadows (255) and contact shadows at wall bases (110)
##   path  : worn foot trails
## Everything near the chunk (its ring of neighbours) is stamped, clipped to the chunk, so roads,
## shadows and trails run on across chunk edges. Image.fill_rect keeps it fast on phones.

const R := 8                       # texels per tile
const SUN := Vector2(1.0, -0.42)   # direction shadows fall in (world). Screen: down-right.
const SHADOW_K := 0.05             # tiles of shadow per logical pixel of height

static var _o := Vector2.ZERO      # chunk origin (tiles) while building

static func build(w: World, cx: int, cy: int, near: Array) -> Dictionary:
	var size := World.CH * R
	_o = Vector2(cx * World.CH, cy * World.CH)
	var road := Image.create(size, size, false, Image.FORMAT_L8)
	var side := Image.create(size, size, false, Image.FORMAT_L8)
	var dirt := Image.create(size, size, false, Image.FORMAT_L8)
	var shade := Image.create(size, size, false, Image.FORMAT_L8)
	var trail := Image.create(size, size, false, Image.FORMAT_L8)
	var area := Rect2(_o - Vector2(4, 4), Vector2(World.CH + 8, World.CH + 8))
	# road polylines: points from this chunk and its neighbours
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var lst = w.road_pts.get(World.ckey(cx + ox, cy + oy))
			if lst == null or cx + ox < 0 or cy + oy < 0 or cx + ox >= World.NC or cy + oy >= World.NC: continue
			for e in lst:
				var k: int = e & 65535
				if k % 2 == 1: continue
				var pth: Dictionary = w.paths[e >> 16]
				var p: Vector2 = pth.pts[k]
				if not area.has_point(p): continue
				var wd: float = pth.w
				if pth.kind == "dirt":
					_disc(dirt, p, wd + 0.1, 255)
					continue
				_disc(side, p, wd + (0.6 if w.in_city(p.x, p.y) else 0.25), 255)
				_disc(road, p, wd, 128)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var lst = w.road_pts.get(World.ckey(cx + ox, cy + oy))
			if lst == null: continue
			for e in lst:
				var pth: Dictionary = w.paths[e >> 16]
				var k: int = e & 65535
				if pth.kind != "highway" and pth.kind != "interstate": continue
				if (k / 3) % 2 != 0: continue
				var p: Vector2 = pth.pts[k]
				if not area.has_point(p): continue
				if pth.kind == "interstate":
					var pts: PackedVector2Array = pth.pts
					var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized().orthogonal()
					for sgn in [-0.7, 0.7]:
						var q: Vector2 = p + dir * sgn
						_px(road, q, 255)
				else:
					_px(road, p, 255)
	# city grid streets and sidewalks are tile-aligned: stamp them per tile
	var x0 := int(_o.x)
	var y0 := int(_o.y)
	for y in range(y0, y0 + World.CH):
		for x in range(x0, x0 + World.CH):
			var t := w.T[y * World.N + x]
			if t == World.ROAD and w.road_d[y * World.NV + x] > 1.5 and w.road_d[y * World.NV + x + 1] > 1.5:
				var r := Rect2i((x - x0) * R, (y - y0) * R, R, R)
				road.fill_rect(r, Color8(128, 128, 128))
			elif t == World.SIDE:
				side.fill_rect(Rect2i((x - x0) * R, (y - y0) * R, R, R), Color8(255, 255, 255))
	var blds := []
	for b in near:
		blds.append_array(b.buildings)
	_footpaths(w, trail, blds, near)
	# keep building floors clean
	for b in blds:
		for c in b.cells:
			var r := Rect2i(int((c.x - _o.x) * R), int((c.y - _o.y) * R), R, R)
			road.fill_rect(_clip(r, size), Color.BLACK)
			side.fill_rect(_clip(r, size), Color.BLACK)
			dirt.fill_rect(_clip(r, size), Color.BLACK)
			trail.fill_rect(_clip(r, size), Color.BLACK)
	_shadows(w, shade, blds, near)
	return {
		"road": ImageTexture.create_from_image(road),
		"side": ImageTexture.create_from_image(side),
		"dirt": ImageTexture.create_from_image(dirt),
		"shade": ImageTexture.create_from_image(shade),
		"path": ImageTexture.create_from_image(trail),
	}

static func _clip(r: Rect2i, size: int) -> Rect2i:
	var q := r.intersection(Rect2i(0, 0, size, size))
	return q if q.size.x > 0 and q.size.y > 0 else Rect2i(0, 0, 0, 0)

static func _px(img: Image, p: Vector2, v: int) -> void:
	var x := int((p.x - _o.x) * R)
	var y := int((p.y - _o.y) * R)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, Color8(v, v, v))

static func _disc(img: Image, p: Vector2, rad: float, v: int) -> void:
	var cx := (p.x - _o.x) * R
	var cy := (p.y - _o.y) * R
	var rr := rad * R
	var col := Color8(v, v, v)
	var bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	for y in range(maxi(0, int(floor(cy - rr))), mini(img.get_height() - 1, int(ceil(cy + rr))) + 1):
		var dy := y + 0.5 - cy
		if absf(dy) > rr: continue
		var hw := sqrt(rr * rr - dy * dy)
		var x0 := int(round(cx - hw))
		var x1 := int(round(cx + hw))
		if x1 > x0:
			var rect := Rect2i(x0, y, x1 - x0, 1).intersection(bounds)
			if rect.size.x > 0 and rect.size.y > 0:
				img.fill_rect(rect, col)

## Worn foot trails: from each enterable building's door to the nearest road, and from settlement
## buildings to their campfire.
static func _footpaths(w: World, img: Image, blds: Array, near: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_o.x) * 7 + int(_o.y) * 13
	for b in blds:
		if b.sealed or b.open or b.door_seg == null: continue
		var start := Vector2(b.out) + Vector2(0.5, 0.5)
		var goal := Vector2(-1, -1)
		if b.settlement >= 0 and b.settlement < w.settlements.size():
			goal = w.settlements[b.settlement].pos
		else:
			var bd := 12.0
			for k in 24:
				var q := start + Vector2.from_angle(k * TAU / 24.0) * (1.5 + (k % 4) * 2.5)
				if w.is_road(q.x, q.y):
					var d := start.distance_to(q)
					if d < bd: bd = d; goal = q
		if goal.x < 0 or start.distance_to(goal) < 1.2: continue
		_trail(w, img, start, goal, rng)

static func _trail(w: World, img: Image, a: Vector2, b: Vector2, rng: RandomNumberGenerator) -> void:
	var L := a.distance_to(b)
	var dir := (b - a).normalized()
	var side := dir.orthogonal()
	var off := 0.0
	var steps := int(L / 0.2)
	for i in steps + 1:
		var t := float(i) / steps
		off = clampf(off * 0.9 + rng.randf_range(-0.12, 0.12), -0.6, 0.6)
		var p := a.lerp(b, t) + side * off * sin(t * PI)
		if w.building_at(p.x, p.y) != 0: continue
		_disc(img, p, 0.26 * (0.6 + 0.4 * sin(t * PI)), 255)

static func _stamp_sweep(img: Image, rect_tiles: Rect2, length: float, v: int) -> void:
	var steps := int(ceil(length / 0.125))
	var bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	for s in range(0, steps + 1):
		var o := SUN.normalized() * (s * 0.125)
		var r := Rect2i(int((rect_tiles.position.x - _o.x + o.x) * R), int((rect_tiles.position.y - _o.y + o.y) * R), int(rect_tiles.size.x * R), int(rect_tiles.size.y * R)).intersection(bounds)
		if r.size.x > 0 and r.size.y > 0:
			img.fill_rect(r, Color8(v, v, v))

static func _rect(img: Image, x: float, y: float, w: int, h: int, v: int) -> void:
	var r := Rect2i(int((x - _o.x) * R), int((y - _o.y) * R), w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, Color8(v, v, v))

static func _shadows(w: World, img: Image, blds: Array, near: Array) -> void:
	var area := Rect2(_o - Vector2(8, 8), Vector2(World.CH + 16, World.CH + 16))
	for b in blds:
		if b.open: continue
		for c in b.cells:
			var r := Rect2i(int((c.x - _o.x) * R) - 2, int((c.y - _o.y) * R) - 2, R + 4, R + 4).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
			if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, Color8(110, 110, 110))
	for b in blds:
		for c in b.cells:
			var fl: int = b.cells[c]
			var h: float = fl * World.FLOOR_H
			if b.roof == "pitched" and not b.ruined: h += 8.0
			if b.open:
				var o := SUN.normalized() * (h * SHADOW_K * 0.8)
				_rect(img, c.x + o.x, c.y + o.y, R, R, 200)
				continue
			if b.holes.has(c): h = World.FLOOR_H * 0.5
			_stamp_sweep(img, Rect2(c.x, c.y, 1, 1), h * SHADOW_K, 255)
	# trees: canopy blob lifted off the ground
	var o := SUN.normalized() * 1.3
	for y in range(int(_o.y) - 2, int(_o.y) + World.CH + 1):
		for x in range(int(_o.x) - 3, int(_o.x) + World.CH + 1):
			if not w.in_bounds(x, y) or w.T[y * World.N + x] != World.TREE: continue
			var cx := x + 0.5 + o.x
			var cy := y + 0.5 + o.y
			for k in [[-4, -2, 8, 4], [-3, -3, 6, 6], [-2, -4, 4, 8]]:
				_rect(img, cx + k[0] / float(R), cy + k[1] / float(R), k[2], k[3], 230)
			_rect(img, x + 0.5, y + 0.5 - 1.0 / R, int(o.x * R), 2, 200)
	for bk in near:
		for car in bk.cars:
			if not area.has_point(car.pos): continue
			var dir := Vector2.from_angle(car.ang)
			for t in range(-5, 6):
				var p: Vector2 = car.pos + dir * (t * 0.22) + SUN.normalized() * 0.25
				_rect(img, p.x - 0.5, p.y - 0.5, 8, 8, 220)
		for d in bk.decor:
			if not d.solid or not area.has_point(d.pos): continue
			var big: bool = d.name in ["watertower", "billboard_x", "billboard_y", "purifier_t3", "purifier_t2", "tower_decor"]
			var oo := SUN.normalized() * (2.4 if big else 0.25)
			var s := 10 if big else 3
			_rect(img, d.pos.x + oo.x - s / float(R), d.pos.y + oo.y - s * 0.5 / R, s * 2, s, 210)
