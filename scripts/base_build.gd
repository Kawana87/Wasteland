class_name BaseBuild
extends Node2D
## Player base building. Wall pieces sit on tile EDGES (like building walls, so collision, shots,
## doors and draw order all work the same way); floors and foundations sit on tiles.
## Build mode: pick a material tier and a piece, then tap (or click) to place one, or drag to lay a
## run of walls / a patch of floor or foundation. Rotation only matters for single taps.
##
## Heights: on bare ground the corners under a piece are levelled (dug or filled a little) so a run of
## walls keeps a straight top. Foundations are raised blocks: they snap to the height of a foundation or
## claimed building they touch, otherwise sit just above the highest corner, and show a side face down
## to the ground on the low side. Anything built on a foundation stands on its top.
## Claimed buildings (a cleared raider den you took over) can be knocked through and extended.

const TIERS := ["scrap", "wood", "stone", "concrete", "fence"]
const PIECES := ["wall", "window", "door", "doorway", "half", "gate", "foundation", "floor", "remove"]
const FENCE_PIECES := ["wall", "gate", "remove"]
const COST := {"scrap": {"scrap": 2}, "wood": {"wood": 2}, "stone": {"scrap": 3, "wood": 1},
	"concrete": {"scrap": 5}, "fence": {"scrap": 1}}
const FLOOR_COST := {"scrap": {"scrap": 1}, "wood": {"wood": 1}, "stone": {"scrap": 1, "wood": 1}, "concrete": {"scrap": 2}}
const FOUND_COST := {"scrap": {"scrap": 4}, "wood": {"wood": 4}, "stone": {"scrap": 4, "wood": 2}, "concrete": {"scrap": 7}}
const HP := {"scrap": 100.0, "wood": 200.0, "stone": 450.0, "concrete": 900.0, "fence": 60.0}
const BASE_R := 12.0           # how far from a camp you may build
const MAX_FACE := 48.0         # tallest foundation side (game px)
const NAMES := {"scrap": "Scrap", "wood": "Wood", "stone": "Stone", "concrete": "Concrete", "fence": "Fence",
	"wall": "Wall", "window": "Window", "door": "Door", "doorway": "Doorway", "half": "Half wall", "gate": "Gate",
	"foundation": "Foundation", "floor": "Floor", "remove": "Remove"}

var g: Game
var w: World
var pieces := {}               # Vector3i(x, y, axis) -> {seg, spr}
var floors := {}               # Vector2i -> {tier, spr}
var founds := {}               # Vector2i -> {tier, top, spr, faces: [Sprite2D]}
var claimed: Array = []        # building ids you own (walls can be knocked out, rooms extended)
var active := false
var tier := "wood"
var piece := "wall"
var axis := 0
var dragging := false
var drag_a := Vector2.ZERO
var drag_b := Vector2.ZERO
var hover := Vector2(-1, -1)
var ghosts: Array = []
var _door_idle := {}           # Seg -> seconds open with nobody in the doorway
var bar: BuildBar
var vgroup := {}               # Vector2i ground corner -> structure id (corners levelled together)
var gverts := {}               # structure id -> Array of its corners
var glevel := {}               # structure id -> its ground height
var orig := {}                 # Vector2i -> ground height before any levelling
var next_group := 1

func setup(game: Game, world: World) -> void:
	g = game
	w = world

# ------------------------------------------------------------------ mode
func can_build_here() -> String:
	if g.player.fl != 0: return "Go outside to build."
	if not in_base(g.player.wpos): return "Build near one of your camps (within %d tiles)." % int(BASE_R)
	return ""

func in_base(p: Vector2) -> bool:
	for c in g.camps:
		if c.wpos.distance_to(p) <= BASE_R: return true
	return false

func enter() -> void:
	var err := can_build_here()
	if err != "":
		g.hud.toast(err)
		return
	g.hud.hide_menu()
	active = true
	if bar == null:
		bar = BuildBar.new()
		bar.base = self
		g.hud.add_child(bar)
	bar.visible = true
	bar.refresh()
	g.hud.touch.build_mode = true
	g.hud.toast("Build mode: tap to place, drag to lay a run. Foundations snap to the height of what they touch.")

func leave() -> void:
	active = false
	dragging = false
	hover = Vector2(-1, -1)
	if bar: bar.visible = false
	g.hud.touch.build_mode = false
	_show_ghosts([], [])

func select(t: String, p: String) -> void:
	if t != "": tier = t
	if p != "": piece = p
	if tier == "fence" and not piece in FENCE_PIECES: piece = "wall"
	if bar: bar.refresh()

func turn() -> void:
	axis = 1 - axis
	if bar: bar.refresh()

# ------------------------------------------------------------------ claiming
func claim_building(bid: int) -> void:
	if bid > 0 and not bid in claimed: claimed.append(bid)

func _claimed_at(t: Vector2i) -> World.Bld:
	var id := w.building_at(t.x + 0.5, t.y + 0.5)
	if id > 0 and id in claimed: return w.buildings[id - 1]
	return null

## Height of a ground corner that belongs to a claimed building's footprint (its floor), or NAN.
func _bld_corner(v: Vector2i) -> float:
	for t in [v, v - Vector2i(1, 0), v - Vector2i(0, 1), v - Vector2i(1, 1)]:
		var b := _claimed_at(t)
		if b: return b.h0
	return NAN

# ------------------------------------------------------------------ pointer input (HUD/screen coordinates)
func press(sp: Vector2) -> void:
	dragging = true
	drag_a = to_world(sp)
	drag_b = drag_a

func move(sp: Vector2) -> void:
	if dragging: drag_b = to_world(sp)
	else: hover = to_world(sp)

func release(sp: Vector2) -> void:
	if not dragging: return
	drag_b = to_world(sp)
	dragging = false
	_commit()
	hover = drag_b

func to_world(sp: Vector2) -> Vector2:
	var m: Vector2 = g.cam.get_screen_center_position() - Vector2(g.vp.size) * 0.5 + sp / Game.SHRINK
	var z := 0.0
	var wp := Vector2.ZERO
	for i in 3:
		var a := m.x / 24.0
		var b := (m.y + z * Iso.S) / 12.0
		wp = Vector2((a + b) * 0.5, (b - a) * 0.5)
		z = w.stand_z(clampf(wp.x, 0.0, World.N - 1.0), clampf(wp.y, 0.0, World.N - 1.0), 0)
	return wp

# ------------------------------------------------------------------ targets
static func snap(p: Vector2, ax: int) -> Vector3i:
	if ax == 0: return Vector3i(int(floor(p.x)), int(round(p.y)), 0)
	return Vector3i(int(round(p.x)), int(floor(p.y)), 1)

static func edge_verts(k: Vector3i) -> Array:
	return [Vector2i(k.x, k.y), Vector2i(k.x + 1, k.y) if k.z == 0 else Vector2i(k.x, k.y + 1)]

static func edge_sides(k: Vector3i) -> Array:
	return [Vector2i(k.x, k.y - 1), Vector2i(k.x, k.y)] if k.z == 0 else [Vector2i(k.x - 1, k.y), Vector2i(k.x, k.y)]

static func tile_verts(t: Vector2i) -> Array:
	return [t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)]

## The edges (walls) or tiles (floors, foundations) a tap / drag from a to b covers.
func targets(a: Vector2, b: Vector2) -> Array:
	var out := []
	if piece in ["floor", "foundation"]:
		var x0 := int(floor(minf(a.x, b.x))); var x1 := int(floor(maxf(a.x, b.x)))
		var y0 := int(floor(minf(a.y, b.y))); var y1 := int(floor(maxf(a.y, b.y)))
		for y in range(y0, mini(y1, y0 + 11) + 1):
			for x in range(x0, mini(x1, x0 + 11) + 1):
				out.append(Vector2i(x, y))
		return out
	if piece == "remove":
		var k = _piece_near(b)
		if k != null:
			out.append(k)
		else:
			var t := Vector2i(int(floor(b.x)), int(floor(b.y)))
			if floors.has(t) or founds.has(t): out.append(t)
		return out
	var d := b - a
	if d.length() < 0.6:
		out.append(snap(b, axis))
		return out
	var ax := 0 if absf(d.x) >= absf(d.y) else 1
	var s := snap(a, ax)
	if ax == 0:
		var ex := int(floor(b.x))
		var st := 1 if ex >= s.x else -1
		for x in range(s.x, ex + st, st):
			out.append(Vector3i(x, s.y, 0))
			if out.size() >= 16: break
	else:
		var ey := int(floor(b.y))
		var st := 1 if ey >= s.y else -1
		for y in range(s.y, ey + st, st):
			out.append(Vector3i(s.x, y, 1))
			if out.size() >= 16: break
	return out

## A built piece, or a wall of a claimed building, near p. Returns its key (Vector3i) or a Seg, or null.
func _piece_near(p: Vector2):
	var best = null
	var bd := 0.45
	for ax in [0, 1]:
		var k := snap(p, ax)
		if pieces.has(k):
			var d := World.seg_dist(p, pieces[k].seg)
			if d < bd: bd = d; best = k
		var bs := _bld_seg(k)
		if bs != null:
			var d2 := World.seg_dist(p, bs)
			if d2 < bd: bd = d2; best = bs
	return best

func _bld_seg(k: Vector3i) -> World.Seg:
	var a := Vector2(k.x, k.y)
	for t in edge_sides(k):
		if not w.in_bounds(t.x, t.y): continue
		for s in w.seg_grid.get(t.y * World.N + t.x, []):
			if s.bid in claimed and s.fl == 0 and s.axis == k.z and s.a.distance_to(a) < 0.01:
				return s
	return null

# ------------------------------------------------------------------ heights
## The height a wall on edge k stands at: a foundation's top, a claimed building's floor, else the
## (levelled) ground.
func edge_z(k: Vector3i) -> float:
	var top := -INF
	for t in edge_sides(k):
		if founds.has(t): top = maxf(top, founds[t].top)
	if top > -INF: return top
	var bz := _bld_corner(Vector2i(k.x, k.y))
	if not is_nan(bz): return bz
	return _level_for(edge_verts(k))

func _on_found(k: Vector3i) -> bool:
	for t in edge_sides(k):
		if founds.has(t): return true
	return false

## Structures levelled on bare ground: corners levelled together share a height; a piece joining two
## merges them onto the bigger one's height, if every corner stays within the slope limit.
func _groups_of(verts: Array) -> Array:
	var gs := []
	for v in verts:
		if vgroup.has(v) and not vgroup[v] in gs: gs.append(vgroup[v])
	gs.sort_custom(func(p, q): return gverts[p].size() > gverts[q].size())
	return gs

func _level_for(verts: Array) -> float:
	for v in verts:
		var bz := _bld_corner(v)
		if not is_nan(bz): return bz
	var gs := _groups_of(verts)
	if not gs.is_empty(): return glevel[gs[0]]
	var s := 0.0
	for v in verts: s += w.vh(v.x, v.y)
	return s / verts.size()

func _ground(v: Vector2i) -> float:
	return orig.get(v, w.vh(v.x, v.y))

func _level_ok(verts: Array, lim: float) -> bool:
	var lv := _level_for(verts)
	for v in verts:
		if absf(_ground(v) - lv) > lim: return false
	var gs := _groups_of(verts)
	for i in range(1, gs.size()):
		for u in gverts[gs[i]]:
			if absf(_ground(u) - lv) > lim: return false
	return true

## Returns true if the ground changed.
func _level(verts: Array) -> bool:
	var lv := _level_for(verts)
	var gs := _groups_of(verts)
	var gid: int
	if gs.is_empty():
		gid = next_group; next_group += 1
		glevel[gid] = lv; gverts[gid] = []
	else:
		gid = gs[0]
	glevel[gid] = lv
	var changed := false
	for i in range(1, gs.size()):                 # merge the other structures in
		for u in gverts[gs[i]]:
			vgroup[u] = gid; gverts[gid].append(u)
			if absf(w.vh(u.x, u.y) - lv) > 0.01: w.set_vh(u.x, u.y, lv); changed = true
		gverts.erase(gs[i]); glevel.erase(gs[i])
	for v in verts:
		if not orig.has(v): orig[v] = w.vh(v.x, v.y)
		if not vgroup.has(v):
			vgroup[v] = gid; gverts[gid].append(v)
		if absf(w.vh(v.x, v.y) - lv) > 0.01:
			w.set_vh(v.x, v.y, lv); changed = true
	return changed

func _relevel_done() -> void:
	g.rebuild_ground(Rect2(g.player.wpos - Vector2(BASE_R + 4, BASE_R + 4), Vector2(BASE_R + 4, BASE_R + 4) * 2.0))
	for k in pieces: _dress(k)
	for t in floors:
		var spr: Sprite2D = floors[t].spr
		spr.position = Iso.to_screen(t.x, t.y, _floor_z(t)).round()
	for t in founds: _found_faces(t)

## Foundation height for a patch whose first tile is t: a touching foundation's or claimed building's
## height, else just above the highest ground corner.
func found_level(t: Vector2i) -> float:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if founds.has(t + d): return founds[t + d].top
		var b := _claimed_at(t + d)
		if b: return b.h0
	var hi := -INF
	for v in tile_verts(t): hi = maxf(hi, w.vh(v.x, v.y))
	return ceilf((hi + 3.0) / 2.0) * 2.0

# ------------------------------------------------------------------ rules
func cost_of(t: String, p: String) -> Dictionary:
	if p == "floor": return FLOOR_COST.get(t, {})
	if p == "foundation": return FOUND_COST.get(t, {})
	var c: Dictionary = COST[t].duplicate()
	if p == "half":
		for k in c: c[k] = maxi(1, int(ceil(c[k] * 0.5)))
	elif p in ["door", "gate"]:
		c["scrap"] = c.get("scrap", 0) + 1
	return c

func affordable(c: Dictionary) -> bool:
	for k in c:
		if g.stash.get(k, 0) < c[k]: return false
	return true

func _someone_on(probe_seg: World.Seg, tile: Vector2i, r: float) -> bool:
	for act in [g.player, g.dog] + g.enemies + g.npcs:
		if not is_instance_valid(act): continue
		if probe_seg != null and World.seg_dist(act.wpos, probe_seg) < r: return true
		if tile.x >= 0 and Vector2i(int(floor(act.wpos.x)), int(floor(act.wpos.y))) == tile: return true
	return false

func edge_problem(k: Vector3i) -> String:
	var a := Vector2(k.x, k.y)
	var b := a + (Vector2(1, 0) if k.z == 0 else Vector2(0, 1))
	if a.x < 1 or a.y < 1 or b.x > World.N - 1 or b.y > World.N - 1: return "edge of the map"
	if pieces.has(k) or w.edge_taken(k.x, k.y, k.z): return "already a wall here"
	if not in_base((a + b) * 0.5): return "too far from camp"
	var sides := edge_sides(k)
	for t in sides:
		var id := w.building_at(t.x + 0.5, t.y + 0.5)
		if id != 0 and not id in claimed: return "inside a building you don't own"
		if not founds.has(t) and id == 0 and w.T[w.idx(t.x, t.y)] == World.TREE: return "a tree is in the way"
	if not _on_found(k) and is_nan(_bld_corner(Vector2i(k.x, k.y))) and not _level_ok(edge_verts(k), 10.0):
		return "too steep (lay a foundation first)"
	var probe := World.Seg.new()
	probe.a = a; probe.b = b
	if _someone_on(probe, Vector2i(-1, -1), 0.4): return "someone is standing there"
	return ""

func floor_problem(t: Vector2i) -> String:
	if t.x < 1 or t.y < 1 or t.x > World.N - 2 or t.y > World.N - 2: return "edge of the map"
	if floors.has(t): return "already floored"
	if not in_base(Vector2(t.x + 0.5, t.y + 0.5)): return "too far from camp"
	if w.building_at(t.x + 0.5, t.y + 0.5) != 0: return "inside a building"
	if founds.has(t): return ""
	if w.T[w.idx(t.x, t.y)] == World.TREE: return "a tree is in the way"
	if not _level_ok(tile_verts(t), 8.0): return "too steep (lay a foundation first)"
	return ""

func found_problem(t: Vector2i, top: float) -> String:
	if t.x < 1 or t.y < 1 or t.x > World.N - 2 or t.y > World.N - 2: return "edge of the map"
	if founds.has(t) or floors.has(t): return "already built on"
	if not in_base(Vector2(t.x + 0.5, t.y + 0.5)): return "too far from camp"
	if w.building_at(t.x + 0.5, t.y + 0.5) != 0: return "inside a building"
	if w.T[w.idx(t.x, t.y)] == World.TREE: return "a tree is in the way"
	for v in tile_verts(t):
		if vgroup.has(v): return "on levelled ground (build next to it)"
	var lo := INF; var hi := -INF
	for v in tile_verts(t):
		lo = minf(lo, w.vh(v.x, v.y)); hi = maxf(hi, w.vh(v.x, v.y))
	if hi > top + 1.0: return "the ground is higher than this foundation"
	if top - lo > MAX_FACE: return "too high above the ground"
	if _someone_on(null, t, 0.0): return "someone is standing there"
	return ""

# ------------------------------------------------------------------ placing
func _commit() -> void:
	var ts := targets(drag_a, drag_b)
	if ts.is_empty(): return
	g.audio.play("build", Vector2.INF, -5.0)
	if piece == "remove":
		for k in ts: remove(k)
		return
	var placed := 0
	var dug := false
	var why := ""
	var c := cost_of(tier, piece)
	var ftop := found_level(ts[0]) if piece == "foundation" else 0.0
	for k in ts:
		var prob := ""
		match piece:
			"floor": prob = floor_problem(k)
			"foundation": prob = found_problem(k, ftop)
			_: prob = edge_problem(k)
		if prob != "":
			why = prob
			continue
		if not affordable(c):
			why = "not enough materials"
			break
		for r in c: g.stash[r] -= c[r]
		match piece:
			"floor":
				if not founds.has(k): dug = _level(tile_verts(k)) or dug
				place_floor(k, tier)
			"foundation":
				place_found(k, tier, ftop)
			_:
				if not _on_found(k) and is_nan(_bld_corner(Vector2i(k.x, k.y))): dug = _level(edge_verts(k)) or dug
				place(k, tier, piece)
		placed += 1
	if dug: _relevel_done()
	if placed == 0 and why != "":
		g.hud.toast("Can't build: %s." % why)
	elif why != "":
		g.hud.toast("Built %d. Stopped: %s." % [placed, why])
	if bar: bar.refresh()

func place(k: Vector3i, t: String, p: String) -> World.Seg:
	var s := World.Seg.new()
	s.a = Vector2(k.x, k.y)
	s.b = s.a + (Vector2(1, 0) if k.z == 0 else Vector2(0, 1))
	s.axis = k.z
	s.side = "b"
	s.fl = 0
	s.bid = -1
	s.tier = t
	s.piece = p
	s.hp = HP[t] * (0.5 if p == "half" else 1.0)
	s.solid = p != "doorway"
	s.see = p in ["window", "half"] or t == "fence"
	if p in ["door", "gate"]:
		s.is_door = true
		s.door = "closed"
		s.mode = "door"
		s.door_hp = s.hp
	w.add_free_seg(s)
	var spr := Sprite2D.new()
	spr.centered = false
	add_child(spr)
	pieces[k] = {"seg": s, "spr": spr}
	_dress(k)
	return s

func _floor_z(t: Vector2i) -> float:
	return founds[t].top if founds.has(t) else w.vh(t.x, t.y)

func place_floor(t: Vector2i, tr: String) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = Assets.tex("bf_" + tr)
	spr.offset = Assets.off("bf_" + tr)
	spr.position = Iso.to_screen(t.x, t.y, _floor_z(t)).round()
	spr.z_as_relative = false
	spr.z_index = Iso.z_for(t.x + t.y + 0.03, 3)
	add_child(spr)
	floors[t] = {"tier": tr, "spr": spr}

func place_found(t: Vector2i, tr: String, top: float) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = Assets.tex("bf_" + tr)
	spr.offset = Assets.off("bf_" + tr)
	spr.position = Iso.to_screen(t.x, t.y, top).round()
	spr.z_as_relative = false
	spr.z_index = Iso.z_for(t.x + t.y + 0.02, 3)
	add_child(spr)
	founds[t] = {"tier": tr, "top": top, "spr": spr, "faces": []}
	w.plat[t] = top
	for n in [t, t - Vector2i(1, 0), t - Vector2i(0, 1)]:
		if founds.has(n): _found_faces(n)

## The two sides of a foundation the camera sees (south and east), down to the ground or to a lower
## neighbouring foundation.
func _found_faces(t: Vector2i) -> void:
	var f: Dictionary = founds[t]
	for s in f.faces: (s as Sprite2D).queue_free()
	f.faces = []
	for side in [[Vector2i(0, 1), Vector3i(t.x, t.y + 1, 0)], [Vector2i(1, 0), Vector3i(t.x + 1, t.y, 1)]]:
		var n: Vector2i = t + side[0]
		var e: Vector3i = side[1]
		var base: float
		if founds.has(n):
			base = founds[n].top
		else:
			var vs := edge_verts(e)
			base = minf(w.vh(vs[0].x, vs[0].y), w.vh(vs[1].x, vs[1].y))
		var h: float = f.top - base
		if h < 1.0: continue
		var hq := clampi(int(ceil(h / 4.0)) * 4, 4, int(MAX_FACE))
		var tx := "bff_%s_%s%d" % [f.tier, "x" if e.z == 0 else "y", hq]
		var s := Sprite2D.new()
		s.centered = false
		s.texture = Assets.tex(tx)
		s.offset = Assets.off(tx)
		s.position = Iso.to_screen(e.x, e.y, f.top).round()
		s.z_as_relative = false
		s.z_index = Iso.z_for(t.x + t.y + 1.0, 1)
		add_child(s)
		f.faces.append(s)

func remove(k) -> void:
	var refund := {}
	if k is World.Seg:                                   # a wall of a claimed building
		var s: World.Seg = k
		w.remove_free_seg(s)
		var b: World.Bld = w.buildings[s.bid - 1]
		b.segs.erase(s)
		for v in g.views:
			if v.b == b: v.remove_seg(s)
		refund = {"scrap": 2}
	elif k is Vector3i and pieces.has(k):
		var s: World.Seg = pieces[k].seg
		refund = cost_of(s.tier, s.piece)
		w.remove_free_seg(s)
		_door_idle.erase(s)
		(pieces[k].spr as Sprite2D).queue_free()
		pieces.erase(k)
	elif k is Vector2i and floors.has(k):
		refund = cost_of(floors[k].tier, "floor")
		(floors[k].spr as Sprite2D).queue_free()
		floors.erase(k)
	elif k is Vector2i and founds.has(k):
		for pk in pieces:
			if k in edge_sides(pk):
				g.hud.toast("Take down the walls on this foundation first.")
				return
		refund = cost_of(founds[k].tier, "foundation")
		for s in founds[k].faces: (s as Sprite2D).queue_free()
		(founds[k].spr as Sprite2D).queue_free()
		founds.erase(k)
		w.plat.erase(k)
		for n in [k - Vector2i(1, 0), k - Vector2i(0, 1)]:
			if founds.has(n): _found_faces(n)
	else:
		return
	var full: bool = k is World.Seg                     # salvage from a building wall: no halving
	for r in refund: g.stash[r] = g.stash.get(r, 0) + (int(refund[r]) if full else int(floor(refund[r] * 0.5)))
	if bar: bar.refresh()

func tex_for(s: World.Seg) -> String:
	var p := s.piece
	if s.is_door and s.door == "open": p = "gateopen" if s.piece == "gate" else "doorway"
	return "bw_%s_%s_%s" % [s.tier, p, "x" if s.axis == 0 else "y"]

func _dress(k: Vector3i) -> void:
	var s: World.Seg = pieces[k].seg
	var spr: Sprite2D = pieces[k].spr
	var tx := tex_for(s)
	spr.texture = Assets.tex(tx)
	spr.offset = Assets.off(tx)
	spr.position = Iso.to_screen(s.a.x, s.a.y, edge_z(k)).round()
	spr.z_as_relative = false
	spr.z_index = Iso.z_for((s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5, 2)

## A built door opened or closed (Game.set_door routes bid -1 here).
func refresh(s: World.Seg) -> void:
	for k in pieces:
		if pieces[k].seg == s:
			_dress(k)
			return

# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if g == null or g.player == null: return
	_doors(delta)
	_fade()
	if not active: return
	if g.hud.menu_open():
		_show_ghosts([], [])
		return
	if can_build_here() != "":
		g.hud.toast(can_build_here() + " Leaving build mode.")
		leave()
		return
	var ts := []
	if dragging: ts = targets(drag_a, drag_b)
	elif hover.x >= 0.0: ts = targets(hover, hover)
	var ok := []
	var c := cost_of(tier, piece)
	var budget := g.stash.duplicate()
	var ftop := found_level(ts[0]) if piece == "foundation" and not ts.is_empty() else 0.0
	for k in ts:
		var good := true
		match piece:
			"remove": good = true
			"floor": good = floor_problem(k) == ""
			"foundation": good = found_problem(k, ftop) == ""
			_: good = edge_problem(k) == ""
		if good and piece != "remove":
			for r in c:
				if budget.get(r, 0) < c[r]: good = false
			if good:
				for r in c: budget[r] -= c[r]
		ok.append(good)
	_show_ghosts(ts, ok, ftop)

func _show_ghosts(ts: Array, ok: Array, ftop: float = 0.0) -> void:
	while ghosts.size() < ts.size():
		var s := Sprite2D.new()
		s.centered = false
		s.z_as_relative = false
		s.z_index = 4080
		add_child(s)
		ghosts.append(s)
	for i in ghosts.size():
		var gs: Sprite2D = ghosts[i]
		if i >= ts.size():
			gs.visible = false
			continue
		gs.visible = true
		var k = ts[i]
		var tx := ""
		var pos := Vector2.ZERO
		if k is World.Seg:
			var bs: World.Seg = k
			tx = "bw_concrete_wall_%s" % ("x" if bs.axis == 0 else "y")
			pos = Iso.to_screen(bs.a.x, bs.a.y, w.buildings[bs.bid - 1].h0)
		elif k is Vector2i:
			var trr: String = tier
			if piece == "remove": trr = floors[k].tier if floors.has(k) else founds[k].tier
			tx = "bf_" + trr
			var z := _floor_z(k)
			if piece == "foundation": z = ftop
			elif piece == "floor" and not founds.has(k): z = _level_for(tile_verts(k))
			pos = Iso.to_screen(k.x, k.y, z)
		else:
			var s: World.Seg = pieces[k].seg if piece == "remove" else null
			var tr: String = s.tier if s else tier
			var pc: String = s.piece if s else piece
			tx = "bw_%s_%s_%s" % [tr, pc, "x" if k.z == 0 else "y"]
			pos = Iso.to_screen(k.x, k.y, edge_z(k))
		gs.texture = Assets.tex(tx)
		gs.offset = Assets.off(tx)
		gs.position = pos.round()
		if piece == "remove": gs.modulate = Color(1.0, 0.45, 0.35, 0.75)
		elif ok[i]: gs.modulate = Color(0.55, 1.0, 0.6, 0.7)
		else: gs.modulate = Color(1.0, 0.35, 0.3, 0.6)

## Walls you're standing behind turn see-through, like buildings do.
func _fade() -> void:
	var pp: Vector2 = g.player.position
	var pd: float = g.player.wpos.x + g.player.wpos.y
	for k in pieces:
		var s: World.Seg = pieces[k].seg
		var spr: Sprite2D = pieces[k].spr
		var d := (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5 - pd
		var cx := spr.position.x + (12.0 if s.axis == 0 else -12.0)
		var hide := d > 0.0 and d < 3.5 and absf(cx - pp.x) < 30.0 and pp.y > spr.position.y - 48.0 and pp.y < spr.position.y + 10.0 and s.piece != "half"
		spr.modulate.a = 0.35 if hide else 1.0

## Built doors and gates swing shut on their own once nobody is in the doorway.
func _doors(delta: float) -> void:
	for k in pieces:
		var s: World.Seg = pieces[k].seg
		if not s.is_door or s.door != "open": continue
		var busy := false
		for act in [g.player, g.dog] + g.enemies:
			if is_instance_valid(act) and World.seg_dist(act.wpos, s) < 0.75: busy = true
		if busy:
			_door_idle[s] = 0.0
			continue
		_door_idle[s] = _door_idle.get(s, 0.0) + delta
		if _door_idle[s] > 2.0:
			_door_idle.erase(s)
			g.set_door(s, "closed")
