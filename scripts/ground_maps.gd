class_name GroundMaps
## Builds the textures the terrain shader samples by world position (8 texels per tile):
##   road  : asphalt (128) and dashed centre paint (255), smooth curves instead of tile steps
##   side  : sidewalks / shoulders
##   dirt  : dirt tracks
##   shade : cast shadows (255) and contact shadows at wall bases (110)
## Everything is stamped with Image.fill_rect so generation stays fast on phones.

const R := 8                       # texels per tile
const SUN := Vector2(1.0, -0.42)   # direction shadows fall in (world). Screen: down-right.
const SHADOW_K := 0.05             # tiles of shadow per logical pixel of height

static func build(w: World) -> Dictionary:
	var size := World.N * R
	var road := Image.create(size, size, false, Image.FORMAT_L8)
	var side := Image.create(size, size, false, Image.FORMAT_L8)
	var dirt := Image.create(size, size, false, Image.FORMAT_L8)
	var shade := Image.create(size, size, false, Image.FORMAT_L8)
	var trail := Image.create(size, size, false, Image.FORMAT_L8)
	for pth in w.paths:
		var pts: PackedVector2Array = pth.pts
		var wd: float = pth.w
		for i in range(0, pts.size(), 2):
			var p := pts[i]
			if pth.kind == "dirt":
				_disc(dirt, p, wd + 0.1, 255)
			else:
				_disc(side, p, wd + (0.6 if w.in_city(p.x, p.y) else 0.25), 255)
		if pth.kind == "dirt":
			continue
		for i in range(0, pts.size(), 2):
			_disc(road, pts[i], wd, 128)
		# dashed centre line on highways
		if pth.kind == "highway":
			for i in range(0, pts.size() - 1):
				if (i / 2) % 2 == 0:
					var p := pts[i]
					road.fill_rect(Rect2i(int(p.x * R), int(p.y * R), 1, 1), Color8(255, 255, 255))
	_footpaths(w, trail)
	# keep building floors clean
	for b in w.buildings:
		for c in b.cells:
			var r := Rect2i(c.x * R, c.y * R, R, R)
			road.fill_rect(r, Color.BLACK)
			side.fill_rect(r, Color.BLACK)
			dirt.fill_rect(r, Color.BLACK)
			trail.fill_rect(r, Color.BLACK)
	_shadows(w, shade)
	return {
		"road": ImageTexture.create_from_image(road),
		"side": ImageTexture.create_from_image(side),
		"dirt": ImageTexture.create_from_image(dirt),
		"shade": ImageTexture.create_from_image(shade),
		"path": ImageTexture.create_from_image(trail),
	}

static func _disc(img: Image, p: Vector2, rad: float, v: int) -> void:
	var cx := p.x * R
	var cy := p.y * R
	var rr := rad * R
	var col := Color8(v, v, v)
	for y in range(int(floor(cy - rr)), int(ceil(cy + rr)) + 1):
		var dy := y + 0.5 - cy
		if absf(dy) > rr: continue
		var hw := sqrt(rr * rr - dy * dy)
		var x0 := int(round(cx - hw))
		var x1 := int(round(cx + hw))
		if x1 > x0:
			var rect := Rect2i(x0, y, x1 - x0, 1).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
			if rect.size.x > 0 and rect.size.y > 0:
				img.fill_rect(rect, col)

## Worn foot trails: from each enterable building's door to the nearest road, and from settlement
## shacks to their campfire. A wobbly line of small discs; the shader roughens the edges.
static func _footpaths(w: World, img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var road_pts := PackedVector2Array()
	for pth in w.paths:
		var pts: PackedVector2Array = pth.pts
		for i in range(0, pts.size(), 3):
			road_pts.append(pts[i])
	for b in w.buildings:
		if b.sealed or b.open or b.door_seg == null: continue
		var start := Vector2(b.out) + Vector2(0.5, 0.5)
		var goal := Vector2(-1, -1)
		if b.settlement >= 0:
			goal = w.settlements[b.settlement].pos
		else:
			var bd := 14.0
			for q in road_pts:
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
		var r := Rect2i(int((rect_tiles.position.x + o.x) * R), int((rect_tiles.position.y + o.y) * R), int(rect_tiles.size.x * R), int(rect_tiles.size.y * R)).intersection(bounds)
		if r.size.x > 0 and r.size.y > 0:
			img.fill_rect(r, Color8(v, v, v))

static func _shadows(w: World, img: Image) -> void:
	var bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	# contact shadow around building footprints first, then the cast shadows over it
	for b in w.buildings:
		if b.open: continue
		for c in b.cells:
			var r := Rect2i(c.x * R - 2, c.y * R - 2, R + 4, R + 4).intersection(bounds)
			img.fill_rect(r, Color8(110, 110, 110))
	for b in w.buildings:
		for c in b.cells:
			var fl: int = b.cells[c]
			var h: float = fl * World.FLOOR_H
			if b.roof == "pitched" and not b.ruined: h += 8.0
			if b.open:
				# canopy: shadow of the roof slab only, offset from the ground
				var o := SUN.normalized() * (h * SHADOW_K * 0.8)
				var r := Rect2i(int((c.x + o.x) * R), int((c.y + o.y) * R), R, R).intersection(bounds)
				img.fill_rect(r, Color8(200, 200, 200))
				continue
			if b.holes.has(c): h = World.FLOOR_H * 0.5
			_stamp_sweep(img, Rect2(c.x, c.y, 1, 1), h * SHADOW_K, 255)
	# trees: canopy blob lifted off the ground
	for y in World.N:
		for x in World.N:
			if w.T[w.idx(x, y)] != World.TREE: continue
			var o := SUN.normalized() * 1.3
			var cx := (x + 0.5 + o.x) * R
			var cy := (y + 0.5 + o.y) * R
			for k in [[-4, -2, 8, 4], [-3, -3, 6, 6], [-2, -4, 4, 8]]:
				var r := Rect2i(int(cx + k[0]), int(cy + k[1]), k[2], k[3]).intersection(bounds)
				if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, Color8(230, 230, 230))
			var tr := Rect2i(int((x + 0.5) * R), int((y + 0.5) * R) - 1, int(o.x * R), 2).intersection(bounds)
			if tr.size.x > 0 and tr.size.y > 0: img.fill_rect(tr, Color8(200, 200, 200))
	# cars: a few squares along the body
	for car in w.cars:
		var dir := Vector2.from_angle(car.ang)
		for t in range(-5, 6):
			var p: Vector2 = car.pos + dir * (t * 0.22) + SUN.normalized() * 0.25
			var r := Rect2i(int(p.x * R) - 4, int(p.y * R) - 4, 8, 8).intersection(bounds)
			if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, Color8(220, 220, 220))
	# solid decor (signs, towers, barrels...) gets a small blob
	for d in w.decor:
		if not d.solid: continue
		var big: bool = d.name in ["watertower", "billboard_x", "billboard_y"]
		var o := SUN.normalized() * (2.4 if big else 0.25)
		var s := 10 if big else 3
		var r := Rect2i(int((d.pos.x + o.x) * R) - s, int((d.pos.y + o.y) * R) - s / 2, s * 2, s).intersection(bounds)
		if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, Color8(210, 210, 210))
