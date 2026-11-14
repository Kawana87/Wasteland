class_name World
extends RefCounted
## Map data + procedural generation + spatial queries (heights, walls, line of sight).
## World units are tiles. Screen projection lives in Iso.

const N := 64
const NV := N + 1
const CITY := 24
const FLOOR_H := 28.0          # height of one storey in pixels

const GRASS := 0
const ROAD := 1
const FLOOR := 2
const TREE := 5
const SIDE := 7
const STUMP := 8

class Seg:
	var a: Vector2
	var b: Vector2
	var axis: int        # 0 = runs along x (constant y), 1 = runs along y (constant x)
	var side: String     # n s w e i(nterior)
	var fl: int
	var window: bool
	var bid: int

class Bld:
	var id: int
	var x0: int
	var y0: int
	var w: int
	var h: int
	var h0: float
	var floors := 1
	var pal := 0
	var fkind := 0
	var raider := false
	var out := Vector2i()
	var stairs := Vector2i(-1, -1)
	var segs: Array = []
	func inside(x: float, y: float) -> bool:
		return x > x0 and x < x0 + w and y > y0 and y < y0 + h

class Crate:
	var pos: Vector2
	var kind: String     # crate, cache, car, bag
	var open := false
	var bid := 0
	var fl := 0

class Car:
	var pos: Vector2
	var axis: String
	var spr: String

class Rope:
	var top: Vector2
	var bottom: Vector2

class RaiderCamp:
	var pos: Vector2
	var ang: float
	var bid := 0
	var cleared := false

var rng := RandomNumberGenerator.new()
var seed_value := 0
var T := PackedByteArray()
var BID := PackedInt32Array()
var V := PackedByteArray()
var G := PackedByteArray()
var CL := PackedByteArray()
var VH := PackedFloat32Array()
var buildings: Array = []
var crates: Array = []
var cars: Array = []
var ropes: Array = []
var posts: Array = []            # Vector2 positions of raider fence posts
var raider_flags: Array = []
var rcamps: Array = []
var spawns: Array = []           # enemy spawn dictionaries
var survivors: Array = []        # survivor spawn dictionaries
var seg_grid := {}               # tile index -> Array[Seg]
var road_x: Array = []
var road_y: Array = []
var start := Vector2(10.5, 10.5)

func idx(x: int, y: int) -> int:
	return y * N + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N

func vh(x: int, y: int) -> float:
	return VH[clampi(y, 0, N) * NV + clampi(x, 0, N)]

func set_vh(x: int, y: int, h: float) -> void:
	if x < 0 or y < 0 or x > N or y > N:
		return
	VH[y * NV + x] = h

## Ground height (pixels) at a world position, bilinear between corner heights.
func hz(wx: float, wy: float) -> float:
	wx = clampf(wx, 0.0, N - 0.001)
	wy = clampf(wy, 0.0, N - 0.001)
	var x0 := int(floor(wx))
	var y0 := int(floor(wy))
	var fx := wx - x0
	var fy := wy - y0
	return lerpf(lerpf(vh(x0, y0), vh(x0 + 1, y0), fx), lerpf(vh(x0, y0 + 1), vh(x0 + 1, y0 + 1), fx), fy)

func tile(x: float, y: float) -> int:
	var tx := int(floor(x))
	var ty := int(floor(y))
	if not in_bounds(tx, ty):
		return GRASS
	return T[idx(tx, ty)]

func building_at(x: float, y: float) -> int:
	var tx := int(floor(x))
	var ty := int(floor(y))
	if not in_bounds(tx, ty):
		return 0
	return BID[idx(tx, ty)]

func bld(id: int) -> Bld:
	return buildings[id - 1] if id > 0 else null

## Height (pixels) an entity stands at, given its floor.
func stand_z(x: float, y: float, fl: int) -> float:
	if fl > 0:
		var id := building_at(x, y)
		if id > 0:
			return buildings[id - 1].h0 + FLOOR_H * fl
	var id0 := building_at(x, y)
	if id0 > 0:
		return buildings[id0 - 1].h0
	return hz(x, y)

func in_city(x: float, y: float) -> bool:
	return x >= CITY and y >= CITY

# ------------------------------------------------------------------ collision
static func seg_dist(p: Vector2, s: Seg) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, s.a, s.b))

func wall_hit(p: Vector2, r: float, fl: int) -> bool:
	var tx := int(floor(p.x))
	var ty := int(floor(p.y))
	for yy in range(ty - 1, ty + 2):
		for xx in range(tx - 1, tx + 2):
			var lst = seg_grid.get(yy * N + xx)
			if lst == null:
				continue
			for s in lst:
				if s.fl == fl and seg_dist(p, s) < r + 0.06:
					return true
	return false

func tree_hit(p: Vector2, r: float) -> bool:
	var tx := int(floor(p.x))
	var ty := int(floor(p.y))
	for yy in range(ty - 1, ty + 2):
		for xx in range(tx - 1, tx + 2):
			if not in_bounds(xx, yy) or T[idx(xx, yy)] != TREE:
				continue
			if p.distance_to(Vector2(xx + 0.5, yy + 0.5)) < r + 0.2:
				return true
	return false

func car_hit(p: Vector2, r: float) -> bool:
	for c in cars:
		var hx_ := 1.2 if c.axis == "x" else 0.42
		var hy_ := 0.42 if c.axis == "x" else 1.2
		if absf(p.x - c.pos.x) < hx_ + r and absf(p.y - c.pos.y) < hy_ + r:
			return true
	return false

func can_stand(p: Vector2, r: float, fl: int) -> bool:
	if p.x < 0.5 or p.y < 0.5 or p.x > N - 0.5 or p.y > N - 0.5:
		return false
	if wall_hit(p, r, fl):
		return false
	if fl > 0:
		return building_at(p.x, p.y) > 0
	return not tree_hit(p, r) and not car_hit(p, r)

## Can you walk from a to b? Uphill steeper than 26 px/tile is a cliff (jumping adds a little lift).
func slope_ok(a: Vector2, b: Vector2, fl: int, lift: float = 0.0) -> bool:
	if fl > 0:
		return true
	var dh := stand_z(b.x, b.y, 0) - stand_z(a.x, a.y, 0)
	if dh <= 0.0:
		return true
	if lift > 0.0 and dh <= lift + 4.0:
		return true
	return dh / maxf(a.distance_to(b), 0.0001) < 26.0

func blocks_shot(p: Vector2, z: float, fl: int) -> bool:
	if wall_hit(p, 0.0, fl):
		return true
	if fl == 0:
		if tree_hit(p, 0.02) or car_hit(p, -0.1):
			return true
		if building_at(p.x, p.y) == 0 and hz(p.x, p.y) > z:
			return true
	return false

func los(a: Vector2, b: Vector2, fl: int) -> bool:
	var za := stand_z(a.x, a.y, fl) + 10.0
	var zb := stand_z(b.x, b.y, fl) + 10.0
	var d := a.distance_to(b)
	var n := int(ceil(d / 0.2))
	for i in range(1, n):
		var t := float(i) / n
		if blocks_shot(a.lerp(b, t), lerpf(za, zb, t) + 2.0, fl):
			return false
	return true

func near_road(x: int, y: int, r: int) -> bool:
	for yy in range(y - r, y + r + 1):
		for xx in range(x - r, x + r + 1):
			if in_bounds(xx, yy) and T[idx(xx, yy)] == ROAD:
				return true
	return false

# ------------------------------------------------------------------ generation
func ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

static func sstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func generate(sd: int) -> void:
	seed_value = sd
	rng.seed = sd
	T.resize(N * N); T.fill(GRASS)
	BID.resize(N * N); BID.fill(0)
	V.resize(N * N)
	G.resize(N * N); G.fill(0)
	CL.resize(N * N); CL.fill(0)
	VH.resize(NV * NV); VH.fill(0.0)
	for i in N * N:
		V[i] = rng.randi_range(0, 3)
	buildings.clear(); crates.clear(); cars.clear(); ropes.clear(); posts.clear()
	raider_flags.clear(); rcamps.clear(); spawns.clear(); survivors.clear(); seg_grid.clear()
	road_x = [34 + ri(-1, 1), 50 + ri(-1, 1)]
	road_y = [34 + ri(-1, 1), 50 + ri(-1, 1)]
	for y in N:
		for x in N:
			var on_x := false
			for r in road_x:
				if x == r or x == r + 1: on_x = true
			var on_y := false
			for r in road_y:
				if y == r or y == r + 1: on_y = true
			if on_x or on_y:
				T[idx(x, y)] = ROAD
	_heights()
	# start camp clearing
	var sh := hz(start.x, start.y)
	for y in range(5, 17):
		for x in range(5, 17):
			var d := Vector2(x, y).distance_to(start)
			var t := sstep(1.0 - (d - 3.0) / 2.5)
			set_vh(x, y, lerpf(vh(x, y), sh, t))
			if in_bounds(x, y) and d < 4.5:
				CL[idx(x, y)] = 1
	# sidewalks in the city
	for y in range(1, N - 1):
		for x in range(1, N - 1):
			if T[idx(x, y)] != GRASS or not in_city(x, y):
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if T[idx(x + o.x, y + o.y)] == ROAD:
					T[idx(x, y)] = SIDE
					break
	# raider camps on plateaus
	var tries := 0
	while rcamps.size() < 2 and tries < 1500:
		tries += 1
		var x := ri(6, N - 7)
		var y := ri(6, N - 7)
		if min(x, y) > CITY - 6: continue
		if Vector2(x, y).distance_to(start) < 17: continue
		var close := false
		for c in rcamps:
			if Vector2(x, y).distance_to(c.pos) < 13: close = true
		if close or near_road(x, y, 5): continue
		_raider_camp(Vector2(x + 0.5, y + 0.5))
	# city blocks + outskirts houses
	var ivx := [[CITY, road_x[0] - 2], [road_x[0] + 3, road_x[1] - 2], [road_x[1] + 3, N - 3]]
	var ivy := [[CITY, road_y[0] - 2], [road_y[0] + 3, road_y[1] - 2], [road_y[1] + 3, N - 3]]
	for ix in ivx:
		for iy in ivy:
			for k in 12:
				var w := ri(4, 8)
				var h := ri(4, 7)
				if ix[1] - ix[0] + 1 < w or iy[1] - iy[0] + 1 < h: continue
				place_building(ri(ix[0], ix[1] - w + 1), ri(iy[0], iy[1] - h + 1), w, h)
	for k in 45:
		var w := ri(4, 6)
		var h := ri(4, 6)
		if rng.randf() < 0.5:
			place_building(ri(2, 16), ri(18, 56), w, h)
		else:
			place_building(ri(18, 56), ri(2, 16), w, h)
	# trees
	for y in N:
		for x in N:
			var i := idx(x, y)
			if T[i] != GRASS or CL[i] == 1: continue
			if rng.randf() < (0.03 if in_city(x, y) else 0.15):
				T[i] = TREE
	# cars, oriented with their road
	for y in N:
		for x in N:
			if T[idx(x, y)] != ROAD or rng.randf() > 0.02: continue
			if Vector2(x, y).distance_to(start) < 8: continue
			var horiz: bool = (y == road_y[0] or y == road_y[0] + 1 or y == road_y[1] or y == road_y[1] + 1)
			var vert: bool = (x == road_x[0] or x == road_x[0] + 1 or x == road_x[1] or x == road_x[1] + 1)
			if horiz and vert: continue
			var c := Car.new()
			c.pos = Vector2(x + 0.5, y + 0.5)
			c.axis = "x" if horiz else "y"
			c.spr = ["teal", "red", "yellow", "burned"][ri(0, 3)]
			var clash := false
			for o in cars:
				if o.pos.distance_to(c.pos) < 3.2: clash = true
			if clash: continue
			cars.append(c)
			var cr := Crate.new()
			cr.pos = c.pos + (Vector2(-1.45, 0.62) if c.axis == "x" else Vector2(0.62, -1.45))
			cr.kind = "car"
			crates.append(cr)
	# keep doors clear of trees and wrecks
	for b in buildings:
		for yy in range(b.out.y - 2, b.out.y + 3):
			for xx in range(b.out.x - 2, b.out.x + 3):
				if in_bounds(xx, yy) and T[idx(xx, yy)] == TREE:
					T[idx(xx, yy)] = GRASS
		var door := Vector2(b.out.x + 0.5, b.out.y + 0.5)
		for k in range(cars.size() - 1, -1, -1):
			if cars[k].pos.distance_to(door) < 1.8:
				var cp: Vector2 = cars[k].pos
				cars.remove_at(k)
				for q in range(crates.size() - 1, -1, -1):
					if crates[q].kind == "car" and crates[q].pos.distance_to(cp) < 2.0:
						crates.remove_at(q)
	# ground variety
	var so := rng.randf() * 100.0
	for y in N:
		for x in N:
			var n := sin(x * 0.37 + so) + sin(y * 0.29 - so * 0.7) + sin((x + y) * 0.17 + so * 0.3)
			var i := idx(x, y)
			G[i] = 1 if n > 1.25 else (2 if n < -1.35 else 0)
			if T[i] == ROAD:
				var r := rng.randf()
				G[i] = 2 if r < 0.035 else (1 if r < 0.2 else 0)
			if T[i] == SIDE:
				G[i] = 1 if rng.randf() < 0.18 else 0
			if T[i] == GRASS and G[i] == 0 and rng.randf() < 0.12:
				G[i] = 3
			if T[i] == GRASS and near_road(x, y, 1) and rng.randf() < 0.6:
				G[i] = 4
	# mutant hound packs + a roaming raider patrol
	for p in 3:
		add_pack(3, start, 16.0, [])
	add_patrol()
	# survivors holed up in city buildings
	var cand := []
	for b in buildings:
		if not b.raider and b.w >= 5 and b.h >= 5 and in_city(b.x0, b.y0):
			cand.append(b)
	cand.shuffle()
	var names := ["Mara", "Dez", "Jun", "Otis", "Rosa", "Hank", "Priya", "Theo", "Wren", "Gus"]
	names.shuffle()
	for k in min(3, cand.size()):
		var b: Bld = cand[k]
		survivors.append({"pos": Vector2(b.x0 + 1.5 + ri(0, b.w - 3), b.y0 + 1.5 + ri(0, b.h - 3)), "name": names[k], "bid": b.id})

func _heights() -> void:
	var s1 := rng.randf() * 10.0
	var s2 := rng.randf() * 10.0
	var s3 := rng.randf() * 10.0
	for y in NV:
		for x in NV:
			var h := 14.0 * (sin(x * 0.19 + s1) + sin(y * 0.23 + s2)) + 9.0 * sin((x + y) * 0.13 + s3) + 10.0 * sin((x - y) * 0.17 + s1 * 2.0) + 10.0
			h = maxf(0.0, h) * sstep((CITY - min(x, y)) / 7.0)
			var rd := 99.0
			for r in road_x: rd = minf(rd, absf(x - r - 1))
			for r in road_y: rd = minf(rd, absf(y - r - 1))
			h *= 0.35 + 0.65 * sstep((rd - 1.0) / 4.0)
			VH[y * NV + x] = h
	for _it in 2:
		var C := VH.duplicate()
		for y in range(1, N):
			for x in range(1, N):
				VH[y * NV + x] = (C[y * NV + x] * 4.0 + C[y * NV + x - 1] + C[y * NV + x + 1] + C[(y - 1) * NV + x] + C[(y + 1) * NV + x]) / 8.0

func add_pack(n: int, avoid: Vector2, min_d: float, camps: Array) -> void:
	for t in 200:
		var x := ri(3, N - 4)
		var y := ri(3, N - 4)
		var i := idx(x, y)
		if in_city(x, y) or CL[i] == 1 or T[i] != GRASS: continue
		if Vector2(x, y).distance_to(avoid) < min_d: continue
		var near_camp := false
		for c in camps:
			if Vector2(x, y).distance_to(c) < 12.0: near_camp = true
		if near_camp: continue
		for k in n:
			spawns.append({"type": "hound", "pos": Vector2(x + 0.5 + rf(-1, 1), y + 0.5 + rf(-1, 1)), "home": Vector2(x + 0.5, y + 0.5), "home_r": 5.0})
		return

func road_point() -> Vector2:
	for t in 300:
		var x := ri(2, N - 3)
		var y := ri(2, N - 3)
		if T[idx(x, y)] == ROAD:
			return Vector2(x + 0.5, y + 0.5)
	return Vector2(30, 30)

func add_patrol() -> void:
	var wps := [road_point(), road_point(), road_point(), road_point()]
	for k in 2:
		spawns.append({"type": "raider", "pos": wps[0] + Vector2(k * 0.6, 0), "patrol": wps})

func _raider_camp(c: Vector2) -> void:
	var base := hz(c.x, c.y)
	var rise := 34.0
	var ang := rng.randf() * TAU
	var top := base + rise
	for vy in range(int(c.y - 10), int(c.y + 11)):
		for vx in range(int(c.x - 10), int(c.x + 11)):
			var d := Vector2(vx, vy).distance_to(c)
			if d > 9.5: continue
			var a := atan2(vy - c.y, vx - c.x)
			var da := absf(angle_difference(a, ang))
			var t := clampf((4.4 - d) / 0.8, 0.0, 1.0)
			if da < 0.42 and d > 3.2:
				t = maxf(t, sstep(1.0 - (d - 3.2) / 5.8))
			set_vh(vx, vy, lerpf(vh(vx, vy), top, t))
	for y in range(int(c.y - 6), int(c.y + 7)):
		for x in range(int(c.x - 6), int(c.x + 7)):
			if in_bounds(x, y) and Vector2(x + 0.5, y + 0.5).distance_to(c) < 5.2:
				CL[idx(x, y)] = 1
	var rc := RaiderCamp.new()
	rc.pos = c
	rc.ang = ang
	var b := place_building(int(round(c.x - 2)), int(round(c.y - 2)), 4, 4, true)
	if b: rc.bid = b.id
	rcamps.append(rc)
	for k in 3:
		var a := ang + 1.4 + k * 1.6
		spawns.append({"type": "raider", "pos": c + Vector2(cos(a), sin(a)) * 3.0, "home": c, "home_r": 2.6, "camp": rcamps.size() - 1})
	for k in 2:
		var a := ang + 2.2 + k * 2.4
		var cr := Crate.new()
		cr.pos = c + Vector2(cos(a), sin(a)) * 3.0
		cr.kind = "cache"
		crates.append(cr)
	var rope_a := ang + PI
	var a2 := 0.0
	while a2 < TAU:
		if absf(angle_difference(a2, ang)) > 0.5 and absf(angle_difference(a2, rope_a)) > 0.3:
			posts.append(c + Vector2(cos(a2), sin(a2)) * 3.5)
		a2 += 0.36
	raider_flags.append(c + Vector2(cos(ang + 1.1), sin(ang + 1.1)) * 3.2)
	var rope := Rope.new()
	rope.top = c + Vector2(cos(rope_a), sin(rope_a)) * 3.85
	rope.bottom = c + Vector2(cos(rope_a), sin(rope_a)) * 5.7
	ropes.append(rope)

func _add_seg(b: Bld, a: Vector2, bb: Vector2, axis: int, side: String, fl: int, window: bool) -> void:
	var s := Seg.new()
	s.a = a; s.b = bb; s.axis = axis; s.side = side; s.fl = fl; s.window = window; s.bid = b.id
	b.segs.append(s)
	var tiles := []
	if axis == 0:
		tiles = [Vector2i(int(a.x), int(a.y) - 1), Vector2i(int(a.x), int(a.y))]
	else:
		tiles = [Vector2i(int(a.x) - 1, int(a.y)), Vector2i(int(a.x), int(a.y))]
	for t in tiles:
		if not in_bounds(t.x, t.y): continue
		var k: int = t.y * N + t.x
		if not seg_grid.has(k): seg_grid[k] = []
		seg_grid[k].append(s)

func place_building(x0: int, y0: int, w: int, h: int, raider: bool = false) -> Bld:
	if x0 < 2 or y0 < 2 or x0 + w >= N - 2 or y0 + h >= N - 2:
		return null
	for y in range(y0 - 1, y0 + h + 1):
		for x in range(x0 - 1, x0 + w + 1):
			var i := idx(x, y)
			var inside := x >= x0 and x < x0 + w and y >= y0 and y < y0 + h
			if inside and (T[i] != GRASS or (CL[i] == 1 and not raider)): return null
			if not inside and (T[i] == FLOOR or BID[i] != 0): return null
	var mn := 1e9
	var mx := -1e9
	var sum := 0.0
	var n := 0
	for y in range(y0, y0 + h + 1):
		for x in range(x0, x0 + w + 1):
			var v := vh(x, y)
			mn = minf(mn, v); mx = maxf(mx, v); sum += v; n += 1
	if mx - mn > (60.0 if raider else 18.0):
		return null
	var h0 := vh(int(round(x0 + w / 2.0)), int(round(y0 + h / 2.0))) if raider else sum / n
	for y in range(y0 - 1, y0 + h + 2):
		for x in range(x0 - 1, x0 + w + 2):
			var inner := x >= x0 and x <= x0 + w and y >= y0 and y <= y0 + h
			set_vh(x, y, h0 if inner else (vh(x, y) + h0) * 0.5)
	var b := Bld.new()
	b.id = buildings.size() + 1
	b.x0 = x0; b.y0 = y0; b.w = w; b.h = h; b.h0 = h0; b.raider = raider
	b.pal = 1 if raider else ri(0, 3)
	b.fkind = 3 if raider else ri(0, 3)
	b.floors = 2 if (not raider and w >= 5 and h >= 5 and rng.randf() < 0.5) else 1
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			T[idx(x, y)] = FLOOR
			BID[idx(x, y)] = b.id
	# door: one gap in the ground-floor outer wall
	var side := ri(0, 3)
	var door := Vector2i()
	if side == 0: door = Vector2i(x0 + ri(1, w - 2), y0)             # north edge
	elif side == 1: door = Vector2i(x0 + ri(1, w - 2), y0 + h)       # south edge
	elif side == 2: door = Vector2i(x0, y0 + ri(1, h - 2))           # west edge
	else: door = Vector2i(x0 + w, y0 + ri(1, h - 2))                 # east edge
	b.out = Vector2i(door.x, door.y - 1) if side == 0 else (Vector2i(door.x, door.y) if side == 1 else (Vector2i(door.x - 1, door.y) if side == 2 else Vector2i(door.x, door.y)))
	var iw := -1
	if w >= 5:
		iw = x0 + ri(2, w - 2)
	for fl in b.floors:
		for x in range(x0, x0 + w):
			if not (fl == 0 and side == 0 and x == door.x):
				_add_seg(b, Vector2(x, y0), Vector2(x + 1, y0), 0, "n", fl, rng.randf() < 0.3)
			if not (fl == 0 and side == 1 and x == door.x):
				_add_seg(b, Vector2(x, y0 + h), Vector2(x + 1, y0 + h), 0, "s", fl, rng.randf() < 0.3)
		for y in range(y0, y0 + h):
			if not (fl == 0 and side == 2 and y == door.y):
				_add_seg(b, Vector2(x0, y), Vector2(x0, y + 1), 1, "w", fl, rng.randf() < 0.3)
			if not (fl == 0 and side == 3 and y == door.y):
				_add_seg(b, Vector2(x0 + w, y), Vector2(x0 + w, y + 1), 1, "e", fl, rng.randf() < 0.3)
		if iw > 0:
			var gap := y0 + ri(0, h - 1)
			for y in range(y0, y0 + h):
				if y != gap and not (side >= 2 and y == door.y and absi(iw - door.x) <= 1):
					_add_seg(b, Vector2(iw, y), Vector2(iw, y + 1), 1, "i", fl, false)
	if b.floors == 2:
		for t in 20:
			var sx := ri(x0, x0 + w - 1)
			var sy := ri(y0, y0 + h - 1)
			if Vector2(sx + 0.5, sy + 0.5).distance_to(Vector2(b.out) + Vector2(0.5, 0.5)) < 2.0: continue
			if sx == iw or sx == iw - 1: continue
			b.stairs = Vector2i(sx, sy)
			break
		if b.stairs.x < 0:
			b.floors = 1
			var keep := []
			for s in b.segs:
				if s.fl == 0: keep.append(s)
			b.segs = keep
	buildings.append(b)
	# loot and vermin on each floor
	for fl in b.floors:
		var nc := ri(1, 3 if raider else 2)
		for k in nc:
			var tx := ri(x0, x0 + w - 1)
			var ty := ri(y0, y0 + h - 1)
			if Vector2i(tx, ty) == b.stairs or Vector2i(tx, ty) == b.out: continue
			var cr := Crate.new()
			cr.pos = Vector2(tx + 0.5, ty + 0.5)
			cr.kind = "cache" if raider else "crate"
			cr.bid = b.id
			cr.fl = fl
			crates.append(cr)
		if not raider and rng.randf() < 0.45:
			spawns.append({"type": "rat", "pos": Vector2(rf(x0 + 0.6, x0 + w - 0.6), rf(y0 + 0.6, y0 + h - 0.6)), "fl": fl, "home_r": 2.0})
	return b
