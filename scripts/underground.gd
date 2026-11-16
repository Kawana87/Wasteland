class_name Underground
## Caves, mines, sewers and old shelters: small maps of their own, reached from entrances out in the
## Wastes (cave mouths in the hills, mine heads in the canyons, manholes in Port Sterling, shelter
## doors set into the rock). Each is built from its entrance's id, so it's the same place every time,
## with something at the bottom worth the trip.
##
## An underground map is a World with only its first rows allocated (62x62 usable tiles inside chunks
## 0..1), so all the rendering, collision and AI code works unchanged.

const SIZE := 62
const NAMES := {
	"cave": ["Howling Cave", "Bat Hollow", "Drip Cave", "The Throat", "Glowworm Grotto", "Coyote Den Cave", "Echo Hole", "Bonepile Cave"],
	"mine": ["Lucky Strike Mine", "Copper Queen Mine", "Shaft No. 9", "Widowmaker Mine", "Red Vein Dig", "Old Sterling Colliery", "Prospect Hole"],
	"sewer": ["Sterling Storm Drain", "Main Sewer Junction", "Pump Station 4", "Overflow Tunnels", "The Underways"],
	"vault": ["Civil Defense Shelter 12", "Sterling Shelter 7", "Bunker Delta", "Project Bluebird Shelter", "Shelter 3 (Abandoned)"],
}
const BOSSES := {
	"cave": ["The Den Mother", "Old Gnasher", "Blind King"], "mine": ["The Foreman", "Pickaxe Pete", "Lamp-Eyes"],
	"sewer": ["The Bloated One", "Sewer King", "Drain Rat Queen"], "vault": ["The Custodian", "Shelter Warden", "Patient Zero"]}

static func info(portal: String) -> Dictionary:
	var kind := portal.get_slice(":", 0)
	var h := absi(hash(portal))
	var names: Array = NAMES.get(kind, ["Underground"])
	return {"kind": kind, "name": names[h % names.size()], "boss": BOSSES.get(kind, ["The Thing"])[(h / 7) % 3]}

static func build(portal: String, seed_value: int, state: Dictionary) -> World:
	var inf := info(portal)
	var kind: String = inf.kind
	var w := World.new()
	w.interior = true
	w.rows = 68
	w.bounds = Vector2i(2, 2)
	w.seed_value = seed_value
	w.rng.seed = hash(portal) + seed_value
	var n := w.rows * World.N
	w.T.resize(n); w.T.fill(World.ROCK)
	w.BID.resize(n); w.BID.fill(0)
	w.V.resize(n); w.V.fill(0)
	w.G.resize(n); w.G.fill(18 if kind == "vault" or kind == "sewer" else 17)
	w.CL.resize(n); w.CL.fill(0)
	var nv := (w.rows + 1) * World.NV
	w.VH.resize(nv); w.VH.fill(0.0)
	w.road_d.resize(nv); w.road_d.fill(99.0)
	w.road_h.resize(nv); w.road_h.fill(0.0)
	w.base_done.resize(World.NC * World.NC); w.base_done.fill(1)
	w.content_done.resize(World.NC * World.NC); w.content_done.fill(1)
	w.opened = state.get("opened", {})
	w.killed = state.get("killed", {})
	var grid := []       # floor cells, local
	var rng: RandomNumberGenerator = w.rng
	var floor_g: int = {"cave": 14, "mine": 2, "sewer": 16, "vault": 15}[kind]
	var open := {}
	match kind:
		"cave": open = _cave(rng)
		"mine": open = _mine(rng)
		"sewer": open = _sewer(rng)
		"vault": open = _vault(rng)
	for c in open:
		var x: int = c.x + 1
		var y: int = c.y + 1
		var i := y * World.N + x
		w.T[i] = World.WATER if open[c] == 2 else World.GRASS
		w.G[i] = floor_g
		w.V[i] = rng.randi_range(0, 3)
	# walls: a vertex is raised only where all four tiles around it are rock, so walls slope into
	# the rock and floors stay flat
	var wall_h := 46.0 if kind != "vault" else 52.0
	for vy in range(0, w.rows):
		for vx in range(0, SIZE + 3):
			var all_rock := true
			for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var x: int = vx + o.x
				var y: int = vy + o.y
				if x >= 0 and y >= 0 and y < w.rows and w.T[y * World.N + x] != World.ROCK:
					all_rock = false
			var hh := 0.0
			if all_rock:
				hh = wall_h + (rng.randf() * 10.0 if kind == "cave" else 0.0)
			elif kind == "cave":
				hh = rng.randf() * 2.0
			if kind == "sewer" and not all_rock:
				var wet := false
				for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
					var x: int = vx + o.x
					var y: int = vy + o.y
					if x >= 0 and y >= 0 and w.T[y * World.N + x] == World.WATER: wet = true
				if wet: hh = -6.0
			w.VH[vy * World.NV + vx] = hh
	# entry: the open cell nearest the top-left; the far end (by walking distance) holds the boss
	var cells: Array = open.keys().filter(func(c): return open[c] == 1)
	cells.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	var entry: Vector2i = cells[0]
	var dist := _bfs(open, entry)
	var far := entry
	var fd := 0
	for c in dist:
		if dist[c] > fd and open[c] == 1: fd = dist[c]; far = c
	var E := Vector2(entry.x + 1.5, entry.y + 1.5)
	var F := Vector2(far.x + 1.5, far.y + 1.5)
	w.start = E + Vector2(1.0, 1.0)
	w._begin()
	var ex := w.add_decor("ladder_up", E, true, Vector2(0.2, 0.2))
	ex.portal = "exit"
	w.add_decor("lamp" if kind != "cave" else "crystal", E + Vector2(-0.6, 1.4), true, Vector2(0.1, 0.1))
	# dressing and lights along the way
	var props: Array = {"cave": ["stalagmite", "rock0", "rock1", "bones", "rock2", "stalagmite"],
		"mine": ["mine_support", "minecart", "barrel_rust", "rubble1", "rock1", "bones"],
		"sewer": ["pipes", "trashbag", "barrel_toxic", "rubble0", "bones", "pipes"],
		"vault": ["furn_locker_a", "barrel", "papers", "rubble0", "furn_filing_a", "bones"]}[kind]
	var lights: Array = {"cave": ["crystal"], "mine": ["lamp", "mine_support"], "sewer": ["lamp"], "vault": ["lamp"]}[kind]
	var solid := ["stalagmite", "minecart", "barrel_rust", "barrel_toxic", "barrel", "furn_locker_a", "furn_filing_a", "pipes", "mine_support"]
	w._shuffle(cells)
	var placed := 0
	for c in cells:
		if placed > 70: break
		var p := Vector2(c.x + 1.5, c.y + 1.5) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		if p.distance_to(E) < 3.0: continue
		var walls := _rock_n(w, c.x + 1, c.y + 1)
		if walls == 0 and rng.randf() < 0.85: continue      # props hug the walls
		var nm: String = props[rng.randi() % props.size()]
		if placed % 6 == 0: nm = lights[rng.randi() % lights.size()]
		w.add_decor(nm, p, nm in solid or nm == "lamp" or nm == "crystal", Vector2(0.2, 0.2), nm in ["papers", "bones", "rock2"])
		placed += 1
	# enemies spread by distance from the entry, thicker toward the end
	var pool: Array = {"cave": ["rat", "rat", "shellback", "ghoul"], "mine": ["ghoul", "ghoul", "rat"], "sewer": ["rat", "rat", "ghoul", "shellback"], "vault": ["ghoul", "ghoul", "raider"]}[kind]
	var groups := 0
	for c in cells:
		if groups > 9: break
		var d: int = dist.get(c, 0)
		if d < 10 or rng.randf() > 0.06 + 0.1 * float(d) / maxf(fd, 1): continue
		var p := Vector2(c.x + 1.5, c.y + 1.5)
		if p.distance_to(F) < 5.0: continue
		var t: String = pool[rng.randi() % pool.size()]
		for k in (rng.randi_range(2, 4) if t == "rat" else rng.randi_range(1, 2)):
			w.spawns.append({"type": t, "pos": p + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)), "home": p, "home_r": 4.0, "loc": portal})
		groups += 1
	# the boss and its hoard at the far end
	var btype: String = {"cave": "brute", "mine": "ghoul", "sewer": "shellback", "vault": "brute"}[kind]
	w.spawns.append({"type": btype, "pos": F, "home": F, "home_r": 3.0, "loc": portal, "boss": inf.boss})
	for k in 2:
		w.spawns.append({"type": pool[0], "pos": F + Vector2(1.2, -0.8 + k * 1.6), "home": F, "home_r": 3.0, "loc": portal})
	for k in 2:
		var cr := World.Crate.new()
		cr.pos = F + Vector2(-1.2 + k * 2.4, 1.0)
		cr.kind = "cache"
		if k == 0: cr.set_meta("extra", Items.gear_of_tier(3, rng))
		w.crates.append(cr)
	# other loot along the way
	for c in cells:
		if rng.randf() > 0.012: continue
		var cr := World.Crate.new()
		cr.pos = Vector2(c.x + 1.5, c.y + 1.5)
		if cr.pos.distance_to(E) < 4.0: continue
		cr.kind = "crate" if rng.randf() < 0.7 else "cache"
		if kind == "mine" and rng.randf() < 0.5: cr.set_meta("extra", "copper")
		if kind == "vault" and rng.randf() < 0.5: cr.set_meta("extra", "tech")
		w.crates.append(cr)
	w._finish()
	return w

static func _rock_n(w: World, x: int, y: int) -> int:
	var n := 0
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if w.T[(y + o.y) * World.N + x + o.x] == World.ROCK: n += 1
	return n

static func _bfs(open: Dictionary, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q := [from]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if open.has(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist

## Keep only the biggest connected part.
static func _largest(open: Dictionary) -> Dictionary:
	var seen := {}
	var best := {}
	for c in open:
		if seen.has(c): continue
		var part := _bfs(open, c)
		for k in part: seen[k] = true
		if part.size() > best.size(): best = part
	var out := {}
	for c in best: out[c] = open[c]
	return out

static func _cave(rng: RandomNumberGenerator) -> Dictionary:
	var g := {}
	for y in SIZE:
		for x in SIZE:
			var edge := x < 2 or y < 2 or x > SIZE - 3 or y > SIZE - 3
			g[Vector2i(x, y)] = 0 if edge else (1 if rng.randf() > 0.44 else 0)
	for it in 5:
		var ng := {}
		for y in SIZE:
			for x in SIZE:
				var walls := 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if g.get(Vector2i(x + ox, y + oy), 0) == 0: walls += 1
				ng[Vector2i(x, y)] = 0 if walls >= 5 or x < 2 or y < 2 or x > SIZE - 3 or y > SIZE - 3 else 1
		g = ng
	var open := {}
	for c in g:
		if g[c] == 1: open[c] = 1
	# a few pools of standing water
	var out := _largest(open)
	var keys := out.keys()
	for k in 3:
		var c: Vector2i = keys[rng.randi() % keys.size()]
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var q := c + Vector2i(ox, oy)
				if out.has(q) and absi(ox) + absi(oy) < 2 and rng.randf() < 0.8: out[q] = 2
	return _largest_walkable(out)

static func _largest_walkable(open: Dictionary) -> Dictionary:
	var walk := {}
	for c in open:
		if open[c] == 1: walk[c] = 1
	var keep := _largest(walk)
	var out := {}
	for c in open:
		if keep.has(c) or open[c] == 2: out[c] = open[c]
	return out

static func _carve(open: Dictionary, a: Vector2i, b: Vector2i, wdt: int) -> void:
	var p := a
	while p != b:
		for oy in range(0, wdt):
			for ox in range(0, wdt):
				var q := p + Vector2i(ox, oy)
				if q.x > 0 and q.y > 0 and q.x < SIZE - 1 and q.y < SIZE - 1: open[q] = 1
		if p.x != b.x and (p.y == b.y or (p.x * 7 + p.y * 13) % 2 == 0): p.x += signi(b.x - p.x)
		else: p.y += signi(b.y - p.y)

static func _room(open: Dictionary, c: Vector2i, rx: int, ry: int, v: int = 1) -> void:
	for y in range(c.y - ry, c.y + ry + 1):
		for x in range(c.x - rx, c.x + rx + 1):
			if x > 0 and y > 0 and x < SIZE - 1 and y < SIZE - 1: open[Vector2i(x, y)] = v

static func _mine(rng: RandomNumberGenerator) -> Dictionary:
	var open := {}
	var nodes := [Vector2i(4, 4)]
	_room(open, nodes[0], 2, 2)
	for k in 12:
		var from: Vector2i = nodes[rng.randi() % nodes.size()]
		var to := Vector2i(clampi(from.x + rng.randi_range(-18, 22), 4, SIZE - 6), clampi(from.y + rng.randi_range(-18, 22), 4, SIZE - 6))
		_carve(open, from, to, 2)
		if rng.randf() < 0.6: _room(open, to, rng.randi_range(2, 4), rng.randi_range(2, 3))
		nodes.append(to)
	return _largest(open)

static func _sewer(rng: RandomNumberGenerator) -> Dictionary:
	var open := {}
	# trunk tunnels on a grid: 2-wide channel of water with a walkway each side
	for line in range(5, SIZE - 5, 14):
		for t in range(3, SIZE - 3):
			for o in range(-2, 2):
				var v := 2 if o == -1 or o == 0 else 1
				var a := Vector2i(t, line + o)
				var b := Vector2i(line + o, t)
				open[a] = mini(open.get(a, 9), v) if open.has(a) else v
				open[b] = mini(open.get(b, 9), v) if open.has(b) else v
	# crossings are dry grates
	for gy in range(5, SIZE - 5, 14):
		for gx in range(5, SIZE - 5, 14):
			_room(open, Vector2i(gx, gy), 2, 2)
	# bridges every so often, and maintenance rooms off the walkways
	for line in range(5, SIZE - 5, 14):
		for t in range(10, SIZE - 6, 9):
			for o in range(-1, 1):
				open[Vector2i(t, line + o)] = 1
				open[Vector2i(line + o, t)] = 1
	for k in 6:
		var line := 5 + 14 * rng.randi_range(0, 3)
		var t := rng.randi_range(8, SIZE - 8)
		var horiz := rng.randf() < 0.5
		var side := 1 if rng.randf() < 0.5 else -1
		var c := Vector2i(t, line + side * 5) if horiz else Vector2i(line + side * 5, t)
		_room(open, c, 2, 2)
		_carve(open, c, Vector2i(t, line + side * 2) if horiz else Vector2i(line + side * 2, t), 1)
	var out := {}
	for c in open:
		if c.x > 0 and c.y > 0 and c.x < SIZE - 1 and c.y < SIZE - 1: out[c] = open[c]
	return _largest_walkable(out)

static func _vault(rng: RandomNumberGenerator) -> Dictionary:
	var open := {}
	var rooms := []
	for t in 60:
		var rw := rng.randi_range(3, 6)
		var rh := rng.randi_range(3, 5)
		var c := Vector2i(rng.randi_range(rw + 2, SIZE - rw - 3), rng.randi_range(rh + 2, SIZE - rh - 3))
		var ok := true
		for r in rooms:
			if absi(r[0].x - c.x) < r[1] + rw + 3 and absi(r[0].y - c.y) < r[2] + rh + 3: ok = false
		if not ok: continue
		rooms.append([c, rw, rh])
		_room(open, c, rw, rh)
		if rooms.size() >= 10: break
	rooms.sort_custom(func(a, b): return a[0].x + a[0].y < b[0].x + b[0].y)
	for i in range(1, rooms.size()):
		_carve(open, rooms[i - 1][0], rooms[i][0], 2)
	if rooms.size() > 3: _carve(open, rooms[0][0], rooms[rooms.size() / 2][0], 2)
	return _largest(open)
