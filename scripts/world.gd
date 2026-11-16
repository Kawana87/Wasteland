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
	var mode := "plain"     # plain, win, broken, boarded, cracked, door, shop, garage, stub
	var solid := true
	var cell := Vector2i()  # the building cell this wall belongs to
	var is_door := false
	var door := ""          # closed, locked, barred, open, broken, sealed
	var door_hp := 0.0
	var see := false        # windows, fences, half walls: block movement but not shots
	var tier := ""          # player-built pieces (bid -1): scrap, wood, stone, concrete, fence
	var piece := ""         # wall, window, doorway, door, half, gate
	var hp := 0.0

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
	var kind := "house"      # house, diner, motel, shop, office, factory, garage, kiosk, canopy, shack, den
	var ruined := false
	var holes := {}          # Vector2i -> true: no upper floor / no roof here
	var furn: Array = []
	var roof := "flat"       # flat, pitched, tin, saw, canopy
	var settlement := -1
	var door_in := Vector2i()
	var door_side := 1
	var cells := {}          # Vector2i -> storeys over that cell
	var parts: Array = []    # [{r: Rect2i, fl: int}]
	var rcol := 0            # roof colour index
	var open := false        # gas-station canopy: counts as outdoors
	var signs: Array = []    # [{tex, seg}]
	var awnings: Array = []  # [{tex, seg}]
	var roof_props: Array = []   # [{tex, pos, cell}]
	var sealed := false      # boarded-up scenery house: can't be entered
	var door_seg: Seg = null
	func inside(x: float, y: float) -> bool:
		return cells.has(Vector2i(int(floor(x)), int(floor(y))))
	func floors_at(c: Vector2i) -> int:
		return cells.get(c, 0)

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

func wall_hit(p: Vector2, r: float, fl: int, shots: bool = false) -> bool:
	var tx := int(floor(p.x))
	var ty := int(floor(p.y))
	for yy in range(ty - 1, ty + 2):
		for xx in range(tx - 1, tx + 2):
			var lst = seg_grid.get(yy * N + xx)
			if lst == null:
				continue
			for s in lst:
				if s.solid and s.fl == fl and not (shots and s.see) and seg_dist(p, s) < r + 0.06:
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
		var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
		var bb: Bld = buildings[id - 1]
		return bb.floors_at(c) > fl and not bb.holes.has(c)
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
	if wall_hit(p, 0.0, fl, true):
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

const SETTLEMENT_NAMES := ["Rustwater", "Tin Hollow", "Saltgrass", "Patchwork", "Cinder Creek", "Last Light"]
const TEMPLATES := {
	"kitchen": {"north": ["counter", "stove", "counter", "fridge"], "west": ["counter"], "center": ["table"]},
	"living": {"north": ["bookshelf", "tv", "armchair"], "west": ["couch"], "center": []},
	"bedroom": {"north": ["bed", "dresser"], "west": ["dresser"], "center": []},
	"office": {"north": ["filing", "terminal", "bookshelf", "filing"], "west": ["filing", "locker"], "center": ["desk"]},
	"shop": {"north": ["shopshelf", "shopshelf", "shopshelf"], "west": ["shopshelf"], "center": ["shopcounter"]},
	"garage": {"north": ["workbench", "barrel", "barrel"], "west": ["shopshelf"], "center": []},
	"shack": {"north": ["mattress", "barrel"], "west": ["workbench"], "center": []},
	"den": {"north": ["mattress", "barrel", "mattress"], "west": ["mattress"], "center": []},
	"diner": {"north": ["booth", "jukebox", "booth", "booth", "booth"], "west": ["booth", "booth"], "center": ["counter"]},
	"motel": {"north": ["bed", "tv"], "west": ["dresser"], "center": []},
	"factory": {"north": ["workbench", "locker", "locker", "workbench", "barrel", "shopshelf"], "west": ["barrel", "shopshelf", "barrel"], "center": ["workbench"]},
	"kiosk": {"north": ["shopshelf", "vending"], "west": ["shopshelf"], "center": []},
}
const FURN_SIZE := {   # long side, depth, height (px)
	"counter": [1.0, 0.5, 12], "stove": [0.5, 0.5, 12], "fridge": [0.5, 0.5, 28], "table": [0.9, 0.6, 10],
	"chair": [0.3, 0.3, 6], "couch": [1.0, 0.45, 8], "armchair": [0.45, 0.45, 8], "tv": [0.4, 0.3, 12],
	"bookshelf": [0.9, 0.3, 26], "bed": [1.0, 0.6, 7], "dresser": [0.6, 0.35, 14], "desk": [0.8, 0.45, 11],
	"filing": [0.35, 0.35, 16], "shopshelf": [1.0, 0.35, 20], "shopcounter": [1.0, 0.4, 12],
	"workbench": [0.9, 0.4, 11], "barrel": [0.35, 0.35, 12], "mattress": [0.9, 0.55, 3],
	"booth": [1.0, 0.45, 12], "jukebox": [0.45, 0.35, 22], "terminal": [0.6, 0.4, 16], "locker": [0.8, 0.3, 26],
	"stool": [0.25, 0.25, 8], "vending": [0.5, 0.4, 28],
}
const CONTAINER_CHANCE := {"fridge": 0.9, "dresser": 0.9, "desk": 0.9, "filing": 0.8, "shopshelf": 0.6,
	"shopcounter": 1.0, "workbench": 0.9, "bookshelf": 0.4, "counter": 0.35, "barrel": 0.3, "mattress": 0.2,
	"locker": 0.8, "terminal": 0.5, "vending": 0.7, "jukebox": 0.3, "booth": 0.15}

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
	# city blocks: diners, motels, gas stations, shops, offices, factories, houses
	var lots := []
	for y in range(CITY, N - 4):
		for x in range(CITY, N - 4):
			lots.append(Vector2i(x, y))
	for i in range(lots.size() - 1, 0, -1):
		var j := ri(0, i)
		var t: Vector2i = lots[i]; lots[i] = lots[j]; lots[j] = t
	# big landmarks first so they get room, then fill the gaps with smaller buildings
	var big := {"office": 3, "factory": 2, "motel": 1, "diner": 2, "gas": 1}
	for lot in lots:
		if BID[idx(lot.x, lot.y)] != 0 or T[idx(lot.x, lot.y)] == ROAD: continue
		var opts := []
		for k in big:
			if big[k] > 0: opts.append(k)
		if opts.is_empty(): break
		var kind: String = opts[ri(0, opts.size() - 1)]
		if kind in ["diner", "gas", "motel"] and not near_road(lot.x + 2, lot.y + 2, 4): continue
		var before := buildings.size()
		place_shape(shape_for(kind, lot.x, lot.y), kind)
		if buildings.size() > before: big[kind] -= 1
	for lot in lots:
		if BID[idx(lot.x, lot.y)] != 0 or T[idx(lot.x, lot.y)] == ROAD: continue
		var kind := _pick_kind(lot.x, lot.y)
		if place_shape(shape_for(kind, lot.x, lot.y), kind) == null and kind != "gas":
			var fb: String = ["house", "garage", "shop"][ri(0, 2)]
			place_shape(shape_for(fb, lot.x, lot.y), fb)
	# outskirts: ranch houses, garages and roadside stops
	for k in 160:
		var x := ri(2, 18) if rng.randf() < 0.5 else ri(18, 56)
		var y := ri(18, 56) if x < 18 else ri(2, 18)
		var kind := _pick_kind(x, y)
		place_shape(shape_for(kind, x, y), kind)
	# a few landmarks
	for k in 2:
		for t in 60:
			var p := Vector2(rf(6, N - 6), rf(6, N - 6))
			if _free_spot(p) and T[idx(int(p.x), int(p.y))] == GRASS and p.distance_to(start) > 10 and _clear_of_buildings(p, 2.0):
				add_decor("watertower", p, true, Vector2(0.55, 0.55))
				break
	for k in 4:
		for t in 60:
			var p := road_point() + Vector2(rf(-2.5, 2.5), rf(-2.5, 2.5))
			var axb := ri(0, 1)
			var far := true
			for d0 in decor:
				if d0.name.begins_with("billboard") and d0.pos.distance_to(p) < 8.0: far = false
			if far and _free_spot(p) and T[idx(int(p.x), int(p.y))] == GRASS and not near_road(int(p.x), int(p.y), 0) and _clear_of_buildings(p, 1.6):
				add_decor("billboard_" + ["x", "y"][axb], p, true, Vector2(1.0, 0.2) if axb == 0 else Vector2(0.2, 1.0))
				break
	# trees
	for y in N:
		for x in N:
			var i := idx(x, y)
			if T[i] != GRASS or CL[i] == 1: continue
			if rng.randf() < (0.03 if in_city(x, y) else 0.13) and _clear_of_buildings(Vector2(x + 0.5, y + 0.5), 0.75):
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
	_lamps()
	_debris()
	_creatures()
	# survivors holed up in city buildings
	var cand := []
	for b in buildings:
		if b.kind in ["house", "shop", "office", "motel", "factory"] and not b.sealed and b.cells.size() >= 12 and in_city(b.x0, b.y0):
			cand.append(b)
	cand.shuffle()
	var sn := ["Mara", "Dez", "Jun", "Otis", "Rosa", "Hank", "Priya", "Theo", "Wren", "Gus"]
	sn.shuffle()
	for k in min(3, cand.size()):
		var b: Bld = cand[k]
		for t in 20:
			var p := rand_cell(b)
			if can_stand(p, 0.28, 0):
				survivors.append({"pos": p, "name": sn[k], "bid": b.id})
				break
	_tidy()
	_fix_spawns()
	_fix_critters()

## Final real-world-logic pass over everything placed: nothing solid inside walls or in front of doors,
## no trees growing through props, wrecks that collide with props are scrapped, door exits are clear.
func _tidy() -> void:
	var doors := []
	for b in buildings:
		doors.append(Vector2(b.out.x + 0.5, b.out.y + 0.5))
	var keep := []
	for d in decor:
		if (d.name.begins_with("fence") or d.name.begins_with("picket")) and d.bid == 0 and building_at(d.pos.x, d.pos.y) != 0:
			continue
		if d.bid != 0 or d.flat or not d.solid or d.name in ["pillar", "fuelpump", "mailbox"]:
			keep.append(d); continue
		var bad := func(q: Vector2) -> bool:
			if building_at(q.x, q.y) != 0 or not _clear_of_buildings(q, d.half.x + 0.05): return true
			for o in keep:
				if o.solid and o.bid == 0 and absf(o.pos.x - q.x) < (o.half.x + d.half.x) * 0.8 and absf(o.pos.y - q.y) < (o.half.y + d.half.y) * 0.8: return true
			for dp in doors:
				if dp.distance_to(q) < 1.05: return true
			return false
		if bad.call(d.pos):
			if d.name.begins_with("fence") or d.name.begins_with("picket"):
				continue                      # fence runs simply stop at the wall
			var moved := false
			for ring in range(1, 9):
				for k in 12:
					var q: Vector2 = d.pos + Vector2.from_angle(k * TAU / 12.0) * ring * 0.25
					if in_bounds(int(q.x), int(q.y)) and not bad.call(q):
						d.pos = q; moved = true; break
				if moved: break
			if not moved:
				continue                      # nowhere sensible: drop it
		keep.append(d)
	decor = keep
	decor_grid.clear()
	for d in decor:
		if d.solid:
			var k := int(floor(d.pos.y)) * N + int(floor(d.pos.x))
			if not decor_grid.has(k): decor_grid[k] = []
			decor_grid[k].append(d)
	# trees under solid props, wrecks hitting props or doors
	for d in decor:
		if not d.solid or d.bid != 0: continue
		for yy in range(int(d.pos.y - d.half.y - 0.4), int(d.pos.y + d.half.y + 0.4) + 1):
			for xx in range(int(d.pos.x - d.half.x - 0.4), int(d.pos.x + d.half.x + 0.4) + 1):
				if in_bounds(xx, yy) and T[idx(xx, yy)] == TREE: T[idx(xx, yy)] = GRASS
	for k in range(cars.size() - 1, -1, -1):
		var c: Car = cars[k]
		var hit := decor_hit(c.pos, 0.9)
		for dp in doors:
			if dp.distance_to(c.pos) < 1.8: hit = true
		if hit:
			cars.remove_at(k)
			for q in range(crates.size() - 1, -1, -1):
				if crates[q].kind == "car" and crates[q].pos.distance_to(c.pos) < 2.2:
					crates.remove_at(q)
	# loot left outdoors that ended up inside a wall
	for cr in crates:
		if cr.bid == 0 and cr.kind != "car" and building_at(cr.pos.x, cr.pos.y) != 0:
			for ring in range(1, 10):
				var q: Vector2 = cr.pos + Vector2.from_angle(ring * 2.4) * ring * 0.3
				if building_at(q.x, q.y) == 0 and can_stand(q, 0.2, 0):
					cr.pos = q; break
	# door exits: the tile outside every door must be walkable
	for b in buildings:
		var o := Vector2i(b.out)
		if in_bounds(o.x, o.y) and T[idx(o.x, o.y)] == TREE: T[idx(o.x, o.y)] = GRASS

## Livestock and crows start (and keep their home) outdoors on open ground; settlers on standable ground.
func _fix_critters() -> void:
	for cr in critters:
		var outdoor: bool = cr.type in ["cattle", "crow"]
		for key in ["pos", "home"]:
			if not cr.has(key): continue
			var p: Vector2 = cr[key]
			var ok := func(q: Vector2) -> bool:
				return in_bounds(int(q.x), int(q.y)) and can_stand(q, 0.3, 0) and (not outdoor or _clear_of_buildings(q, 0.6))
			if ok.call(p): continue
			for ring in range(1, 24):
				var found := false
				for k in 12:
					var q: Vector2 = p + Vector2.from_angle(k * TAU / 12.0) * ring * 0.35
					if ok.call(q):
						cr[key] = q; found = true; break
				if found: break

## Move any spawn that landed inside a wall, furniture, tree or wreck to the nearest spot it can stand on.
func _fix_spawns() -> void:
	for sp in spawns:
		var fl: int = sp.get("fl", 0)
		var p: Vector2 = sp.pos
		if can_stand(p, 0.22, fl):
			continue
		var found := false
		for ring in range(1, 14):
			var r := ring * 0.25
			for k in 12:
				var q := p + Vector2.from_angle(k * TAU / 12.0) * r
				if in_bounds(int(q.x), int(q.y)) and can_stand(q, 0.22, fl) and building_at(q.x, q.y) == building_at(p.x, p.y):
					sp.pos = q; found = true; break
			if found: break

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
			c.spr = ["teal", "red", "yellow", "teal", "red", "burned"][ri(0, 5)]
			var clash := false
			for o in cars:
				if o.pos.distance_to(c.pos) < 3.0: clash = true
			if clash: continue
			# whole body footprint (and a little margin) must be clear of buildings and trees
			var fw := Vector2.from_angle(c.ang)
			var bad := false
			for u in [-1.4, -0.7, 0.0, 0.7, 1.4]:
				for v in [-0.5, 0.5]:
					var q: Vector2 = c.pos + fw * u + fw.orthogonal() * v
					if not in_bounds(int(q.x), int(q.y)) or building_at(q.x, q.y) > 0 or T[idx(int(q.x), int(q.y))] == TREE:
						bad = true
			if bad: continue
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
			if in_bounds(int(p.x), int(p.y)) and T[idx(int(p.x), int(p.y))] in [GRASS, SIDE] and rng.randf() < 0.9 and _clear_of_buildings(p, 0.8) and not tree_hit(p, 0.3) and not car_hit(p, 0.4):
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

## Retro street lamps along city streets and highways, alternating sides.
func _lamps() -> void:
	for pth in paths:
		if pth.kind == "dirt": continue
		var pts: PackedVector2Array = pth.pts
		var side := 1.0
		for i in range(6, pts.size() - 2, 22):
			var p := pts[i]
			if not in_city(p.x, p.y) and rng.randf() < 0.6: continue
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var q: Vector2 = p + dir.orthogonal() * side * (pth.w + 0.75)
			side = -side
			if _free_spot(q) and T[idx(int(q.x), int(q.y))] != ROAD and _clear_of_buildings(q, 0.7):
				add_decor("lamp", q, true, Vector2(0.08, 0.08))

## No building within r tiles of p (tall props must not stand against or inside walls).
func _clear_of_buildings(p: Vector2, r: float) -> bool:
	for k in 8:
		var q := p + Vector2.from_angle(k * PI / 4.0) * r
		if building_at(q.x, q.y) != 0:
			return false
	return building_at(p.x, p.y) == 0

func _free_spot(p: Vector2) -> bool:
	if not in_bounds(int(p.x), int(p.y)): return false
	var t := T[idx(int(p.x), int(p.y))]
	if (t == GRASS or t == SIDE or t == ROAD or t == DIRT_ROAD) and not car_hit(p, 0.3) and not tree_hit(p, 0.3) and building_at(p.x, p.y) == 0 and not decor_hit(p, 0.15):
		for b in buildings:
			if Vector2(b.out.x + 0.5, b.out.y + 0.5).distance_squared_to(p) < 1.2:
				return false
		return true
	return false

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
	for k in 160:
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
		if (b.ruined or (in_city(b.x0, b.y0) and rng.randf() < 0.25)) and not b.kind in ["den", "shack", "canopy", "kiosk"] and not b.sealed and b.settlement < 0:
			var p := rand_cell(b)
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

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]   # n s w e
const DIR_SIDE := ["n", "s", "w", "e"]

## Wall segment on edge `d` (index into DIRS) of cell c.
func _edge(b: Bld, c: Vector2i, d: int, fl: int, side: String) -> Seg:
	var x := float(c.x)
	var y := float(c.y)
	var s: Seg
	match d:
		0: s = _add_seg(b, Vector2(x, y), Vector2(x + 1, y), 0, side, fl, false)
		1: s = _add_seg(b, Vector2(x, y + 1), Vector2(x + 1, y + 1), 0, side, fl, false)
		2: s = _add_seg(b, Vector2(x, y), Vector2(x, y + 1), 1, side, fl, false)
		_: s = _add_seg(b, Vector2(x + 1, y), Vector2(x + 1, y + 1), 1, side, fl, false)
	s.cell = c
	return s

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

## Player-built wall pieces live in seg_grid like building walls (bid -1), so collision, shots and doors work.
func add_free_seg(s: Seg) -> void:
	for t in _seg_tiles(s):
		var k: int = t.y * N + t.x
		if not seg_grid.has(k): seg_grid[k] = []
		seg_grid[k].append(s)

func remove_free_seg(s: Seg) -> void:
	for t in _seg_tiles(s):
		var lst = seg_grid.get(t.y * N + t.x)
		if lst != null: lst.erase(s)

func _seg_tiles(s: Seg) -> Array:
	var out := []
	var ts := [Vector2i(int(s.a.x), int(s.a.y) - 1), Vector2i(int(s.a.x), int(s.a.y))] if s.axis == 0 else [Vector2i(int(s.a.x) - 1, int(s.a.y)), Vector2i(int(s.a.x), int(s.a.y))]
	for t in ts:
		if in_bounds(t.x, t.y): out.append(t)
	return out

## Is there already a wall (building or built) on this tile edge?
func edge_taken(x: int, y: int, axis: int) -> bool:
	var a := Vector2(x, y)
	for t in [Vector2i(x, y), Vector2i(x - 1, y), Vector2i(x, y - 1)]:
		if not in_bounds(t.x, t.y): continue
		for s in seg_grid.get(t.y * N + t.x, []):
			if s.fl == 0 and s.axis == axis and s.a.distance_to(a) < 0.01:
				return true
	return false

# ------------------------------------------------------------------ building shapes
## A building footprint is a list of non-overlapping rectangles ("parts").
func shape_for(kind: String, x0: int, y0: int) -> Array:
	var r := rng.randf()
	match kind:
		"house":
			var w := ri(4, 5); var h := ri(3, 4)
			if r < 0.55: return _shape_L(x0, y0, w, h, ri(2, 3), 2)
			if r < 0.7: return _shape_T(x0, y0, w + 1, h, 2, 2)
			return [Rect2i(x0, y0, w, h)]
		"diner":
			var long := ri(6, 7)
			var parts := [Rect2i(x0, y0, long, 3)] if r < 0.5 else [Rect2i(x0, y0, 3, long)]
			if rng.randf() < 0.5:
				var m: Rect2i = parts[0]
				parts.append(Rect2i(m.position.x + m.size.x, m.position.y, 2, 2) if m.size.x > m.size.y else Rect2i(m.position.x, m.position.y + m.size.y, 2, 2))
			return parts
		"motel":
			var long := ri(6, 8)
			if r < 0.5: return [Rect2i(x0, y0, long, 2), Rect2i(x0, y0 + 2, 2, ri(2, 3))]
			if r < 0.8: return [Rect2i(x0, y0, long, 2), Rect2i(x0, y0 + 2, 2, 2), Rect2i(x0 + long - 2, y0 + 2, 2, 2)]
			return [Rect2i(x0, y0, 2, long), Rect2i(x0 + 2, y0, ri(2, 3), 2)]
		"shop":
			var w := ri(4, 6); var h := ri(4, 5)
			if r < 0.35: return _shape_L(x0, y0, w, h, 2, 2)
			return [Rect2i(x0, y0, w, h)]
		"office":
			var w := ri(6, 8); var h := ri(3, 4)
			if r < 0.45: return _shape_T(x0, y0, w, h, ri(2, 3), ri(2, 3))
			if r < 0.8: return _shape_U(x0, y0, w, h, 2, ri(2, 3))
			return [Rect2i(x0, y0, w, h + 1)]
		"factory":
			var w := ri(7, 9); var h := ri(5, 6)
			if r < 0.5: return [Rect2i(x0, y0, w, h), Rect2i(x0 + w, y0 + h - 2, 2, 2)]
			return [Rect2i(x0, y0, w, h)]
		"garage":
			return [Rect2i(x0, y0, ri(4, 5), ri(3, 4))]
		"kiosk":
			return [Rect2i(x0, y0, 3, 3)]
	return [Rect2i(x0, y0, ri(4, 6), ri(4, 5))]

## main rect + a wing hanging off one side, flush with one end
func _shape_L(x0: int, y0: int, w: int, h: int, ww: int, wh: int) -> Array:
	var main := Rect2i(x0, y0, w, h)
	match ri(0, 3):
		0: return [main, Rect2i(x0 + (0 if rng.randf() < 0.5 else w - ww), y0 + h, ww, wh)]
		1: return [main, Rect2i(x0 + w, y0 + (0 if rng.randf() < 0.5 else h - ww), wh, ww)]
		2: return [Rect2i(x0, y0 + wh, w, h), Rect2i(x0 + (0 if rng.randf() < 0.5 else w - ww), y0, ww, wh)]
	return [Rect2i(x0 + wh, y0, w, h), Rect2i(x0, y0 + (0 if rng.randf() < 0.5 else h - ww), wh, ww)]

func _shape_T(x0: int, y0: int, w: int, h: int, ww: int, wh: int) -> Array:
	if rng.randf() < 0.5:
		return [Rect2i(x0, y0, w, h), Rect2i(x0 + (w - ww) / 2, y0 + h, ww, wh)]
	return [Rect2i(x0, y0, h, w), Rect2i(x0 + h, y0 + (w - ww) / 2, wh, ww)]

func _shape_U(x0: int, y0: int, w: int, h: int, ww: int, wh: int) -> Array:
	if rng.randf() < 0.5:
		return [Rect2i(x0, y0, w, h), Rect2i(x0, y0 + h, ww, wh), Rect2i(x0 + w - ww, y0 + h, ww, wh)]
	return [Rect2i(x0, y0, h, w), Rect2i(x0 + h, y0, wh, ww), Rect2i(x0 + h, y0 + w - ww, wh, ww)]

func _pick_kind(x: int, y: int) -> String:
	var r := rng.randf()
	if in_city(x, y):
		if near_road(x + 2, y + 2, 4):
			if r < 0.3: return "shop"
			if r < 0.42: return "diner"
			if r < 0.52: return "gas"
			if r < 0.62: return "motel"
			if r < 0.82: return "office"
			return "house"
		if r < 0.4: return "house"
		if r < 0.6: return "office"
		if r < 0.78: return "factory"
		return "garage"
	if near_road(x + 2, y + 2, 4):
		if r < 0.15: return "gas"
		if r < 0.27: return "diner"
		if r < 0.37: return "motel"
	return "house" if r < 0.8 else "garage"

const KIND_INFO := {   # wall palettes, roof style, floor kind, window chance, max storeys
	"house": {"pal": [0, 1, 2, 3], "roof": "pitched", "fk": [0, 2], "win": 0.35, "fl": 2},
	"diner": {"pal": [9], "roof": "flat", "fk": [1], "win": 0.2, "fl": 1},
	"motel": {"pal": [10, 1, 2], "roof": "pitched", "fk": [2], "win": 0.3, "fl": 1},
	"shop": {"pal": [6, 7, 1], "roof": "flat", "fk": [4, 3], "win": 0.3, "fl": 2},
	"office": {"pal": [8, 7], "roof": "flat", "fk": [2, 4], "win": 0.55, "fl": 2},
	"factory": {"pal": [11, 8], "roof": "saw", "fk": [3], "win": 0.2, "fl": 1},
	"garage": {"pal": [5, 8, 6], "roof": "pitched", "fk": [3], "win": 0.15, "fl": 1},
	"kiosk": {"pal": [10], "roof": "flat", "fk": [4], "win": 0.3, "fl": 1},
	"shack": {"pal": [5], "roof": "tin", "fk": [3], "win": 0.2, "fl": 1},
	"den": {"pal": [6], "roof": "flat", "fk": [3], "win": 0.2, "fl": 1},
	"canopy": {"pal": [10], "roof": "canopy", "fk": [3], "win": 0.0, "fl": 1},
}

## Old single-rectangle entry point (raider dens, settlement shacks).
func place_building(x0: int, y0: int, w: int, h: int, kind: String = "", door_side: int = -1, allow_clear: bool = false) -> Bld:
	return place_shape([Rect2i(x0, y0, w, h)], kind if kind != "" else _pick_kind(x0, y0), door_side, allow_clear)

## Places a gas station: kiosk + canopy over two pumps + a tall pole sign.
func place_gas(x0: int, y0: int) -> bool:
	var along_x := rng.randf() < 0.5
	var cr := Rect2i(x0 + 4, y0, 4, 3) if along_x else Rect2i(x0, y0 + 4, 3, 4)
	if not _can_place([Rect2i(x0, y0, 3, 3)]) or not _can_place([cr]): return false
	var k: Bld = place_shape([Rect2i(x0, y0, 3, 3)], "kiosk")
	if k == null: return false
	var c: Bld = place_shape([cr], "canopy", -1, false, true)
	if c == null: return true
	c.open = true
	var a := Vector2(cr.position)
	var e := Vector2(cr.end)
	for p in [Vector2(a.x + 0.35, a.y + 0.35), Vector2(e.x - 0.35, a.y + 0.35), Vector2(a.x + 0.35, e.y - 0.35), Vector2(e.x - 0.35, e.y - 0.35)]:
		add_decor("pillar", p, true, Vector2(0.08, 0.08))
		decor[decor.size() - 1].bid = 0
	var mid := (a + e) * 0.5
	for o in ([Vector2(-0.8, 0), Vector2(0.8, 0)] if along_x else [Vector2(0, -0.8), Vector2(0, 0.8)]):
		add_decor("fuelpump", mid + o, true, Vector2(0.14, 0.12))
		decor[decor.size() - 1].bid = 0
	var sp := Vector2(e.x + 0.6, e.y + 0.6) if along_x else Vector2(e.x + 0.6, e.y + 0.4)
	if _free_spot(sp):
		add_decor("sign_gas", sp, true, Vector2(0.08, 0.08))
	return true

func place_shape(parts: Array, kind: String, door_side: int = -1, allow_clear: bool = false, open: bool = false) -> Bld:
	if kind == "gas":
		var p0: Rect2i = parts[0]
		place_gas(p0.position.x, p0.position.y)
		return null
	var raider := kind == "den"
	var info: Dictionary = KIND_INFO.get(kind, KIND_INFO["house"])
	var cells := {}
	var bb: Rect2i = parts[0]
	for r in parts:
		bb = bb.merge(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[Vector2i(x, y)] = 1
	if not _can_place(parts, raider, allow_clear):
		return null
	var mn := 1e9
	var mx := -1e9
	var sum := 0.0
	var n := 0
	for c in cells:
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var v := vh(c.x + o.x, c.y + o.y)
			mn = minf(mn, v); mx = maxf(mx, v); sum += v; n += 1
	if mx - mn > (60.0 if raider else 18.0):
		return null
	var ctr := Vector2(bb.position) + Vector2(bb.size) * 0.5
	var h0 := vh(int(round(ctr.x)), int(round(ctr.y))) if raider else sum / n
	for y in range(bb.position.y - 1, bb.end.y + 2):
		for x in range(bb.position.x - 1, bb.end.x + 2):
			var inner := false
			for o in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				if cells.has(Vector2i(x, y) + o): inner = true
			set_vh(x, y, h0 if inner else (vh(x, y) + h0) * 0.5)
	var b := Bld.new()
	b.id = buildings.size() + 1
	b.x0 = bb.position.x; b.y0 = bb.position.y; b.w = bb.size.x; b.h = bb.size.y
	b.h0 = h0; b.raider = raider; b.kind = kind; b.open = open
	var pals: Array = info.pal
	b.pal = pals[ri(0, pals.size() - 1)]
	var fks: Array = info.fk
	b.fkind = fks[ri(0, fks.size() - 1)]
	b.rcol = ri(0, 4)
	b.roof = info.roof
	if kind == "garage" and rng.randf() < 0.5: b.roof = "flat"
	if kind == "motel" and rng.randf() < 0.4: b.roof = "flat"
	b.ruined = kind in ["house", "office", "shop", "garage", "diner", "motel", "factory"] and rng.randf() < (0.28 if in_city(b.x0, b.y0) else 0.3)
	# storeys per part: the biggest part may get a second floor, wings usually stay low
	var big := 0
	for i in parts.size():
		if parts[i].get_area() > parts[big].get_area(): big = i
	var two := int(info.fl) >= 2 and rng.randf() < (0.7 if kind == "office" else 0.4)
	for i in parts.size():
		var r: Rect2i = parts[i]
		var f := 1
		if two and (i == big or (kind == "office" and rng.randf() < 0.5)) and r.size.x >= 3 and r.size.y >= 3:
			f = 2
		b.parts.append({"r": r, "fl": f})
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[Vector2i(x, y)] = f
	b.cells = cells
	for c in cells:
		b.floors = maxi(b.floors, cells[c])
		T[idx(c.x, c.y)] = FLOOR
		BID[idx(c.x, c.y)] = b.id
	buildings.append(b)
	if kind == "canopy":
		return b
	# door: an outer ground-floor edge, preferably facing a road and the camera
	var cands := []
	for c in cells:
		for d in 4:
			var nb: Vector2i = c + DIRS[d]
			if cells.has(nb) or not in_bounds(nb.x, nb.y): continue
			var t := T[idx(nb.x, nb.y)]
			if t == FLOOR or t == TREE or BID[idx(nb.x, nb.y)] != 0: continue
			var score := rng.randf()
			if door_side >= 0: score += 5.0 if d == door_side else 0.0
			else:
				if near_road(nb.x, nb.y, 2): score += 2.0
				if d == 1 or d == 3: score += 0.6
			cands.append([score, c, d])
	if cands.is_empty():
		cands.append([0.0, cells.keys()[0], 1])
	cands.sort_custom(func(p, q): return p[0] > q[0])
	var dc: Vector2i = cands[0][1]
	var dd: int = cands[0][2]
	b.door_in = dc
	b.out = dc + DIRS[dd]
	b.door_side = dd
	# outer walls on every storey
	for fl in b.floors:
		for c in cells:
			if cells[c] <= fl: continue
			for d in 4:
				var nb: Vector2i = c + DIRS[d]
				if cells.has(nb) and cells[nb] > fl: continue
				var s := _edge(b, c, d, fl, DIR_SIDE[d])
				if fl == 0 and c == dc and d == dd:
					s.is_door = true
					b.door_seg = s
	# interior walls: between parts (one gap each) and splitting long parts
	var gaps := {}
	for fl in b.floors:
		for i in b.parts.size():
			for j in range(i + 1, b.parts.size()):
				var shared := []
				for c in cells:
					if cells[c] <= fl or not b.parts[i].r.has_point(c): continue
					for d in 4:
						var nb: Vector2i = c + DIRS[d]
						if b.parts[j].r.has_point(nb) and cells[nb] > fl:
							shared.append([c, d])
				if shared.is_empty() or kind in ["diner"]: continue
				var gi := shared.size() / 2
				for k in shared.size():
					if k == gi:
						gaps[shared[k][0]] = true
						gaps[shared[k][0] + DIRS[shared[k][1]]] = true
						continue
					_edge(b, shared[k][0], shared[k][1], fl, "i")
		for p in b.parts:
			var r: Rect2i = p.r
			if p.fl <= fl or kind in ["shack", "den", "diner", "factory", "kiosk"] or raider: continue
			if r.size.x >= 6 or (kind == "motel" and r.size.x >= 4 and r.size.y == 2):
				var step := 3 if kind == "motel" else r.size.x
				var xs := range(r.position.x + 3, r.end.x - 1, 3) if kind == "motel" else [r.position.x + ri(2, r.size.x - 3)]
				for wx in xs:
					var gy := r.position.y + ri(0, r.size.y - 1)
					for y in range(r.position.y, r.end.y):
						if y == gy:
							gaps[Vector2i(wx, y)] = true; gaps[Vector2i(wx - 1, y)] = true
							continue
						_edge(b, Vector2i(wx, y), 2, fl, "i")
	# stairs in a two-storey part
	if b.floors == 2:
		var opts := []
		for c in cells:
			if cells[c] < 2 or c == dc or Vector2(c).distance_to(Vector2(dc)) < 1.5 or gaps.has(c): continue
			opts.append(c)
		if opts.is_empty():
			b.floors = 1
			for c in cells: cells[c] = 1
			for p in b.parts: p.fl = 1
			b.segs = b.segs.filter(func(s): return s.fl == 0)
		else:
			b.stairs = opts[ri(0, opts.size() - 1)]
	_dress_walls(b, info)
	_pick_door(b)
	if b.ruined:
		_ruin(b)
	if b.sealed:
		_extras(b)
		return b
	_furnish(b, gaps)
	_extras(b)
	if raider:
		for k in ri(1, 2):
			var cr := Crate.new()
			cr.pos = Vector2(cells.keys()[ri(0, cells.size() - 1)]) + Vector2(0.5, 0.5)
			cr.kind = "cache"
			cr.bid = b.id
			crates.append(cr)
	if kind != "den" and kind != "shack" and not b.sealed and rng.randf() < 0.35:
		spawns.append({"type": "rat", "pos": rand_cell(b), "fl": 0, "home_r": 2.0})
	return b

func _can_place(parts: Array, raider: bool = false, allow_clear: bool = false) -> bool:
	var cells := {}
	var bb: Rect2i = parts[0]
	for r in parts:
		bb = bb.merge(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[Vector2i(x, y)] = 1
	if bb.position.x < 2 or bb.position.y < 2 or bb.end.x >= N - 2 or bb.end.y >= N - 2:
		return false
	for y in range(bb.position.y - 1, bb.end.y + 1):
		for x in range(bb.position.x - 1, bb.end.x + 1):
			var i := idx(x, y)
			var inside := cells.has(Vector2i(x, y))
			if inside and ((T[i] != GRASS and T[i] != SIDE) or (CL[i] == 1 and not raider and not allow_clear)): return false
			if not inside and (T[i] == FLOOR or BID[i] != 0): return false
	return true

const DOOR_MODE := {"closed": "door", "locked": "doorlock", "barred": "doorbar", "open": "dooropen", "broken": "doorbroken", "sealed": "doorsealed"}

## Front door state. Some ordinary houses are sealed scenery you can't enter at all.
func _pick_door(b: Bld) -> void:
	var s := b.door_seg
	if s == null: return
	var r := rng.randf()
	var st := "open"
	match b.kind:
		"shack", "den", "kiosk", "diner":
			st = "open" if r < 0.7 else "closed"
		"house", "garage", "motel":
			if r < 0.3: st = "open"
			elif r < 0.55: st = "closed"
			elif r < 0.8: st = "locked"
			else: st = "barred"
			if b.kind != "motel" and not b.ruined and b.settlement < 0 and rng.randf() < 0.22 and Vector2(b.x0, b.y0).distance_to(start) > 8:
				st = "sealed"
		_:
			if r < 0.25: st = "open"
			elif r < 0.5: st = "closed"
			elif r < 0.85: st = "locked"
			else: st = "barred"
	if b.ruined and st != "sealed":
		st = "broken" if rng.randf() < 0.5 else "open"
	s.door = st
	s.mode = DOOR_MODE[st]
	s.solid = st in ["closed", "locked", "barred", "sealed"]
	s.door_hp = {"locked": 10.0, "barred": 18.0, "closed": 6.0}.get(st, 0.0)
	if st == "sealed":
		b.sealed = true
		for w in b.segs:
			if w.mode in ["win", "broken", "shop"]: w.mode = "boarded"

## Called by the game when a door changes state.
func set_door(s: Seg, st: String) -> void:
	s.door = st
	s.mode = DOOR_MODE[st]
	s.solid = st in ["closed", "locked", "barred", "sealed"]

func rand_cell(b: Bld) -> Vector2:
	var ks: Array = b.cells.keys()
	return Vector2(ks[ri(0, ks.size() - 1)]) + Vector2(0.5, 0.5)

func _front(s: Seg) -> bool:   # south / east faces are the ones the camera sees
	return s.side == "s" or s.side == "e"

## Windows, shopfronts, painted doors, garage doors and weathering.
func _dress_walls(b: Bld, info: Dictionary) -> void:
	var garage_done := false
	var k := 0
	for s in b.segs:
		if s.side == "i" or s.is_door: continue
		k += 1
		var r := rng.randf()
		var ground: bool = s.fl == 0
		var on_door_side: bool = s.side == DIR_SIDE[b.door_side]
		match b.kind:
			"diner", "kiosk":
				if ground and (on_door_side or _front(s)) and r < 0.75: s.mode = "shop"
			"shop":
				if ground and on_door_side and r < 0.8: s.mode = "shop"
			"motel":
				if ground and _front(s): s.mode = "door" if k % 3 == 0 else ("win" if k % 3 == 1 else "plain")
			"garage", "factory":
				if ground and not garage_done and _front(s) and r < 0.5:
					s.mode = "garage"; garage_done = true
		if s.mode == "plain" and rng.randf() < float(info.win):
			s.mode = "win"
		if s.mode == "plain" and b.kind == "house" and ground and _front(s) and rng.randf() < 0.08:
			s.mode = "door"
		# weathering
		var w := rng.randf()
		if s.mode == "win" or s.mode == "shop":
			if w < 0.45: s.mode = "broken"
			elif w < 0.65: s.mode = "boarded"
		elif s.mode == "plain" and w < 0.12:
			s.mode = "cracked"

## Ruined building: the roof is gone and the top storey is a broken shell you can see into.
## The collapse comes from one corner and works down: near the corner the top storey is gone entirely
## and the storey below is broken off; further out the top storey walls are ragged stubs, front walls
## mostly broken so the inside shows. Nothing is left floating over a broken wall.
func _ruin(b: Bld) -> void:
	var edge_cells := []
	for c in b.cells:
		for d in DIRS:
			if not b.cells.has(c + d): edge_cells.append(c); break
	var cc: Vector2i = edge_cells[ri(0, edge_cells.size() - 1)]
	var corner := Vector2(cc) + Vector2(rf(0, 1), rf(0, 1))
	var cr := rf(1.6, 2.6)
	var broken_low := {}            # wall positions broken off on a lower storey
	for s in b.segs:
		var d: float = ((s.a + s.b) * 0.5).distance_to(corner)
		var top: int = b.floors_at(s.cell) - 1
		if s.fl < top and d < cr * 0.6 and not s.is_door:
			s.mode = "stub"; s.solid = false
			broken_low["%s|%s" % [str(s.a), str(s.b)]] = s.fl
	var keep := []
	for s in b.segs:
		var k := "%s|%s" % [str(s.a), str(s.b)]
		if broken_low.has(k) and s.fl > broken_low[k]:
			continue                  # fell down with the wall below it
		var top: int = b.floors_at(s.cell) - 1
		if s.fl == top and not s.is_door and s.mode != "stub":
			var d: float = ((s.a + s.b) * 0.5).distance_to(corner)
			var front: bool = s.side == "s" or s.side == "e"
			if d < cr or (front and rng.randf() < 0.65) or (s.side == "i" and rng.randf() < 0.5) or rng.randf() < 0.2:
				s.mode = "stub"; s.solid = false
		keep.append(s)
	b.segs = keep
	for c in b.cells:
		if b.cells[c] < 2: continue
		if Vector2(c.x + 0.5, c.y + 0.5).distance_to(corner) < cr * 0.6 + 0.5 and c != b.stairs:
			b.holes[c] = true
		elif rng.randf() < 0.08 and c != b.stairs:
			b.holes[c] = true
	var rp := corner.lerp(Vector2(b.x0 + b.w * 0.5, b.y0 + b.h * 0.5), 0.25)
	if b.cells.has(Vector2i(int(rp.x), int(rp.y))):
		add_decor("rubble%d" % ri(0, 2), rp)
		add_decor("bricks", rp + Vector2(rf(-0.5, 0.5), rf(-0.5, 0.5)))

## True when (x, y) on storey fl can be seen from outside: open structures, and the roofless top
## storey of a ruin.
func open_from_outside(x: float, y: float, fl: int) -> bool:
	var id := building_at(x, y)
	if id == 0: return fl == 0
	var b := bld(id)
	return b.open or (b.ruined and fl == b.floors_at(Vector2i(int(x), int(y))) - 1)

const SHOP_SIGNS := ["grocery", "hardware", "clinic", "radio", "bar"]

## Signs, awnings, rooftop clutter and yard props.
func _extras(b: Bld) -> void:
	var fronts := []
	for s in b.segs:
		if _front(s) and s.mode != "stub" and s.fl == b.cells.get(s.cell, 1) - 1: fronts.append(s)
	var ground_front: Array = fronts.filter(func(s): return s.fl == 0)
	match b.kind:
		"shop", "office", "garage", "factory":
			var word: String = SHOP_SIGNS[ri(0, SHOP_SIGNS.size() - 1)]
			if b.kind == "office": word = "cityhall" if rng.randf() < 0.4 else ""
			if b.kind == "garage": word = "garage"
			if b.kind == "factory": word = "factory"
			if word != "" and fronts.size() > 0:
				var s: Seg = fronts[ri(0, fronts.size() - 1)]
				b.signs.append({"tex": "wsign_%s_%s" % [word, "x" if s.axis == 0 else "y"], "seg": s})
			if b.kind == "shop":
				var col: String = ["c84a3a", "3e8a86", "d8b040"][ri(0, 2)]
				for s in ground_front:
					if s.mode in ["shop", "broken", "boarded"] and rng.randf() < 0.8:
						b.awnings.append({"tex": "awning_%s_%s" % [col, "x" if s.axis == 0 else "y"], "seg": s})
	var flat_cells := []
	for c in b.cells:
		if not b.holes.has(c): flat_cells.append(c)
	if b.roof == "flat" and flat_cells.size() > 0 and not b.ruined:
		var props: Array = {"office": ["ac_unit", "ac_unit", "roof_vent", "antenna", "roof_tank"], "shop": ["ac_unit", "roof_vent"],
			"diner": ["roof_vent"], "kiosk": ["roof_vent"], "garage": ["roof_vent"], "motel": ["ac_unit"]}.get(b.kind, [])
		for nm in props:
			if rng.randf() < 0.7:
				var c: Vector2i = flat_cells[ri(0, flat_cells.size() - 1)]
				b.roof_props.append({"tex": nm, "pos": Vector2(c) + Vector2(rf(0.3, 0.7), rf(0.3, 0.7)), "cell": c})
	if b.kind == "diner" and not b.ruined:
		var p: Dictionary = b.parts[0]
		var c := Vector2(p.r.get_center())
		b.roof_props.append({"tex": "sign_diner", "pos": c, "cell": Vector2i(int(c.x), int(c.y))})
	# yard / street props outside the door
	var out := Vector2(b.out) + Vector2(0.5, 0.5)
	var side := Vector2(DIRS[b.door_side]).orthogonal()
	match b.kind:
		"house":
			if rng.randf() < 0.6: _try_decor("mailbox", out + side * 1.2, true, Vector2(0.08, 0.08))
			if rng.randf() < 0.5:
				var ax := "x" if (b.door_side == 0 or b.door_side == 1) else "y"
				for k in [-3, -2, 2, 3]:
					_try_decor("picket_" + ax, out + side * k + Vector2(DIRS[b.door_side]) * 0.4, false)
			if rng.randf() < 0.5: _try_decor("shrub", out + side * -1.3, false)
		"motel":
			_try_decor("sign_motel", out + side * 2.0 + Vector2(DIRS[b.door_side]) * 1.2, true, Vector2(0.08, 0.08))
			if rng.randf() < 0.6: _try_decor("vending_" + ("x" if b.door_side < 2 else "y"), out + side * -1.2, true, Vector2(0.2, 0.15))
		"diner":
			if rng.randf() < 0.6: _try_decor("vending_" + ("x" if b.door_side < 2 else "y"), out + side * 1.3, true, Vector2(0.2, 0.15))
		"shop", "office":
			if rng.randf() < 0.4: _try_decor(["newsbox", "phonebooth", "bench", "hydrant"][ri(0, 3)], out + side * 1.4, true, Vector2(0.15, 0.15))

func _try_decor(name: String, p: Vector2, solid: bool, half: Vector2 = Vector2(0.2, 0.2)) -> void:
	if _free_spot(p) and p.distance_to(start) > 4.0:
		var ti := idx(int(p.x), int(p.y))
		if T[ti] == ROAD: return
		add_decor(name, p, solid, half)

func _rooms_for(b: Bld) -> Dictionary:
	match b.kind:
		"house": return {0: ["kitchen", "living", "bedroom"], 1: ["bedroom", "bedroom"]}
		"shop": return {0: ["shop", "shop"], 1: ["office", "bedroom"]}
		"office": return {0: ["office", "office"], 1: ["office", "office"]}
		"garage": return {0: ["garage", "garage"]}
		"shack": return {0: ["shack"]}
		"den": return {0: ["den"]}
		"diner": return {0: ["diner", "kitchen"]}
		"motel": return {0: ["motel"]}
		"factory": return {0: ["factory", "office"]}
		"kiosk": return {0: ["kiosk"]}
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

## Rooms = parts, with long parts split where an interior wall was built.
func _furnish(b: Bld, gaps: Dictionary) -> void:
	var rooms := _rooms_for(b)
	var blocked := gaps.duplicate()
	blocked[b.door_in] = true
	blocked[b.stairs] = true
	for o in DIRS:
		blocked[b.door_in + o] = true
		if b.stairs.x >= 0: blocked[b.stairs + o] = true
	for fl in b.floors:
		var types: Array = rooms.get(fl, rooms[0])
		var ri_ := 0
		for p in b.parts:
			if p.fl <= fl: continue
			var r: Rect2i = p.r
			# split points from interior walls running along y inside this part
			var xs := [r.position.x]
			for s in b.segs:
				if s.side == "i" and s.fl == fl and s.axis == 1 and r.has_point(Vector2i(int(s.a.x), int(s.a.y))) and int(s.a.x) > r.position.x and not xs.has(int(s.a.x)):
					xs.append(int(s.a.x))
			xs.sort()
			xs.append(r.end.x)
			for q in range(xs.size() - 1):
				var rx0: int = xs[q]
				var rx1: int = xs[q + 1]
				var tpl: Dictionary = TEMPLATES[types[mini(ri_, types.size() - 1)]]
				ri_ += 1
				var items: Array = tpl.north
				var k := 0
				for x in range(rx0, rx1):
					if k >= items.size(): break
					var t := Vector2i(x, r.position.y)
					if blocked.has(t) or (b.holes.has(t) and fl > 0): continue
					var nm: String = items[k]
					_add_furn(b, nm, Vector2(x + 0.5, r.position.y + FURN_SIZE[nm][1] * 0.5 + 0.08), "a", fl)
					k += 1
				items = tpl.west
				k = 0
				for y in range(r.position.y + 1, r.end.y):
					if k >= items.size(): break
					var t := Vector2i(rx0, y)
					if blocked.has(t) or (b.holes.has(t) and fl > 0): continue
					if rng.randf() < 0.3: continue
					var nm: String = items[k]
					_add_furn(b, nm, Vector2(rx0 + FURN_SIZE[nm][1] * 0.5 + 0.08, y + 0.5), "b", fl)
					k += 1
				if tpl.center.size() > 0 and rx1 - rx0 >= 3 and r.size.y >= 3:
					var cp := Vector2((rx0 + rx1) * 0.5, r.position.y + r.size.y * 0.5 + 0.4)
					var ct := Vector2i(int(cp.x), int(cp.y))
					if not blocked.has(ct) and cp.distance_to(Vector2(b.door_in) + Vector2(0.5, 0.5)) > 1.6 and not (fl > 0 and b.holes.has(ct)):
						var nm: String = tpl.center[0]
						_add_furn(b, nm, cp, "a", fl)
						if nm == "table" or nm == "desk":
							_add_furn(b, "chair", cp + Vector2(0, 0.55), "a", fl)
						if nm == "counter":
							for sx in [-0.35, 0.35]:
								_add_furn(b, "stool", cp + Vector2(sx, 0.55), "a", fl)
				for m in ri(1, 3):
					var pp := Vector2(rf(rx0 + 0.4, rx1 - 0.4), rf(r.position.y + 1.2, r.end.y - 0.4))
					if fl == 0:
						add_decor(["papers", "papers", "rubble2", "bones", "trashbag"][ri(0, 4)] if b.kind != "shack" else "papers", pp, false, Vector2.ZERO, true)
