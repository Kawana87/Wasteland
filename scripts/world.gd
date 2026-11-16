class_name World
extends RefCounted
## Map data + procedural generation + spatial queries (heights, walls, line of sight).
## World units are tiles. Screen projection lives in Iso.

const N := 2048
const NV := N + 1
const CH := 32                 # chunk size (tiles)
const NC := N / CH             # chunks per side
const HS := 800.0              # pixels of height per unit of world-map height
const FLOOR_H := 28.0          # height of one storey in pixels

const GRASS := 0
const ROAD := 1
const FLOOR := 2
const TREE := 5
const SIDE := 7
const STUMP := 8
const DIRT_ROAD := 9
const WATER := 10
const ROCK := 11                # solid underground rock / bunker wall

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
	var info := ""            # "Title|text" — something to look at (vignettes)
	var portal := ""          # entrance to an underground map ("kind:id"), or "exit"

class Settlement:
	var name: String
	var pos: Vector2
	var radius := 7.0
	var trader := Vector2.ZERO
	var id := ""
	var hook := ""
	var small := false

class Rope:
	var top: Vector2
	var bottom: Vector2

class RaiderCamp:
	var pos: Vector2
	var ang: float
	var bid := 0
	var cleared := false
	var claimed := false

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
var gen_ms := 0                 # time spent building all locations at load (perf check)
## While a chunk's content is generated, everything solid it makes must stay inside this rect
## (the chunk minus a 2-tile border). Neighbouring chunks then never see each other's content, so a
## chunk comes out the same whichever neighbour streamed in first (Review 2). Empty = no limit.
var gen_rect := Rect2()
var skip_reach := false         # perf comparison only
var reserve_r := 0.0            # nothing solid is generated this close to the home camp (set once start is known)
var plat := {}                   # Vector2i -> top height of a player-built foundation on that tile
const STEP := 10.0               # you can walk up a ledge this high (px) onto or off a foundation

func idx(x: int, y: int) -> int:
	return y * N + x

## Underground maps reuse World with only the first `rows` rows allocated (see Underground).
var interior := false
var rows := N
var bounds := Vector2i(NC, NC)

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < rows

func vh(x: int, y: int) -> float:
	return VH[clampi(y, 0, mini(N, rows)) * NV + clampi(x, 0, N)]

func set_vh(x: int, y: int, h: float) -> void:
	if x < 0 or y < 0 or x > N or y > mini(N, rows):
		return
	VH[y * NV + x] = h

## Ground height (pixels) at a world position, bilinear between corner heights.
func hz(wx: float, wy: float) -> float:
	wx = clampf(wx, 0.0, N - 0.001)
	wy = clampf(wy, 0.0, mini(N, rows) - 0.001)
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
	if not plat.is_empty():
		var t := Vector2i(int(floor(x)), int(floor(y)))
		if plat.has(t): return plat[t]
	return hz(x, y)

func in_city(x: float, y: float) -> bool:
	return density(int(x), int(y)) > 110

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
	for c in car_grid.get(int(floor(p.y)) * N + int(floor(p.x)), []):
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
	if fl == 0 and (tile(p.x, p.y) == WATER or tile(p.x, p.y) == ROCK):
		return false
	if fl > 0:
		var id := building_at(p.x, p.y)
		if id == 0:
			return false
		var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
		var bb: Bld = buildings[id - 1]
		return bb.floors_at(c) > fl and not bb.holes.has(c)
	return not tree_hit(p, r) and not car_hit(p, r) and not decor_hit(p, r)

## Nearest spot within maxr where something of radius r can stand, on floor fl. When outside
## (fl 0) and not allowed indoors, building tiles don't count. Returns Vector2.INF if none.
func nearest_free(p: Vector2, r: float, fl: int = 0, maxr: float = 2.0, indoors_ok: bool = true) -> Vector2:
	var ok := func(q: Vector2) -> bool:
		if not can_stand(q, r, fl): return false
		return indoors_ok or fl > 0 or building_at(q.x, q.y) == 0
	if ok.call(p): return p
	var step := 0.25
	var ring := step
	while ring <= maxr + 0.001:
		var n := maxi(8, int(ring * 16))
		for k in n:
			var q := p + Vector2.from_angle(k * TAU / n) * ring
			if ok.call(q): return q
		ring += step
	return Vector2.INF

## Can you walk from a to b? Uphill steeper than 26 px/tile is a cliff (jumping adds a little lift).
func slope_ok(a: Vector2, b: Vector2, fl: int, lift: float = 0.0) -> bool:
	if fl > 0:
		return true
	var dh := stand_z(b.x, b.y, 0) - stand_z(a.x, a.y, 0)
	if dh <= 0.0:
		return true
	if not plat.is_empty() and dh <= STEP and (plat.has(Vector2i(int(floor(a.x)), int(floor(a.y)))) or plat.has(Vector2i(int(floor(b.x)), int(floor(b.y))))):
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
		if tree_hit(p, 0.02) or car_hit(p, -0.1) or tile(p.x, p.y) == ROCK:
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

const ACTOR_R := {"brute": 0.35, "shellback": 0.38, "rat": 0.18}

## Where an actor of radius r placed at p should really stand: p itself if free, else the nearest
## free spot within maxr tiles in the same building (or outside, if it started outside). INF = nowhere.
func settle_pos(p: Vector2, r: float, fl: int = 0, outdoor_only: bool = false, maxr: float = 2.0) -> Vector2:
	var bid := building_at(p.x, p.y)
	var ok := func(q: Vector2) -> bool:
		if not can_stand(q, r, fl): return false
		if building_at(q.x, q.y) != bid: return false
		return not outdoor_only or _clear_of_buildings(q, r + 0.3)
	if ok.call(p): return p
	var ring := 0.25
	while ring <= maxr:
		var n := maxi(8, int(ring * 16))
		for k in n:
			var q := p + Vector2.from_angle(k * TAU / n) * ring
			if ok.call(q): return q
		ring += 0.25
	return Vector2.INF

## Livestock and crows start (and keep their home) outdoors on open ground; settlers on standable ground.
func _fix_critters(from: int = 0) -> void:
	for i in range(critters.size() - 1, from - 1, -1):
		var cr: Dictionary = critters[i]
		var outdoor: bool = cr.type in ["cattle", "crow"]
		var rr := 0.3 if cr.type == "cattle" else 0.25
		var sq := settle_pos(cr.pos, rr, 0, outdoor, 5.0)
		if sq == Vector2.INF and cr.has("home"): sq = settle_pos(cr.home, rr, 0, outdoor, 5.0)   # e.g. a guard post out on the water
		if sq == Vector2.INF:
			if cr.type != "trader": critters.remove_at(i)
			continue
		cr.pos = sq
		if cr.has("home") and not can_stand(cr.home, rr, 0): cr.home = sq

## Move any spawn that landed inside a wall, furniture, tree or wreck to the nearest spot it can stand on.
func _fix_spawns(from: int = 0) -> void:
	for i in range(spawns.size() - 1, from - 1, -1):
		var sp: Dictionary = spawns[i]
		var q := settle_pos(sp.pos, ACTOR_R.get(sp.type, 0.25), sp.get("fl", 0))
		if q == Vector2.INF: spawns.remove_at(i)
		else: sp.pos = q

# ------------------------------------------------------------------ roads
static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func add_decor(name: String, p: Vector2, solid: bool = false, half: Vector2 = Vector2(0.2, 0.2), flat: bool = false) -> Decor:
	var d := Decor.new()
	d.name = name; d.pos = p; d.solid = solid; d.half = half; d.flat = flat
	d.bid = building_at(p.x, p.y)
	if solid and reserved(p, -3.0): return d     # keep the camp's inner 5 tiles clear (not added)
	if solid and gen_rect.size.x > 0.0 and not gen_rect.grow(-d.half.x).has_point(p): return d
	decor.append(d)
	if solid:
		var k := int(floor(p.y)) * N + int(floor(p.x))
		if not decor_grid.has(k): decor_grid[k] = []
		decor_grid[k].append(d)
	return d

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
		return not door_grid.has(int(p.y) * N + int(p.x))
	return false

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
	if kind != "canopy":
		# needs at least one wall with dry ground outside for the door
		var dry := false
		for c in cells:
			for o in DIRS:
				var nb: Vector2i = c + o
				if cells.has(nb) or not in_bounds(nb.x, nb.y): continue
				var t := T[idx(nb.x, nb.y)]
				if t != WATER and t != ROCK and t != FLOOR and biome(nb.x, nb.y) != B_WATER: dry = true; break
			if dry: break
		if not dry: return null
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
			if t == WATER or t == ROCK or biome(nb.x, nb.y) == B_WATER: continue   # never a door onto water
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
	if not skip_reach: _fix_reach(b)
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
	if gen_rect.size.x > 0.0 and not gen_rect.encloses(Rect2(bb)): return false
	if reserve_r > 0.0:
		var nearest := start.clamp(Vector2(bb.position), Vector2(bb.end))
		if nearest.distance_to(start) < reserve_r: return false
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

## Walkable sample points (half-tile grid) reachable on floor fl from the door (ground) or the
## stairs (upper floors), for something the player's size.
const PR := 0.28
func reach_map(b: Bld, fl: int) -> Dictionary:
	var start := Vector2(b.door_in) + Vector2(0.5, 0.5) if fl == 0 else Vector2(b.stairs) + Vector2(0.5, 0.5)
	if fl > 0 and b.stairs.x < 0: return {}
	var key := func(q: Vector2) -> Vector2i: return Vector2i(int(round(q.x * 2.0)), int(round(q.y * 2.0)))
	var ok := func(q: Vector2) -> bool:
		var c := Vector2i(int(floor(q.x)), int(floor(q.y)))
		if not b.cells.has(c) or b.cells[c] <= fl or (fl > 0 and b.holes.has(c)): return false
		return not wall_hit(q, PR, fl) and not furn_hit(q, PR, fl)
	var seen := {}
	var q0: Vector2 = start
	if not ok.call(q0):
		var found := false
		for o in [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5), Vector2(0.25, 0.25), Vector2(-0.25, -0.25)]:
			if ok.call(start + o): q0 = start + o; found = true; break
		if not found: return {}
	var todo := [q0]
	seen[key.call(q0)] = q0
	while todo.size():
		var q: Vector2 = todo.pop_back()
		for o in [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
			var n: Vector2 = q + o
			var k: Vector2i = key.call(n)
			if seen.has(k): continue
			if ok.call(n) and ok.call(q + o * 0.5):
				seen[k] = n
				todo.append(n)
	return seen

## What can't be reached in a building: floor tiles with room to stand that you can't get to,
## loot furniture you can't get within reach of, and the stairs. [{what, fl, at, furn?}]
func reach_problems(b: Bld) -> Array:
	var out := []
	if b.sealed or b.kind == "canopy": return out
	for fl in b.floors:
		var seen := reach_map(b, fl)
		if seen.is_empty():
			if fl == 0 or b.stairs.x >= 0: out.append({"what": "entrance", "fl": fl, "at": Vector2(b.door_in if fl == 0 else b.stairs)})
			continue
		var got := {}
		for k in seen: got[Vector2i(int(floor(seen[k].x)), int(floor(seen[k].y)))] = true
		for c in b.cells:
			if b.cells[c] <= fl or (fl > 0 and b.holes.has(c)) or got.has(c): continue
			# only count tiles where you could stand at all
			var room := false
			for o in [Vector2(0.5, 0.5), Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.3, 0.7), Vector2(0.7, 0.3)]:
				var q: Vector2 = Vector2(c) + o
				if not wall_hit(q, PR, fl) and not furn_hit(q, PR, fl): room = true; break
			if room: out.append({"what": "tile", "fl": fl, "at": Vector2(c) + Vector2(0.5, 0.5)})
		if fl == 0 and b.stairs.x >= 0 and b.floors > 1:
			var sc := Vector2(b.stairs) + Vector2(0.5, 0.5)
			var near := false
			for k in seen:
				if seen[k].distance_to(sc) < 0.8: near = true; break
			if not near: out.append({"what": "stairs", "fl": 0, "at": sc})
		for f in b.furn:
			if f.fl != fl or f.crate == null: continue
			var near := false
			for k in seen:
				if seen[k].distance_to(f.pos) < 1.1: near = true; break
			if not near: out.append({"what": "loot", "fl": fl, "at": f.pos, "furn": f})
	return out

## Furniture must never wall off part of a building: remove the piece blocking the way, nearest
## first, until everything (floor, stairs, loot) can be reached from the door. Cheap: a few
## small flood fills per building, at generation time.
func _fix_reach(b: Bld) -> void:
	for it in 40:
		var probs := reach_problems(b)
		if probs.is_empty(): return
		var pr: Dictionary = probs[0]
		var seen := reach_map(b, pr.fl)
		if pr.fl > 0 and _patch_hole(b, pr, seen): continue
		# the piece between the reachable area and the problem: closest to the problem among those
		# touching the reachable area (or anything at all if nothing is reachable yet)
		var best: Furn = null
		var bd := 1e9
		for f in b.furn:
			if f.fl != pr.fl or f == pr.get("furn"): continue
			var touches := seen.is_empty()
			if not touches:
				for k in seen:
					if seen[k].distance_to(f.pos) < maxf(f.half.x, f.half.y) + PR + 0.55: touches = true; break
			if not touches: continue
			var d: float = f.pos.distance_to(pr.at)
			if d < bd: bd = d; best = f
		if best == null:
			if pr.has("furn"): _drop_furn(b, pr.furn)   # loot nobody can reach: take it away
			elif pr.what == "tile" and pr.fl > 0:
				b.holes[Vector2i(int(floor(pr.at.x)), int(floor(pr.at.y)))] = true   # a cut-off scrap of floor: let it fall in
			else: return
		else:
			_drop_furn(b, best)

## Upper floors cut into islands by ruin holes: floor over the hole cell that joins the reachable
## part to the stranded part (nearest the problem).
func _patch_hole(b: Bld, pr: Dictionary, seen: Dictionary) -> bool:
	if seen.is_empty(): return false
	var got := {}
	for k in seen: got[Vector2i(int(floor(seen[k].x)), int(floor(seen[k].y)))] = true
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for h in b.holes:
		if b.cells.get(h, 0) <= pr.fl: continue
		var touches := false
		for o in DIRS:
			if got.has(h + o): touches = true; break
		if not touches: continue
		var d: float = (Vector2(h) + Vector2(0.5, 0.5)).distance_to(pr.at)
		if d < bd: bd = d; best = h
	if best.x < 0 or bd > 6.0: return false
	b.holes.erase(best)
	return true

func _drop_furn(b: Bld, f: Furn) -> void:
	b.furn.erase(f)
	if f.crate != null: crates.erase(f.crate)

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

# ------------------------------------------------------------------ streamed world
## The Sable Wastes is one 2048x2048-tile world made from the world-map data (height, biome, city
## density and road polylines at one pixel per tile). Nothing is generated up front: a chunk gets its
## base (terrain, water, roads) the first time something near it is needed, and its content (towns,
## buildings, props, people) once its neighbours have a base. Content only ever touches its own chunk
## plus a small margin, so a chunk whose ring of neighbours has content is final and can be shown.

const BIOMES := ["waste", "hills", "woods", "farm", "salt", "marsh", "canyon", "crater", "city", "suburb", "water", "gorge", "peak", "beach"]
const B_WASTE := 0
const B_HILLS := 1
const B_WOODS := 2
const B_FARM := 3
const B_SALT := 4
const B_MARSH := 5
const B_CANYON := 6
const B_CRATER := 7
const B_CITY := 8
const B_SUBURB := 9
const B_WATER := 10
const B_GORGE := 11
const B_PEAK := 12
const B_BEACH := 13
const ROAD_W := {"interstate": 2.1, "highway": 1.55, "road": 1.15, "track": 0.75}
const GRID := 13                 # city street grid spacing (tiles)

var data: WorldData
var hraw := PackedByteArray()
var braw := PackedByteArray()
var hmin := 0.0
var hmax := 1.0
var VH_W := 16.0                 # water surface height (px)
var base_done := PackedByteArray()
var content_done := PackedByteArray()
var road_pts := {}               # chunk key -> PackedInt32Array of path_index * 65536 + point index
var road_h := PackedFloat32Array()
var locs: Array = []             # world-map locations: {id, name, type, hook, pos (tiles), r, done, rect}
var items := {}                  # chunk key -> {buildings, decor, cars, crates, spawns, critters, poles, posts, flags, ropes, survivors, lights}
var car_grid := {}               # tile index -> Array[Car]
var door_grid := {}              # tile index -> true (outside tile of a door, and its neighbours)
var discovered := {}             # location id -> true
var opened := {}                 # crate position key -> true (survives a reload)
var killed := {}                 # spawn key -> true
var cleared := {}                # location id -> true
var _mark := {}

static func pkey(p: Vector2) -> String:
	return "%d,%d" % [int(p.x * 4.0), int(p.y * 4.0)]

static func ckey(cx: int, cy: int) -> int:
	return cy * NC + cx

static func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x) / CH, 0, NC - 1), clampi(int(p.y) / CH, 0, NC - 1))

func hn(x: int, y: int) -> float:
	if interior: return 0.0
	var i := clampi(y, 0, N - 1) * N + clampi(x, 0, N - 1)
	return hraw.decode_u16(i * 2) / 65535.0 * (hmax - hmin) + hmin

func biome(x: int, y: int) -> int:
	if interior: return B_WASTE
	return braw[(clampi(y, 0, N - 1) * N + clampi(x, 0, N - 1)) * 4]

func density(x: int, y: int) -> int:
	if interior: return 0
	return braw[(clampi(y, 0, N - 1) * N + clampi(x, 0, N - 1)) * 4 + 1]

func biome_name(p: Vector2) -> String:
	return BIOMES[biome(int(p.x), int(p.y))]

func load_data(sd: int, start_id: String = "patchwork") -> void:
	seed_value = sd
	rng.seed = sd
	data = load("res://assets/worldmap/data/world_data.res")
	hraw = data.height
	braw = data.biome
	var m: Dictionary = data.meta
	hmin = float(m.hmin)
	hmax = float(m.hmax)
	VH_W = (float(m.water_level) - hmin) * HS
	T.resize(N * N); T.fill(GRASS)
	BID.resize(N * N); BID.fill(0)
	V.resize(N * N); V.fill(0)
	G.resize(N * N); G.fill(0)
	CL.resize(N * N); CL.fill(0)
	VH.resize(NV * NV); VH.fill(0.0)
	road_d.resize(NV * NV); road_d.fill(99.0)
	road_h.resize(NV * NV); road_h.fill(0.0)
	base_done.resize(NC * NC); base_done.fill(0)
	content_done.resize(NC * NC); content_done.fill(0)
	_prep_roads(m.roads)
	_prep_locations()
	var sl := loc_by_id(start_id)
	if sl.is_empty(): sl = loc_by_id("patchwork")
	# home camp: on open, standable ground just outside town, preferring the side nearest a road
	var best := Vector2(sl.pos) + Vector2(-sl.r - 12.0, 9.5)
	var bs := -1e9
	for k in 24:
		var q: Vector2 = sl.pos + Vector2.from_angle(k * TAU / 24.0) * (sl.r + 12.0)
		var ck := chunk_of(q)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				ensure_base(ck.x + ox, ck.y + oy)
		var i := idx(int(q.x), int(q.y))
		if (T[i] != GRASS and T[i] != SIDE) or biome(int(q.x), int(q.y)) in [B_WATER, B_GORGE, B_PEAK]: continue
		var score := -absf(hz(q.x, q.y) - hz(q.x + 3, q.y + 3)) - absf(hz(q.x, q.y) - hz(q.x - 3, q.y + 2))
		if not _clear_of_buildings(q, 4.5): score -= 50.0
		if _road_near(q, 8.0) != Vector2.ZERO: score += 20.0
		if score > bs: bs = score; best = q
	start = Vector2(floor(best.x) + 0.5, floor(best.y) + 0.5)
	reserve_r = 8.0
	ensure_content(chunk_of(start).x, chunk_of(start).y)

## Inside the home camp's clear zone (Review 2: a gas station once generated on top of it).
func reserved(p: Vector2, pad: float = 0.0) -> bool:
	return reserve_r > 0.0 and p.distance_to(start) < reserve_r + pad

## Road polylines become dense point lists with a height profile: smoothed along the road, and carried
## level over water and gorges as a causeway.
func _prep_roads(roads: Array) -> void:
	paths.clear()
	for r in roads:
		var kind: String = r.kind
		var ctrl := []
		for q in r.path:
			ctrl.append(Vector2(q[0], q[1]))
		if ctrl.size() < 2: continue
		var c := [ctrl[0]] + ctrl + [ctrl[-1]]
		var pts := PackedVector2Array()
		for i in range(1, c.size() - 2):
			var n := maxi(1, int(c[i].distance_to(c[i + 1]) * 3.0))
			for k in n:
				pts.append(_catmull(c[i - 1], c[i], c[i + 1], c[i + 2], float(k) / n))
		pts.append(ctrl[-1])
		var hs := PackedFloat32Array()
		var wet := []
		for p in pts:
			var b := biome(int(p.x), int(p.y))
			var h := hn(int(p.x), int(p.y))
			var w: bool = b == B_WATER or b == B_GORGE or h < 0.004
			wet.append(w)
			hs.append(h)
		# bridges: interpolate across wet runs between the dry ends
		var i := 0
		while i < pts.size():
			if not wet[i]: i += 1; continue
			var j := i
			while j < pts.size() and wet[j]: j += 1
			var ha: float = hs[i - 1] if i > 0 else (hs[j] if j < pts.size() else 0.01)
			var hb: float = hs[j] if j < pts.size() else ha
			for k in range(i, j):
				var t := float(k - i + 1) / (j - i + 1)
				hs[k] = maxf(lerpf(ha, hb, t), 0.012)
			i = j
		# smooth the profile
		var sm := PackedFloat32Array()
		sm.resize(hs.size())
		for k in hs.size():
			var s := 0.0
			var n := 0
			for o in range(-8, 9):
				var q := clampi(k + o, 0, hs.size() - 1)
				s += hs[q]; n += 1
			sm[k] = s / n
		var pi := paths.size()
		paths.append({"pts": pts, "w": ROAD_W.get(kind, 1.0), "kind": "dirt" if kind == "track" else kind, "h": sm})
		var last := -1
		for k in pts.size():
			var ck := chunk_of(pts[k])
			var key := ckey(ck.x, ck.y)
			if not road_pts.has(key): road_pts[key] = PackedInt32Array()
			road_pts[key].append(pi * 65536 + k)

func _prep_locations() -> void:
	locs.clear()
	var f := FileAccess.open("res://assets/worldmap/locations.json", FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	for l in d.locations:
		var p := Vector2(l.px[0] + 0.5, l.px[1] + 0.5)
		var r: float = clampf(float(l.size) * 0.11, 7.0, 21.0)
		var e := {"id": l.id, "name": l.name, "type": l.type, "hook": l.hook, "pos": p, "r": r, "done": false,
			"danger": int(l.get("danger", 1)), "faction": l.get("faction", ""), "trade": l.get("trade", ""), "biome": l.get("biome", "")}
		var m := r + 14.0
		e.rect = Rect2(p - Vector2(m, m), Vector2(m, m) * 2.0)
		locs.append(e)

func loc_by_id(id: String) -> Dictionary:
	for l in locs:
		if l.id == id: return l
	return {}

func nearest_loc(p: Vector2, extra: float = 0.0) -> Dictionary:
	var best := {}
	var bd := 1e9
	for l in locs:
		var d: float = p.distance_to(l.pos) - l.r - extra
		if d < bd: bd = d; best = l
	return best if bd < 0.0 else {}

func chunk_rect(cx: int, cy: int) -> Rect2i:
	return Rect2i(cx * CH, cy * CH, CH, CH)

# ---------------------------------------------------------------- base
func _vert_h(vx: int, vy: int) -> float:
	var s := 0.0
	var wet := false
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var x: int = clampi(vx + o.x, 0, N - 1)
		var y: int = clampi(vy + o.y, 0, N - 1)
		if braw[(y * N + x) * 4] == B_WATER: wet = true
		s += hn(x, y)
	if wet: return VH_W
	var h := (s * 0.25 - hmin) * HS
	# ease banks down to the water so shores slope gently instead of stepping off a ledge
	var near := 9.0
	for oy in range(-3, 3):
		for ox in range(-3, 3):
			var x: int = clampi(vx + ox, 0, N - 1)
			var y: int = clampi(vy + oy, 0, N - 1)
			if braw[(y * N + x) * 4] == B_WATER:
				near = minf(near, Vector2(ox + 0.5, oy + 0.5).length())
	if near < 3.5:
		h = lerpf(VH_W + 1.0, h, sstep((near - 0.7) / 2.8))
	return h

func _ground_for(b: int, x: int, y: int) -> int:
	var n := sin(x * 0.37 + seed_value) + sin(y * 0.29 - seed_value * 0.7) + sin((x + y) * 0.17 + 3.0)
	var r := rng.randf()
	match b:
		B_WASTE: return 2 if n < -1.1 else (1 if n > 0.2 else (3 if r < 0.04 else 0))
		B_HILLS: return 1 if n > 0.6 else (4 if n < -1.5 else 0)
		B_WOODS: return 11 if n > -0.4 else 0
		B_FARM: return 9 if n > -0.8 else 1
		B_SALT: return 5 if n > -1.6 else 2
		B_MARSH: return 7 if n > -0.3 else 0
		B_CANYON, B_GORGE: return 6 if n > -0.9 else 12
		B_CRATER: return 8 if n > 0.0 else 2
		B_CITY: return 13 if n > -0.6 else 2
		B_SUBURB: return 0 if n > -0.6 else 1
		B_PEAK: return 4 if n > -0.4 else 6
		B_BEACH: return 10
	return 0

func ensure_base(cx: int, cy: int) -> void:
	if cx < 0 or cy < 0 or cx >= NC or cy >= NC: return
	var key := ckey(cx, cy)
	if base_done[key]: return
	base_done[key] = 1
	rng.seed = hash(key * 7919 + seed_value)
	var x0 := cx * CH
	var y0 := cy * CH
	for y in range(y0, y0 + CH):
		for x in range(x0, x0 + CH):
			var i := y * N + x
			var b := braw[i * 4]
			T[i] = WATER if b == B_WATER else GRASS
			V[i] = rng.randi_range(0, 3)
			G[i] = _ground_for(b, x, y)
	var vx1 := x0 + CH + (1 if cx == NC - 1 else 0)
	var vy1 := y0 + CH + (1 if cy == NC - 1 else 0)
	for vy in range(y0, vy1):
		for vx in range(x0, vx1):
			VH[vy * NV + vx] = _vert_h(vx, vy)
			road_d[vy * NV + vx] = 99.0
	# roads from points in this chunk and its neighbours
	var rect := Rect2i(x0, y0, CH, CH)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var lst = road_pts.get(ckey(cx + ox, cy + oy))
			if lst == null or cx + ox < 0 or cy + oy < 0 or cx + ox >= NC or cy + oy >= NC: continue
			for e in lst:
				var pth: Dictionary = paths[e >> 16]
				var k: int = e & 65535
				var p: Vector2 = pth.pts[k]
				var w: float = pth.w
				var hh: float = (pth.h[k] - hmin) * HS
				var dirt: bool = pth.kind == "dirt"
				for yy in range(maxi(int(floor(p.y - w - 1)), y0), mini(int(p.y + w + 2), y0 + CH)):
					for xx in range(maxi(int(floor(p.x - w - 1)), x0), mini(int(p.x + w + 2), x0 + CH)):
						if p.distance_to(Vector2(xx + 0.5, yy + 0.5)) <= w:
							var i := yy * N + xx
							if dirt:
								if T[i] == GRASS or T[i] == WATER: T[i] = DIRT_ROAD
							else:
								T[i] = ROAD
				var R := w + 5.0
				for vy in range(maxi(int(floor(p.y - R)), y0), mini(int(p.y + R + 1), vy1)):
					for vx in range(maxi(int(floor(p.x - R)), x0), mini(int(p.x + R + 1), vx1)):
						var dv := p.distance_to(Vector2(vx, vy)) - w
						var vi := vy * NV + vx
						if dv < road_d[vi]:
							road_d[vi] = dv
							road_h[vi] = hh
	for vy in range(y0, vy1):
		for vx in range(x0, vx1):
			var vi := vy * NV + vx
			var d := road_d[vi]
			if d < 6.0:
				VH[vi] = lerpf(road_h[vi], VH[vi], sstep((d - 0.4) / 4.5))
	# city street grid and sidewalks
	for y in range(y0, y0 + CH):
		for x in range(x0, x0 + CH):
			var i := y * N + x
			var dn := braw[i * 4 + 1]
			var b := braw[i * 4]
			if T[i] == WATER or (b != B_CITY and b != B_SUBURB): continue
			var gx := posmod(x, GRID)
			var gy := posmod(y, GRID)
			var lim := 150 if (gx < 2 and gy < 2) else 175
			if (gx < 2 or gy < 2) and dn > (120 if b == B_CITY else lim) and T[i] == GRASS:
				T[i] = ROAD
				G[i] = 0
	for y in range(y0, y0 + CH):
		for x in range(x0, x0 + CH):
			var i := y * N + x
			if T[i] != GRASS or braw[i * 4 + 1] < 90: continue
			var gx := posmod(x, GRID)
			var gy := posmod(y, GRID)
			var near := (gx == 2 or gy == 2 or gx == GRID - 1 or gy == GRID - 1) and _grid_road_near(x, y)
			if near or minf(minf(road_d[y * NV + x], road_d[y * NV + x + 1]), minf(road_d[(y + 1) * NV + x], road_d[(y + 1) * NV + x + 1])) < 0.9:
				T[i] = SIDE

func _grid_road_near(x: int, y: int) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var xx: int = x + o.x
		var yy: int = y + o.y
		if xx < 0 or yy < 0 or xx >= N or yy >= N: continue
		var gx := posmod(xx, GRID)
		var gy := posmod(yy, GRID)
		var i := yy * N + xx
		if (gx < 2 or gy < 2) and T[i] == ROAD: return true
	return false

# ---------------------------------------------------------------- content
## Items of one kind in the 3x3 chunks around p (for interaction queries).
func near(p: Vector2, kind: String) -> Array:
	var c := chunk_of(p)
	var out := []
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var bk = items.get(ckey(c.x + ox, c.y + oy))
			if bk != null: out.append_array(bk[kind])
	return out

func _bucket(key: int) -> Dictionary:
	if not items.has(key):
		items[key] = {"buildings": [], "decor": [], "cars": [], "crates": [], "spawns": [], "critters": [], "poles": [], "posts": [], "flags": [], "ropes": [], "survivors": []}
	return items[key]

func _begin() -> void:
	_mark = {"buildings": buildings.size(), "decor": decor.size(), "cars": cars.size(), "crates": crates.size(), "spawns": spawns.size(),
		"critters": critters.size(), "poles": pole_lines.size(), "posts": posts.size(), "flags": raider_flags.size(), "ropes": ropes.size(), "survivors": survivors.size()}

func _finish() -> void:
	if gen_rect.size.x > 0.0:
		# loose items a chunk made must stay inside it too (see gen_rect)
		var gr := gen_rect.grow(1.0)
		for nm in ["crates", "spawns", "critters", "survivors"]:
			var arr: Array = {"crates": crates, "spawns": spawns, "critters": critters, "survivors": survivors}[nm]
			for i in range(arr.size() - 1, _mark[nm] - 1, -1):
				if not gr.has_point(arr[i].pos): arr.remove_at(i)
	_tidy_new()
	var lists := {"buildings": buildings, "decor": decor, "cars": cars, "crates": crates, "spawns": spawns, "critters": critters,
		"poles": pole_lines, "posts": posts, "flags": raider_flags, "ropes": ropes, "survivors": survivors}
	for nm in lists:
		var arr: Array = lists[nm]
		for i in range(_mark[nm], arr.size()):
			var it = arr[i]
			var p: Vector2
			match nm:
				"buildings": p = Vector2(it.x0 + it.w * 0.5, it.y0 + it.h * 0.5)
				"poles": p = it[0]
				"posts", "flags": p = it
				"ropes": p = it.bottom
				"spawns", "critters", "survivors": p = it.pos
				_: p = it.pos
			var ck := chunk_of(p)
			var key := ckey(ck.x, ck.y)
			_bucket(key)[nm].append(it)
			if nm == "spawns" or nm == "critters": it["chunk"] = key
			if nm == "spawns":
				it["key"] = it.type + pkey(it.pos)
				if killed.has(it.key): it["dead"] = true
			elif nm == "crates" and opened.has(pkey(it.pos)):
				it.open = true
	for b in buildings.slice(_mark.buildings):
		if b.door_seg != null:
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					door_grid[(b.out.y + oy) * N + b.out.x + ox] = true

func ensure_content(cx: int, cy: int) -> void:
	if cx < 0 or cy < 0 or cx >= NC or cy >= NC: return
	var key := ckey(cx, cy)
	if content_done[key]: return
	content_done[key] = 1
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			ensure_base(cx + ox, cy + oy)
	var rect := Rect2(cx * CH, cy * CH, CH, CH)
	# named places reach a little past their rect (levelled yards, fences): build any that come
	# near this chunk first, so the chunk always sees them
	for l in locs:
		if not l.done and l.rect.grow(10.0).intersects(rect):
			_gen_location(l)
	var base_seed := hash(key * 104729 + seed_value * 31)
	_begin()
	var r := chunk_rect(cx, cy)
	gen_rect = Rect2(r.position + Vector2i(2, 2), r.size - Vector2i(4, 4))
	var dmax := 0
	for k in 9:
		dmax = maxi(dmax, density(r.position.x + 4 + (k % 3) * 12, r.position.y + 4 + (k / 3) * 12))
	# each step gets its own seed, so one step using more or fewer rolls can't shift the next
	rng.seed = base_seed
	if dmax > 100:
		_chunk_city(r)
	rng.seed = base_seed + 1
	_chunk_roadside(cx, cy, r)
	rng.seed = base_seed + 2
	if dmax < 60 and nearest_loc(Vector2(r.get_center()), 30.0).is_empty():
		_chunk_poi(cx, cy, r)
	rng.seed = base_seed + 3
	_chunk_trees(r)
	rng.seed = base_seed + 4
	_chunk_cars(cx, cy, r)
	rng.seed = base_seed + 5
	_chunk_debris(cx, cy, r)
	rng.seed = base_seed + 6
	_chunk_creatures(r)
	rng.seed = base_seed + 7
	_finish()
	gen_rect = Rect2()

## Everything a chunk needs before it can be shown: content in it and all around it.
func ensure_ready(cx: int, cy: int) -> void:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			ensure_content(cx + ox, cy + oy)

func is_ready(cx: int, cy: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var x := cx + ox
			var y := cy + oy
			if x < 0 or y < 0 or x >= NC or y >= NC: continue
			if not content_done[ckey(x, y)]: return false
	return true

## Shift a building up to `most` tiles so it sits m tiles inside the chunk; [] if it can't.
func _nudge_inside(parts: Array, r: Rect2i, m: int, most: int) -> Array:
	var bb: Rect2i = parts[0]
	for q in parts: bb = bb.merge(q)
	var lo := r.position + Vector2i(m, m)
	var hi := r.end - Vector2i(m + 1, m + 1)
	var d := Vector2i(maxi(0, lo.x - bb.position.x) - maxi(0, bb.end.x - hi.x), maxi(0, lo.y - bb.position.y) - maxi(0, bb.end.y - hi.y))
	if absi(d.x) > most or absi(d.y) > most: return []
	var out := []
	for q in parts: out.append(Rect2i(q.position + d, q.size))
	return out if _inside(out, r, m) else []

func _inside(parts: Array, r: Rect2i, m: int = 1) -> bool:
	var bb: Rect2i = parts[0]
	for q in parts: bb = bb.merge(q)
	return bb.position.x >= r.position.x + m and bb.position.y >= r.position.y + m and bb.end.x <= r.end.x - m - 1 and bb.end.y <= r.end.y - m - 1

## Fisher-Yates with the seeded rng. Array.shuffle() uses Godot's global
## random generator, which made the city different on every load.
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

## Port Sterling and its suburbs: a block on every grid cell, the kind of building set by density.
func _chunk_city(r: Rect2i) -> void:
	var lots := []
	for y in range(r.position.y + 2, r.end.y - 3):
		for x in range(r.position.x + 2, r.end.x - 3):
			var gx := posmod(x, GRID)
			var gy := posmod(y, GRID)
			if (gx == 3 or gx == 7 or gx == 10) and (gy == 3 or gy == 7 or gy == 10):
				lots.append(Vector2i(x, y))
	_shuffle(lots)
	for lot in lots:
		var d := density(lot.x + 2, lot.y + 2)
		var b := biome(lot.x + 2, lot.y + 2)
		if d < 60 or T[idx(lot.x, lot.y)] != GRASS and T[idx(lot.x, lot.y)] != SIDE: continue
		if b == B_WATER: continue
		var kind := "house"
		var q := rng.randf()
		if d > 200:
			kind = ["office", "office", "shop", "factory", "motel", "diner", "shop"][ri(0, 6)]
		elif d > 150:
			kind = ["shop", "office", "house", "garage", "diner", "factory"][ri(0, 5)]
		elif d > 100:
			kind = "house" if q < 0.7 else ["garage", "shop"][ri(0, 1)]
		else:
			if q < 0.25: continue
			kind = "house" if q < 0.9 else "garage"
		var parts := shape_for(kind, lot.x, lot.y)
		# stay 2 tiles inside the chunk: placing a building reads tiles 1 beyond it and levels the
		# ground 1-2 beyond it, so this keeps chunks from depending on which neighbour loaded first
		parts = _nudge_inside(parts, r, 2, 4)
		if parts.is_empty(): continue
		place_shape(parts, kind)

## Houses strung along roads where density is light, and roadside stops (gas, diner, motel) along
## the big roads out in the wastes.
func _chunk_roadside(cx: int, cy: int, r: Rect2i) -> void:
	var lst = road_pts.get(ckey(cx, cy))
	if lst == null: return
	var tries := 0
	for e in lst:
		tries += 1
		if tries % 7 != 0: continue
		var pth: Dictionary = paths[e >> 16]
		if pth.kind == "dirt": continue
		var k: int = e & 65535
		var pts: PackedVector2Array = pth.pts
		var p: Vector2 = pts[k]
		var d := density(int(p.x), int(p.y))
		var chance := 0.0
		var kind := "house"
		if d > 25: chance = 0.25 + d / 600.0
		elif pth.kind != "road" and rng.randf() < 0.035:
			chance = 1.0
			kind = ["gas", "diner", "motel", "gas", "garage"][ri(0, 4)]
		elif rng.randf() < 0.025:
			chance = 1.0
			kind = "house" if rng.randf() < 0.7 else "garage"
		if rng.randf() > chance: continue
		var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var off: float = pth.w + rf(1.6, 3.2)
		var at := p + dir.orthogonal() * side * (off + 2.5)
		var parts := _nudge_inside(shape_for(kind, int(at.x) - 2, int(at.y) - 2), r, 2, 3)
		if parts.is_empty(): continue
		place_shape(parts, kind)

# ---------------------------------------------------------------- towns and sites
const TOWN_NAMES_SMALL := ["Survivor camp", "Drifter camp", "Scav camp", "Wayfarers' fire", "Road camp"]

func _flatten(c: Vector2, r: float, h0: float, clear: bool) -> void:
	for vy in range(int(c.y - r - 4), int(c.y + r + 5)):
		for vx in range(int(c.x - r - 4), int(c.x + r + 5)):
			if gen_rect.size.x > 0.0 and not gen_rect.grow(1.0).has_point(Vector2(vx, vy)): continue
			var d := Vector2(vx, vy).distance_to(c)
			set_vh(vx, vy, lerpf(vh(vx, vy), h0, sstep(1.0 - (d - r) / 4.0)))
	if clear:
		for y in range(int(c.y - r), int(c.y + r + 1)):
			for x in range(int(c.x - r), int(c.x + r + 1)):
				if in_bounds(x, y) and Vector2(x + 0.5, y + 0.5).distance_to(c) < r:
					CL[idx(x, y)] = 1

func _gen_location(l: Dictionary) -> void:
	# places close to each other are always built in list order, whichever is reached first
	var saved := gen_rect
	gen_rect = Rect2()
	for o in locs:
		if o == l: break
		if not o.done and o.rect.grow(10.0).intersects(l.rect.grow(10.0)):
			_gen_location(o)
	_gen_location_raw(l)
	gen_rect = saved

func _gen_location_raw(l: Dictionary) -> void:
	if l.done: return
	l.done = true
	var rr: Rect2 = l.rect
	var c0 := chunk_of(rr.position)
	var c1 := chunk_of(rr.end)
	for cy in range(c0.y - 1, c1.y + 2):
		for cx in range(c0.x - 1, c1.x + 2):
			ensure_base(cx, cy)
	rng.seed = hash(str(l.id)) + seed_value
	if cleared.has(l.id): l.cleared = true
	_begin()
	match l.type:
		"town", "hub", "settlement", "camp":
			if l.id == "rattlebone_camp" or l.faction == "Raiders":
				_raider_town(l)
			else:
				_town(l)
		"dungeon":
			var s0 := spawns.size()
			_dungeon(l)
			for i in range(s0, spawns.size()): spawns[i]["loc"] = l.id
		"landmark":
			_landmark(l)
		_:
			pass      # Port Sterling's districts are built block by block from the density map
	_finish()

## A friendly town: a yard flattened around a well or fire, shacks and a few real buildings around it,
## a scrap fence ring with gaps for the roads, traders, settlers and livestock, and whatever the town
## is known for (water purifiers by the lake, fields in the marsh, salt pans, glass furnaces...).
func _town(l: Dictionary) -> void:
	var c: Vector2 = l.pos
	var r: float = l.r
	var h0 := hz(c.x, c.y)
	# don't drown the yard: lake towns sit on the shore, the centre nudged onto dry ground
	if T[idx(int(c.x), int(c.y))] == WATER or tile(c.x, c.y) == ROAD:
		for ring in range(1, 30):
			var moved := false
			for k in 16:
				var q := c + Vector2.from_angle(k * TAU / 16.0) * ring
				if in_bounds(int(q.x), int(q.y)) and T[idx(int(q.x), int(q.y))] == GRASS:
					c = q; moved = true; break
			if moved: break
		h0 = hz(c.x, c.y)
	l.pos = c
	_flatten(c, r * 0.8, h0, true)
	var st := Settlement.new()
	st.name = l.name
	st.pos = c
	st.radius = r
	st.id = l.id
	st.hook = l.hook
	settlements.append(st)
	var si := settlements.size() - 1
	for y in range(int(c.y - r), int(c.y + r + 1)):
		for x in range(int(c.x - r), int(c.x + r + 1)):
			if in_bounds(x, y) and Vector2(x + 0.5, y + 0.5).distance_to(c) < r * 0.75 and T[idx(x, y)] == GRASS:
				G[idx(x, y)] = 2 if rng.randf() < 0.7 else 0
	add_decor("campfire_decor", c, true, Vector2(0.25, 0.25))
	st.trader = c + Vector2(1.6, 0.4)
	add_decor("stall", st.trader + Vector2(0, -0.6), true, Vector2(0.5, 0.2))
	critters.append({"type": "trader", "pos": st.trader, "home": st.trader, "settlement": si})
	# rings of shacks, then proper buildings further out, doors toward the middle
	var n_shacks := int(r * 0.55) + 2
	var a0 := rf(0, TAU)
	var placed := 0
	for ring: float in [0.42, 0.68]:
		var count := n_shacks if ring < 0.5 else int(n_shacks * 1.3)
		for k in count:
			var a := a0 + k * TAU / count + rf(-0.2, 0.2) + ring * 2.0
			var p := c + Vector2.from_angle(a) * r * ring
			var dv := c - p
			var side := (3 if dv.x > 0 else 2) if absf(dv.x) > absf(dv.y) else (1 if dv.y > 0 else 0)
			var kind := "shack"
			if ring > 0.5 and rng.randf() < 0.35: kind = ["house", "garage", "shop"][ri(0, 2)]
			var w := ri(3, 4)
			var h := ri(3, 4)
			var b: Bld
			if kind == "shack":
				b = place_building(int(round(p.x - w * 0.5)), int(round(p.y - h * 0.5)), w, h, "shack", side, true)
			else:
				b = place_shape(shape_for(kind, int(p.x) - 2, int(p.y) - 2), kind, side, true)
			if b:
				b.settlement = si
				b.ruined = false
				placed += 1
	# second trader for bigger towns
	if r > 15.0:
		var tp := c + Vector2(-2.2, 1.8)
		add_decor("stall", tp + Vector2(0, -0.6), true, Vector2(0.5, 0.2))
		critters.append({"type": "trader", "pos": tp, "home": tp, "settlement": si})
	add_decor("pump", c + Vector2(-1.5, -1.8), true, Vector2(0.15, 0.15))
	# market row: stalls along one side of the yard, busier in bigger towns
	var mdir := Vector2.from_angle(a0 + PI * 0.5)
	for k in int(r / 5.0) + 1:
		var mp := c + mdir * (2.6 + k * 1.7) + mdir.orthogonal() * 1.6
		_try_decor("stall", mp, true, Vector2(0.5, 0.2))
		_try_decor(["barrel", "trashbag", "barrel_rust"][ri(0, 2)], mp + mdir.orthogonal() * 0.9, true, Vector2(0.17, 0.17))
	# lamps around the yard so towns glow at night
	for k in int(r / 3.0) + 2:
		var lp := c + Vector2.from_angle(a0 + k * TAU / (int(r / 3.0) + 2) + 0.3) * r * 0.55
		_try_decor("lamp", lp, true, Vector2(0.08, 0.08))
	# drifters camped at the edge
	for k in ri(1, 3):
		_try_decor("tent", c + Vector2.from_angle(rf(0, TAU)) * r * 0.8, true, Vector2(0.45, 0.45))
	add_decor("tower_decor", c + Vector2.from_angle(a0 + 0.7) * r * 0.85, true, Vector2(0.25, 0.25))
	if r > 12.0: add_decor("tower_decor", c + Vector2.from_angle(a0 + 3.6) * r * 0.85, true, Vector2(0.25, 0.25))
	for k in 6:
		var gp := c + Vector2(-3.6 + (k % 3), 2.4 + int(k / 3))
		add_decor("garden", Vector2(floor(gp.x), floor(gp.y)), false, Vector2.ZERO, true)
	_town_hook(l, c, r, si)
	# fence ring with gaps where roads come in
	var steps := int(r * 2.4)
	for k in steps:
		var a := k * TAU / steps
		var fp := c + Vector2.from_angle(a) * (r * 0.92)
		if not in_bounds(int(fp.x), int(fp.y)): continue
		var t := T[idx(int(fp.x), int(fp.y))]
		if t == ROAD or t == DIRT_ROAD or t == WATER or k % 9 == 4: continue
		add_decor("fence", fp)
	for k in ri(4, 6) + int(r / 4):
		critters.append({"type": "settler", "pos": c + Vector2(rf(-r, r), rf(-r, r)) * 0.4, "home": c, "settlement": si, "look": ri(1, 3)})
	for k in ri(1, 3):
		critters.append({"type": "cattle", "pos": c + Vector2(rf(-r, r) * 0.6, r * 0.55), "home": c + Vector2(0, r * 0.55)})
	# guards
	for k in 2:
		critters.append({"type": "settler", "pos": c + Vector2.from_angle(a0 + k * PI) * r * 0.85, "home": c + Vector2.from_angle(a0 + k * PI) * r * 0.85, "settlement": si, "look": 3})

func _town_hook(l: Dictionary, c: Vector2, r: float, si: int) -> void:
	var hook: String = l.hook
	match hook:
		"lake", "dam":
			# purifiers in a row at the waterline
			var shore := Vector2.ZERO
			var bd := 1e9
			for k in 32:
				var q := c + Vector2.from_angle(k * TAU / 32.0) * r * 1.2
				for s in 8:
					var qq := c.lerp(q, s / 7.0)
					if in_bounds(int(qq.x), int(qq.y)) and T[idx(int(qq.x), int(qq.y))] == WATER:
						var d := qq.distance_to(c)
						if d < bd: bd = d; shore = c.lerp(qq, (d - 1.6) / d)
						break
			if shore == Vector2.ZERO: shore = c + Vector2(r * 0.5, 0)
			var tang := (shore - c).orthogonal().normalized()
			for k in [-2, -1, 0, 1, 2]:
				var tier := "purifier_t3" if k == 0 else ("purifier_t2" if absi(k) == 1 else "purifier_t1")
				_try_decor(tier, shore + tang * k * 1.6, true, Vector2(0.45, 0.45))
			for k in 4:
				_try_decor("barrel", shore + tang * (k - 1.5) * 1.1 - (shore - c).normalized() * 1.4, true, Vector2(0.17, 0.17))
		"wetlands", "farm":
			for k in 22:
				var gp := c + Vector2(rf(-r, r), rf(-r, r)) * 0.8
				if _free_spot(gp) and CL[idx(int(gp.x), int(gp.y))] == 1 and building_at(gp.x, gp.y) == 0:
					add_decor("garden", Vector2(floor(gp.x), floor(gp.y)), false, Vector2.ZERO, true)
			for k in ri(3, 5):
				critters.append({"type": "cattle", "pos": c + Vector2(rf(-r, r), rf(-r, r)) * 0.6, "home": c})
		"salt flat":
			for k in 10:
				_try_decor("rubble2", c + Vector2(rf(-r, r), rf(-r, r)) * 0.7, false)
			for k in 4:
				_try_decor("barrel", c + Vector2(rf(-r, r), rf(-r, r)) * 0.5, true, Vector2(0.17, 0.17))
		"canyon", "crater rim":
			for k in 6:
				_try_decor("barrel_rust", c + Vector2(rf(-r, r), rf(-r, r)) * 0.6, true, Vector2(0.17, 0.17))
			add_decor("watertower", c + Vector2.from_angle(1.0) * r * 0.55, true, Vector2(0.55, 0.55))
		"mall", "stadium", "prison":
			# the town lives inside one big shell: a ring of walls of a huge old building
			var big := place_shape([Rect2i(int(c.x - 7), int(c.y - 13), 14, 6)], "factory", 1, true)
			if big: big.settlement = si; big.ruined = false
			add_decor("billboard_x", c + Vector2(-r * 0.6, -r * 0.6), true, Vector2(1.0, 0.2))
		_:
			if rng.randf() < 0.6: add_decor("watertower", c + Vector2.from_angle(2.2) * r * 0.6, true, Vector2(0.55, 0.55))

func _raider_town(l: Dictionary) -> void:
	var c: Vector2 = l.pos
	_raider_camp(c)
	for k in 3:
		_raider_camp_extra(c + Vector2.from_angle(k * TAU / 3.0 + 0.4) * l.r * 0.6)

func _raider_camp_extra(c: Vector2) -> void:
	var b := place_building(int(c.x) - 2, int(c.y) - 2, ri(3, 4), ri(3, 4), "den", -1, true)
	for k in 2:
		spawns.append({"type": "raider", "pos": c + Vector2(rf(-2, 2), rf(-2, 2)), "home": c, "home_r": 3.0})
	if b:
		var cr := Crate.new()
		cr.pos = c + Vector2(0.5, 2.6)
		cr.kind = "cache"
		crates.append(cr)

## Hostile sites from the map: a compound of ruins full of the faction that holds it, with good loot.
func _dungeon(l: Dictionary) -> void:
	var c: Vector2 = l.pos
	var r: float = l.r
	var fac: String = l.faction
	var enemy := "ghoul"
	if fac.find("aider") >= 0: enemy = "raider"
	elif fac.find("obot") >= 0 or fac.find("ecur") >= 0: enemy = "raider"
	elif fac.find("ut") >= 0 or fac.find("east") >= 0: enemy = "shellback"
	var kinds := ["factory", "office", "garage", "shop"]
	for k in int(r / 3.0) + 2:
		var p := c + Vector2.from_angle(rf(0, TAU)) * rf(2.0, r * 0.8)
		var kind: String = kinds[ri(0, kinds.size() - 1)]
		var b := place_shape(shape_for(kind, int(p.x) - 3, int(p.y) - 2), kind, -1, false)
		if b:
			for m in ri(1, 2):
				spawns.append({"type": enemy, "pos": rand_cell(b), "home": rand_cell(b), "home_r": 3.0})
			var cr := Crate.new()
			cr.pos = rand_cell(b)
			cr.kind = "cache"
			cr.bid = b.id
			crates.append(cr)
	for k in int(r / 2.5) + 3:
		var p := c + Vector2.from_angle(rf(0, TAU)) * rf(1.0, r)
		spawns.append({"type": enemy if rng.randf() < 0.75 else ["brute", "shellback", "ghoul"][ri(0, 2)], "pos": p, "home": p, "home_r": 4.0})
	for k in 8:
		_try_decor(["barrel_toxic", "rubble1", "bones", "barrel_rust"][ri(0, 3)], c + Vector2(rf(-r, r), rf(-r, r)) * 0.8, k % 2 == 0, Vector2(0.17, 0.17))
	add_decor("sign_rad", c + Vector2(r * 0.9, 0.5))

## Landmarks: something to see on the road, with a little trouble and a little loot.
func _landmark(l: Dictionary) -> void:
	var c: Vector2 = l.pos
	var r: float = l.r
	var id: String = l.id
	if id == "starlite_crossing" or id == "moonbeam_drivein" or id == "founders_bridge":
		var kinds := ["diner", "gas", "motel", "shop"]
		for k in 5:
			var p := c + Vector2.from_angle(k * 1.3) * r * 0.5
			var kind: String = kinds[k % kinds.size()]
			place_shape(shape_for(kind, int(p.x) - 3, int(p.y) - 2), kind)
		for k in 4:
			spawns.append({"type": "ghoul", "pos": c + Vector2(rf(-r, r), rf(-r, r)) * 0.5, "home": c, "home_r": r * 0.6})
		add_decor("billboard_y", c + Vector2(r * 0.7, -r * 0.4), true, Vector2(0.2, 1.0))
	elif id in ["radio_kzap", "starwatch", "owls_perch", "lookout_station_3"]:
		_flatten(c, 4.0, hz(c.x, c.y), true)
		add_decor("tower_decor", c, true, Vector2(0.3, 0.3))
		place_building(int(c.x) + 2, int(c.y) - 1, 3, 3, "shack", -1, true)
		for k in 3: _try_decor("barrel", c + Vector2(rf(-3, 3), rf(-3, 3)), true, Vector2(0.17, 0.17))
		spawns.append({"type": "raider", "pos": c + Vector2(2, 3), "home": c, "home_r": 3.0})
	else:
		# a wreck field / ruin cluster
		for k in 6:
			var p := c + Vector2.from_angle(rf(0, TAU)) * rf(1.0, r * 0.8)
			var cc := Car.new()
			cc.k = ri(0, 7); cc.ang = cc.k * PI / 4.0; cc.pos = p; cc.spr = "burned"
			_add_car(cc)
		for k in 3:
			var b := place_shape(shape_for("garage", int(c.x) + ri(-8, 6), int(c.y) + ri(-8, 6)), "garage")
			if b: b.ruined = true
		for k in 5:
			spawns.append({"type": ["ghoul", "rat", "shellback"][ri(0, 2)], "pos": c + Vector2(rf(-r, r), rf(-r, r)) * 0.6, "home": c, "home_r": r * 0.6})
		add_decor("watertower", c + Vector2(r * 0.5, r * 0.3), true, Vector2(0.55, 0.55))

## Wasteland chunk with no town: maybe one small site. You never quite know what's out there.
func _chunk_poi(cx: int, cy: int, r: Rect2i) -> void:
	var h := absi(hash(ckey(cx, cy) * 31 + seed_value * 7)) % 1000
	if h > 300: return
	var c := Vector2(r.position.x + rf(12, 20), r.position.y + rf(12, 20))
	var ti := idx(int(c.x), int(c.y))
	if T[ti] != GRASS or c.distance_to(start) < 40.0: return
	var b := biome(int(c.x), int(c.y))
	if b == B_WATER or b == B_GORGE or b == B_PEAK: return
	var hs := []
	for o in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4), Vector2.ZERO]:
		hs.append(hz(c.x + o.x, c.y + o.y))
	var flat: bool = hs.max() - hs.min() < 26.0
	var near_road_pt := _road_near(c, 9.0)
	var roll := rng.randf()
	var ug := rng.randf()
	if ug < 0.2:
		var kind := ""
		if b in [B_HILLS, B_PEAK, B_WOODS]: kind = "cave" if rng.randf() < 0.6 else "mine"
		elif b in [B_CANYON, B_GORGE, B_CRATER]: kind = "mine" if rng.randf() < 0.6 else "cave"
		elif b in [B_WASTE, B_SALT, B_FARM]:
			var q := rng.randf()
			kind = "vault" if q < 0.25 else ("cave" if q < 0.5 else ("mine" if q < 0.65 else ""))
		if kind != "" and _clear_of_buildings(c, 3.0):
			_add_portal(kind, c)
			return
	if rng.randf() < 0.3 and flat:
		_poi_vignette(c)
		return
	if near_road_pt != Vector2.ZERO and roll < 0.3:
		_poi_raider_gas(c, r)
	elif roll < 0.45 and flat:
		_raider_camp(c)
	elif roll < 0.62:
		_poi_survivors(c)
	elif roll < 0.72:
		_poi_caravan(c)
	elif roll < 0.8:
		_poi_nest(c, b)
	elif roll < 0.87:
		_poi_toxic(c)
	elif roll < 0.94:
		_poi_scav(c, r)
	else:
		if _free_spot(c) and _clear_of_buildings(c, 2.0):
			add_decor("watertower" if rng.randf() < 0.5 else "billboard_x", c, true, Vector2(0.55, 0.55))

const PORTAL_SPR := {"cave": "cave_mouth", "mine": "mine_entrance", "vault": "vault_door", "sewer": "manhole"}

func _add_portal(kind: String, c: Vector2) -> void:
	var d := add_decor(PORTAL_SPR[kind], c, kind != "sewer", Vector2(0.9, 0.9) if kind != "sewer" else Vector2(0.3, 0.3), kind == "sewer")
	d.portal = "%s:%d_%d" % [kind, int(c.x), int(c.y)]
	if kind != "sewer":
		for k in 3:
			_try_decor(["bones", "rubble2", "rock1", "barrel_rust"][ri(0, 3)], c + Vector2(rf(1.2, 2.4), rf(1.2, 2.4)), false)

func _road_near(c: Vector2, rad: float) -> Vector2:
	for k in 40:
		var q := c + Vector2(rf(-rad, rad), rf(-rad, rad))
		if in_bounds(int(q.x), int(q.y)) and T[idx(int(q.x), int(q.y))] == ROAD:
			return q
	return Vector2.ZERO

## A scene left where it happened, with something to read when you look closer.
func _poi_vignette(c: Vector2) -> void:
	var v: Array = Lore.VIGNETTES[ri(0, Lore.VIGNETTES.size() - 1)]
	var first := true
	for nm in v[2]:
		var p := c + (Vector2.ZERO if first else Vector2(rf(-1.6, 1.6), rf(-1.2, 1.2)))
		if nm == "car":
			var cc := Car.new()
			cc.k = ri(0, 7); cc.ang = cc.k * PI / 4.0; cc.pos = c + Vector2(2.2, 0.6); cc.spr = "burned" if rng.randf() < 0.5 else "teal"
			if _car_fits(cc): _add_car(cc)
			continue
		var d := add_decor(nm, p, nm in ["barrel_rust", "barrel", "jersey_x", "campfire_decor", "post"], Vector2(0.17, 0.17))
		if first and d != null:
			d.info = v[0] + "|" + v[1]
		first = false
	if rng.randf() < 0.6:
		var cr := Crate.new()
		cr.pos = c + Vector2(rf(-1.5, 1.5), rf(0.8, 1.6))
		cr.kind = "crate"
		crates.append(cr)

func _poi_raider_gas(c: Vector2, r: Rect2i) -> void:
	var x := clampi(int(c.x) - 4, r.position.x + 2, r.end.x - 11)
	var y := clampi(int(c.y) - 4, r.position.y + 2, r.end.y - 11)
	if not place_gas(x, y): return
	for k in 3:
		spawns.append({"type": "raider", "pos": Vector2(x + rf(0, 7), y + rf(4, 7)), "home": Vector2(x + 3, y + 3), "home_r": 4.0})
	for k in 4:
		_try_decor(["jersey_x", "barrel_rust", "tire", "jersey_y"][k], Vector2(x + rf(-1, 8), y + rf(-1, 8)), true, Vector2(0.4, 0.15))
	var cr := Crate.new()
	cr.pos = Vector2(x + 1.5, y + 4.2)
	cr.kind = "cache"
	crates.append(cr)
	raider_flags.append(Vector2(x + 7.5, y - 0.5))

func _poi_survivors(c: Vector2) -> void:
	_flatten(c, 3.0, hz(c.x, c.y), true)
	var st := Settlement.new()
	st.name = TOWN_NAMES_SMALL[ri(0, TOWN_NAMES_SMALL.size() - 1)]
	st.pos = c
	st.id = "camp_%d_%d" % [int(round(c.x)), int(round(c.y))]   # stable across sessions (index isn't)
	st.radius = 4.5
	st.small = true
	settlements.append(st)
	var si := settlements.size() - 1
	add_decor("campfire_decor", c, true, Vector2(0.25, 0.25))
	for k in ri(1, 2):
		_try_decor("tent", c + Vector2.from_angle(k * 2.4 + 0.5) * 2.4, true, Vector2(0.45, 0.45))
	for k in ri(2, 3):
		var a := k * TAU / 3.0 + 0.3
		critters.append({"type": "settler", "pos": c + Vector2.from_angle(a) * 1.3, "home": c, "settlement": si, "look": ri(1, 3), "home_r": 1.2})
	if rng.randf() < 0.5:
		st.trader = c + Vector2(1.2, -1.0)
		critters.append({"type": "trader", "pos": st.trader, "home": st.trader, "settlement": si})
	var cr := Crate.new()
	cr.pos = c + Vector2(-1.8, 1.2)
	cr.kind = "crate"
	crates.append(cr)

func _poi_caravan(c: Vector2) -> void:
	for k in ri(2, 3):
		var cc := Car.new()
		cc.k = ri(0, 7); cc.ang = cc.k * PI / 4.0
		cc.pos = c + Vector2.from_angle(k * 2.1) * 2.4
		cc.spr = "burned" if rng.randf() < 0.6 else ["teal", "red", "yellow"][ri(0, 2)]
		if _car_fits(cc): _add_car(cc)
	for k in 3:
		_try_decor(["bones", "barrel_rust", "trashbag", "tire"][ri(0, 3)], c + Vector2(rf(-3, 3), rf(-3, 3)), false)
	var cr := Crate.new()
	cr.pos = c + Vector2(0.4, 0.6)
	cr.kind = "crate"
	crates.append(cr)
	for k in ri(1, 2):
		spawns.append({"type": "brute" if rng.randf() < 0.2 else "ghoul", "pos": c + Vector2(rf(-5, 5), rf(-5, 5)), "home": c, "home_r": 6.0})

func _poi_nest(c: Vector2, b: int) -> void:
	var t := "rat"
	if b == B_SALT or b == B_CRATER or b == B_CANYON: t = "shellback"
	for k in ri(3, 5):
		spawns.append({"type": t, "pos": c + Vector2(rf(-2, 2), rf(-2, 2)), "home": c, "home_r": 3.5})
	for k in 5:
		_try_decor(["bones", "bones", "rubble2", "deadbush"][ri(0, 3)], c + Vector2(rf(-2.5, 2.5), rf(-2.5, 2.5)), false)
	var cr := Crate.new()
	cr.pos = c
	cr.kind = "cache"
	crates.append(cr)

func _poi_toxic(c: Vector2) -> void:
	add_decor("puddle_toxic", c, false, Vector2.ZERO, true)
	add_decor("puddle_toxic", c + Vector2(rf(-1.5, 1.5), rf(-1.5, 1.5)), false, Vector2.ZERO, true)
	for m in 3:
		_try_decor("barrel_toxic", c + Vector2.from_angle(rf(0, TAU)) * rf(1.0, 2.2), true, Vector2(0.17, 0.17))
	add_decor("sign_rad", c + Vector2(2.4, 0.5))
	spawns.append({"type": "shellback", "pos": c + Vector2(1.5, 1.5), "home": c, "home_r": 4.0})

func _poi_scav(c: Vector2, r: Rect2i) -> void:
	var b := place_building(clampi(int(c.x) - 2, r.position.x + 2, r.end.x - 7), clampi(int(c.y) - 2, r.position.y + 2, r.end.y - 7), 4, 3, "shack")
	if b == null: return
	var cr := Crate.new()
	cr.pos = rand_cell(b)
	cr.kind = "crate"
	cr.bid = b.id
	crates.append(cr)
	if rng.randf() < 0.5:
		spawns.append({"type": "raider", "pos": Vector2(b.out) + Vector2(0.5, 0.5), "home": Vector2(b.out) + Vector2(0.5, 0.5), "home_r": 3.0})
	else:
		var st := Settlement.new()
		st.name = "Scavenger shack"
		st.pos = Vector2(b.out) + Vector2(0.5, 0.5)
		st.id = "shack_%d_%d" % [b.out.x, b.out.y]
		st.radius = 3.0
		st.small = true
		settlements.append(st)
		st.trader = st.pos + Vector2(0.8, 0.8)
		critters.append({"type": "trader", "pos": st.trader, "home": st.trader, "settlement": settlements.size() - 1})

# ---------------------------------------------------------------- per-chunk scatter
const TREE_P := [0.025, 0.07, 0.16, 0.03, 0.0, 0.09, 0.008, 0.0, 0.015, 0.05, 0.0, 0.004, 0.03, 0.01]

func _chunk_trees(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * N + x
			if T[i] != GRASS or CL[i] == 1: continue
			var b := braw[i * 4]
			var p: float = TREE_P[b]
			if b == B_WOODS:
				p *= 0.5 + 0.5 * sin(x * 0.11 + y * 0.07) * sin(y * 0.13 - x * 0.05) + 0.5
			if rng.randf() < p and _clear_of_buildings(Vector2(x + 0.5, y + 0.5), 0.75) and not door_grid.has(i):
				T[i] = TREE
			elif b != B_SALT and b != B_CRATER and (G[i] == 3 or rng.randf() < (0.05 if b != B_WOODS else 0.12)):
				add_decor("tuft%d" % ri(0, 2), Vector2(x + rf(0.2, 0.8), y + rf(0.2, 0.8)), false, Vector2.ZERO, true)
			else:
				_scatter(b, x, y, i)

## Rocks, cacti, reeds, salt crusts: what lies about in each kind of country.
const SCATTER := {
	B_WASTE: [0.02, ["rock0", "rock1", "rock2", "tumbleweed", "deadbush", "deadbush", "cactus0", "bones"]],
	B_HILLS: [0.018, ["rock0", "rock1", "rock2", "boulder", "deadbush"]],
	B_PEAK: [0.04, ["rock0", "rock1", "boulder", "boulder", "rock2"]],
	B_CANYON: [0.03, ["redrock", "rock1", "cactus0", "cactus1", "rock2", "tumbleweed"]],
	B_GORGE: [0.03, ["redrock", "redrock", "rock1", "rock2"]],
	B_SALT: [0.03, ["saltrock", "saltrock", "rock2", "bones"]],
	B_CRATER: [0.02, ["rock2", "rock0", "saltrock"]],
	B_MARSH: [0.05, ["reeds0", "reeds1", "reeds0", "deadbush"]],
	B_BEACH: [0.02, ["reeds0", "rock2", "tire"]],
	B_FARM: [0.004, ["rock2", "deadbush"]],
	B_WOODS: [0.01, ["rock1", "deadbush", "rock0"]],
}
const SOLID_SCATTER := {"boulder": Vector2(0.55, 0.45), "redrock": Vector2(0.45, 0.4), "cactus0": Vector2(0.12, 0.12), "cactus1": Vector2(0.25, 0.15)}

func _scatter(b: int, x: int, y: int, i: int) -> void:
	var sc = SCATTER.get(b)
	if sc == null: return
	var p: float = sc[0]
	var wet := false
	if b != B_MARSH:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if in_bounds(x + o.x, y + o.y) and T[idx(x + o.x, y + o.y)] == WATER: wet = true
	if wet:
		if rng.randf() < 0.18: add_decor(["reeds0", "reeds1"][ri(0, 1)], Vector2(x + rf(0.2, 0.8), y + rf(0.2, 0.8)))
		return
	if rng.randf() >= p: return
	var pool: Array = sc[1]
	var nm: String = pool[ri(0, pool.size() - 1)]
	var at := Vector2(x + rf(0.25, 0.75), y + rf(0.25, 0.75))
	if SOLID_SCATTER.has(nm):
		if door_grid.has(i) or not _clear_of_buildings(at, 1.0) or road_d[y * NV + x] < 1.5: return
		add_decor(nm, at, true, SOLID_SCATTER[nm])
	else:
		add_decor(nm, at)

func _car_fits(c: Car) -> bool:
	var fw := Vector2.from_angle(c.ang)
	for u in [-1.4, -0.7, 0.0, 0.7, 1.4]:
		for v in [-0.5, 0.5]:
			var q: Vector2 = c.pos + fw * u + fw.orthogonal() * v
			if not in_bounds(int(q.x), int(q.y)) or building_at(q.x, q.y) > 0 or T[idx(int(q.x), int(q.y))] == TREE or T[idx(int(q.x), int(q.y))] == WATER:
				return false
	return not car_hit(c.pos, 1.6)

func _add_car(c: Car) -> void:
	if gen_rect.size.x > 0.0 and not gen_rect.grow(-1.0).has_point(c.pos): return
	cars.append(c)
	for yy in range(int(c.pos.y) - 2, int(c.pos.y) + 3):
		for xx in range(int(c.pos.x) - 2, int(c.pos.x) + 3):
			var k := yy * N + xx
			if not car_grid.has(k): car_grid[k] = []
			car_grid[k].append(c)
	var cr := Crate.new()
	var fwd := Vector2.from_angle(c.ang)
	cr.pos = c.pos - fwd * 1.5 + fwd.orthogonal() * 0.55
	cr.kind = "car"
	crates.append(cr)

func _remove_car(c: Car) -> void:
	cars.erase(c)
	for yy in range(int(c.pos.y) - 2, int(c.pos.y) + 3):
		for xx in range(int(c.pos.x) - 2, int(c.pos.x) + 3):
			var lst = car_grid.get(yy * N + xx)
			if lst != null: lst.erase(c)

func _chunk_cars(cx: int, cy: int, r: Rect2i) -> void:
	var lst = road_pts.get(ckey(cx, cy))
	if lst != null:
		var n := 0
		for e in lst:
			n += 1
			var pth: Dictionary = paths[e >> 16]
			if pth.kind == "dirt": continue
			var k: int = e & 65535
			var pts: PackedVector2Array = pth.pts
			if k < 2 or k > pts.size() - 3: continue
			if rng.randf() > (0.018 if pth.kind == "interstate" else 0.01): continue
			var p := pts[k]
			if p.distance_to(start) < 9: continue
			var dir := (pts[k + 1] - pts[k - 1]).normalized()
			var lane: float = rf(-pth.w + 0.6, pth.w - 0.6)
			var c := Car.new()
			c.k = posmod(int(round(dir.angle() / (PI / 4.0))) + (4 if rng.randf() < 0.3 else 0), 8)
			c.ang = c.k * PI / 4.0
			c.pos = p + dir.orthogonal() * lane
			c.spr = ["teal", "red", "yellow", "teal", "red", "burned"][ri(0, 5)]
			if not r.has_point(Vector2i(c.pos)): continue
			if _car_fits(c): _add_car(c)
		# power poles along highways and interstates
		for e in lst:
			var pth: Dictionary = paths[e >> 16]
			var k: int = e & 65535
			if pth.kind != "highway" and pth.kind != "interstate": continue
			if k % 78 != 0 or k == 0: continue
			var pts: PackedVector2Array = pth.pts
			var line := PackedVector2Array()
			for j in range(k, mini(k + 78 * 3, pts.size() - 1), 78):
				var dir := (pts[mini(j + 1, pts.size() - 1)] - pts[maxi(j - 1, 0)]).normalized()
				var p: Vector2 = pts[j] + dir.orthogonal() * float(pth.w + 1.6)
				if not r.grow(-1).has_point(Vector2i(p)) and line.size() > 0: break
				if in_bounds(int(p.x), int(p.y)) and T[idx(int(p.x), int(p.y))] in [GRASS, SIDE] and _clear_of_buildings(p, 0.8) and not tree_hit(p, 0.3) and not car_hit(p, 0.4):
					line.append(p)
			if line.size() > 1:
				pole_lines.append(line)
	# parked cars on city streets
	if density(r.position.x + 16, r.position.y + 16) > 140:
		for t in 6:
			var x := ri(r.position.x + 2, r.end.x - 3)
			var y := ri(r.position.y + 2, r.end.y - 3)
			if T[idx(x, y)] != ROAD: continue
			var c := Car.new()
			c.k = 0 if posmod(y, GRID) < 2 else 2
			if rng.randf() < 0.5: c.k += 4
			c.ang = c.k * PI / 4.0
			c.pos = Vector2(x + 0.5, y + 0.5) if posmod(y, GRID) >= 2 and posmod(x, GRID) >= 2 else Vector2(x + 1.0, y + 1.0)
			c.spr = ["teal", "red", "yellow", "burned", "burned"][ri(0, 4)]
			if _car_fits(c): _add_car(c)

func _chunk_debris(cx: int, cy: int, r: Rect2i) -> void:
	var lst = road_pts.get(ckey(cx, cy))
	if lst != null:
		for e in lst:
			if rng.randf() > 0.035: continue
			var pth: Dictionary = paths[e >> 16]
			var k: int = e & 65535
			var pts: PackedVector2Array = pth.pts
			if k < 1 or k > pts.size() - 2: continue
			var dir := (pts[k + 1] - pts[k - 1]).normalized()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			if pth.kind != "dirt" and rng.randf() < 0.1:
				var p: Vector2 = pts[k] + dir.orthogonal() * rf(-0.4, 0.4)
				if r.has_point(Vector2i(p)) and _free_spot(p):
					var along_x := absf(dir.x) > absf(dir.y)
					add_decor("jersey_x" if along_x else "jersey_y", p, true, Vector2(0.5, 0.13) if along_x else Vector2(0.13, 0.5))
			else:
				var p: Vector2 = pts[k] + dir.orthogonal() * side * (pth.w + rf(0.3, 1.4))
				if not r.has_point(Vector2i(p)) or not _free_spot(p): continue
				var pick: String = ["trashbag", "tire", "rubble0", "papers", "barrel_rust", "tire", "rubble1"][ri(0, 6)]
				add_decor(pick, p, pick == "barrel_rust", Vector2(0.17, 0.17), pick == "papers")
		# street lamps in town, sparse along highways
		for e in lst:
			var pth: Dictionary = paths[e >> 16]
			var k: int = e & 65535
			if pth.kind == "dirt" or k % 66 != 0 or k == 0: continue
			var pts: PackedVector2Array = pth.pts
			if k > pts.size() - 2: continue
			var p := pts[k]
			if density(int(p.x), int(p.y)) < 60 and rng.randf() < 0.7: continue
			var dir := (pts[k + 1] - pts[k - 1]).normalized()
			var q: Vector2 = p + dir.orthogonal() * (1.0 if (k / 66) % 2 == 0 else -1.0) * (pth.w + 0.75)
			if r.has_point(Vector2i(q)) and _free_spot(q) and T[idx(int(q.x), int(q.y))] != ROAD and _clear_of_buildings(q, 0.7):
				add_decor("lamp", q, true, Vector2(0.08, 0.08))
	var d := density(r.position.x + 16, r.position.y + 16)
	if d > 120:
		for k in 14:
			var p := Vector2(rf(r.position.x + 1, r.end.x - 1), rf(r.position.y + 1, r.end.y - 1))
			if _free_spot(p):
				var pick: String = ["rubble0", "rubble1", "rubble2", "bricks", "papers", "trashbag", "barrel_rust", "tire"][ri(0, 7)]
				add_decor(pick, p, pick == "barrel_rust", Vector2(0.17, 0.17), pick == "papers")
		# a manhole down into the sewers now and then
		if rng.randf() < 0.22:
			for t in 20:
				var x := ri(r.position.x + 3, r.end.x - 4)
				var y := ri(r.position.y + 3, r.end.y - 4)
				if T[idx(x, y)] == SIDE and _free_spot(Vector2(x + 0.5, y + 0.5)):
					_add_portal("sewer", Vector2(x + 0.5, y + 0.5))
					break
		# grid-street lamps at corners
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if posmod(x, GRID) == 2 and posmod(y, GRID) == 2 and T[idx(x, y)] == SIDE and rng.randf() < 0.7:
					add_decor("lamp", Vector2(x + 0.25, y + 0.25), true, Vector2(0.08, 0.08))
	if d < 40 and rng.randf() < 0.25:
		var c := Vector2(rf(r.position.x + 3, r.end.x - 3), rf(r.position.y + 3, r.end.y - 3))
		if _free_spot(c):
			for m in ri(3, 5):
				critters.append({"type": "crow", "pos": c + Vector2(rf(-1, 1), rf(-1, 1)), "home": c})

const SURVIVOR_NAMES := ["Mara", "Dez", "Jun", "Otis", "Rosa", "Hank", "Priya", "Theo", "Wren", "Gus", "Ines", "Bo", "Lark", "Ezra", "Nell", "Kit"]

## Wild things by how far you are from Patchwork: the further out, the worse.
func _chunk_creatures(r: Rect2i) -> void:
	var ctr := Vector2(r.get_center())
	var far := clampf(ctr.distance_to(start) / 900.0, 0.0, 1.0)
	var near_town := not nearest_loc(ctr, 20.0).is_empty()
	for b in buildings.slice(_mark.buildings):
		if b.settlement >= 0 or b.sealed or b.kind in ["den", "shack", "canopy", "kiosk"]: continue
		if (b.ruined and rng.randf() < 0.45) or (density(b.x0, b.y0) > 170 and rng.randf() < 0.2):
			var p := rand_cell(b)
			if p.distance_to(start) < 30: continue
			if not b.ruined and b.cells.size() >= 12 and rng.randf() < 0.12:
				survivors.append({"pos": p, "name": SURVIVOR_NAMES[ri(0, SURVIVOR_NAMES.size() - 1)], "bid": b.id})
				continue
			spawns.append({"type": "ghoul", "pos": p, "home": p, "home_r": 3.0})
			if rng.randf() < 0.3 + far * 0.4:
				spawns.append({"type": "ghoul", "pos": p + Vector2(rf(-0.5, 0.5), rf(-0.5, 0.5)), "home": p, "home_r": 3.0})
	if near_town or ctr.distance_to(start) < 50: return
	if rng.randf() < 0.18 + far * 0.25:
		var p := Vector2(rf(r.position.x + 4, r.end.x - 4), rf(r.position.y + 4, r.end.y - 4))
		if not _free_spot(p): return
		var bm := biome(int(p.x), int(p.y))
		var pool := ["ghoul", "rat", "shellback"]
		match bm:
			B_WOODS, B_HILLS: pool = ["ghoul", "rat", "rat", "brute"]
			B_SALT, B_CRATER, B_CANYON: pool = ["shellback", "shellback", "brute"]
			B_MARSH: pool = ["shellback", "ghoul", "rat"]
			B_CITY, B_SUBURB: pool = ["ghoul", "ghoul", "rat"]
		var t: String = pool[ri(0, pool.size() - 1)]
		if t == "brute" and far < 0.25: t = "ghoul"
		for k in (ri(2, 4) if t == "rat" else ri(1, 2 + int(far * 2))):
			spawns.append({"type": t, "pos": p + Vector2(rf(-1.5, 1.5), rf(-1.5, 1.5)), "home": p, "home_r": 5.0})

## After a batch of content: nothing solid inside walls or in front of doors, no trees through props,
## wrecks that hit props scrapped, outdoor loot out of walls, spawns and critters on standable ground.
func _tidy_new() -> void:
	var doors := []
	for b in buildings.slice(_mark.buildings):
		doors.append(Vector2(b.out.x + 0.5, b.out.y + 0.5))
	var near_door := func(q: Vector2) -> bool:
		for dp in doors:
			if dp.distance_to(q) < 1.05: return true
		return door_grid.has(int(q.y) * N + int(q.x)) and false
	var keep := []
	for i in range(_mark.decor, decor.size()):
		var d: Decor = decor[i]
		if (d.name.begins_with("fence") or d.name.begins_with("picket")) and d.bid == 0 and building_at(d.pos.x, d.pos.y) != 0:
			_ungrid(d); continue
		if d.bid != 0 or d.flat or not d.solid or d.name in ["pillar", "fuelpump", "mailbox"]:
			keep.append(d); continue
		if building_at(d.pos.x, d.pos.y) != 0 or not _clear_of_buildings(d.pos, d.half.x + 0.05) or near_door.call(d.pos):
			_ungrid(d)
			if d.name.begins_with("fence") or d.name.begins_with("picket"): continue
			var moved := false
			for ring in range(1, 9):
				for k in 12:
					var q: Vector2 = d.pos + Vector2.from_angle(k * TAU / 12.0) * ring * 0.25
					if gen_rect.size.x > 0.0 and not gen_rect.grow(-d.half.x).has_point(q): continue
					if in_bounds(int(q.x), int(q.y)) and building_at(q.x, q.y) == 0 and _clear_of_buildings(q, d.half.x + 0.05) and not near_door.call(q):
						d.pos = q; moved = true; break
				if moved: break
			if not moved: continue
			_grid(d)
		keep.append(d)
	decor.resize(_mark.decor)
	decor.append_array(keep)
	for d in keep:
		if not d.solid or d.bid != 0: continue
		for yy in range(int(d.pos.y - d.half.y - 0.4), int(d.pos.y + d.half.y + 0.4) + 1):
			for xx in range(int(d.pos.x - d.half.x - 0.4), int(d.pos.x + d.half.x + 0.4) + 1):
				if in_bounds(xx, yy) and T[idx(xx, yy)] == TREE: T[idx(xx, yy)] = GRASS
	for k in range(cars.size() - 1, _mark.cars - 1, -1):
		var c: Car = cars[k]
		var hit := decor_hit(c.pos, 0.9)
		for dp in doors:
			if dp.distance_to(c.pos) < 1.8: hit = true
		if hit:
			_remove_car(c)
			for q in range(crates.size() - 1, _mark.crates - 1, -1):
				if crates[q].kind == "car" and crates[q].pos.distance_to(c.pos) < 2.2:
					crates.remove_at(q)
	for i in range(_mark.crates, crates.size()):
		var cr: Crate = crates[i]
		if cr.bid == 0 and cr.kind != "car" and building_at(cr.pos.x, cr.pos.y) != 0:
			for ring in range(1, 10):
				var q: Vector2 = cr.pos + Vector2.from_angle(ring * 2.4) * ring * 0.3
				if building_at(q.x, q.y) == 0 and can_stand(q, 0.2, 0):
					cr.pos = q; break
	for b in buildings.slice(_mark.buildings):
		var o := Vector2i(b.out)
		for yy in range(o.y - 1, o.y + 2):
			for xx in range(o.x - 1, o.x + 2):
				if in_bounds(xx, yy) and T[idx(xx, yy)] == TREE: T[idx(xx, yy)] = GRASS
	_fix_spawns(_mark.spawns)
	_fix_critters(_mark.critters)
	_cap_groups(_mark.spawns)

## New players shouldn't meet packs of 5-6 in their first few minutes: near the home camp, any
## group (spawns sharing a home) is trimmed to 3.
const EARLY_R := 300.0
const EARLY_MAX := 3
func _cap_groups(from: int) -> void:
	if reserve_r <= 0.0: return
	var groups := {}
	for i in range(from, spawns.size()):
		var sp: Dictionary = spawns[i]
		if sp.has("boss") or sp.pos.distance_to(start) > EARLY_R: continue
		var k := pkey(sp.get("home", sp.pos))
		if not groups.has(k): groups[k] = []
		groups[k].append(i)
	var drop := []
	for k in groups:
		var lst: Array = groups[k]
		for j in range(EARLY_MAX, lst.size()): drop.append(lst[j])
	drop.sort()
	for j in range(drop.size() - 1, -1, -1): spawns.remove_at(drop[j])

func _grid(d: Decor) -> void:
	if not d.solid: return
	var k := int(floor(d.pos.y)) * N + int(floor(d.pos.x))
	if not decor_grid.has(k): decor_grid[k] = []
	decor_grid[k].append(d)

func _ungrid(d: Decor) -> void:
	if not d.solid: return
	var lst = decor_grid.get(int(floor(d.pos.y)) * N + int(floor(d.pos.x)))
	if lst != null: lst.erase(d)

## A road tile near p (for patrols and wanderers), or p itself if there is none close.
func road_point_near(p: Vector2, rad: float = 30.0) -> Vector2:
	for t in 200:
		var q := p + Vector2(rf(-rad, rad), rf(-rad, rad))
		var x := int(q.x)
		var y := int(q.y)
		if in_bounds(x, y) and base_done[ckey(x / CH, y / CH)] and T[idx(x, y)] == ROAD:
			return Vector2(x + 0.5, y + 0.5)
	return p

func add_monster(avoid: Vector2, min_d: float, camps: Array) -> void:
	for t in 60:
		var p := avoid + Vector2.from_angle(rf(0, TAU)) * rf(min_d, min_d + 10.0)
		var ck := chunk_of(p)
		if not content_done[ckey(ck.x, ck.y)] or not _free_spot(p) or settlement_at(p, 8.0) >= 0: continue
		var near_camp := false
		for c in camps:
			if p.distance_to(c) < 12.0: near_camp = true
		if near_camp: continue
		var far := clampf(p.distance_to(start) / 900.0, 0.0, 1.0)
		var t2 := "ghoul" if rng.randf() < 0.65 else ("shellback" if rng.randf() < 0.7 or far < 0.3 else "brute")
		var sp := {"type": t2, "pos": p, "home": p, "home_r": 5.0, "roam": true}
		spawns.append(sp)
		var key := ckey(ck.x, ck.y)
		sp["chunk"] = key
		_bucket(key).spawns.append(sp)
		return

## A raider patrol walking between road points near p.
func add_patrol(p: Vector2 = start) -> void:
	var wps := [road_point_near(p), road_point_near(p), road_point_near(p), road_point_near(p)]
	var key := ckey(chunk_of(wps[0]).x, chunk_of(wps[0]).y)
	for k in 2 + (1 if rng.randf() < 0.4 else 0):
		var sp := {"type": "raider", "pos": wps[0] + Vector2(k * 0.6, 0), "patrol": wps, "roam": true, "chunk": key}
		spawns.append(sp)
		_bucket(key).spawns.append(sp)
