extends RefCounted
## Automated runs for screenshots, playtests and balance checks (only created with --autostart).
## Each takes the Game as g.

var g: Game

var errlog: ErrCounter

## Counts engine and script errors so a check run that hit one fails, even when the broken
## code path made a check look like it passed (Review 2).
class ErrCounter extends Logger:
	var n := 0
	var first := ""
	var ignore: Array = []   # substrings of expected errors (e.g. parsing a deliberately corrupt save)
	var mx := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING: return
		var msg := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		for i in ignore:
			if msg.contains(i): return
		mx.lock()
		n += 1
		if first == "": first = msg
		mx.unlock()
	func _log_message(message: String, error: bool) -> void:
		pass

func _init(game: Game) -> void:
	g = game
	errlog = ErrCounter.new()
	OS.add_logger(errlog)
	DirAccess.make_dir_recursive_absolute("user://shots")
	_watchdog.call_deferred()


# ------------------------------------------------------------------ debug (used for automated screenshots)
func _debug_shots() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.aw = 0.0
	_snap(out + "/1_start.png")
	await g.get_tree().create_timer(0.3).timeout
	var home: Dictionary = g.world.loc_by_id(g.origin().loc)
	if not home.is_empty():
		g.player.wpos = home.pos + Vector2(2.5, 2.5)
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
	g.player.wpos = _city_spot()
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
	if g.invs.visible: g.invs.close_screen()
	g.day_t = 0.7
	g.player.wpos = _city_spot()
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
## Somewhere standable in downtown Port Sterling (for city screenshots).
func _city_spot() -> Vector2:
	var c: Dictionary = g.world.loc_by_id("sterling_downtown")
	var p: Vector2 = c.pos if not c.is_empty() else g.world.start
	for i in 30:
		var q := p + Vector2(i * 1.3, i * 0.7)
		if g.world.can_stand(q, 0.3, 0): return q
	return p


func _debug_play() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
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
	var mk0 := g.inv_count("medkit")
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
	var taken := 0
	var hp_prev := g.player.hp
	for i in 60 * 20:
		await g.get_tree().process_frame
		if g.player.hp < hp_prev: taken += hp_prev - g.player.hp
		hp_prev = g.player.hp
		if g.locked != null:
			locks += 1
			if first_lock < 0: first_lock = g.time - t0
			g.shoot()
		if g.player.hp < g.player.max_hp * 0.4 and g.inv_count("medkit") > 0 and g.busy.is_empty(): g.use_item("medkit")
		if g.state != "play": plog.append("went down at t=%.0f" % (g.time - t0)); break
		if i == 200: await _snap("user://shots/play_fight.png")
		if g.enemies.filter(func(e): return not e.dead).is_empty():
			plog.append("all dead at t=%.1f s" % (g.time - t0)); break
	plog.append("fight: kills %d/6, ammo used %d, hp %d -> %d, first lock %.1f s, frames locked %d, medkits used %d" % [g.player.kills - k0, a0 - g.inv_count("ammo_pistol"), hp0, g.player.hp, first_lock, locks, mk0 - g.inv_count("medkit")])
	for l in plog: print("PLAY ", l)
	check("bot reaches town", plog[0].contains("reached=true") or plog.any(func(x): return x.contains("reached=true")), "walk to start town")
	print("PLAY fight damage taken: %d (%d -> %d HP)" % [taken, hp0, g.player.hp])
	check("fight is winnable", g.state == "play" and g.player.kills - k0 == 6 and mk0 - g.inv_count("medkit") <= 1, "state %s, kills %d/6, med kits used %d (target: win using at most 1)" % [g.state, g.player.kills - k0, mk0 - g.inv_count("medkit")])
	finish()

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
	# script time per frame while walking around normally (Review 1 target ~4.5 ms)
	g.hud.hide_menu()
	if g.invs.visible: g.invs.close_screen()
	var pt: Array[float] = []
	for i in 240:
		await g.get_tree().process_frame
		g._bot_move = Vector2(cos(i * 0.01), sin(i * 0.013))
		if i > 30: pt.append(g.proc_ms)
	g._bot_move = Vector2.ZERO
	pt.sort()
	var med: float = pt[pt.size() / 2]
	check("script time", med <= 4.5, "median %.2f ms, 95th %.2f ms in Game._process (lavapipe CPU, so slower than a real device)" % [med, pt[int(pt.size() * 0.95)]])
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
	g.open_inventory(); g.hud.hide_menu(); g.invs.close_screen()
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
			if g.invs.visible: g.invs.close_screen()   # equipping above reopens the STATUS screen
			var lp0 := g.inv_count("lockpick")
			g.open_door(sg)
			for i in 900:
				await g.get_tree().process_frame
				if g.busy.is_empty(): break
			# a snapped pick is a working lock too (40% fail chance per try)
			picked = 1 if sg.door == "open" or g.inv_count("lockpick") < lp0 else -1
			if picked < 0: print("DOOR pick failed: door %s, busy %s, toast '%s', inv %.2f, state %s, menu %s, map %s, invs %s" % [sg.door, str(g.busy), g.hud.toast_l.text, g.player.inv, g.state, str(g.hud.menu_open()), str(g.wmap.visible), str(g.invs.visible)])
		if sg.door == "barred" and bashed == 0:
			g.player.wpos = Vector2(b.out) + Vector2(0.5, 0.5)
			for i in 30:
				g.bash_door(sg, 2.0)
				if sg.door == "broken": break
			bashed = 1 if sg.door == "broken" else -1
	print("DOORS picked=%d bashed=%d sealed=%d lockpicks=%d" % [picked, bashed, sealed_n, g.inv_count("lockpick")])
	print("SOAK DONE state=%s hp=%d kills=%d camps=%d enemies=%d" % [g.state, g.player.hp, g.player.kills, g.camps.size(), g.enemies.size()])
	check("soak survives", g.state in ["play", "travel"] and g.camps.size() > 0, "state %s, camps %d" % [g.state, g.camps.size()])
	check("doors work", (picked > 0 or bashed > 0) and picked >= 0 and bashed >= 0, "picked %d bashed %d (needs at least one real success)" % [picked, bashed])
	finish()

# ------------------------------------------------------------------ balance checks (Review 1 retest)
var fails := 0

func check(name: String, ok: bool, detail: String) -> void:
	print("%s %s — %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

## A script error inside a check stops its coroutine, so finish() would never run and the
## process would hang. End the run 20 s after the first error, or after 9 minutes regardless.
var done := false
func _watchdog() -> void:
	var t0 := Time.get_ticks_msec()
	var err_t := -1
	while not done:
		await g.get_tree().create_timer(1.0).timeout
		if errlog.n > 0 and err_t < 0: err_t = Time.get_ticks_msec()
		if err_t >= 0 and Time.get_ticks_msec() - err_t > 20000:
			print("FAIL run stopped — script error: ", errlog.first); fails += 1; finish(); return
		if Time.get_ticks_msec() - t0 > 540000:
			print("FAIL run timed out"); fails += 1; finish(); return

func finish() -> void:
	if done: return
	done = true
	check("no script errors", errlog.n == 0, "%d errors%s" % [errlog.n, (", first: " + errlog.first) if errlog.n else ""])
	print("CHECKS done: %d failed" % fails)
	g.get_tree().quit(1 if fails > 0 else 0)

func _trader_for(si: int) -> Npc:
	for n in g.npcs:
		if n.type == "trader" and n.settlement == si: return n
	return null

func _wait_travel() -> void:
	while g.state == "travel":
		await g.get_tree().process_frame

## The Review 1 money loop: buy where a good is made, fast travel to a town that pays more, sell,
## come back, five times. Then sell 30 of one good in one town and compare the last price to the first.
func _debug_econ_check() -> void:
	await g.get_tree().create_timer(1.0).timeout
	var home := _trader_for(g.in_settlement if g.in_settlement >= 0 else 0)
	for n in g.npcs:
		if n.type == "trader" and n.settlement >= 0 and not g.world.settlements[n.settlement].small: home = n; break
	var hsi: int = home.settlement
	var hm := Economy.market(g.world, hsi)
	var good := ""
	for k in hm:
		if hm[k].made: good = k; break
	# best nearby destination for that good, by base sell price
	var best: Dictionary = {}
	var bestp := 0.0
	for l in g.world.locs:
		if l.type not in ["town", "hub", "settlement"] or l.pos.distance_to(home.wpos) < 50 or l.pos.distance_to(home.wpos) > 450: continue
		var d: float = Economy._maker_dist(g.world, good, l.pos)
		if Economy.makes_at(g.world, l.hook, l.pos).has(good): continue
		if d > bestp: bestp = d; best = l
	print("ECON loop: buy %s at %s, sell at %s" % [good, g.world.settlements[hsi].name, best.get("name", "?")])
	g.player.carry.scrap = 150
	g.inventory.append({"id": "food", "n": 40})
	var s0: int = g.player.carry.scrap
	var lvl0: int = g.level
	var t0: float = g.now()
	var rt := Time.get_ticks_msec()
	var hpos: Vector2 = home.wpos
	for trip in 5:
		home = _trader_for(hsi)
		if home == null:
			g.player.wpos = hpos; g.player.sync(); g._stream(true)
			home = _trader_for(hsi)
		g.player.wpos = home.wpos + Vector2(0.8, 0.8)
		g.player.sync(); g._stream(true)
		g.in_settlement = -1
		for k in 30:
			var before: int = g.inv_count(good)
			g._buy_good(home, good, 1, hm[good].buy)
			if g.inv_count(good) == before: break
		g.hud.hide_menu()
		g.world.discovered[best.id] = true
		g.travel_to_loc(best)
		await _wait_travel()
		for e in g.enemies: e.queue_free()
		g.enemies.clear()
		var dsi := -1
		for i in g.world.settlements.size():
			if g.world.settlements[i].id == best.id: dsi = i
		var tr := _trader_for(dsi)
		if tr:
			g.player.wpos = tr.wpos + Vector2(0.8, 0.8)
			g.player.sync()
			var m := Economy.market(g.world, dsi)
			g._sell_good(tr, good, g.inv_count(good), m[good].sell)
			g.hud.hide_menu()
		g.world.discovered[g.world.settlements[hsi].id] = true
		g.travel_to_loc(g.world.loc_by_id(g.world.settlements[hsi].id))
		await _wait_travel()
		for e in g.enemies: e.queue_free()
		g.enemies.clear()
		print("ECON trip %d: scrap %d, level %d, day %.2f" % [trip + 1, g.player.carry.scrap, g.level, g.now()])
	var gain: int = g.player.carry.scrap - s0
	check("trade loop profit", gain < 300, "+%d scrap over 5 round trips (target under +300)" % gain)
	check("trade loop no level", g.level == lvl0, "level %d -> %d" % [lvl0, g.level])
	check("travel advances clock", g.now() - t0 > 0.1, "clock moved %.2f days (%d real s)" % [g.now() - t0, (Time.get_ticks_msec() - rt) / 1000])
	# saturation: sell 30 of one good in one place
	home = _trader_for(hsi)
	var dsi2: int = hsi
	var g2 := "water" if good != "water" else "salt"
	g.inv_add(g2, 30)
	var m2 := Economy.market(g.world, dsi2)
	var first := Economy.sell_price(g.econ, g.world.settlements[dsi2].id, g2, m2[g2].sell, g.now())
	var last := Economy.sell_price(g.econ, g.world.settlements[dsi2].id, g2, m2[g2].sell, g.now(), 29)
	check("selling saturates", last <= first * 0.7 and last >= first * 0.39, "30th unit %d vs first %d (%.0f%%)" % [last, first, 100.0 * last / first])
	if home == null:
		g.player.wpos = hpos; g.player.sync(); g._stream(true)
		for i in 10: await g.get_tree().process_frame
		home = _trader_for(hsi)
	check("home trader found", home != null, "trader at %s" % g.world.settlements[hsi].name)
	if home:
		var cap := Economy.purse(g.econ, g.world, hsi, g.now())
		g.econ.purse[g.world.settlements[hsi].id] = [30, g.now()]
		var sc: int = g.player.carry.scrap
		var had := g.inv_count(g2)
		g._sell_good(home, g2, 30, m2[g2].sell)
		var paid: int = g.player.carry.scrap - sc
		check("trader purse limits", paid > 0 and paid <= 30 and had - g.inv_count(g2) < 30 and cap > 30, "a 30-scrap purse paid %d for %d of 30 units (full purse %d)" % [paid, had - g.inv_count(g2), cap])
	g.hud.hide_menu()
	check("stash stays at camp", g._scrap_total() == g.player.carry.scrap, "traders see %d (carry %d, stash %d)" % [g._scrap_total(), g.player.carry.scrap, g.stash.scrap])
	finish()

## Review 1 combat checks: idle player vs 1 and 5 ghouls, then the hold-fire bot vs 4 ghouls + 2 raiders.
func _open_spot() -> Vector2:
	var at: Vector2 = g.player.wpos + Vector2(14, 6)
	for t in 60:
		if g.world.can_stand(at, 0.4, 0) and g.world.settlement_at(at, 14.0) < 0 and g.camp_near(at, 12.0) == null and g.world.building_at(at.x, at.y) == 0: break
		at += Vector2(6, 3)
	return at

func _idle_vs(n: int, at: Vector2 = Vector2.INF) -> float:
	# damage per second from n ghouls on a player who just stands there. Measured over 12 s from the
	# first hit with a huge health pool, so regen and dying don't muddy the numbers.
	if at == Vector2.INF: at = _open_spot()
	g.player.wpos = at
	var mh := g.player.max_hp
	g.player.max_hp = 1000.0
	g.player.hp = 1000.0
	g.player.inv = 0.0
	g.player.sync(); g.rebase(); g._stream(true)
	for e in g.enemies: e.queue_free()
	g.enemies.clear()
	for k in n:
		var e: Enemy = g._spawn_enemy({"type": "ghoul", "pos": at + Vector2.from_angle(k * TAU / n) * 2.0, "home": at, "home_r": 10.0})
		e.aw = 100.0; e.last = at
	var t0: float = g.time
	var hit_t := -1.0
	var taken := 0.0
	var hc0: int = g.hurt_calls
	var hb0: int = g.hurt_blocked
	var prev: float = g.player.hp
	while g.time - t0 < 30.0:
		await g.get_tree().process_frame
		g.player.wpos = at   # knockback would walk you out of reach
		if g.player.hp < prev:
			if hit_t < 0: hit_t = g.time
			taken += prev - g.player.hp
		prev = g.player.hp
		if hit_t >= 0 and g.time - hit_t >= 12.0: break
	var dists := []
	for e in g.enemies: dists.append("%.1f" % e.wpos.distance_to(at))
	print("COMBAT %d ghouls: %d hits, %d swallowed by the grace window, distances %s" % [n, g.hurt_calls - hc0, g.hurt_blocked - hb0, str(dists)])
	for e in g.enemies: e.queue_free()
	g.enemies.clear()
	g.player.max_hp = mh
	g.player.hp = mh
	return taken / 12.0

func _debug_combat_check() -> void:
	await g.get_tree().create_timer(1.0).timeout
	g.equip.body = ""; g.equip.head = ""
	# one fixed open spot, three runs each, averaged: a single run is too noisy
	var spot := _open_spot()
	var tt := {1: 0.0, 3: 0.0, 5: 0.0}
	for run in 3:
		for n in [1, 3, 5]:
			var dps: float = await _idle_vs(n, spot)
			tt[n] += dps / 3.0
			print("COMBAT run %d: %d ghouls deal %.2f HP/s" % [run + 1, n, dps])
	var d1: float = maxf(tt[1], 0.01)
	print("COMBAT damage per second (avg of 3): 1 ghoul %.2f, 3 ghouls %.2f, 5 ghouls %.2f; 20 HP lasts %.0f / %.0f / %.0f s" % [tt[1], tt[3], tt[5], 20.0 / d1, 20.0 / maxf(tt[3], 0.01), 20.0 / maxf(tt[5], 0.01)])
	check("damage stacks (3)", tt[3] / d1 >= 2.5, "3 ghouls hurt %.1fx as fast as 1 (target 2.5-3x)" % (tt[3] / d1))
	check("damage stacks (5)", tt[5] / d1 >= 3.0, "5 ghouls hurt %.1fx as fast as 1 (target 3x+)" % (tt[5] / d1))
	# hold-fire bot
	var at := _open_spot()
	g.player.wpos = at
	g.player.hp = g.player.max_hp
	g.player.sync(); g.rebase(); g._stream(true)
	for e in g.enemies: e.queue_free()
	g.enemies.clear()
	g.inv_add("ammo_pistol", 60)
	g.inv_add("medkit", 2)
	var mk0 := g.inv_count("medkit")
	var foes := []
	for k in 6:
		var e: Enemy = g._spawn_enemy({"type": "ghoul" if k < 4 else "raider", "pos": at + Vector2.from_angle(k * 1.05) * 9.0, "home": at, "home_r": 12.0})
		e.aw = 100.0; e.last = at
		foes.append(e)
	var hp0: float = g.player.hp
	var lowest := hp0
	var t0: float = g.time
	var won := false
	while g.time - t0 < 30.0 and g.state == "play":
		await g.get_tree().process_frame
		for e in g.enemies:   # only the six we set up: nothing streamed in from nearby camps
			if not foes.has(e) and not e.dead: e.queue_free(); g.enemies.erase(e); break
		if g.locked != null: g.shoot()
		if g.player.hp < g.player.max_hp * 0.4 and g.inv_count("medkit") > 0 and g.busy.is_empty(): g.use_item("medkit")
		lowest = minf(lowest, g.player.hp)
		if foes.all(func(e): return not is_instance_valid(e) or e.dead): won = true; break
	var lost := hp0 - lowest
	var alive: Array = g.enemies.filter(func(e): return not e.dead)
	print("COMBAT bot: won=%s, lowest hp %.0f (lost %.0f of %.0f), %.1fs, state %s, alive %s" % [won, lowest, lost, hp0, g.time - t0, g.state, str(alive.map(func(e): return "%s d%.1f aw%.0f hp%.0f" % [e.type, e.wpos.distance_to(g.player.wpos), e.aw, e.hp]))])
	var used := mk0 - g.inv_count("medkit")
	check("early fight: win using at most 1 med kit", won and used <= 1, "won %s, med kits used %d, lowest HP %.0f of %.0f" % [str(won), used, lowest, hp0])
	# death drops a recovery bag with cargo
	g.state = "play"
	g.player.hp = g.player.max_hp
	g.inv_add("fuel", 10)
	g.player.carry.scrap = 25
	g.player.hp = 0.0
	g.hurt_player(g.player.wpos, 1.0)
	g.player.hp = 0.0
	g.state = "down"
	g.respawn()
	check("death drops a recovery bag", not g.recovery.is_empty() and g.inv_count("fuel") == 0 and g.player.carry.scrap == 0, "bag %s, fuel carried %d, scrap %d" % [str(not g.recovery.is_empty()), g.inv_count("fuel"), g.player.carry.scrap])
	check("waking costs something", g.player.hp < g.player.max_hp and g.bruised_t > 0.0, "hp %.0f/%.0f, bruised %.0f" % [g.player.hp, g.player.max_hp, g.bruised_t])
	finish()

## Review 1 save safety: backups, corrupted saves, start-over confirmation.
func _debug_save_check() -> void:
	errlog.ignore = ["JSON", "Parse", "parse"]
	await g.get_tree().create_timer(1.0).timeout
	g.save_game()
	g.player.carry.scrap = 77
	g.save_game()
	check("backup written", FileAccess.file_exists(g.BAK_PATH), "save.bak.json exists")
	# a half-written temp file must not hurt the real save
	var f := FileAccess.open(g.SAVE_PATH + ".tmp", FileAccess.WRITE)
	f.store_string("{\"v\": 2, \"seed\": 12, \"px\"")
	f.close()
	check("save survives a killed write", g._read_save(g.SAVE_PATH) != null, "save.json still parses with a broken .tmp beside it")
	# corrupt the save: loading should fall back to the backup
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{garbage")
	f.close()
	g.load_game()
	await g.get_tree().create_timer(1.0).timeout
	check("corrupt save loads backup", g.state == "play", "state %s after loading with a corrupt save" % g.state)
	# corrupt both: never silently replaced
	for p in [g.SAVE_PATH, g.BAK_PATH]:
		f = FileAccess.open(p, FileAccess.WRITE)
		f.store_string("{garbage")
		f.close()
	g.load_game()
	await g.get_tree().create_timer(0.3).timeout
	check("broken saves ask first", g.hud.menu_open() and FileAccess.get_file_as_string(g.SAVE_PATH) == "{garbage", "menu open %s, save untouched %s" % [str(g.hud.menu_open()), str(FileAccess.get_file_as_string(g.SAVE_PATH) == "{garbage")])
	await _snap("user://shots/save_broken.png")
	g.hud.hide_menu()
	g.new_game_flow()
	await g.get_tree().create_timer(0.3).timeout
	check("start over asks", g.hud.menu_open(), "confirmation shown with a save present")
	await _snap("user://shots/save_confirm.png")
	g.hud.hide_menu()
	g.choose_origin()
	await g.get_tree().create_timer(0.4).timeout
	await _snap("user://shots/origin_cards.png")
	g.hud.hide_menu()
	var m := g.migrate({"v": 1, "seed": 3})
	check("old saves migrate", int(m.v) == g.SAVE_VERSION and m.has("econ") and m.has("days"), "v1 -> v%d" % int(m.v))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.BAK_PATH))
	finish()

## Review 1 P2 UI: toast queue, stacked speech, touch layout.
func _debug_ui_check() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.aw = 0.0
	g.hud.toast_q.clear(); g.hud.toast_t = 0.0
	g.hud.toast("First message")
	g.hud.toast("Second message")
	g.hud.toast("Second message")
	g.hud.toast("Third message")
	check("toasts queue", g.hud.toast_l.text == "First message" and g.hud.toast_q.size() == 2, "showing '%s', %d waiting" % [g.hud.toast_l.text, g.hud.toast_q.size()])
	await g.get_tree().create_timer(1.5).timeout
	check("toasts stay 2 s+", g.hud.toast_l.text == "First message", "still '%s' after 1.5 s" % g.hud.toast_l.text)
	await g.get_tree().create_timer(1.5).timeout
	check("duplicates merge", g.hud.toast_l.text.contains("Second message  (x2)"), "'%s'" % g.hud.toast_l.text)
	for i in 4:
		g.add_text(g.player.wpos + Vector2(0.1 * i, 0), "Overlapping line %d" % i, Color.WHITE, 3.0)
	await g.get_tree().create_timer(0.3).timeout
	var rs: Array[Rect2] = []
	for f in g.floaters: rs.append(Rect2(f.label.position, f.label.size))
	var overlap := false
	for a in rs.size():
		for b in range(a + 1, rs.size()):
			if rs[a].intersects(rs[b]): overlap = true
	check("speech doesn't overlap", not overlap and rs.size() >= 4, "%d labels, overlap %s" % [rs.size(), str(overlap)])
	# toast clear of the HUD buttons, and old messages don't follow you to a new place
	g.hud.toast("A fairly long message to check that the box stays clear of the buttons on the left side.")
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var tr := g.hud.toast_box.get_global_rect()
	var hit := false
	for b in [g.hud.crt_btn, g.hud.radio_btn, g.hud.aim_btn]:
		if tr.intersects(b.get_global_rect()): hit = true
	check("toast clear of HUD buttons", not hit, "toast %s" % str(tr))
	g.hud.toast("Arrived at Somewhere Old")
	g.hud.toast("Another old message")
	g.hud.clear_toasts()   # what _begin_trip, enter_under, exit_under and respawn call
	check("old messages cleared on travel", g.hud.toast_q.is_empty() and not g.hud.toast_box.visible, "%d queued" % g.hud.toast_q.size())
	g.perk_points = 1
	g.gain_xp(0)
	await g.get_tree().process_frame
	check("level-up isn't a pop-up", not g.hud.menu_open() and g.hud.perk_btn.visible, "menu %s, PERK button %s" % [str(g.hud.menu_open()), str(g.hud.perk_btn.visible)])
	g.player.hp = 1
	g.player.inv = 0.0
	g.hurt_player(g.player.wpos + Vector2(1, 0), 6.0)
	check("HP never negative", g.player.hp >= 0.0, "hp %.1f" % g.player.hp)
	await g.get_tree().create_timer(0.2).timeout
	if g.state == "down":
		while g.state != "play": await g.get_tree().process_frame
	g.hud.show_card("TEST PLACE\nDISCOVERED")
	g.hud.toast("A message at the same time")
	await g.get_tree().create_timer(0.6).timeout
	var cr2: Rect2 = g.hud.card_l.get_global_rect()
	cr2 = Rect2(cr2.position.x, cr2.position.y + 10, cr2.size.x, 70)   # the two text lines, not the label's padding
	check("card clear of message and prompt", not cr2.intersects(g.hud.toast_box.get_global_rect()) and not cr2.intersects(g.hud.prompt_l.get_global_rect()), "card %s toast %s" % [str(g.hud.card_l.get_global_rect()), str(g.hud.toast_box.get_global_rect())])
	await _snap("user://shots/ui_card.png")
	g.using_touch = true
	g.hud.touch.enabled = true
	g.hud.touch.visible = true
	await g.get_tree().create_timer(0.3).timeout
	await _snap("user://shots/ui_touch.png")
	check("touch prompt wording", not g.hud.prompt_l.text.contains("USE ") or g.hud.prompt_l.text.begins_with("Tap"), "'%s'" % g.hud.prompt_l.text)
	finish()

# ------------------------------------------------------------------ Review 2 checks
## Everything generated in a set of chunks, as comparable strings.
func _chunk_sig(w: World, chunks: Array) -> Dictionary:
	var rects := []
	for c in chunks: rects.append(Rect2(Vector2(c) * World.CH, Vector2.ONE * World.CH))
	var inr := func(p: Vector2) -> bool:
		for r in rects:
			if r.has_point(p): return true
		return false
	var b := []
	for x in w.buildings:
		if inr.call(Vector2(x.x0, x.y0)): b.append("%s@%d,%d %dx%d" % [x.kind, x.x0, x.y0, x.w, x.h])
	var cr := []
	for x in w.crates:
		if inr.call(x.pos): cr.append("%s@%s" % [x.kind, str(x.pos.snapped(Vector2(0.01, 0.01)))])
	var sp := []
	for x in w.spawns:
		if inr.call(x.pos): sp.append("%s@%s" % [x.type, str(x.pos.snapped(Vector2(0.01, 0.01)))])
	b.sort(); cr.sort(); sp.sort()
	return {"b": b, "c": cr, "s": sp}

## Same seed, chunks generated in two different orders: the same city every time.
func _debug_determinism() -> void:
	await g.get_tree().create_timer(0.5).timeout
	var sd := 185393
	var spots := ["sterling_downtown", "patchwork", "redwall"]
	var probe := World.new()
	probe.load_data(sd, "patchwork")
	var chunks := []
	for id in spots:
		var l := probe.loc_by_id(id)
		var ck := World.chunk_of(l.pos)
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				chunks.append(ck + Vector2i(ox, oy))
	# a suburb block too: somewhere around Port Sterling with low-mid density
	var sl := probe.loc_by_id("sterling_downtown")
	chunks.append(World.chunk_of(sl.pos + Vector2(90, 60)))
	chunks.append(World.chunk_of(sl.pos + Vector2(-80, 70)))
	var sigs := []
	for run in 3:
		var w := World.new()
		w.load_data(sd, "patchwork")   # same save = same origin; only the load order changes
		var order := chunks.duplicate()
		if run == 1: order.reverse()
		if run == 2:
			var r := RandomNumberGenerator.new(); r.seed = 7
			for i in range(order.size() - 1, 0, -1):
				var j := r.randi_range(0, i); var t = order[i]; order[i] = order[j]; order[j] = t
		for c in order: w.ensure_content(c.x, c.y)
		sigs.append(_chunk_sig(w, chunks))
		print("DET locations built in %d ms" % w.gen_ms)
		print("DET run %d: %d buildings, %d crates, %d spawns" % [run, sigs[run].b.size(), sigs[run].c.size(), sigs[run].s.size()])
	for k in ["b", "c", "s"]:
		var same: bool = sigs[0][k] == sigs[1][k] and sigs[0][k] == sigs[2][k]
		if not same:
			for run in [1, 2]:
				for x in sigs[run][k]:
					if not sigs[0][k].has(x): print("DET diff run %d %s: %s" % [run, k, x]); break
		check("same %s every load" % {"b": "buildings", "c": "crates", "s": "spawns"}[k], same, "%d / %d / %d" % [sigs[0][k].size(), sigs[1][k].size(), sigs[2][k].size()])
	finish()

## 20 new worlds (every origin), home camp in the open.
func _debug_start_clear() -> void:
	await g.get_tree().create_timer(0.5).timeout
	var bad := 0
	for i in 20:
		var o: Dictionary = g.ORIGINS[i % g.ORIGINS.size()]
		var sd := 1000 + i * 7919
		var w := World.new()
		w.load_data(sd, o.loc)
		var ck := World.chunk_of(w.start)
		w.ensure_ready(ck.x, ck.y)
		var why := []
		for y in range(-6, 7):
			for x in range(-6, 7):
				var q := w.start + Vector2(x, y)
				if Vector2(x, y).length() < 6.0 and w.building_at(q.x, q.y) != 0: why.append("building at %s" % str(q)); break
			if why.size(): break
		if w.decor_hit(w.start, 3.5): why.append("solid prop at camp")
		var pp := w.nearest_free(w.start + Vector2(0, 1.5), 0.3, 0, 6.0, false)
		if pp == Vector2.INF or pp.distance_to(w.start) > 4.0: why.append("no standing room")
		if why.size():
			bad += 1
			print("START %d (%s, seed %d) at %s: %s" % [i, o.id, sd, str(w.start), ", ".join(why)])
	check("start camp in the open", bad == 0, "%d of 20 new worlds had a blocked camp" % bad)
	finish()

## Market saturation and a supply job survive saving here and reloading somewhere else.
func _debug_reload_state() -> void:
	await g.get_tree().create_timer(1.0).timeout
	var tr: Npc = null
	for n in g.npcs:
		if n.type == "trader" and n.settlement >= 0: tr = n; break
	check("found a trader", tr != null, "")
	if tr == null: finish(); return
	var si := tr.settlement
	var st: World.Settlement = g.world.settlements[si]
	var m := Economy.market(g.world, si)
	var good := "salt"
	for k in m:
		if not m[k].made: good = k; break
	var p0 := Economy.sell_price(g.econ, st.id, good, m[good].sell, g.now())
	g.inv_add(good, 15)
	g.econ.purse[st.id] = [9999, g.now()]
	g._sell_good(tr, good, 15, m[good].sell)
	g.hud.hide_menu()
	var p1 := Economy.sell_price(g.econ, st.id, good, m[good].sell, g.now())
	# a supply job for a town far away (not loaded)
	var far: Dictionary = {}
	for l in g.world.locs:
		if l.type in ["town", "hub"] and l.pos.distance_to(g.player.wpos) > 600: far = l; break
	g.jobs.append({"kind": "supply", "title": "Bring 5 Salt to %s" % far.name, "target": far.pos, "good": "salt", "n": 5, "st": far.id, "reward": 40, "xp": 40, "from": st.name, "desc": ""})
	# save standing somewhere else, so settlements stream in a different order on load
	var away: Vector2 = far.pos + Vector2(20, 20)
	g.player.wpos = g.world.nearest_free(away, 0.3, 0, 30.0, false)
	g.player.sync(); g.rebase(); g._stream(true)
	for i in 30: await g.get_tree().process_frame
	g.save_game()
	g.load_game()
	for i in 90: await g.get_tree().process_frame
	var e0 := errlog.n
	for i in 120: await g.get_tree().process_frame   # compass + world map draw the job every frame
	g.wmap.open()
	for i in 10: await g.get_tree().process_frame
	g.wmap.close()
	check("supply job reloads cleanly", errlog.n == e0 and g.jobs.size() > 0 and g.jobs[0].get("st", "") == far.id, "%d errors in 2 s, job town %s" % [errlog.n - e0, g.jobs[0].get("st", "?") if g.jobs.size() else "none"])
	var p2 := Economy.sell_price(g.econ, st.id, good, m[good].sell, g.now())
	check("market state stays with its town", p1 < p0 and absf(p2 - p1) <= 1, "%s at %s: %d before selling, %d after, %d after reload from %d tiles away" % [good, st.name, p0, p1, p2, int(away.distance_to(st.pos))])
	var other := -1
	for i in g.world.settlements.size():
		if g.world.settlements[i].id != st.id: other = i; break
	if other >= 0:
		var mo := Economy.market(g.world, other)
		var po := Economy.sell_price(g.econ, g.world.settlements[other].id, good, mo[good].sell, g.now())
		check("other towns unaffected", po == mo[good].sell, "%s at %s: %d (base %d)" % [good, g.world.settlements[other].name, po, mo[good].sell])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.BAK_PATH))
	finish()

## Collision sweep over every named place and 250 random chunks (Review 2 P2).
func _debug_collide() -> void:
	await g.get_tree().create_timer(0.5).timeout
	var w := World.new()
	w.load_data(185393, "patchwork")
	var r := RandomNumberGenerator.new(); r.seed = 99
	var chunks := {}
	for l in w.locs:
		var ck := World.chunk_of(l.pos)
		chunks[ck] = true
	for i in 250:
		chunks[Vector2i(r.randi_range(2, World.NC - 3), r.randi_range(2, World.NC - 3))] = true
	var t0 := Time.get_ticks_msec()
	for ck in chunks: w.ensure_ready(ck.x, ck.y)
	print("COLLIDE generated %d areas in %d ms" % [chunks.size(), Time.get_ticks_msec() - t0])
	var cnt := {"tile": 0, "loot": 0, "stairs": 0, "entrance": 0, "tile_up": 0}
	var bad_b := 0
	var water_doors := 0
	var ex := {}
	for b in w.buildings:
		var probs := w.reach_problems(b)
		if probs.size(): bad_b += 1
		for p in probs:
			var k: String = p.what if not (p.what == "tile" and p.fl > 0) else "tile_up"
			cnt[k] += 1
			if not ex.has(k): ex[k] = "%s at %s fl %d" % [b.kind, str(p.at), p.fl]
		if not b.sealed and b.kind != "canopy" and w.in_bounds(b.out.x, b.out.y):
			var t := w.T[w.idx(b.out.x, b.out.y)]
			if t == World.WATER or t == World.ROCK: water_doors += 1; ex["door"] = "%s at %s" % [b.kind, str(b.out)]
	var sp_raw := 0
	var sp_bad := 0
	for s in w.spawns:
		var rr: float = World.ACTOR_R.get(s.type, 0.25)
		if not w.can_stand(s.pos, rr, s.get("fl", 0)): sp_raw += 1
		var q := w.settle_pos(s.pos, rr, s.get("fl", 0))
		if q == Vector2.INF: sp_bad += 1; ex["spawn"] = "%s at %s" % [s.type, str(s.pos)]
	var cr_bad := 0
	for c in w.critters:
		var q := w.settle_pos(c.pos, 0.3 if c.type == "cattle" else 0.25, 0, c.type in ["cattle", "crow"], 5.0)
		if q == Vector2.INF: cr_bad += 1; ex["npc"] = "%s at %s" % [c.type, str(c.pos)]
	print("COLLIDE %d buildings, %d spawns, %d npcs/critters; examples %s" % [w.buildings.size(), w.spawns.size(), w.critters.size(), str(ex)])
	check("buildings fully reachable", cnt.tile == 0 and cnt.entrance == 0, "%d of %d buildings have a problem: %d ground tiles, %d blocked entrances" % [bad_b, w.buildings.size(), cnt.tile, cnt.entrance])
	check("upper floors reachable", cnt.tile_up == 0, "%d upper-floor tiles" % cnt.tile_up)
	check("loot reachable", cnt.loot == 0, "%d loot furniture out of reach" % cnt.loot)
	check("stairs reachable", cnt.stairs == 0, "%d" % cnt.stairs)
	check("no doors onto water", water_doors == 0, "%d" % water_doors)
	check("spawns stand free", sp_bad == 0, "%d of %d have nowhere to stand (%d needed nudging when spawned)" % [sp_bad, w.spawns.size(), sp_raw])
	check("traders, settlers, cattle stand free", cr_bad == 0, "%d of %d" % [cr_bad, w.critters.size()])
	finish()

## Walls hold even with a 0.3 s frame (Review 2: 179 of 291 walk-throughs before).
func _debug_wall_check() -> void:
	await g.get_tree().create_timer(1.0).timeout
	for e in g.enemies: e.queue_free()
	g.enemies.clear()
	var tests := 0
	var through := 0
	var r := RandomNumberGenerator.new(); r.seed = 5
	for b in g.world.buildings:
		if tests >= 291: break
		if b.sealed or b.kind == "canopy" or b.open or b.ruined: continue
		var c := Vector2(b.x0 + b.w * 0.5, b.y0 + b.h * 0.5)
		if c.distance_to(g.player.wpos) > 400: continue
		for k in 24:
			if tests >= 291: break
			var ang := r.randf() * TAU
			# start just outside, run straight at the middle of the building for 1.8 s in 0.3 s frames
			var start := c + Vector2.from_angle(ang) * (maxf(b.w, b.h) * 0.75 + 1.5)
			if g.world.building_at(start.x, start.y) != 0 or not g.world.can_stand(start, 0.28, 0): continue
			g.player.wpos = start; g.player.fl = 0; g.player.climb = {}
			var dir := (c - start).normalized()
			var sdir := Actor.world_to_screen_dir(dir).normalized()
			for f in 6:
				g.player.step(0.3, sdir, sdir)
			tests += 1
			var inside: bool = g.world.building_at(g.player.wpos.x, g.player.wpos.y) == b.id
			var via_door: bool = b.door_seg != null and not b.door_seg.solid   # an open doorway is a way in
			if inside and not via_door:
				through += 1
				print("WALL through: %s at %s from %s, door %s (%s), now %s" % [b.kind, str(c), str(start), str(b.door_in), b.door_seg.mode if b.door_seg else "none", str(g.player.wpos)])
	check("walls hold with 0.3 s frames", through == 0 and tests > 100, "%d of %d runs went through a wall" % [through, tests])
	finish()
