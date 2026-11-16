extends "res://scripts/game_base.gd"
## Game: streaming chunks in and out, spawning sprites and actors, draw order, visibility, camera, world life.


func origin() -> Dictionary:
	for o in ORIGINS:
		if o.id == origin_id: return o
	return ORIGINS[0]


func perk(id: String) -> int:
	return int(perks.get(id, 0))


func gain_xp(n: int, why: String = "") -> void:
	if rested_t > 0.0: n = int(ceil(n * 1.1))
	xp += n
	if why != "": add_text(player.wpos + Vector2(0, -0.6), "+%d XP  %s" % [n, why], Color(0.95, 0.85, 0.4), 1.8)
	while xp >= Perks.xp_needed(level):
		xp -= Perks.xp_needed(level)
		level += 1
		audio.play("levelup", Vector2.INF, -2.0, 0.0)
		hud.show_card("LEVEL %d" % level)
		_offer_perk.call_deferred()


func _offer_perk() -> void:
	var opts := Perks.choices(perks)
	if opts.is_empty(): return
	var btns := []
	var lines := ["Level %d. Choose a perk:" % level]
	for id in opts:
		var pd: Dictionary = Perks.LIST[id]
		lines.append("%s (rank %d/%d) — %s" % [pd.name, perk(id) + 1, pd.max, pd.desc])
		var pid: String = id
		btns.append([pd.name, func():
			perks[pid] = perk(pid) + 1
			hud.hide_menu()
			recalc_max()
			hud.toast("%s learned." % Perks.LIST[pid].name), false])
	hud.show_menu("Level up!", lines, btns)


func _chunk_dist(cx: int, cy: int, p: Vector2) -> float:
	var r := Rect2(cx * World.CH, cy * World.CH, World.CH, World.CH)
	var dx := maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x))
	var dy := maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))
	return maxf(dx, dy)


func _stream(sync: bool) -> void:
	var p := player.wpos
	var t0 := Time.get_ticks_msec()
	var c0 := World.chunk_of(p)
	var want := []
	var ahead := []
	for cy in range(c0.y - 3, c0.y + 4):
		for cx in range(c0.x - 3, c0.x + 4):
			if cx < 0 or cy < 0 or cx >= world.bounds.x or cy >= world.bounds.y: continue
			var d := _chunk_dist(cx, cy, p)
			var key := World.ckey(cx, cy)
			if d <= LOAD_R and not loaded.has(key): want.append([d, cx, cy])
			elif d <= AHEAD_R and not world.content_done[key]: ahead.append([d, cx, cy])
	want.sort_custom(func(a, b): return a[0] < b[0])
	if sync:
		while _pending_props.size(): _load_props(_pending_props.pop_front())
	elif _pending_props.size():
		_load_props(_pending_props.pop_front())
		return
	for w in want:
		var was_ready: bool = world.is_ready(w[1], w[2])
		world.ensure_ready(w[1], w[2])
		if not sync and not was_ready and Time.get_ticks_msec() - t0 > 6: return   # generated content this frame: show it next frame
		_load_chunk(w[1], w[2], sync)
		if not sync: return
	if not sync and Time.get_ticks_msec() - t0 < 4 and ahead.size() > 0:
		ahead.sort_custom(func(a, b): return a[0] < b[0])
		world.ensure_content(ahead[0][1], ahead[0][2])
	for key in loaded.keys():
		var cx: int = key % World.NC
		var cy: int = key / World.NC
		if _chunk_dist(cx, cy, p) > KEEP_R: _unload_chunk(key)
	# actors that wandered (or were left) far away go back to their spawn records
	for e in enemies:
		if not e.dead and absf(e.wpos.x - p.x) + absf(e.wpos.y - p.y) > KEEP_R * 1.6:
			var sp = e.get_meta("sp") if e.has_meta("sp") else null
			if sp != null:
				sp.active = false
				sp.pos = e.wpos
			e.dead = true
			e.queue_free()
	enemies = enemies.filter(func(e): return not e.dead)
	for n in npcs:
		if absf(n.wpos.x - p.x) + absf(n.wpos.y - p.y) > KEEP_R * 1.6:
			var d = n.get_meta("sp") if n.has_meta("sp") else null
			if d != null: d.active = false
			n.queue_free()
	npcs = npcs.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())


func _load_chunk(cx: int, cy: int, props: bool = true) -> void:
	var key := World.ckey(cx, cy)
	var cn := Node2D.new()
	root.add_child(cn)
	_parent = cn
	_light_tag = key
	var rec := {"node": cn, "trees": [], "crates": [], "furn": [], "decor": [], "views": []}
	loaded[key] = rec
	var near := []
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if cx + ox >= 0 and cy + oy >= 0 and cx + ox < World.NC and cy + oy < World.NC:
				near.append(world._bucket(World.ckey(cx + ox, cy + oy)))
	var tm := TerrainMesh.new()
	tm.build(world, cx, cy, near)
	rec.terrain = tm
	# keep ground meshes in back-to-front chunk order
	var order := cx + cy
	var at := terrain_root.get_child_count()
	for i in terrain_root.get_child_count():
		var o: TerrainMesh = terrain_root.get_child(i)
		if o.chunk.x + o.chunk.y > order or (o.chunk.x + o.chunk.y == order and o.chunk.x > cx):
			at = i; break
	terrain_root.add_child(tm)
	terrain_root.move_child(tm, at)
	_parent = root
	_light_tag = -1
	if props: _load_props(key)
	else: _pending_props.append(key)


## Second half of loading a chunk (sprites, buildings, people), done a frame after the ground so a
## new chunk never costs one long frame.
func _load_props(key: int) -> void:
	var rec: Dictionary = loaded[key]
	var cn: Node2D = rec.node
	_parent = cn
	_light_tag = key
	var cx := key % World.NC
	var cy := key / World.NC
	var w := world
	var x0 := cx * World.CH
	var y0 := cy * World.CH
	for y in range(y0, y0 + World.CH):
		for x in range(x0, x0 + World.CH):
			var i := y * World.N + x
			if w.T[i] == World.TREE:
				var p := Vector2(x + 0.5, y + 0.5)
				tree_nodes[i] = _sprite(_tree_tex(x, y, w.V[i]), p, w.hz(p.x, p.y), Vector2(-12, -36))
				rec.trees.append(i)
	var bk: Dictionary = w._bucket(key)
	for b in bk.buildings:
		for rp in b.roof_props:
			_light_for(rp.tex, rp.pos, b.h0 + b.floors_at(rp.cell) * World.FLOOR_H)
		var v := BuildingView.new()
		v.setup(w, b)
		cn.add_child(v)
		views.append(v)
		rec.views.append(v)
		for f in b.furn:
			var s := _sprite("furn_%s_%s" % [f.name, f.orient], f.pos, w.stand_z(f.pos.x, f.pos.y, f.fl), Vector2(-24, -40))
			s.z_index = Iso.z_for(f.pos.x + f.pos.y, 3 + f.fl * 2)
			if f.crate != null and f.crate.open: s.modulate = Color(0.78, 0.74, 0.7)
			furn_nodes[f] = s
			rec.furn.append(f)
	for c in bk.cars:
		_sprite("car_%s_%d" % [c.spr, c.k], c.pos, w.hz(c.pos.x, c.pos.y), Vector2(-40, -34))
	for d in bk.decor:
		var s := _decor_sprite(d)
		decor_nodes[d] = s
		rec.decor.append(d)
	for line in bk.poles:
		_pole_line(line)
	for cr in bk.crates:
		if cr.kind == "car" or cr.kind == "brute_drop": continue
		if cr.kind != "crate" and cr.kind != "cache" and cr.kind != "bag" and cr.kind != "brute": continue
		var z := w.stand_z(cr.pos.x, cr.pos.y, cr.fl)
		var tex: String = cr.kind if cr.kind != "brute" else "bag"
		if cr.open and (cr.kind == "crate" or cr.kind == "cache"): tex = cr.kind + "_open"
		if cr.open and (cr.kind == "bag" or cr.kind == "brute"): continue
		var s := _sprite(tex, cr.pos, z, Vector2(-8, -12), 0.1)
		s.z_index = Iso.z_for(cr.pos.x + cr.pos.y, 3 + cr.fl * 2)
		crate_nodes[cr] = s
		rec.crates.append(cr)
	for p in bk.posts:
		_sprite("post", p, w.hz(p.x, p.y), Vector2(-1, -14))
	for p in bk.flags:
		_sprite("flag_raider", p, w.hz(p.x, p.y), Vector2(-1, -30))
	for r in bk.ropes:
		_rope(r)
	for sp in bk.spawns:
		if not sp.get("dead", false) and not sp.get("active", false):
			_spawn_enemy(sp)
	for d in bk.critters:
		if not d.get("active", false):
			var n := _spawn_npc(d)
			n.set_meta("sp", d)
			d.active = true
	for s in bk.survivors:
		if s.get("active", false) or s.get("recruited", false) or s.name in _recruited_names: continue
		s.active = true
		var a := Actor.new()
		root.add_child(a)
		if not a.use_rendered("survivor", 8): a.make_body("survivor", 6, 16, 24)
		a.wpos = s.pos
		a.set_meta("name", s.name)
		a.set_meta("recruited", false)
		a.set_meta("slot", survivors.size())
		a.set_meta("sp", s)
		survivors.append(a)
	_parent = root
	_light_tag = -1


func _unload_chunk(key: int) -> void:
	var rec: Dictionary = loaded[key]
	loaded.erase(key)
	_pending_props.erase(key)
	for i in rec.trees: tree_nodes.erase(i)
	for c in rec.crates: crate_nodes.erase(c)
	for f in rec.furn: furn_nodes.erase(f)
	for d in rec.decor: decor_nodes.erase(d)
	for v in rec.views: views.erase(v)
	lights.remove_tag(key)
	var r := Rect2(key % World.NC * World.CH, key / World.NC * World.CH, World.CH, World.CH)
	smoke_spots = smoke_spots.filter(func(q): return not r.has_point(q))
	rec.terrain.queue_free()
	rec.node.queue_free()
	for s in survivors:
		if not s.get_meta("recruited") and r.has_point(s.wpos):
			s.get_meta("sp").active = false
			s.queue_free()
	survivors = survivors.filter(func(s): return not s.is_queued_for_deletion())


## Rebuild the ground meshes of loaded chunks touching rect (after the ground was re-levelled).
func rebuild_ground(rect: Rect2) -> void:
	for key in loaded:
		var cx: int = key % World.NC
		var cy: int = key / World.NC
		if not Rect2(cx * World.CH - 1, cy * World.CH - 1, World.CH + 2, World.CH + 2).intersects(rect): continue
		var near := []
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if cx + ox >= 0 and cy + oy >= 0 and cx + ox < World.NC and cy + oy < World.NC:
					near.append(world._bucket(World.ckey(cx + ox, cy + oy)))
		loaded[key].terrain.build(world, cx, cy, near)


## z_index only spans +-4096: every so often re-centre draw order on the player and shift every
## placed node to match (fixed layers like the ground and the FX layer stay put).
func rebase() -> void:
	var o := player.wpos.x + player.wpos.y
	var dz := -int(round((o - Iso.origin) * 16.0))
	if dz == 0: return
	Iso.origin += -dz / 16.0
	_shift_z(root, dz, false)


func _shift_z(n: Node, dz: int, under: bool) -> void:
	for c in n.get_children():
		if not (c is CanvasItem):
			continue
		var ci := c as CanvasItem
		var moved := under
		if (not ci.z_as_relative or not under) and ci.z_index > -3990 and ci.z_index < 3990 and ci.z_index != 0:
			ci.z_index = clampi(ci.z_index + dz, -3985, 3985)
			moved = true
		_shift_z(c, dz, moved and ci.z_as_relative)


func _spawn_npc(d: Dictionary) -> Npc:
	var n := Npc.new()
	root.add_child(n)
	n.setup(d)
	npcs.append(n)
	return n


func _spawn_enemy(s: Dictionary) -> Enemy:
	var e := Enemy.new()
	root.add_child(e)
	e.setup(s)
	e.set_meta("sp", s)
	s.active = true
	if s.has("boss"):
		e.set_meta("boss", s.boss)
		e.hp *= 6.0
		e.max_hp = e.hp
	enemies.append(e)
	return e


func _sprite(tex: String, at: Vector2, z: float, off: Vector2, depth_bias: float = 0.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.offset = Assets.off(tex)
	s.position = Iso.to_screen(at.x, at.y, z).round()
	s.z_index = Iso.z_for(at.x + at.y + depth_bias, 3)
	_parent.add_child(s)
	return s


func _light_for(nm: String, p: Vector2, z: float) -> void:
	if LIGHTS.has(nm):
		var L: Array = LIGHTS[nm]
		lights.add(Iso.to_screen(p.x, p.y, z + L[0]) + Vector2(L[1], 0), L[2], L[3], L[4], _light_tag)


## Trees grow in patches: each 8x8 area leans pine, leafy or dry scrub, with dead trees mixed in.
func _tree_tex(x: int, y: int, v: int) -> String:
	var h := absi((x * 73856093) ^ (y * 19349663)) % 997
	if v == 3 and h % 3 == 0:
		return TREES_DEAD[h % TREES_DEAD.size()]
	var region := absi((x / 8) * 7 + (y / 8) * 13 + world.seed_value) % 5
	var pool: Array = TREES_PINE if region == 0 else (TREES_DRY if region == 1 else TREES_LEAFY)
	if h % 5 == 0: pool = TREES_LEAFY        # a few strays of other kinds in every patch
	var tex: String = pool[h % pool.size()]
	return tex if ResourceLoader.exists("res://assets/sprites/%s.png" % tex) else "tree%d" % (v % 3)


func _decor_sprite(d: World.Decor) -> Sprite2D:
	var w := world
	var z := w.stand_z(d.pos.x, d.pos.y, 0)
	var s: Sprite2D
	match d.name:
		"campfire_decor":
			s = _sprite("campfire0", d.pos, z, Vector2(-8, -16))
			smoke_spots.append(d.pos)
			s.set_meta("anim", true)
		"stall": s = _sprite("furn_shopcounter_a", d.pos, z, Vector2(-24, -40))
		"tower_decor": s = _sprite("tower", d.pos, z, Vector2(-12, -48))
		"pump": s = _sprite("pump", d.pos, z, Vector2(-6, -29))
		"garden":
			s = _sprite("garden", d.pos, w.vh(int(d.pos.x), int(d.pos.y)), Vector2(-16, 0))
			s.z_index = -4000
		_:
			s = _sprite(d.name, d.pos, z, Vector2.ZERO)
			if d.flat:
				s.z_index = -4000 if d.name.begins_with("tuft") or d.name == "puddle_toxic" else Iso.z_for(d.pos.x + d.pos.y - 0.6, 0)
	_light_for(d.name, d.pos, z)
	return s


func _pole_line(line: PackedVector2Array) -> void:
	var w := world
	var tops := []
	for p in line:
		var z := w.hz(p.x, p.y)
		_sprite("pole", p, z, Vector2(-4, -60))
		tops.append(Iso.to_screen(p.x, p.y, z) + Vector2(0, -83))
	for i in range(tops.size() - 1):
		for side in [-5.0, 18.0]:
			var l := Line2D.new()
			l.width = 1.0
			l.default_color = Color("2a2420")
			l.antialiased = false
			var a: Vector2 = tops[i] + Vector2(side, 0)
			var bb: Vector2 = tops[i + 1] + Vector2(side, 0)
			var pts := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				pts.append((a.lerp(bb, t) + Vector2(0, sin(t * PI) * 6.0)).round())
			l.points = pts
			l.z_index = Iso.z_for(line[i].x + line[i].y + 1.0, 8)
			_parent.add_child(l)


func _rope(r: World.Rope) -> void:
	var w := world
	var l := Line2D.new()
	l.width = 1.0
	l.default_color = Color("e0c890")
	l.antialiased = false
	var a := Iso.to_screen(r.top.x, r.top.y, w.hz(r.top.x, r.top.y) + 2)
	var b := Iso.to_screen(r.bottom.x, r.bottom.y, w.hz(r.bottom.x, r.bottom.y))
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append((a.lerp(b, t) + Vector2(sin(t * 3.1) * 2.0, 0)).round())
	l.points = pts
	l.z_index = Iso.z_for(r.bottom.x + r.bottom.y, 3)
	_parent.add_child(l)
	var hook := Line2D.new()
	hook.width = 1.0
	hook.default_color = Color("9a9a9a")
	hook.points = PackedVector2Array([(a + Vector2(-2, 0)).round(), (a + Vector2(2, -2)).round()])
	hook.z_index = l.z_index
	_parent.add_child(hook)


# ------------------------------------------------------------------ helpers
func sfx(_name: String) -> void:
	pass   # sound effects come in a later milestone


func camp_near(p: Vector2, r: float):
	var best = null
	var bd := r
	for c in camps:
		var d: float = c.wpos.distance_to(p)
		if d < bd:
			bd = d
			best = c
	return best


func any_up(k: String) -> bool:
	for c in camps:
		if c.up[k]: return true
	return false


func danger() -> bool:
	for e in enemies:
		if not e.dead and e.st == 2 and e.wpos.distance_to(player.wpos) < 14.0:
			return true
	return false


func burst(p: Vector2, n: int, cols: Array, z: float, fl: int = 0) -> void:
	var gz := world.stand_z(p.x, p.y, fl)
	for i in n:
		particles.append({"pos": p, "z": z, "gz": gz, "vel": Vector2(randf_range(-2, 2), randf_range(-2, 2)), "vz": randf_range(10, 40), "col": cols[i % cols.size()], "life": randf_range(0.3, 0.8)})


func add_text(p: Vector2, txt: String, col: Color = Color("f2e6c8"), dur: float = 1.6) -> void:
	floaters.append({"pos": p, "z": 18.0, "t": dur, "label": hud.float_text(txt, col)})


func noise(at: Vector2, rad: float, amt: float) -> void:
	noise_level = maxf(noise_level, amt / 70.0)
	for e in enemies:
		if not e.dead:
			e.hear(at, rad, amt)


## world pixel position -> HUD (UI) coordinates
func to_hud(px: Vector2) -> Vector2:
	var vs := Vector2(vp.size)
	return (px - cam.get_screen_center_position() + vs * 0.5) * SHRINK


func recalc_max() -> void:
	player.max_hp = 20 + (4 if any_up("tent") else 0) + 4 * perk("toughness") + int(origin().get("hp", 20)) - 20
	player.hp = minf(player.hp, player.max_hp)


## Roaming encounters out in the open: every so often something comes over the rise — a raider
## gang, a pack of hounds... er, mutants, a lone merchant with a pack animal. Never next to towns.
func _encounters(delta: float) -> void:
	encounter_t += delta
	if encounter_t < 75.0: return
	encounter_t = randf_range(-30.0, 0.0)
	var p := player.wpos
	if world.settlement_at(p, 25.0) >= 0 or not world.nearest_loc(p, 10.0).is_empty(): return
	if camp_near(p, 15.0) != null: return
	var a := randf() * TAU
	var at := p + Vector2.from_angle(a) * 24.0
	if not world.can_stand(at, 0.3, 0): return
	var far := clampf(p.distance_to(world.start) / 900.0, 0.0, 1.0)
	var r := randf()
	var key := World.ckey(World.chunk_of(at).x, World.chunk_of(at).y)
	var bk := world._bucket(key)
	if r < 0.3:
		var n := 2 + int(randf() * (2.0 + far * 3.0))
		for k in n:
			var sp := {"type": "raider", "pos": at + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), "home": p, "home_r": 6.0, "roam": true, "chunk": key}
			world.spawns.append(sp); bk.spawns.append(sp)
			var e := _spawn_enemy(sp)
			if not origin().get("raider", false): e.aw = 60.0
		hud.toast("A raider crew rolls by. They know your colours." if origin().get("raider", false) else "Voices on the wind — raiders, and they've seen you.")
	elif r < 0.55:
		var t: String = ["ghoul", "rat", "shellback", "brute"][mini(3, int(randf() * (2.5 + far * 2.0)))]
		for k in (4 if t == "rat" else 2):
			var sp := {"type": t, "pos": at + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), "home": at, "home_r": 8.0, "roam": true, "chunk": key}
			world.spawns.append(sp); bk.spawns.append(sp)
			_spawn_enemy(sp)
	elif r < 0.8:
		var wps := [at, world.road_point_near(at, 20.0), p + Vector2(randf_range(-20, 20), randf_range(-20, 20)), world.road_point_near(p, 30.0)]
		var d := {"type": "wanderer", "pos": at, "patrol": wps, "chunk": key}
		bk.critters.append(d)
		var nn := _spawn_npc(d)
		nn.set_meta("sp", d)
		d.active = true
		var cow := {"type": "cattle", "pos": at + Vector2(1.0, 0.5), "home": at, "chunk": key}
		hud.toast("A travelling merchant is heading your way.")
	else:
		var cr := World.Crate.new()
		cr.pos = at
		cr.kind = "cache"
		_place_crate(cr)
		crate_nodes[cr].texture = Assets.tex("cache")
		add_text(at, "something glints over there", Color("f2e27a"), 3.0)


## Locations come up on the map once you get near them (or can see their lights over the hill).
func _discover() -> void:
	var p := player.wpos
	for l in world.locs:
		if world.discovered.has(l.id): continue
		if p.distance_to(l.pos) < l.r + 30.0:
			world.discovered[l.id] = true
			if time > 1.0:
				hud.show_card("%s\n%s" % [l.name.to_upper(), "DISCOVERED"])
				audio.play("discover", Vector2.INF, -3.0, 0.0)
				gain_xp(40 if l.type == "dungeon" else 25, "")


func _world_life(delta: float) -> void:
	var p := player
	# day / night colour grade — a full day takes 8 minutes
	day_t = fmod(day_t + delta / DAY_LEN, 1.0)
	rested_t = maxf(0.0, rested_t - delta)
	var sun := sin(day_t * TAU)          # 0.25 = noon, 0.75 = midnight
	var dayness := clampf(sun * 1.6 + 0.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(sun) * 3.0, 0.0, 1.0)
	var tint := Vector3(1.0, 0.97, 0.9).lerp(Vector3(0.62, 0.72, 1.0), 1.0 - dayness)
	tint = tint.lerp(Vector3(1.12, 0.86, 0.7), dusk * 0.6)
	if weather: tint *= weather.tint()
	if under != "":
		tint = Vector3(0.86, 0.88, 0.95)
		dayness = 0.35
	if grade:
		grade.set_shader_parameter("tint", tint)
		grade.set_shader_parameter("bright", lerpf(0.58, 1.0, dayness) * (weather.dim() if weather else 1.0))
		grade.set_shader_parameter("sat", lerpf(0.55, 0.82, dayness))
	lights.strength = clampf((1.0 - dayness) * 1.1, 0.0, 0.9)
	# your lantern: a soft light that follows you at night and underground
	lights.lights = lights.lights.filter(func(l): return l.tag != -2)
	if dayness < 0.6:
		lights.add(Iso.to_screen(p.wpos.x, p.wpos.y, p.ground_z() + 16.0), Color(1.0, 0.9, 0.7), 70.0 if under != "" else 40.0, false, -2)
	# settlement greeting
	var si := world.settlement_at(p.wpos)
	if si != in_settlement:
		in_settlement = si
		if si >= 0 and time - float(greeted.get(si, -999.0)) > 240.0:
			greeted[si] = time
			var stn: World.Settlement = world.settlements[si]
			hud.toast(("%s. Folks here trade and talk — look for the trader." % stn.name) if not stn.small else "%s. Someone's sitting by the fire." % stn.name)
	# campfires flicker and smoke
	var fr := int(time * 6.0) % 2
	for d in decor_nodes:
		var spr: Sprite2D = decor_nodes[d]
		if spr.has_meta("anim"):
			spr.texture = Assets.tex("campfire%d" % fr)
	for sp in smoke_spots:
		if randf() < delta * 5.0 and sp.distance_to(p.wpos) < 22.0:
			particles.append({"pos": sp + Vector2(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), "vel": Vector2(0.25, -0.15), "gz": world.hz(sp.x, sp.y), "z": 10.0, "vz": 9.0, "life": 2.2, "col": Color(0.55, 0.52, 0.48, 0.7), "fl": 0, "smoke": true})
	# drifting dust motes
	if randf() < delta * 3.0:
		var a := p.wpos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		particles.append({"pos": a, "vel": Vector2(0.6, 0.2), "gz": world.hz(a.x, a.y), "z": randf_range(8, 30), "vz": 0.5, "life": 3.0, "col": Color(0.85, 0.78, 0.6, 0.5), "fl": 0, "smoke": true})


func _separate() -> void:
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a: Enemy = enemies[i]
			var b: Enemy = enemies[j]
			if a.dead or b.dead or a.fl != b.fl: continue
			var d := b.wpos - a.wpos
			var l := d.length()
			if l < 0.45 and l > 0.0:
				var push := d / l * (0.45 - l) * 0.5
				a.move(-push)
				b.move(push)


func _update_visibility() -> void:
	var p := player
	var pb := p.building()
	if pb > 0 and world.bld(pb).open and p.fl == 0:
		pb = -pb    # under a canopy: the canopy roof lifts but everything else counts as outdoors
	if pb != _last_pb or p.fl != _last_pfl:
		_last_pb = pb
		_last_pfl = p.fl
		for v in views:
			v.update_view(absi(pb), p.fl)
	if pb < 0: pb = 0
	var vis := func(x: float, y: float, fl: int) -> bool:
		var b := world.building_at(x, y)
		if b == pb and fl == p.fl: return true
		if b == 0: return fl == 0
		return pb != b and world.open_from_outside(x, y, fl)
	for e in enemies:
		e.visible = not e.dead and vis.call(e.wpos.x, e.wpos.y, e.fl)
	for c in crate_nodes:
		var s: Sprite2D = crate_nodes[c]
		s.visible = vis.call(c.pos.x, c.pos.y, c.fl) and s.texture != null
	for f in furn_nodes:
		var fs: Sprite2D = furn_nodes[f]
		fs.visible = (f.bid == pb and f.fl == p.fl) or (f.bid != pb and world.open_from_outside(f.pos.x, f.pos.y, f.fl))
		if f.crate != null and f.crate.open: fs.modulate = Color(0.78, 0.74, 0.7)
	for d in decor_nodes:
		if d.bid > 0:
			(decor_nodes[d] as Sprite2D).visible = (d.bid == pb and p.fl == 0) or (d.bid != pb and world.open_from_outside(d.pos.x, d.pos.y, 0))
	for n in npcs:
		if n.type != "crow":
			n.visible = vis.call(n.wpos.x, n.wpos.y, 0)
	# see-through: fade buildings and trees standing between the camera and the player
	var pscr := p.position + Vector2(0, -18)
	var pdepth := p.wpos.x + p.wpos.y
	for v in views:
		# fade only when the building really hides you (you're behind it); your own building uses the cutaway
		var fade: bool = v.b.id != pb and pdepth < v.front_depth and v.screen_rect().has_point(pscr) and v.occludes(p.wpos, [6.0, 20.0], p.ground_z())
		v.set_faded(fade)
	for k in faded_trees:
		if is_instance_valid(faded_trees[k]): (faded_trees[k] as Sprite2D).modulate.a = 1.0
	faded_trees.clear()
	var px := int(p.wpos.x); var py := int(p.wpos.y)
	for dy in range(0, 4):
		for dx in range(0, 4):
			var ti := world.idx(clampi(px + dx, 0, World.N - 1), clampi(py + dy, 0, World.N - 1))
			if tree_nodes.has(ti):
				var ts: Sprite2D = tree_nodes[ti]
				if absf(ts.position.x - p.position.x) < 14.0 and ts.position.y > p.position.y - 2.0 and ts.position.y - 34.0 < p.position.y:
					ts.modulate.a = 0.35
					faded_trees[ti] = ts
	var main: Camp = camps[0]
	for c in camps:
		if c.main: main = c
	for s in survivors:
		if s.get_meta("recruited"):
			var a: float = s.get_meta("slot") * 2.1 + 0.6
			s.wpos = main.wpos + Vector2(cos(a), sin(a)) * 1.6
			s.visible = true
		else:
			s.visible = vis.call(s.wpos.x, s.wpos.y, 0)
		if s.rendered:
			var look: Vector2 = (main.wpos - s.wpos) if s.get_meta("recruited") else (p.wpos - s.wpos)
			s.face(Actor.world_to_screen_dir(look), 0)
		else:
			s.body.frame = 0
			s.body.flip_h = (main.wpos.x - s.wpos.x) < 0 if s.get_meta("recruited") else (p.wpos.x - p.wpos.y) < (s.wpos.x - s.wpos.y)
		s.sync()
	dog.visible = dog.fl == p.fl or pb == 0


func _update_camera() -> void:
	cam.position = (player.position + Vector2(0, -18)).round()
	fx.queue_redraw()
	for f in floaters:
		f.t -= get_process_delta_time()
		f.z += get_process_delta_time() * 10.0
		var px := Iso.to_screen(f.pos.x, f.pos.y, world.hz(f.pos.x, f.pos.y) + f.z)
		var l: Label = f.label
		l.position = to_hud(px) - Vector2(l.size.x * 0.5, 0)
		l.modulate.a = clampf(f.t, 0.0, 1.0)
		if f.t <= 0.0:
			l.queue_free()
	floaters = floaters.filter(func(f): return f.t > 0.0)
