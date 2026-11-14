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
const DIRT_ROAD := 9

class Seg:
	var a: Vector2
	var b: Vector2
	var axis: int        # 0 = runs along x (constant y), 1 = runs along y (constant x)
	var side: String     # n s w e i(nterior)
	var fl: int
	var window: bool
	var bid: int
	var mode := "plain"     # plain, win, broken, boarded, cracked, stub
	var solid := true

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
	var kind := "house"      # house, shop, office, garage, shack, den
	var ruined := false
	var holes := {}          # Vector2i -> true: no upper floor / no roof here
	var furn: Array = []
	var roof := "flat"       # flat, pitched, tin
	var settlement := -1
	var door_in := Vector2i()
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
	var k := 0               # facing, in 45 degree steps of world angle
	var ang := 0.0
	var spr: String

class Furn:
	var pos: Vector2
	var half: Vector2
	var name: String
	var orient: String
	var bid := 0
	var fl := 0
	var h := 10.0
	var crate: Crate = null

class Decor:
	var name: String
	var pos: Vector2
	var solid := false
	var half := Vector2(0.2, 0.2)
	var flat := false
	var bid := 0

class Settlement:
	var name: String
	var pos: Vector2
	var radius := 7.0
	var trader := Vector2.ZERO

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
var decor: Array = []
var decor_grid := {}             # tile index -> Array[Decor] (solid ones only)
var settlements: Array = []
var paths: Array = []            # {pts: PackedVector2Array, w: float, kind: String}
var pole_lines: Array = []       # Array of PackedVector2Array (power poles along highways)
var critters: Array = []         # {type, pos, home}
var road_d := PackedFloat32Array()
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
				if s.solid and s.fl == fl and seg_dist(p, s) < r + 0.06:
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
		var d: Vector2 = (p - c.pos).rotated(-c.ang)
		if absf(d.x) < 1.2 + r and absf(d.y) < 0.42 + r:
			return true
	return false

func furn_hit(p: Vector2, r: float, fl: int, tall_only: bool = false) -> bool:
	var id := building_at(p.x, p.y)
	if id == 0:
		return false
	for f in buildings[id - 1].furn:
		if f.fl != fl or (tall_only and f.h < 12.0):
			continue
		if absf(p.x - f.pos.x) < f.half.x + r and absf(p.y - f.pos.y) < f.half.y + r:
			return true
	return false

func decor_hit(p: Vector2, r: float) -> bool:
	var tx := int(floor(p.x))
	var ty := int(floor(p.y))
	for yy in range(ty - 1, ty + 2):
		for xx in range(tx - 1, tx + 2):
			var lst = decor_grid.get(yy * N + xx)
			if lst == null:
				continue
			for d in lst:
				if absf(p.x - d.pos.x) < d.half.x + r and absf(p.y - d.pos.y) < d.half.y + r:
					return true
	return false

func can_stand(p: Vector2, r: float, fl: int) -> bool:
	if p.x < 0.5 or p.y < 0.5 or p.x > N - 0.5 or p.y > N - 0.5:
		return false
	if wall_hit(p, r, fl):
		return false
	if furn_hit(p, r, fl):
		return false
	if fl > 0:
		var id := building_at(p.x, p.y)
		if id == 0:
			return false
		return not buildings[id - 1].holes.has(Vector2i(int(floor(p.x)), int(floor(p.y))))
	return not tree_hit(p, r) and not car_hit(p, r) and not decor_hit(p, r)

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
	if furn_hit(p, 0.0, fl, true):
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

func is_road(x: float, y: float) -> bool:
	var t := tile(x, y)
	return t == ROAD or t == DIRT_ROAD

func settlement_at(p: Vector2, extra: float = 0.0) -> int:
	for i in settlements.size():
		if p.distance_to(settlements[i].pos) < settlements[i].radius + extra:
			return i
	return -1

# ------------------------------------------------------------------ generation
func ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)

static func sstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

const SETTLEMENT_NAMES := ["Rustwater", "Tin Hollow", "Saltgrass", "Haven Flats", "Cinder Creek", "Last Light"]
const TEMPLATES := {
	"kitchen": {"north": ["counter", "stove", "counter", "fridge"], "west": ["counter"], "center": ["table"]},
	"living": {"north": ["bookshelf", "tv", "armchair"], "west": ["couch"], "center": []},
	"bedroom": {"north": ["bed", "dresser"], "west": ["dresser"], "center": []},
	"office": {"north": ["filing", "bookshelf", "filing"], "west": ["filing"], "center": ["desk"]},
	"shop": {"north": ["shopshelf", "shopshelf", "shopshelf"], "west": ["shopshelf"], "center": ["shopcounter"]},
	"garage": {"north": ["workbench", "barrel", "barrel"], "west": ["shopshelf"], "center": []},
	"shack": {"north": ["mattress", "barrel"], "west": ["workbench"], "center": []},
	"den": {"north": ["mattress", "barrel", "mattress"], "west": ["mattress"], "center": []},
}
const FURN_SIZE := {   # long side, depth, height (px)
	"counter": [1.0, 0.5, 12], "stove": [0.5, 0.5, 12], "fridge": [0.5, 0.5, 28], "table": [0.9, 0.6, 10],
	"chair": [0.3, 0.3, 6], "couch": [1.0, 0.45, 8], "armchair": [0.45, 0.45, 8], "tv": [0.4, 0.3, 12],
	"bookshelf": [0.9, 0.3, 26], "bed": [1.0, 0.6, 7], "dresser": [0.6, 0.35, 14], "desk": [0.8, 0.45, 11],
	"filing": [0.35, 0.35, 16], "shopshelf": [1.0, 0.35, 20], "shopcounter": [1.0, 0.4, 12],
	"workbench": [0.9, 0.4, 11], "barrel": [0.35, 0.35, 12], "mattress": [0.9, 0.55, 3],
}
const CONTAINER_CHANCE := {"fridge": 0.9, "dresser": 0.9, "desk": 0.9, "filing": 0.8, "shopshelf": 0.6,
	"shopcounter": 1.0, "workbench": 0.9, "bookshelf": 0.4, "counter": 0.35, "barrel": 0.3, "mattress": 0.2}

func generate(sd: int) -> void:
	seed_value = sd
	rng.seed = sd
	T.resize(N * N); T.fill(GRASS)
	BID.resize(N * N); BID.fill(0)
	V.resize(N * N)
	G.resize(N * N); G.fill(0)
	CL.resize(N * N); CL.fill(0)
	VH.resize(NV * NV); VH.fill(0.0)
	road_d.resize(NV * NV); road_d.fill(99.0)
	for i in N * N:
		V[i] = rng.randi_range(0, 3)
	for a in [buildings, crates, cars, ropes, posts, raider_flags, rcamps, spawns, survivors, decor, settlements, paths, pole_lines, critters]:
		a.clear()
	seg_grid.clear(); decor_grid.clear()
	_roads()
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
	# sidewalks along city roads
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
	while rcamps.size() < 2 and tries < 2000:
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
	# friendly settlements
	tries = 0
	var names := SETTLEMENT_NAMES.duplicate()
	names.shuffle()
	while settlements.size() < 2 and tries < 2000:
		tries += 1
		var x := ri(7, N - 8)
		var y := ri(7, N - 8)
		if in_city(x, y) and rng.randf() < 0.7: continue
		var c := Vector2(x + 0.5, y + 0.5)
		if c.distance_to(start) < 13: continue
		var bad := false
		for r in rcamps:
			if c.distance_to(r.pos) < 15: bad = true
		for s in settlements:
			if c.distance_to(s.pos) < 16: bad = true
		if bad: continue
		var hs := []
		for o in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4), Vector2.ZERO]:
			hs.append(hz(c.x + o.x, c.y + o.y))
		if hs.max() - hs.min() > 22.0: continue
		_settlement(c, names[settlements.size()])
	# city buildings, placed between the winding streets
	for k in 320:
		var w := ri(4, 8)
		var h := ri(4, 7)
		place_building(ri(CITY, N - 3 - w), ri(CITY, N - 3 - h), w, h)
	# outskirts houses and garages
	for k in 60:
		var w := ri(4, 6)
		var h := ri(4, 6)
		if rng.randf() < 0.5:
			place_building(ri(2, 18), ri(18, 58), w, h)
		else:
			place_building(ri(18, 58), ri(2, 18), w, h)
	# trees
	for y in N:
		for x in N:
			var i := idx(x, y)
			if T[i] != GRASS or CL[i] == 1: continue
			if rng.randf() < (0.03 if in_city(x, y) else 0.13):
				T[i] = TREE
	_cars()
	# keep doors clear of trees and wrecks
	for b in buildings:
		for yy in range(b.out.y - 2, b.out.y + 3):
			for xx in range(b.out.x - 2, b.out.x + 3):
				if in_bounds(xx, yy) and T[idx(xx, yy)] == TREE:
					T[idx(xx, yy)] = GRASS
		var door := Vector2(b.out.x + 0.5, b.out.y + 0.5)
		for k in range(cars.size() - 1, -1, -1):
			if cars[k].pos.distance_to(door) < 2.0:
				var cp: Vector2 = cars[k].pos
				cars.remove_at(k)
				for q in range(crates.size() - 1, -1, -1):
					if crates[q].kind == "car" and crates[q].pos.distance_to(cp) < 2.2:
						crates.remove_at(q)
	# ground variety
	var so := rng.randf() * 100.0
	for y in N:
		for x in N:
			var n := sin(x * 0.37 + so) + sin(y * 0.29 - so * 0.7) + sin((x + y) * 0.17 + so * 0.3)
			var i := idx(x, y)
			G[i] = 1 if n > 1.0 else (2 if n < -1.35 else 0)
			if T[i] == ROAD:
				var r := rng.randf()
				G[i] = 2 if r < 0.04 else (1 if r < 0.3 else 0)
			if T[i] == SIDE:
				G[i] = 1 if rng.randf() < 0.25 else 0
			if T[i] == GRASS and G[i] == 0 and rng.randf() < 0.12:
				G[i] = 3
			if T[i] == GRASS and near_road(x, y, 1) and rng.randf() < 0.5:
				G[i] = 4
	_debris()
	_creatures()
	# survivors holed up in city buildings
	var cand := []
	for b in buildings:
		if b.kind != "den" and b.kind != "shack" and b.w >= 5 and b.h >= 5 and in_city(b.x0, b.y0):
			cand.append(b)
	cand.shuffle()
	var sn := ["Mara", "Dez", "Jun", "Otis", "Rosa", "Hank", "Priya", "Theo", "Wren", "Gus"]
	sn.shuffle()
	for k in min(3, cand.size()):
		var b: Bld = cand[k]
		for t in 20:
			var p := Vector2(b.x0 + 1.5 + ri(0, b.w - 3), b.y0 + 1.5 + ri(0, b.h - 3))
			if can_stand(p, 0.28, 0):
				survivors.append({"pos": p, "name": sn[k], "bid": b.id})
				break

# ------------------------------------------------------------------ roads
static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _path(ctrl: Array, w: float, kind: String) -> void:
	var c := [ctrl[0]] + ctrl + [ctrl[-1]]
	var pts := PackedVector2Array()
	for i in range(1, c.size() - 2):
		var n := maxi(2, int(c[i].distance_to(c[i + 1]) * 4.0))
		for k in n:
			pts.append(_catmull(c[i - 1], c[i], c[i + 1], c[i + 2], float(k) / n))
	pts.append(ctrl[-1])
	paths.append({"pts": pts, "w": w, "kind": kind})
	var td := {}
	for p in pts:
		for yy in range(int(floor(p.y - w - 1)), int(p.y + w + 2)):
			for xx in range(int(floor(p.x - w - 1)), int(p.x + w + 2)):
				if not in_bounds(xx, yy): continue
				var d := p.distance_to(Vector2(xx + 0.5, yy + 0.5))
				if d <= w:
					var i := idx(xx, yy)
					if kind == "dirt":
						if T[i] == GRASS: T[i] = DIRT_ROAD
					else:
						T[i] = ROAD
		if kind != "dirt":
			for vy in range(int(floor(p.y - 6)), int(p.y + 7)):
				for vx in range(int(floor(p.x - 6)), int(p.x + 7)):
					if vx < 0 or vy < 0 or vx > N or vy > N: continue
					var dv := p.distance_to(Vector2(vx, vy))
					if dv < road_d[vy * NV + vx]:
						road_d[vy * NV + vx] = dv

func _wobbly(a: Vector2, b: Vector2, steps: int, amp: float) -> Array:
	var ctrl := [a]
	var nrm := (b - a).orthogonal().normalized()
	for k in range(1, steps):
		var t := float(k) / steps
		ctrl.append(a.lerp(b, t) + nrm * rf(-amp, amp))
	ctrl.append(b)
	return ctrl

func _roads() -> void:
	# two highways cross the map and meet in the city, plus curving city streets and dirt tracks
	var h1 := _wobbly(Vector2(-3, rf(24, 34)), Vector2(N + 3, rf(36, 54)), 6, 3.5)
	h1.insert(3, Vector2(rf(38, 46), rf(38, 46)))
	_path(h1, 1.15, "highway")
	var h2 := _wobbly(Vector2(rf(24, 34), -3), Vector2(rf(36, 54), N + 3), 6, 3.5)
	_path(h2, 1.15, "highway")
	_path(_wobbly(Vector2(rf(28, 36), N + 3), Vector2(N + 3, rf(28, 36)), 4, 3.0), 0.95, "street")
	_path(_wobbly(Vector2(CITY - 3, rf(48, 58)), Vector2(rf(50, 58), CITY - 3), 4, 3.0), 0.95, "street")
	for k in 3:
		var p1: PackedVector2Array = paths[k % 2].pts
		var from := Vector2.ZERO
		for t in 50:
			from = p1[ri(0, p1.size() - 1)]
			if min(from.x, from.y) < CITY - 3 and from.distance_to(start) > 9: break
		var to := from + Vector2.from_angle(rf(0, TAU)) * rf(10, 18)
		to = to.clamp(Vector2(3, 3), Vector2(N - 4, N - 4))
		_path(_wobbly(from, to, 3, 2.5), 0.6, "dirt")

func _heights() -> void:
	var s1 := rng.randf() * 10.0
	var s2 := rng.randf() * 10.0
	var s3 := rng.randf() * 10.0
	for y in NV:
		for x in NV:
			var h := 14.0 * (sin(x * 0.19 + s1) + sin(y * 0.23 + s2)) + 9.0 * sin((x + y) * 0.13 + s3) + 10.0 * sin((x - y) * 0.17 + s1 * 2.0) + 10.0
			h = maxf(0.0, h) * sstep((CITY - min(x, y)) / 7.0)
			var rd := road_d[y * NV + x]
			h *= 0.35 + 0.65 * sstep((rd - 1.0) / 4.0)
			VH[y * NV + x] = h
	for _it in 2:
		var C := VH.duplicate()
		for y in range(1, N):
			for x in range(1, N):
				VH[y * NV + x] = (C[y * NV + x] * 4.0 + C[y * NV + x - 1] + C[y * NV + x + 1] + C[(y - 1) * NV + x] + C[(y + 1) * NV + x]) / 8.0

func _cars() -> void:
	for pth in paths:
		if pth.kind == "dirt": continue
		var pts: PackedVector2Array = pth.pts
		var n := pts.size()
		for t in int(n / 22):
			var i := ri(2, n - 3)
			var p := pts[i]
			if p.distance_to(start) < 9 or not in_bounds(int(p.x), int(p.y)): continue
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var lane := 0.45 if rng.randf() < 0.5 else -0.45
			var c := Car.new()
			c.k = posmod(int(round(dir.angle() / (PI / 4.0))) + (4 if rng.randf() < 0.3 else 0), 8)
			c.ang = c.k * PI / 4.0
			c.pos = p + dir.orthogonal() * lane
			c.spr = ["teal", "red", "yellow", "burned", "burned"][ri(0, 4)]
			var clash := false
			for o in cars:
				if o.pos.distance_to(c.pos) < 3.0: clash = true
			if clash or building_at(c.pos.x, c.pos.y) > 0: continue
			cars.append(c)
			var cr := Crate.new()
			var fwd := Vector2.from_angle(c.ang)
			cr.pos = c.pos - fwd * 1.5 + fwd.orthogonal() * 0.55
			cr.kind = "car"
			crates.append(cr)
	# power poles with sagging wires along the highways
	for pth in paths:
		if pth.kind != "highway": continue
		var pts: PackedVector2Array = pth.pts
		var line := PackedVector2Array()
		var i := 0
		while i < pts.size() - 1:
			var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var p := pts[i] + dir.orthogonal() * 2.3
			if in_bounds(int(p.x), int(p.y)) and T[idx(int(p.x), int(p.y))] in [GRASS, SIDE] and rng.randf() < 0.9:
				line.append(p)
			elif line.size() > 1:
				pole_lines.append(line)
				line = PackedVector2Array()
			i += 26
		if line.size() > 1:
			pole_lines.append(line)

func add_decor(name: String, p: Vector2, solid: bool = false, half: Vector2 = Vector2(0.2, 0.2), flat: bool = false) -> void:
	var d := Decor.new()
	d.name = name; d.pos = p; d.solid = solid; d.half = half; d.flat = flat
	d.bid = building_at(p.x, p.y)
	decor.append(d)
	if solid:
		var k := int(floor(p.y)) * N + int(floor(p.x))
		if not decor_grid.has(k): decor_grid[k] = []
		decor_grid[k].append(d)

func _free_spot(p: Vector2) -> bool:
	if not in_bounds(int(p.x), int(p.y)): return false
	var t := T[idx(int(p.x), int(p.y))]
	return (t == GRASS or t == SIDE or t == ROAD or t == DIRT_ROAD) and not car_hit(p, 0.3) and not tree_hit(p, 0.3) and building_at(p.x, p.y) == 0

func _debris() -> void:
	for pth in paths:
		var pts: PackedVector2Array = pth.pts
		for t in int(pts.size() / 10):
			var i := ri(1, pts.size() - 2)
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var r := rng.randf()
			if pth.kind != "dirt" and r < 0.12:
				var p: Vector2 = pts[i] + dir.orthogonal() * rf(-0.4, 0.4)
				if _free_spot(p):
					var along_x := absf(dir.x) > absf(dir.y)
					add_decor("jersey_x" if along_x else "jersey_y", p, true, Vector2(0.5, 0.13) if along_x else Vector2(0.13, 0.5))
			else:
				var p: Vector2 = pts[i] + dir.orthogonal() * side * (pth.w + rf(0.3, 1.4))
				if not _free_spot(p): continue
				var pick: String = ["trashbag", "tire", "rubble0", "papers", "barrel_rust", "cart", "rubble1"][ri(0, 6)]
				if pick == "cart" and not in_city(p.x, p.y): pick = "tire"
				add_decor(pick, p, pick == "barrel_rust", Vector2(0.17, 0.17), pick == "papers")
	# city clutter
	for k in 70:
		var p := Vector2(rf(CITY, N - 2), rf(CITY, N - 2))
		if _free_spot(p):
			var pick: String = ["rubble0", "rubble1", "rubble2", "bricks", "papers", "trashbag", "barrel_rust", "tire"][ri(0, 7)]
			add_decor(pick, p, pick == "barrel_rust", Vector2(0.17, 0.17), pick == "papers")
	# wild clutter: bones, dead bushes, fences, toxic spills
	for k in 90:
		var p := Vector2(rf(2, N - 2), rf(2, N - 2))
		if in_city(p.x, p.y) or not _free_spot(p) or CL[idx(int(p.x), int(p.y))] == 1: continue
		add_decor(["deadbush", "deadbush", "bones", "rubble2", "fence", "tire"][ri(0, 5)], p)
	for k in 3:
		for t in 50:
			var c := Vector2(rf(4, N - 5), rf(4, N - 5))
			if not _free_spot(c) or c.distance_to(start) < 10 or settlement_at(c, 4.0) >= 0: continue
			add_decor("puddle_toxic", c, false, Vector2.ZERO, true)
			add_decor("puddle_toxic", c + Vector2(rf(-1.5, 1.5), rf(-1.5, 1.5)), false, Vector2.ZERO, true)
			for m in 3:
				var bp := c + Vector2.from_angle(rf(0, TAU)) * rf(1.0, 2.2)
				if _free_spot(bp): add_decor("barrel_toxic", bp, true, Vector2(0.17, 0.17))
			add_decor("sign_rad", c + Vector2(2.4, 0.5))
			spawns.append({"type": "shellback", "pos": c + Vector2(1.5, 1.5), "home": c, "home_r": 4.0})
			break
	# grass tufts
	for y in N:
		for x in N:
			var i := idx(x, y)
			if T[i] == GRASS and (G[i] == 3 or rng.randf() < 0.06):
				add_decor("tuft%d" % ri(0, 2), Vector2(x + rf(0.2, 0.8), y + rf(0.2, 0.8)), false, Vector2.ZERO, true)
	# crows pecking about out in the wilds
	for k in 6:
		var c := Vector2(rf(3, N - 3), rf(3, N - 3))
		if _free_spot(c) and not in_city(c.x, c.y):
			for m in ri(3, 5):
				critters.append({"type": "crow", "pos": c + Vector2(rf(-1, 1), rf(-1, 1)), "home": c})

func _creatures() -> void:
	# fewer, tougher mutants: feral ghouls in the ruins, a couple of brutes, rats indoors
	var placed := 0
	for b in buildings:
		if placed >= 5: break
		if (b.ruined or (in_city(b.x0, b.y0) and rng.randf() < 0.25)) and b.kind != "den" and b.kind != "shack" and b.settlement < 0:
			var p := Vector2(b.x0 + b.w * 0.5, b.y0 + b.h * 0.5)
			if p.distance_to(start) < 14: continue
			spawns.append({"type": "ghoul", "pos": p + Vector2(rf(-1, 1), rf(-1, 1)), "home": p, "home_r": 3.0})
			if rng.randf() < 0.4:
				spawns.append({"type": "ghoul", "pos": p + Vector2(rf(-1, 1), rf(-1, 1)), "home": p, "home_r": 3.0})
			placed += 1
	var brutes := 0
	for t in 300:
		if brutes >= 2: break
		var p := Vector2(rf(4, N - 4), rf(4, N - 4))
		if not _free_spot(p) or p.distance_to(start) < 20 or settlement_at(p, 6.0) >= 0: continue
		var ok := true
		for s in spawns:
			if s.type == "brute" and s.pos.distance_to(p) < 20: ok = false
		if not ok: continue
		spawns.append({"type": "brute", "pos": p, "home": p, "home_r": 5.0})
		brutes += 1
	add_patrol()

func add_monster(avoid: Vector2, min_d: float, camps: Array) -> void:
	for t in 200:
		var p := Vector2(rf(3, N - 4), rf(3, N - 4))
		if not _free_spot(p) or p.distance_to(avoid) < min_d or settlement_at(p, 6.0) >= 0: continue
		var near_camp := false
		for c in camps:
			if p.distance_to(c) < 12.0: near_camp = true
		if near_camp: continue
		spawns.append({"type": "ghoul" if rng.randf() < 0.7 else "shellback", "pos": p, "home": p, "home_r": 5.0})
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
	var b := place_building(int(round(c.x - 2)), int(round(c.y - 2)), 4, 4, "den")
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
	add_decor("barrel_rust", c + Vector2.from_angle(ang + 3.6) * 2.6, true, Vector2(0.17, 0.17))
	add_decor("bones", c + Vector2.from_angle(ang - 0.8) * 2.4)

func _settlement(c: Vector2, sname: String) -> void:
	var st := Settlement.new()
	st.name = sname
	st.pos = c
	settlements.append(st)
	var si := settlements.size() - 1
	# flatten a yard
	var h0 := hz(c.x, c.y)
	for vy in range(int(c.y - 9), int(c.y + 10)):
		for vx in range(int(c.x - 9), int(c.x + 10)):
			var d := Vector2(vx, vy).distance_to(c)
			set_vh(vx, vy, lerpf(vh(vx, vy), h0, sstep(1.0 - (d - 6.0) / 3.0)))
	for y in range(int(c.y - 7), int(c.y + 8)):
		for x in range(int(c.x - 7), int(c.x + 8)):
			if in_bounds(x, y) and Vector2(x + 0.5, y + 0.5).distance_to(c) < 7.0:
				CL[idx(x, y)] = 1
				if T[idx(x, y)] == GRASS: G[idx(x, y)] = 2
	# shacks in a rough ring, doors facing the fire
	var a0 := rf(0, TAU)
	for k in 4:
		var a := a0 + k * TAU / 4.0 + rf(-0.3, 0.3)
		var w := ri(3, 4)
		var h := ri(3, 4)
		var p := c + Vector2.from_angle(a) * 4.6
		var side := 0
		var dv := c - p
		if absf(dv.x) > absf(dv.y): side = 3 if dv.x > 0 else 2
		else: side = 1 if dv.y > 0 else 0
		var b := place_building(int(round(p.x - w * 0.5)), int(round(p.y - h * 0.5)), w, h, "shack", side, true)
		if b: b.settlement = si
	add_decor("campfire_decor", c, true, Vector2(0.25, 0.25))
	st.trader = c + Vector2(1.6, 0.4)
	add_decor("stall", st.trader + Vector2(0, -0.6), true, Vector2(0.5, 0.2))
	for k in 4:
		var gp := c + Vector2(-2.6 + (k % 2), 1.6 + int(k / 2))
		add_decor("garden", Vector2(floor(gp.x), floor(gp.y)), false, Vector2.ZERO, true)
	add_decor("pump", c + Vector2(-1.5, -1.8), true, Vector2(0.15, 0.15))
	add_decor("tower_decor", c + Vector2(2.6, -2.6), true, Vector2(0.25, 0.25))
	for k in 10:
		var a := k * TAU / 10.0 + rf(-0.1, 0.1)
		if k % 3 == 1: continue
		add_decor("fence", c + Vector2.from_angle(a) * 6.8)
	critters.append({"type": "trader", "pos": st.trader, "home": st.trader, "settlement": si})
	for k in ri(3, 4):
		critters.append({"type": "settler", "pos": c + Vector2(rf(-2, 2), rf(-2, 2)), "home": c, "settlement": si, "look": ri(1, 3)})
	for k in ri(1, 2):
		critters.append({"type": "cattle", "pos": c + Vector2(rf(-5, 5), rf(3, 5)), "home": c + Vector2(0, 4)})

func _add_seg(b: Bld, a: Vector2, bb: Vector2, axis: int, side: String, fl: int, window: bool) -> Seg:
	var s := Seg.new()
	s.a = a; s.b = bb; s.axis = axis; s.side = side; s.fl = fl; s.window = window; s.bid = b.id
	s.mode = "win" if window else "plain"
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
	return s

func _pick_kind(x0: int, y0: int, w: int, h: int) -> String:
	var r := rng.randf()
	if in_city(x0, y0):
		var by_road := near_road(x0 + w / 2, y0 + h / 2, maxi(w, h) / 2 + 2)
		if by_road:
			return "shop" if r < 0.45 else ("office" if r < 0.7 else "house")
		return "house" if r < 0.55 else ("office" if r < 0.75 else "garage")
	return "house" if r < 0.75 else "garage"

func place_building(x0: int, y0: int, w: int, h: int, kind: String = "", door_side: int = -1, allow_clear: bool = false) -> Bld:
	var raider := kind == "den"
	if x0 < 2 or y0 < 2 or x0 + w >= N - 2 or y0 + h >= N - 2:
		return null
	for y in range(y0 - 1, y0 + h + 1):
		for x in range(x0 - 1, x0 + w + 1):
			var i := idx(x, y)
			var inside := x >= x0 and x < x0 + w and y >= y0 and y < y0 + h
			if inside and (T[i] != GRASS or (CL[i] == 1 and not raider and not allow_clear)): return null
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
	b.kind = kind if kind != "" else _pick_kind(x0, y0, w, h)
	b.pal = 5 if b.kind == "shack" else (1 if raider else ri(0, 3))
	b.fkind = {"shop": 1, "office": 2, "garage": 3, "den": 3, "shack": 3}.get(b.kind, ri(0, 1) * 2)
	b.floors = 2 if (b.kind in ["house", "office", "shop"] and w >= 5 and h >= 5 and rng.randf() < 0.55) else 1
	b.roof = "tin" if b.kind == "shack" else ("pitched" if b.kind in ["house", "garage"] else "flat")
	b.ruined = b.kind in ["house", "office", "shop", "garage"] and rng.randf() < (0.3 if in_city(x0, y0) else 0.35)
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			T[idx(x, y)] = FLOOR
			BID[idx(x, y)] = b.id
	# door: one gap in the ground-floor outer wall
	var side := door_side if door_side >= 0 else ri(0, 3)
	var door := Vector2i()
	if side == 0: door = Vector2i(x0 + ri(1, w - 2), y0)
	elif side == 1: door = Vector2i(x0 + ri(1, w - 2), y0 + h)
	elif side == 2: door = Vector2i(x0, y0 + ri(1, h - 2))
	else: door = Vector2i(x0 + w, y0 + ri(1, h - 2))
	b.out = Vector2i(door.x, door.y - 1) if side == 0 else (Vector2i(door.x, door.y) if side == 1 else (Vector2i(door.x - 1, door.y) if side == 2 else Vector2i(door.x, door.y)))
	b.door_in = Vector2i(door.x, y0) if side == 0 else (Vector2i(door.x, y0 + h - 1) if side == 1 else (Vector2i(x0, door.y) if side == 2 else Vector2i(x0 + w - 1, door.y)))
	var iw := -1
	if w >= 5 and b.kind != "shack" and not raider:
		iw = x0 + ri(2, w - 2)
	var gaps := {}
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
			gaps[fl] = gap
			for y in range(y0, y0 + h):
				if y != gap:
					_add_seg(b, Vector2(iw, y), Vector2(iw, y + 1), 1, "i", fl, false)
	if b.floors == 2:
		for t in 30:
			var sx := ri(x0, x0 + w - 1)
			var sy := ri(y0 + 1, y0 + h - 1)
			if Vector2i(sx, sy) == b.door_in or Vector2(sx, sy).distance_to(Vector2(b.door_in)) < 1.5: continue
			if sx == iw or sx == iw - 1: continue
			b.stairs = Vector2i(sx, sy)
			break
		if b.stairs.x < 0:
			b.floors = 1
			var keep := []
			for s in b.segs:
				if s.fl == 0: keep.append(s)
			b.segs = keep
	# weathering: broken / boarded windows, cracks
	for s in b.segs:
		if s.side == "i": continue
		var r := rng.randf()
		if s.window:
			s.mode = "broken" if r < 0.5 else ("boarded" if r < 0.75 else "win")
		elif r < 0.15:
			s.mode = "cracked"
	# ruins: one corner has collapsed
	if b.ruined:
		var corner := Vector2([x0, x0 + w][ri(0, 1)], [y0, y0 + h][ri(0, 1)])
		var cr := rf(1.6, 2.6)
		for s in b.segs:
			var mid: Vector2 = (s.a + s.b) * 0.5
			if mid.distance_to(corner) < cr:
				s.mode = "stub"
				s.solid = false
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				if Vector2(x + 0.5, y + 0.5).distance_to(corner) < cr + 0.3 and Vector2i(x, y) != b.stairs:
					b.holes[Vector2i(x, y)] = true
				elif rng.randf() < 0.08:
					b.holes[Vector2i(x, y)] = true
		var rp := corner.lerp(Vector2(x0 + w * 0.5, y0 + h * 0.5), 0.25)
		add_decor("rubble%d" % ri(0, 2), rp)
		add_decor("bricks", rp + Vector2(rf(-0.6, 0.6), rf(-0.6, 0.6)))
	buildings.append(b)
	_furnish(b, iw, gaps)
	if raider:
		for k in ri(1, 2):
			var cr := Crate.new()
			cr.pos = Vector2(rf(x0 + 1, x0 + w - 1), rf(y0 + 1.6, y0 + h - 1))
			cr.kind = "cache"
			cr.bid = b.id
			crates.append(cr)
	if b.kind != "den" and b.kind != "shack" and rng.randf() < 0.35:
		spawns.append({"type": "rat", "pos": Vector2(rf(x0 + 0.6, x0 + w - 0.6), rf(y0 + 0.6, y0 + h - 0.6)), "fl": ri(0, b.floors - 1), "home_r": 2.0})
	return b

func _rooms_for(b: Bld) -> Dictionary:
	match b.kind:
		"house": return {0: ["kitchen", "living"], 1: ["bedroom", "bedroom"]}
		"shop": return {0: ["shop", "shop"], 1: ["office", "bedroom"]}
		"office": return {0: ["office", "office"], 1: ["office", "office"]}
		"garage": return {0: ["garage", "garage"]}
		"shack": return {0: ["shack"]}
		"den": return {0: ["den"]}
	return {0: ["living", "kitchen"]}

func _add_furn(b: Bld, name: String, p: Vector2, orient: String, fl: int) -> Furn:
	var sz: Array = FURN_SIZE[name]
	var f := Furn.new()
	f.name = name; f.pos = p; f.orient = orient; f.bid = b.id; f.fl = fl; f.h = sz[2]
	f.half = Vector2(sz[0], sz[1]) * 0.5 if orient == "a" else Vector2(sz[1], sz[0]) * 0.5
	if rng.randf() < CONTAINER_CHANCE.get(name, 0.0):
		var c := Crate.new()
		c.pos = p
		c.kind = name
		c.bid = b.id
		c.fl = fl
		crates.append(c)
		f.crate = c
	b.furn.append(f)
	return f

func _furnish(b: Bld, iw: int, gaps: Dictionary) -> void:
	var rooms := _rooms_for(b)
	var blocked := {b.door_in: true, b.stairs: true}
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		blocked[b.door_in + o] = true
		if b.stairs.x >= 0: blocked[b.stairs + o] = true
	for fl in b.floors:
		var types: Array = rooms.get(fl, rooms[0])
		var spans := [[b.x0, b.x0 + b.w]] if iw < 0 else [[b.x0, iw], [iw, b.x0 + b.w]]
		for ri_ in spans.size():
			var rx0: int = spans[ri_][0]
			var rx1: int = spans[ri_][1]
			var tpl: Dictionary = TEMPLATES[types[mini(ri_, types.size() - 1)]]
			var gap: int = gaps.get(fl, -99)
			# along the back (north) wall
			var items: Array = tpl.north
			var k := 0
			for x in range(rx0, rx1):
				if k >= items.size(): break
				var t := Vector2i(x, b.y0)
				if blocked.has(t) or b.holes.has(t) and fl > 0: continue
				var nm: String = items[k]
				var d: float = FURN_SIZE[nm][1]
				_add_furn(b, nm, Vector2(x + 0.5, b.y0 + d * 0.5 + 0.08), "a", fl)
				k += 1
			# along the west wall
			items = tpl.west
			k = 0
			for y in range(b.y0 + 1, b.y0 + b.h):
				if k >= items.size(): break
				var t := Vector2i(rx0, y)
				if blocked.has(t) or y == gap or (b.holes.has(t) and fl > 0): continue
				if rng.randf() < 0.4: continue
				var nm: String = items[k]
				var d: float = FURN_SIZE[nm][1]
				_add_furn(b, nm, Vector2(rx0 + d * 0.5 + 0.08, y + 0.5), "b", fl)
				k += 1
			# something in the middle of bigger rooms
			if tpl.center.size() > 0 and rx1 - rx0 >= 3 and b.h >= 4:
				var cp := Vector2((rx0 + rx1) * 0.5, b.y0 + b.h * 0.5 + 0.4)
				var ct := Vector2i(int(cp.x), int(cp.y))
				if not blocked.has(ct) and cp.distance_to(Vector2(b.door_in) + Vector2(0.5, 0.5)) > 1.6 and not (fl > 0 and b.holes.has(ct)):
					var nm: String = tpl.center[0]
					_add_furn(b, nm, cp, "a", fl)
					if nm == "table" or nm == "desk":
						_add_furn(b, "chair", cp + Vector2(0, 0.55), "a", fl)
			# a bit of mess
			for m in ri(1, 3):
				var p := Vector2(rf(rx0 + 0.4, rx1 - 0.4), rf(b.y0 + 1.2, b.y0 + b.h - 0.4))
				if fl == 0:
					add_decor(["papers", "papers", "rubble2", "bones"][ri(0, 3)] if b.kind != "shack" else "papers", p, false, Vector2.ZERO, true)
