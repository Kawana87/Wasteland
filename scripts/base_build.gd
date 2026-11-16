class_name BaseBuild
extends Node2D
## Player base building. Wall pieces sit on tile EDGES (like building walls, so collision, shots,
## doors and draw order all work the same way); floors sit on tiles.
## Build mode: pick a material tier and a piece, then tap (or click) to place one, or drag to lay a
## run of walls / a patch of floor. Rotation only matters for single taps: a drag picks its own axis.

const TIERS := ["scrap", "wood", "stone", "concrete", "fence"]
const PIECES := ["wall", "window", "door", "doorway", "half", "gate", "floor", "remove"]
const FENCE_PIECES := ["wall", "gate", "remove"]
const COST := {"scrap": {"scrap": 2}, "wood": {"wood": 2}, "stone": {"scrap": 3, "wood": 1},
	"concrete": {"scrap": 5}, "fence": {"scrap": 1}}
const FLOOR_COST := {"scrap": {"scrap": 1}, "wood": {"wood": 1}, "stone": {"scrap": 1, "wood": 1}, "concrete": {"scrap": 2}}
const HP := {"scrap": 100.0, "wood": 200.0, "stone": 450.0, "concrete": 900.0, "fence": 60.0}
const BASE_R := 12.0           # how far from a camp you may build
const NAMES := {"scrap": "Scrap", "wood": "Wood", "stone": "Stone", "concrete": "Concrete", "fence": "Fence",
	"wall": "Wall", "window": "Window", "door": "Door", "doorway": "Doorway", "half": "Half wall", "gate": "Gate",
	"floor": "Floor", "remove": "Remove"}

var g: Game
var w: World
var pieces := {}               # Vector3i(x, y, axis) -> {seg, spr}
var floors := {}               # Vector2i -> {tier, spr}
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
	g.hud.toast("Build mode: tap to place, drag to lay a run of walls. Walk with the left stick / WASD.")

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
		z = w.hz(clampf(wp.x, 0.0, World.N - 1.0), clampf(wp.y, 0.0, World.N - 1.0))
	return wp

# ------------------------------------------------------------------ targets
static func snap(p: Vector2, ax: int) -> Vector3i:
	if ax == 0: return Vector3i(int(floor(p.x)), int(round(p.y)), 0)
	return Vector3i(int(round(p.x)), int(floor(p.y)), 1)

## The edges (walls) or tiles (floors) a tap / drag from a to b covers.
func targets(a: Vector2, b: Vector2) -> Array:
	var out := []
	if piece == "floor":
		var x0 := int(floor(minf(a.x, b.x))); var x1 := int(floor(maxf(a.x, b.x)))
		var y0 := int(floor(minf(a.y, b.y))); var y1 := int(floor(maxf(a.y, b.y)))
		for y in range(y0, mini(y1, y0 + 11) + 1):
			for x in range(x0, mini(x1, x0 + 11) + 1):
				out.append(Vector2i(x, y))
		return out
	if piece == "remove":
		var k = _piece_near(b)
		if k != null: out.append(k)
		elif floors.has(Vector2i(int(floor(b.x)), int(floor(b.y)))): out.append(Vector2i(int(floor(b.x)), int(floor(b.y))))
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

func _piece_near(p: Vector2):
	var best = null
	var bd := 0.45
	for ax in [0, 1]:
		var k := snap(p, ax)
		if pieces.has(k):
			var s: World.Seg = pieces[k].seg
			var d := World.seg_dist(p, s)
			if d < bd: bd = d; best = k
	return best

# ------------------------------------------------------------------ rules
func cost_of(t: String, p: String) -> Dictionary:
	if p == "floor": return FLOOR_COST.get(t, {})
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

func edge_problem(k: Vector3i) -> String:
	var a := Vector2(k.x, k.y)
	var b := a + (Vector2(1, 0) if k.z == 0 else Vector2(0, 1))
	if a.x < 1 or a.y < 1 or b.x > World.N - 1 or b.y > World.N - 1: return "edge of the map"
	if pieces.has(k) or w.edge_taken(k.x, k.y, k.z): return "already a wall here"
	if not in_base((a + b) * 0.5): return "too far from camp"
	if absf(w.hz(a.x, a.y) - w.hz(b.x, b.y)) > 10.0: return "too steep"
	var sides := [Vector2i(k.x, k.y - 1), Vector2i(k.x, k.y)] if k.z == 0 else [Vector2i(k.x - 1, k.y), Vector2i(k.x, k.y)]
	for t in sides:
		if w.building_at(t.x + 0.5, t.y + 0.5) != 0: return "inside a building"
		if w.T[w.idx(t.x, t.y)] == World.TREE: return "a tree is in the way"
	var probe := World.Seg.new()
	probe.a = a; probe.b = b
	for act in [g.player, g.dog] + g.enemies + g.npcs:
		if is_instance_valid(act) and World.seg_dist(act.wpos, probe) < 0.4: return "someone is standing there"
	return ""

func floor_problem(t: Vector2i) -> String:
	if t.x < 1 or t.y < 1 or t.x > World.N - 2 or t.y > World.N - 2: return "edge of the map"
	if floors.has(t): return "already floored"
	if not in_base(Vector2(t.x + 0.5, t.y + 0.5)): return "too far from camp"
	if w.building_at(t.x + 0.5, t.y + 0.5) != 0: return "inside a building"
	if w.T[w.idx(t.x, t.y)] == World.TREE: return "a tree is in the way"
	var hs := [w.vh(t.x, t.y), w.vh(t.x + 1, t.y), w.vh(t.x, t.y + 1), w.vh(t.x + 1, t.y + 1)]
	if hs.max() - hs.min() > 8.0: return "too steep"
	return ""

# ------------------------------------------------------------------ placing
func _commit() -> void:
	var ts := targets(drag_a, drag_b)
	if ts.is_empty(): return
	if piece == "remove":
		for k in ts: remove(k)
		return
	var placed := 0
	var why := ""
	var c := cost_of(tier, piece)
	for k in ts:
		var prob: String = floor_problem(k) if piece == "floor" else edge_problem(k)
		if prob != "":
			why = prob
			continue
		if not affordable(c):
			why = "not enough materials"
			break
		for r in c: g.stash[r] -= c[r]
		if piece == "floor": place_floor(k, tier)
		else: place(k, tier, piece)
		placed += 1
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

func place_floor(t: Vector2i, tr: String) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = Assets.tex("bf_" + tr)
	spr.offset = Assets.off("bf_" + tr)
	var z := (w.vh(t.x, t.y) + w.vh(t.x + 1, t.y) + w.vh(t.x, t.y + 1) + w.vh(t.x + 1, t.y + 1)) * 0.25
	spr.position = Iso.to_screen(t.x, t.y, z).round()
	spr.z_as_relative = false
	spr.z_index = Iso.z_for(t.x + t.y + 0.02, 3)
	add_child(spr)
	floors[t] = {"tier": tr, "spr": spr}

func remove(k) -> void:
	var refund := {}
	if k is Vector3i and pieces.has(k):
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
	else:
		return
	for r in refund: g.stash[r] = g.stash.get(r, 0) + int(floor(refund[r] * 0.5))
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
	spr.position = Iso.to_screen(s.a.x, s.a.y, minf(w.hz(s.a.x, s.a.y), w.hz(s.b.x, s.b.y))).round()
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
	for k in ts:
		var good := true
		if piece == "remove": good = true
		elif piece == "floor": good = floor_problem(k) == ""
		else: good = edge_problem(k) == ""
		if good and piece != "remove":
			for r in c:
				if budget.get(r, 0) < c[r]: good = false
			if good:
				for r in c: budget[r] -= c[r]
		ok.append(good)
	_show_ghosts(ts, ok)

func _show_ghosts(ts: Array, ok: Array) -> void:
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
		if k is Vector2i:
			tx = "bf_" + (floors[k].tier if piece == "remove" else tier)
			pos = Iso.to_screen(k.x, k.y, w.vh(k.x, k.y))
		else:
			var s: World.Seg = pieces[k].seg if piece == "remove" else null
			var tr: String = s.tier if s else tier
			var pc: String = s.piece if s else piece
			tx = "bw_%s_%s_%s" % [tr, pc, "x" if k.z == 0 else "y"]
			pos = Iso.to_screen(k.x, k.y, minf(w.hz(k.x, k.y), w.hz(k.x + (1 if k.z == 0 else 0), k.y + (1 if k.z == 1 else 0))))
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
