extends RefCounted
## Automated runs for screenshots, playtests and balance checks (only created with --autostart).
## Each takes the Game as g.

var g: Game

func _init(game: Game) -> void:
	g = game


# ------------------------------------------------------------------ debug (used for automated screenshots)
func _debug_shots() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.aw = 0.0
	_snap(out + "/1_start.png")
	await g.get_tree().create_timer(0.3).timeout
	if g.world.settlements.size() > 0:
		g.player.wpos = g.world.settlements[0].pos + Vector2(2.5, 2.5)
		await g.get_tree().create_timer(0.8).timeout
		_snap(out + "/2_settlement.png")
	var done_in := false
	for b in g.world.buildings:
		if b.floors == 2 and not b.raider and not done_in:
			done_in = true
			g.player.fl = 0
			g.player.wpos = Vector2(b.out) + Vector2(0.5, 2.5)
			await g.get_tree().create_timer(0.6).timeout
			_snap(out + "/3_outside_2floor.png")
			g.player.wpos = Vector2(b.stairs) + Vector2(0.5, 0.5)
			await g.get_tree().create_timer(0.6).timeout
			_snap(out + "/4_inside_ground.png")
			g.interact()
			await g.get_tree().create_timer(0.6).timeout
			_snap(out + "/5_upstairs.png")
			g.player.fl = 0
			g.player.wpos = Vector2(b.x0 + b.w * 0.5, b.y0 - 1.2)
			await g.get_tree().create_timer(0.6).timeout
			_snap(out + "/6_behind_building.png")
	for e in g.enemies:
		if e.type in ["brute", "ghoul"]:
			g.player.wpos = e.wpos + Vector2(2.5, 2.5)
			g.player.fl = e.fl
			await g.get_tree().create_timer(0.5).timeout
			_snap(out + "/7_%s.png" % e.type)
			break
	g.player.fl = 0
	g.player.wpos = Vector2(44, 40)
	await g.get_tree().create_timer(0.6).timeout
	_snap(out + "/8_city.png")
	for kind in ["diner", "canopy", "motel", "factory", "office", "house"]:
		for b in g.world.buildings:
			if b.kind == kind:
				g.player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
				g.player.fl = 0
				for e in g.enemies: e.aw = 0.0
				await g.get_tree().create_timer(0.5).timeout
				_snap(out + "/k_%s.png" % kind)
				break
	var seen := {}
	for b in g.world.buildings:
		var sg: World.Seg = b.door_seg
		if sg == null or seen.has(sg.door) or sg.side in ["n", "w"]: continue
		seen[sg.door] = true
		g.player.fl = 0
		g.player.wpos = Vector2(b.out) + Vector2(0.5, 0.5) + Vector2(World.DIRS[b.door_side]) * 1.2
		await g.get_tree().create_timer(0.4).timeout
		_snap(out + "/door_%s.png" % sg.door)
	g.inv_add("shotgun"); g.inv_add("road_helmet"); g.inv_add("ammo_shell", 8)
	g.open_inventory()
	await g.get_tree().create_timer(0.4).timeout
	_snap(out + "/9_inventory.png")
	g.hud.hide_menu()
	g.day_t = 0.7
	g.player.wpos = Vector2(44, 40)
	await g.get_tree().create_timer(0.6).timeout
	_snap(out + "/10_night_city.png")
	for b in g.world.buildings:
		if b.kind == "canopy" or b.kind == "diner" or b.kind == "motel":
			g.player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
			await g.get_tree().create_timer(0.5).timeout
			_snap(out + "/11_night_%s.png" % b.kind)
			break
	print("SHOTS DONE ", ProjectSettings.globalize_path(out))
	g.get_tree().quit()


func _debug_ruins() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.aw = 0.0
	var n := 0
	for b in g.world.buildings:
		if not b.ruined or n >= 8: continue
		g.player.fl = 0
		g.player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
		for t in 20:
			if g.world.can_stand(g.player.wpos, 0.25, 0): break
			g.player.wpos += Vector2(0.5, 0.3)
		await g.get_tree().create_timer(0.4).timeout
		await _snap(out + "/r_%d_f%d.png" % [n, b.floors]); n += 1
	g.get_tree().quit()


func _debug_desks() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.visible = false; e.aw = 0.0
	var n := 0
	for b in g.world.buildings:
		for f in b.furn:
			if f.name == "chair" and n < 4:
				g.player.fl = f.fl
				g.player.wpos = f.pos + Vector2(1.2, 0.6)
				await g.get_tree().create_timer(0.4).timeout
				await _snap(out + "/d_%d.png" % n); n += 1
	g.get_tree().quit()


func _debug_upstairs() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.visible = false; e.aw = 0.0
	var n := 0
	for b in g.world.buildings:
		if b.floors < 2 or n >= 10: continue
		for c in b.cells:
			if b.cells[c] >= 2 and not b.holes.has(c):
				g.player.fl = 1
				g.player.wpos = Vector2(c) + Vector2(0.5, 0.5)
				await g.get_tree().create_timer(0.4).timeout
				print("UP shot %d: b%d %s ruined=%s parts=%s" % [n, b.id, b.kind, str(b.ruined), str(b.parts)])
				await _snap(out + "/u_%02d_%s.png" % [n, b.kind]); n += 1
				break
	g.get_tree().quit()


func _debug_bestiary() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	g.player.hp = 9999.0; g.player.max_hp = 9999.0
	var done := {}
	for e in g.enemies:
		if done.has(e.type): continue
		done[e.type] = true
		for o in g.enemies: o.aw = 0.0; o.st = 0
		g.player.fl = e.fl
		g.player.wpos = e.wpos + Vector2(1.6, 1.6)
		e.st = 2; e.aw = 1.0
		await g.get_tree().create_timer(0.6).timeout
		await _snap(out + "/b_%s.png" % e.type)
	g.get_tree().quit()


func _debug_tour() -> void:
	# Visual QA over the streamed world: towns and sample spots in every biome, with timings.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	await _snap(out + "/w_start.png")
	var stops := []
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var xy := a.substr(5).split(",")
			stops.append(["at_%s_%s" % [xy[0], xy[1]], Vector2(float(xy[0]), float(xy[1]))])
	for l in g.world.locs:
		if only == "" or l.id in only.split(","): stops.append([l.id, l.pos + Vector2(0, l.r * 0.3)])
	if only == "" or "biomes" in only.split(","):
		var seen := {}
		var r := RandomNumberGenerator.new()
		r.seed = 3
		for t in 4000:
			var q := Vector2(r.randf_range(40, World.N - 40), r.randf_range(40, World.N - 40))
			var bn := g.world.biome_name(q)
			if seen.get(bn, 0) >= 1: continue
			seen[bn] = seen.get(bn, 0) + 1
			stops.append(["biome_" + bn, q])
	for st in stops:
		var t0 := Time.get_ticks_msec()
		var p: Vector2 = st[1]
		g.world.ensure_ready(World.chunk_of(p).x, World.chunk_of(p).y)
		for ring in 30:
			if g.world.can_stand(p, 0.25, 0) and g.world.building_at(p.x, p.y) == 0: break
			p += Vector2(randf_range(-2, 2), randf_range(-2, 2)) * (1 + ring * 0.3)
		g.player.fl = 0
		g.player.wpos = p
		g.player.sync()
		g.rebase()
		g._stream(true)
		var t1 := Time.get_ticks_msec()
		for e in g.enemies: e.aw = 0.0; e.st = 0
		await g.get_tree().create_timer(0.3).timeout
		await _snap(out + "/w_%s.png" % st[0])
		print("TOUR %s at %s: %d ms, loaded %d chunks, %d enemies, %d npcs, %d views, %d trees" % [st[0], str(p.round()), t1 - t0, g.loaded.size(), g.enemies.size(), g.npcs.size(), g.views.size(), g.tree_nodes.size()])
	g.get_tree().quit()


## Playtest bot: walks from the home camp into town, then fights at a dungeon with auto-aim, logging
## what happens (for tuning).
func _debug_play() -> void:
	await g.get_tree().create_timer(1.0).timeout
	var plog := []
	var orig_toast := g.hud.toast_l.text
	var t0 := g.time
	var goal: Vector2 = g.world.loc_by_id(g.origin().loc).pos
	var steps := 0
	var stuck := 0
	var last := g.player.wpos
	while g.player.wpos.distance_to(goal) > 6.0 and steps < 60 * 50:
		steps += 1
		var dir := (goal - g.player.wpos).normalized()
		# steer around obstacles
		var mv := dir
		if stuck > 20: mv = dir.rotated(PI * 0.5 * (1 if (steps / 60) % 2 == 0 else -1))
		var sd := Vector2((mv.x - mv.y), (mv.x + mv.y) * 0.5).normalized()   # g.world -> screen-ish stick
		Input.action_release("fire")
		g._bot_move = sd
		await g.get_tree().process_frame
		if _wants_fire_bot(): g.shoot()
		if steps % 30 == 0:
			stuck = stuck + 1 if g.player.wpos.distance_to(last) < 0.3 else 0
			last = g.player.wpos
		if g.hud.toast_l.text != orig_toast:
			orig_toast = g.hud.toast_l.text
			plog.append("t=%.0fs toast: %s" % [g.time - t0, orig_toast]); print("PLAY ", plog[-1])
	g._bot_move = Vector2.ZERO
	plog.append("walk to town: %.0f s, reached=%s, hp %d/%d, kills %d" % [g.time - t0, str(g.player.wpos.distance_to(goal) <= 6.0), g.player.hp, g.player.max_hp, g.player.kills])
	await _snap("user://shots/play_town.png")
	# open-ground fight: a few ghouls and raiders come at you; stand and shoot with auto-aim
	var at := g.player.wpos + Vector2(14, 6)
	for t in 40:
		if g.world.can_stand(at, 0.3, 0) and g.world.settlement_at(at, 10.0) < 0: break
		at += Vector2(6, 3)
	g.player.wpos = at
	g.player.sync(); g.rebase(); g._stream(true)
	for e in g.enemies: e.queue_free()
	g.enemies.clear()
	g.inv_add("ammo_pistol", 40); g.inv_add("medkit", 3)
	for k in 6:
		var sp := {"type": "ghoul" if k < 4 else "raider", "pos": at + Vector2.from_angle(k * 1.05) * 9.0, "home": at, "home_r": 12.0}
		var e := g._spawn_enemy(sp)
		e.aw = 100.0; e.last = at
	var hp0 := g.player.hp
	var k0 := g.player.kills
	var a0 := g.inv_count("ammo_pistol")
	var locks := 0
	var first_lock := -1.0
	t0 = g.time
	for i in 60 * 20:
		await g.get_tree().process_frame
		if g.locked != null:
			locks += 1
			if first_lock < 0: first_lock = g.time - t0
			g.shoot()
		if g.player.hp < g.player.max_hp * 0.4 and g.inv_count("medkit") > 0: g.use_item("medkit")
		if g.state != "play": plog.append("went down at t=%.0f" % (g.time - t0)); break
		if i == 200: await _snap("user://shots/play_fight.png")
		if g.enemies.filter(func(e): return not e.dead).is_empty():
			plog.append("all dead at t=%.1f s" % (g.time - t0)); break
	plog.append("fight: kills %d/6, ammo used %d, hp %d -> %d, first lock %.1f s, frames locked %d, medkits used %d" % [g.player.kills - k0, a0 - g.inv_count("ammo_pistol"), hp0, g.player.hp, first_lock, locks, 3 + 0 - g.inv_count("medkit") + (2 if g.origin_id == "drifter" else 0)])
	for l in plog: print("PLAY ", l)
	g.get_tree().quit()

func _wants_fire_bot() -> bool:
	return g.locked != null


## Trade + save round trip: buy goods at the start town, save, reload, check they're still there.
func _debug_econ() -> void:
	await g.get_tree().create_timer(1.0).timeout
	var tr: Npc = null
	for n in g.npcs:
		if n.type == "trader" and n.settlement >= 0: tr = n; break
	g.stash.scrap = 200
	if tr:
		g.open_goods(tr)
		await g.get_tree().create_timer(0.3).timeout
		await _snap("user://shots/econ_goods.png")
		var m := Economy.market(g.world, tr.settlement)
		for gd in m:
			if m[gd].stock: g._buy_good(tr, gd, 5, m[gd].buy)
		print("ECON market ", g.world.settlements[tr.settlement].name, " ", m)
	g.hud.hide_menu()
	print("ECON carried goods ", g.goods_carried(), " scrap ", g._scrap_total(), " inv ", g.inventory)
	g.wmap.open()
	await g.get_tree().create_timer(0.3).timeout
	await _snap("user://shots/econ_map.png")
	g.wmap.zoom = 4.0
	g.wmap._layout()
	await g.get_tree().create_timer(0.3).timeout
	await _snap("user://shots/econ_map_zoom.png")
	g.wmap.close()
	g.save_game()
	var inv_before := str(g.inventory)
	g.load_game()
	await g.get_tree().create_timer(1.0).timeout
	print("ECON reload same inv: ", str(g.inventory) == inv_before, " origin ", g.origin_id, " pos ", g.player.wpos)
	g.get_tree().quit()


## Immersion check: weather, radio line, compass, a job, a note, a level up.
func _debug_immersion() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	var tr: Npc = null
	for n in g.npcs:
		if n.type == "trader" and n.settlement >= 0: tr = n; break
	if tr:
		g.player.wpos = tr.wpos + Vector2(0.8, 0.8)
		g.player.sync()
		g.open_jobs(tr)
		await g.get_tree().create_timer(0.3).timeout
		await _snap("user://shots/imm_jobs.png")
		var off: Dictionary = tr.get_meta("job")
		off.taken = true
		g.jobs.append(off)
		g.hud.hide_menu()
	g.audio.toggle_radio()
	g.weather.kind = "rad"; g.weather.amt = 0.9; g.weather.target = 0.9; g.weather.t_left = 99
	g.hud.show_card("PATCHWORK\nDISCOVERED")
	await g.get_tree().create_timer(1.0).timeout
	await _snap("user://shots/imm_rad.png")
	g.weather.kind = "rain"
	await g.get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_rain.png")
	g.weather.kind = "dust"
	await g.get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_dust.png")
	g.weather.amt = 0.0; g.weather.target = 0.0
	g.gain_xp(500, "test")
	await g.get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_level.png")
	g.hud.hide_menu()
	g._find_note()
	await g.get_tree().create_timer(0.3).timeout
	await _snap("user://shots/imm_note.png")
	g.hud.hide_menu()
	print("IMM jobs ", g.jobs.size(), " level ", g.level, " perks ", g.perks, " notes ", g.notes_read, " radio ", g.audio.radio_on, " beds ", g.audio.bed_target)
	g.get_tree().quit()


## Underground check: go down into one of each kind, look around, fight a little, climb out.
func _debug_under() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	for kind in ["cave", "mine", "sewer", "vault"]:
		var t0 := Time.get_ticks_msec()
		var portal := "%s:%d_%d" % [kind, 500 + kind.length(), 700]
		g._swap_under(portal, g.player.wpos)
		var t1 := Time.get_ticks_msec()
		await g.get_tree().create_timer(0.5).timeout
		await _snap("user://shots/under_%s.png" % kind)
		var boss = null
		for s in g.world.spawns:
			if s.has("boss"): boss = s
		# jump next to the boss
		g.player.wpos = boss.pos + Vector2(-3, -3)
		for t in 20:
			if g.world.can_stand(g.player.wpos, 0.3, 0): break
			g.player.wpos += Vector2(randf_range(-1, 1), randf_range(-1, 1))
		g.player.sync(); g._stream(true)
		await g.get_tree().create_timer(0.6).timeout
		await _snap("user://shots/under_%s_boss.png" % kind)
		print("UNDER %s: %s, built in %d ms, %d spawns, %d crates, %d decor, start %s, boss %s at %s, enemies active %d" % [kind, Underground.info(portal).name, t1 - t0, g.world.spawns.size(), g.world.crates.size(), g.world.decor.size(), str(g.world.start), boss.boss, str(boss.pos), g.enemies.size()])
		g._swap_out()
		await g.get_tree().create_timer(0.3).timeout
	print("UNDER back on surface at ", g.player.wpos, " world interior=", g.world.interior, " loaded ", g.loaded.size())
	await _snap("user://shots/under_back.png")
	g.get_tree().quit()


## Sleep check: find an unowned bed nearby, sleep until morning.
func _debug_sleep() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	var bed: World.Furn = null
	var bb: World.Bld = null
	for b in g.world.buildings:
		if b.settlement >= 0: continue
		for f in b.furn:
			if f.name == "bed" and f.fl == 0 and b.door_seg != null: bed = f; bb = b; break
		if bed: break
	print("SLEEP bed ", bed != null, " in ", bb.kind if bb else "-")
	if bed == null: g.get_tree().quit(); return
	g.player.wpos = bed.pos + Vector2(0.6, 0.6)
	for t in 20:
		if g.world.can_stand(g.player.wpos, 0.2, 0) and g.world.building_at(g.player.wpos.x, g.player.wpos.y) == bb.id: break
		g.player.wpos = bed.pos + Vector2(randf_range(-1, 1), randf_range(-1, 1))
	g.player.sync(); g.rebase(); g._stream(true)
	await g.get_tree().create_timer(0.5).timeout
	var t := g.find_target()
	print("SLEEP target ", t.get("k", "none"), " prompt ", g.hud.prompt.text if g.hud.get("prompt") else "")
	await _snap("user://shots/sleep_bed.png")
	g.player.hp = 6.0
	var d0 := g.day_t
	g._sleep(8.0, false)
	await g.get_tree().create_timer(2.0).timeout
	print("SLEEP day %.3f -> %.3f, hp %.1f, rested %.0f, state %s" % [d0, g.day_t, g.player.hp, g.rested_t, g.state])
	g.open_sleep(false)
	await g.get_tree().create_timer(0.4).timeout
	await _snap("user://shots/sleep_menu.png")
	g.get_tree().quit()


## Walk along the interstate for a while, measuring frame times while chunks stream in.
func _debug_walk() -> void:
	await g.get_tree().create_timer(1.0).timeout
	var worst := 0.0
	var sum := 0.0
	var n := 0
	var dir := Vector2(1, 0.15).normalized()
	for i in 900:
		var t0 := Time.get_ticks_usec()
		g.player.wpos += dir * 3.4 / 60.0 * 4.0
		g.player.sync()
		await g.get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt); sum += dt; n += 1
		if i % 150 == 0:
			print("WALK %d at %s: avg %.1f ms worst %.1f ms, loaded %d, nodes %d, enemies %d" % [i, str(g.player.wpos.round()), sum / n, worst, g.loaded.size(), g.root.get_child_count(), g.enemies.size()])
			await _snap("user://shots/walk_%d.png" % i)
			worst = 0.0; sum = 0.0; n = 0
	g.get_tree().quit()


func _debug_fade() -> void:
	# See-through check around one house: front, beside, behind, inside.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.visible = false; e.aw = 0.0
	var bld: World.Bld = null
	for b in g.world.buildings:
		if b.floors == 1 and b.w >= 4 and b.h >= 4 and not b.raider and b.door_seg != null:
			bld = b; break
	if bld == null: bld = g.world.buildings[0]
	var spots := {"front": Vector2(bld.x0 + bld.w + 1.2, bld.y0 + bld.h + 1.2),
		"beside": Vector2(bld.x0 + bld.w + 1.0, bld.y0 - 0.8),
		"behind": Vector2(bld.x0 + bld.w * 0.5, bld.y0 - 0.9),
		"behind_corner": Vector2(bld.x0 - 0.8, bld.y0 + bld.h * 0.5),
		"inside": Vector2(bld.x0 + bld.w * 0.5, bld.y0 + bld.h * 0.5)}
	for k in spots:
		g.player.fl = 0
		g.player.wpos = spots[k]
		await g.get_tree().create_timer(0.5).timeout
		var pscr := g.player.position + Vector2(0, -18)
		for v in g.views:
			if v.screen_rect().has_point(pscr):
				print("FADEDBG %s pb=%d pz=%.1f p=%s | b%d %s h0=%.1f roof=%s parts=%s front=%.1f occ=%s faded=%s" % [k, g.player.building(), g.player.ground_z(), str(g.player.wpos), v.b.id, v.b.kind, v.b.h0, v.b.roof, str(v.b.parts), v.front_depth, str(v.occludes(g.player.wpos, [6.0, 20.0], g.player.ground_z())), str(v._faded)])
		await _snap(out + "/fade_%s.png" % k)
	g.get_tree().quit()


func _debug_char() -> void:
	# Player sprite check: every facing, idle / walk / crouch, snapped in the live scene.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.visible = false; e.aw = 0.0
	g.set_process(false)
	g.player.set_process(false)
	g.player.set_physics_process(false)
	for mode in ["idle", "walk", "crouch"]:
		for k in 8:
			g.player.aim = Vector2.from_angle(k * PI / 4.0)
			g.player.crouch = mode == "crouch"
			g.player.moving = mode == "walk"
			g.player.walk_i = k % 4
			g.player._visual()
			g._update_camera()
			await g.get_tree().process_frame
			await _snap(out + "/char_%s_%d.png" % [mode, k])
	g.get_tree().quit()


func _debug_build() -> void:
	# Base building check: lays out a compound by hand and through the pointer code path, tests
	# collision, shots through windows, a door, removal, the ghost, and takes screenshots.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.visible = false; e.aw = 0.0; e.wpos = Vector2(2, 2)
	g.stash = {"scrap": 400, "cloth": 50, "wood": 400}
	var o := Vector2(floor(g.world.start.x) + 2.0, floor(g.world.start.y) - 3.0)
	var ok := 0; var bad := []
	var plan := [
		[Vector3i(0, 0, 0), "concrete", "wall"], [Vector3i(1, 0, 0), "concrete", "window"], [Vector3i(2, 0, 0), "concrete", "wall"],
		[Vector3i(0, 3, 0), "concrete", "wall"], [Vector3i(1, 3, 0), "concrete", "door"], [Vector3i(2, 3, 0), "concrete", "wall"],
		[Vector3i(0, 0, 1), "concrete", "wall"], [Vector3i(0, 1, 1), "concrete", "window"], [Vector3i(0, 2, 1), "concrete", "wall"],
		[Vector3i(3, 0, 1), "wood", "wall"], [Vector3i(3, 1, 1), "wood", "door"], [Vector3i(3, 2, 1), "wood", "wall"],
		[Vector3i(-2, 5, 0), "fence", "wall"], [Vector3i(-1, 5, 0), "fence", "wall"], [Vector3i(0, 5, 0), "fence", "gate"],
		[Vector3i(1, 5, 0), "fence", "wall"], [Vector3i(2, 5, 0), "stone", "half"], [Vector3i(3, 5, 0), "stone", "half"],
	]
	for p in plan:
		var k: Vector3i = p[0] + Vector3i(int(o.x), int(o.y), 0)
		var why := g.base.edge_problem(k)
		if why == "":
			g.base._level(BaseBuild.edge_verts(k)); g.base.place(k, p[1], p[2]); ok += 1
		else:
			bad.append("%s %s: %s" % [str(k), p[2], why])
	for y in 3:
		for x in 3:
			var t := Vector2i(int(o.x) + x, int(o.y) + y)
			if g.base.floor_problem(t) == "": g.base._level(BaseBuild.tile_verts(t)); g.base.place_floor(t, "wood" if x == 0 else "concrete")
	g.base._relevel_done()
	print("BUILD placed %d, refused %d %s" % [ok, bad.size(), str(bad)])
	# collision: can't stand on a wall, can inside the room
	print("BUILD stand-on-wall=%s stand-inside=%s" % [str(g.world.can_stand(o + Vector2(0.5, 0.0), 0.25, 0)), str(g.world.can_stand(o + Vector2(1.5, 1.5), 0.25, 0))])
	# shots: window lets shots through, wall stops them
	print("BUILD shot-through-window=%s shot-through-wall=%s" % [str(not g.world.blocks_shot(o + Vector2(1.5, 0.0), 10.0, 0)), str(not g.world.blocks_shot(o + Vector2(0.5, 0.0), 10.0, 0))])
	# pointer path: drag a run of scrap walls along x via screen coordinates
	g.base.enter()
	g.base.select("scrap", "wall")
	var a := o + Vector2(5.2, 0.0); var b := o + Vector2(8.6, 0.1)
	g.base.press(g.to_hud(Iso.to_screen(a.x, a.y, g.world.hz(a.x, a.y))))
	g.base.move(g.to_hud(Iso.to_screen(b.x, b.y, g.world.hz(b.x, b.y))))
	print("BUILD drag targets: %s" % str(g.base.targets(g.base.drag_a, g.base.drag_b)))
	g.base.release(g.to_hud(Iso.to_screen(b.x, b.y, g.world.hz(b.x, b.y))))
	print("BUILD pieces now %d, floors %d, stash %s" % [g.base.pieces.size(), g.base.floors.size(), str(g.stash)])
	# door
	var dk := Vector3i(int(o.x) + 1, int(o.y) + 3, 0)
	var dseg: World.Seg = g.base.pieces[dk].seg
	g.open_door(dseg)
	print("BUILD door opened=%s solid=%s" % [dseg.door, str(dseg.solid)])
	g.player.wpos = o + Vector2(1.5, 4.5)
	await g.get_tree().create_timer(0.5).timeout
	await _snap(out + "/build_front.png")
	g.player.wpos = o + Vector2(4.5, 4.5)
	await g.get_tree().create_timer(3.0).timeout
	print("BUILD door after waiting=%s" % dseg.door)
	# ghost: hover a run and screenshot
	g.base.select("wood", "wall")
	var ga := o + Vector2(-2.0, 7.0); var gb := o + Vector2(-2.0, 10.4)
	g.base.press(g.to_hud(Iso.to_screen(ga.x, ga.y, g.world.hz(ga.x, ga.y))))
	g.base.move(g.to_hud(Iso.to_screen(gb.x, gb.y, g.world.hz(gb.x, gb.y))))
	g.player.wpos = o + Vector2(2.5, 7.5)
	await g.get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_ghost.png")
	g.base.release(g.to_hud(Iso.to_screen(gb.x, gb.y, g.world.hz(gb.x, gb.y))))
	# behind the compound: walls in front should fade
	g.player.wpos = o + Vector2(1.5, -0.7)
	await g.get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_behind.png")
	g.player.wpos = o + Vector2(1.5, 1.5)
	await g.get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_inside.png")
	# remove
	g.base.select("", "remove")
	var rk := Vector3i(int(o.x) + 2, int(o.y), 0)
	g.base.remove(rk)
	print("BUILD removed=%s stash %s" % [str(not g.base.pieces.has(rk)), str(g.stash)])
	# foundations on a slope: find a sloped patch near camp, lay a 3x3 concrete foundation, wall it
	var best := Vector2i(-1, -1); var bslope := 0.0
	for y in range(int(g.world.start.y) - 9, int(g.world.start.y) + 10):
		for x in range(int(g.world.start.x) - 9, int(g.world.start.x) + 10):
			var okp := true; var lo := INF; var hi := -INF
			for yy in 3:
				for xx in 3:
					var t := Vector2i(x + xx, y + yy)
					if not g.world.in_bounds(t.x, t.y) or g.world.building_at(t.x + 0.5, t.y + 0.5) != 0 or g.world.T[g.world.idx(t.x, t.y)] == World.TREE or g.base.founds.has(t) or g.base.floors.has(t): okp = false
					for v in BaseBuild.tile_verts(t):
						lo = minf(lo, g.world.vh(v.x, v.y)); hi = maxf(hi, g.world.vh(v.x, v.y))
					for vv in BaseBuild.tile_verts(t):
						if g.base.vgroup.has(vv): okp = false
			if okp and x > 3 and y > 3 and hi - lo > bslope and hi - lo < 30.0 and g.base.in_base(Vector2(x + 1.5, y + 1.5)):
				bslope = hi - lo; best = Vector2i(x, y)
	print("BUILD slope patch %s drop %.1f px" % [str(best), bslope])
	if best.x >= 0:
		g.base.select("concrete", "foundation")
		g.base.drag_a = Vector2(best.x + 0.5, best.y + 0.5); g.base.drag_b = Vector2(best.x + 2.5, best.y + 2.5)
		g.base._commit()
		g.base.select("wood", "wall")
		g.base.drag_a = Vector2(best.x + 0.2, best.y + 0.0); g.base.drag_b = Vector2(best.x + 2.8, best.y + 0.0); g.base._commit()
		g.base.drag_a = Vector2(best.x + 0.0, best.y + 0.2); g.base.drag_b = Vector2(best.x + 0.0, best.y + 2.8); g.base._commit()
		g.base.select("wood", "door")
		g.base.drag_a = Vector2(best.x + 3.0, best.y + 1.5); g.base.drag_b = g.base.drag_a; g.base.axis = 1; g.base._commit()
		var mid := Vector2(best.x + 1.5, best.y + 1.5)
		for t in g.base.founds: print("BUILD found %s top %.1f faces %d" % [str(t), g.base.founds[t].top, g.base.founds[t].faces.size()])
		print("BUILD foundations %d top %.1f stand_z %.1f ground %.1f walls %d" % [g.base.founds.size(), g.base.founds[best].top if g.base.founds.has(best) else -1.0, g.world.stand_z(mid.x, mid.y, 0), g.world.hz(mid.x, mid.y), g.base.pieces.size()])
		g.player.wpos = mid + Vector2(2.2, 2.2)
		for v in g.views: v.visible = false            # debug framing only: nothing in front of the patch
		await g.get_tree().create_timer(0.4).timeout
		await _snap(out + "/build_foundation.png")
		for v in g.views: v.visible = true
		g.player.wpos = mid
		await g.get_tree().create_timer(0.4).timeout
		print("BUILD player z on foundation %.1f" % g.player.ground_z())
	# claim a raider den, knock out a wall, extend it
	if not g.world.rcamps.is_empty():
		var rc = g.world.rcamps[0]
		for e in g.enemies:
			if e.camp == 0: e.dead = true; e.visible = false
		rc.cleared = true
		g.player.wpos = rc.pos + Vector2(0, 4.0)
		g.claim_den(rc)
		var bb: World.Bld = g.world.buildings[rc.bid - 1]
		var wall: World.Seg = null
		for s in bb.segs:
			if s.fl == 0 and s.side == "s" and not s.is_door: wall = s; break
		var n0 := bb.segs.size()
		if wall: g.base.remove(wall)
		print("BUILD den b%d h0 %.1f segs %d -> %d, edge free=%s" % [bb.id, bb.h0, n0, bb.segs.size(), str(wall != null and not g.world.edge_taken(int(wall.a.x), int(wall.a.y), wall.axis))])
		if wall:
			# a foundation patch south of the gap, snapped to the den floor, walled on its sides
			var t0 := Vector2i(int(wall.a.x), int(wall.a.y))
			g.base.select("stone", "foundation")
			g.base.drag_a = Vector2(t0.x + 0.5, t0.y + 0.5); g.base.drag_b = Vector2(t0.x + 0.5, t0.y + 1.5); g.base._commit()
			g.base.select("scrap", "wall")
			g.base.drag_a = Vector2(t0.x, t0.y + 0.2); g.base.drag_b = Vector2(t0.x, t0.y + 1.8); g.base._commit()
			g.base.drag_a = Vector2(t0.x + 1, t0.y + 0.2); g.base.drag_b = Vector2(t0.x + 1, t0.y + 1.8); g.base._commit()
			g.base.drag_a = Vector2(t0.x + 0.5, t0.y + 2); g.base.drag_b = g.base.drag_a; g.base.axis = 0; g.base._commit()
			print("BUILD den extension founds top %s" % str(g.base.founds.get(t0, {}).get("top", -1)))
			for kk in [Vector3i(t0.x, t0.y, 1), Vector3i(t0.x, t0.y + 1, 1), Vector3i(t0.x + 1, t0.y, 1), Vector3i(t0.x, t0.y + 2, 0)]:
				print("BUILD den edge %s built=%s why=%s" % [str(kk), str(g.base.pieces.has(kk)), g.base.edge_problem(kk)])
		g.player.wpos = Vector2(bb.x0 + bb.w * 0.5 + 1.0, bb.y0 + bb.h + 3.0)
		for t in g.base.founds:
			if t.y >= bb.y0 + bb.h: print("BUILD den found %s top %.1f spr %s vis %s faces %d" % [str(t), g.base.founds[t].top, str(g.base.founds[t].spr.position), str(g.base.founds[t].spr.visible), g.base.founds[t].faces.size()])
		for v in g.views:
			v.visible = v.b.id == rc.bid
			if v.visible: print("BUILD den view at x0 %d y0 %d w %d h %d kind %s walls %d faded %s; player %s" % [bb.x0, bb.y0, bb.w, bb.h, bb.kind, v.walls.size(), str(v._faded), str(g.player.wpos)])
		await g.get_tree().create_timer(0.5).timeout
		await _snap(out + "/build_den.png")
		for v in g.views: v.visible = true
	g.get_tree().quit()


func _debug_inv() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	for k in ["pistol_10mm", "shotgun", "rifle", "smg", "machete", "spiked_bat", "road_helmet", "combat_vest", "jacket", "ammo_shell", "ammo_rifle"]:
		g.inv_add(k, 1 if not k.begins_with("ammo") else 12)
	g.equip_item("pistol_10mm")
	g.invs.sel = "shotgun"
	g.open_inventory()
	await g.get_tree().create_timer(0.5).timeout
	await _snap("user://shots/inventory.png")
	g.get_tree().quit()


func _debug_map() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	await _snap("user://shots/hud.png")
	g.wmap.open()
	await g.get_tree().create_timer(0.6).timeout
	await _snap("user://shots/worldmap.png")
	g.get_tree().quit()


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	g.get_viewport().get_texture().get_image().save_png(path)


func _debug_soak() -> void:
	# Plays itself for a while to shake out runtime errors: wanders, fights, loots, builds a camp, travels.
	await g.get_tree().create_timer(0.5).timeout
	g.stash = {"scrap": 40, "cloth": 20, "wood": 40}
	var steps := 0
	for e in g.enemies:
		if e.type == "raider" and e.camp >= 0:
			g.player.wpos = e.wpos + Vector2(3, 0)
			break
	for i in 400:
		await g.get_tree().process_frame
		g.player.aim = Vector2(cos(i * 0.05), sin(i * 0.05))
		if i % 20 == 0: g.shoot()
		if i % 45 == 0: g.melee()
		if i % 30 == 0: g.interact()
	g.player.wpos = g.world.start + Vector2(12, 0)
	for e in g.enemies:
		e.aw = 0.0
		e.st = 0
	print("camp problem: ", g.camp_problem())
	g.new_camp()
	g.hud.hide_menu()
	await g.get_tree().create_timer(0.3).timeout
	g._build(g.camps[0], g.UPG[3])
	g.hud.hide_menu()
	g._start_travel(g.camps[0])
	await g.get_tree().create_timer(2.0).timeout
	for i in 300:
		await g.get_tree().process_frame
		g.player.step(g.get_process_delta_time(), Vector2(cos(i * 0.02), sin(i * 0.03)), Vector2.ZERO)
		if i % 50 == 0: g.player.start_jump()
	var tr: Npc = null
	for n in g.npcs:
		if n.type == "trader": tr = n
	if tr:
		g.open_trade(tr); g.hud.hide_menu()
	g.open_inventory(); g.hud.hide_menu()
	g.inv_add("shotgun"); g.inv_add("ammo_shell", 10); g.inv_add("combat_vest"); g.equip_item("shotgun"); g.equip_item("combat_vest")
	for i in 30:
		await g.get_tree().process_frame
		if i % 8 == 0: g.shoot()
	g.quick_heal()
	g.day_t = 0.7
	await g.get_tree().create_timer(0.3).timeout
	# doors: pick a lock, bash a barricade
	var picked := 0
	var bashed := 0
	var sealed_n := 0
	for b in g.world.buildings:
		if b.sealed: sealed_n += 1
		var sg: World.Seg = b.door_seg
		if sg == null: continue
		if sg.door == "locked" and picked == 0:
			g.player.wpos = Vector2(b.out) + Vector2(0.5, 0.5)
			for a in ["left", "right", "up", "down"]: Input.action_release(a)
			g.player.inv = 0.0
			g.hud.hide_menu()
			g.open_door(sg)
			for i in 200:
				await g.get_tree().process_frame
				if g.busy.is_empty(): break
			picked = 1 if sg.door == "open" else -1
		if sg.door == "barred" and bashed == 0:
			g.player.wpos = Vector2(b.out) + Vector2(0.5, 0.5)
			for i in 30:
				g.bash_door(sg, 2.0)
				if sg.door == "broken": break
			bashed = 1 if sg.door == "broken" else -1
	print("DOORS picked=%d bashed=%d sealed=%d lockpicks=%d" % [picked, bashed, sealed_n, g.inv_count("lockpick")])
	print("SOAK DONE state=%s hp=%d kills=%d camps=%d enemies=%d" % [g.state, g.player.hp, g.player.kills, g.camps.size(), g.enemies.size()])
	g.get_tree().quit()
