extends "res://scripts/game_combat.gd"
## Game: camps, fast travel, sleeping and the underground.


# ------------------------------------------------------------------ sleeping
## Sleep in any bed nobody owns (ruins, motels, claimed dens) or at your camp. Time passes, you heal,
## and a full night's sleep leaves you Well Rested (+10% XP for a day). Out in the open ruins
## something might find you while you sleep; camps are safer.
func open_sleep(at_camp: bool) -> void:
	if danger():
		hud.toast("You can't sleep with enemies hunting you.")
		return
	var hh := fmod(day_t * 24.0 + 6.0, 24.0)
	var to_morning := fmod(6.0 - hh + 24.0, 24.0)
	var to_evening := fmod(19.0 - hh + 24.0, 24.0)
	var lines := ["It's %02d:%02d. HP %d/%d.%s" % [int(hh), int(fmod(hh, 1.0) * 60.0), int(player.hp), int(player.max_hp),
		"" if at_camp else "\nAn old bed. Lumpy, but it beats the dirt."]]
	var btns := []
	for o in [[1.0, "Sleep 1 hour"], [3.0, "Sleep 3 hours"], [to_morning, "Sleep until morning (06:00)"], [to_evening, "Sleep until evening (19:00)"]]:
		var h: float = o[0]
		if h < 0.5: continue
		btns.append(["%s — %dh" % [o[1], int(round(h))] if o[0] != 1.0 and o[0] != 3.0 else o[1], func(): hud.hide_menu(); _sleep(h, at_camp), false])
	btns.append(["Not now", hud.hide_menu, false])
	hud.show_menu("Sleep", lines, btns)


func _sleep(hours: float, at_camp: bool) -> void:
	var safe := at_camp or world.settlement_at(player.wpos, 2.0) >= 0 or base.claimed.has(player.building()) or under != ""
	var ambush := not safe and hours >= 2.0 and randf() < 0.18
	var slept := hours * (randf_range(0.3, 0.8) if ambush else 1.0)
	travel = {"to": {"cname": "", "wpos": player.wpos}, "t": 0.0, "done": false, "text": "Sleeping…", "card": false,
		"swap": func():
			day_t = fmod(day_t + slept / 24.0, 1.0)
			player.hp = minf(player.max_hp, player.hp + slept * player.max_hp / 6.0)
			if slept >= 6.0:
				rested_t = DAY_LEN
			for e in enemies: e.aw = 0.0
			if ambush: _sleep_ambush()
			else:
				travel.msg = ("You wake up Well Rested (+10% XP for a day)." if slept >= 6.0 else "You slept %d hours." % int(round(slept)))}
	state = "travel"


func _sleep_ambush() -> void:
	var p := player.wpos
	var t: String = ["raider", "ghoul", "rat"][randi() % 3]
	var key := World.ckey(World.chunk_of(p).x, World.chunk_of(p).y)
	for k in (3 if t == "rat" else 2):
		var at := p + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 6.0)
		if not world.can_stand(at, 0.3, player.fl): continue
		var sp := {"type": t, "pos": at, "home": p, "home_r": 6.0, "chunk": key}
		world.spawns.append(sp); world._bucket(key).spawns.append(sp)
		var e := _spawn_enemy(sp)
		e.aw = 100.0; e.last = p
	travel.msg = "Something's moving in the dark — you're awake!"


func enter_under(portal: String, at: Vector2) -> void:
	if danger():
		hud.toast("Not with enemies on your tail.")
		return
	var inf := Underground.info(portal)
	travel = {"to": {"cname": inf.name, "wpos": at}, "t": 0.0, "done": false, "text": "Going down into %s…" % inf.name,
		"swap": func(): _swap_under(portal, at)}
	state = "travel"


func exit_under() -> void:
	if under == "": return
	travel = {"to": {"cname": "The Sable Wastes", "wpos": ow.pos}, "t": 0.0, "done": false, "text": "Climbing back out…", "swap": _swap_out}
	state = "travel"


func _despawn_all() -> void:
	for key in loaded.keys(): _unload_chunk(key)
	for e in enemies:
		var sp = e.get_meta("sp") if e.has_meta("sp") else null
		if sp != null: sp.active = false; sp.pos = e.wpos
		e.queue_free()
	enemies.clear()
	for n in npcs:
		var d = n.get_meta("sp") if n.has_meta("sp") else null
		if d != null: d.active = false
		n.queue_free()
	npcs.clear()
	for s in survivors:
		if not s.get_meta("recruited"):
			if s.has_meta("sp"): s.get_meta("sp").active = false
			s.queue_free()
	survivors = survivors.filter(func(s): return not s.is_queued_for_deletion())
	bullets.clear(); particles.clear(); smoke_spots.clear()
	locked = null


func _swap_under(portal: String, outside: Vector2) -> void:
	_despawn_all()
	ow = {"world": world, "pos": outside + Vector2(0.0, 1.6), "lights": lights.lights.duplicate()}
	lights.lights.clear()
	for c in camps: c.visible = false
	base.visible = false
	if not under_state.has(portal): under_state[portal] = {"opened": {}, "killed": {}, "cleared": false}
	world = Underground.build(portal, ow.world.seed_value, under_state[portal])
	under = portal
	player.wpos = world.start
	player.fl = 0
	player.climb = {}
	dog.wpos = player.wpos + Vector2(-0.8, 0.3)
	player.sync()
	rebase()
	_stream(true)
	for e in enemies: e.aw = 0.0
	if not under_state[portal].get("visited", false):
		under_state[portal].visited = true
		gain_xp(20, "")
	hud.toast("%s. Find the way down to whatever lives at the bottom — the ladder by the entrance takes you back up." % Underground.info(portal).name)


func _swap_out() -> void:
	_despawn_all()
	lights.lights.clear()
	world = ow.world
	lights.lights = ow.lights
	for c in camps: c.visible = true
	base.visible = true
	under = ""
	player.wpos = ow.pos
	player.fl = 0
	dog.wpos = player.wpos + Vector2(-0.8, 0.3)
	player.sync()
	rebase()
	_stream(true)
	for e in enemies: e.aw = 0.0
	ow = {}


func _check_under_cleared() -> void:
	if under == "" or under_state[under].get("cleared", false): return
	for s in world.spawns:
		if not s.get("dead", false): return
	under_state[under].cleared = true
	hud.show_card("%s\nCLEARED" % Underground.info(under).name.to_upper())
	audio.play("discover", Vector2.INF, -3.0, 0.0)
	gain_xp(100, "")


# ------------------------------------------------------------------ camps
func camp_problem() -> String:
	var p := player
	if camps.size() >= 4: return "You can run up to 4 camps."
	if p.building() > 0: return "Not inside a building."
	var hs := []
	for o in [Vector2.ZERO, Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
		hs.append(world.hz(p.wpos.x + o.x, p.wpos.y + o.y))
	if hs.max() - hs.min() > 12.0: return "Ground is too steep here."
	for c in camps:
		if c.wpos.distance_to(p.wpos) < 9.0: return "Too close to another camp."
	if danger(): return "Enemies are hunting you."
	if stash.wood < 4 or stash.scrap < 2: return "Needs 4 wood + 2 scrap in your stash."
	return ""


func camp_name() -> String:
	var p := player
	var n := "Meadow Camp"
	var trees := 0
	for y in range(-3, 4):
		for x in range(-3, 4):
			if world.tile(p.wpos.x + x, p.wpos.y + y) == World.TREE: trees += 1
	var bn := world.biome_name(p.wpos)
	if bn == "hills" or bn == "peak": n = "Hilltop Camp"
	elif bn == "salt": n = "Saltpan Camp"
	elif bn == "marsh": n = "Fen Camp"
	elif bn == "canyon" or bn == "gorge": n = "Canyon Camp"
	elif world.in_city(p.wpos.x, p.wpos.y): n = "City Camp"
	elif world.near_road(int(p.wpos.x), int(p.wpos.y), 2): n = "Roadside Camp"
	elif trees > 5: n = "Woodland Camp"
	var base := n
	var k := 2
	var taken := true
	while taken:
		taken = false
		for c in camps:
			if c.cname == n: taken = true
		if taken:
			n = "%s %d" % [base, k]
			k += 1
	return n


func new_camp() -> void:
	var err := camp_problem()
	if err != "":
		hud.toast(err)
		return
	stash.wood -= 4
	stash.scrap -= 2
	var c := Camp.new()
	root.add_child(c)
	c.setup(player.wpos + Vector2(0, -1), camp_name(), false)
	_light_for("campfire_decor", c.wpos, world.hz(c.wpos.x, c.wpos.y))
	camps.append(c)
	hud.toast("Set up %s. Your stash is shared between all camps." % c.cname)
	open_camp_menu()


func can_pay(cost: Dictionary) -> bool:
	for k in RES:
		if stash[k] < cost.get(k, 0): return false
	return true


func cost_str(cost: Dictionary) -> String:
	var s := []
	for k in RES:
		if cost.get(k, 0) > 0: s.append("%d %s" % [cost[k], k])
	return ", ".join(s)


## A cleared raider den you're standing at, not yet yours.
func _den_near(p: Vector2):
	for rc in world.rcamps:
		if rc.cleared and not rc.claimed and rc.pos.distance_to(p) < 7.0: return rc
	return null


## Take over a cleared den: it becomes a camp, and its building is yours to knock through and extend.
func claim_den(rc) -> void:
	rc.claimed = true
	var at: Vector2 = rc.pos + Vector2(0, 3.4)
	for k in 16:
		var c: Vector2 = rc.pos + Vector2.from_angle(k * TAU / 16.0) * 3.6
		if world.can_stand(c, 0.4, 0) and world.building_at(c.x, c.y) == 0: at = c; break
	var cp := Camp.new()
	root.add_child(cp)
	cp.setup(at, "Den Outpost", false)
	_light_for("campfire_decor", cp.wpos, world.hz(cp.wpos.x, cp.wpos.y))
	camps.append(cp)
	base.claim_building(rc.bid)
	hud.hide_menu()
	hud.toast("The den is yours. Open Build to knock out its walls (Remove) and extend it.")


func open_camp_menu() -> void:
	if state != "play": return
	if under != "":
		hud.toast("No camping down here. Find the ladder back up.")
		return
	var c = camp_near(player.wpos, 3.2)
	var line := "Shared stash: %d scrap · %d cloth · %d wood" % [stash.scrap, stash.cloth, stash.wood]
	var btns := []
	if c != null:
		btns.append(["Sleep by the fire", func(): hud.hide_menu(); open_sleep(true), false])
	var den = _den_near(player.wpos)
	if den != null:
		btns.append(["Claim this raider den as your outpost", func(): claim_den(den), false])
	if base.can_build_here() == "":
		btns.append(["Build: walls, foundations, floors…", base.enter, false])
	if c != null:
		for u in UPG:
			if c.up[u.k]:
				btns.append(["✓ %s — built" % u.n, func(): pass, true])
			else:
				var uu = u
				btns.append(["%s (%s) — %s" % [u.n, cost_str(u.c), u.d], func(): _build(c, uu), not can_pay(u.c)])
		btns.append(["Fast travel to another camp…", open_travel_menu, camps.size() < 2])
		if not c.main:
			btns.append(["Make this my main camp", func(): _make_main(c), false])
			btns.append(["Pack up this camp", func(): _pack(c), false])
		btns.append(["Close", hud.hide_menu, false])
		hud.show_menu(c.cname + (" — main camp" if c.main else ""), [line], btns)
	else:
		var err := camp_problem()
		btns.append(["Set up a new camp here (4 wood, 2 scrap)" + ("" if err == "" else "  — " + err), new_camp, err != ""])
		btns.append(["Fast travel to a camp…", open_travel_menu, false])
		btns.append(["Close", hud.hide_menu, false])
		hud.show_menu("Set up a new camp", [line], btns)


func _build(c: Camp, u: Dictionary) -> void:
	if not can_pay(u.c): return
	for k in RES:
		stash[k] -= u.c.get(k, 0)
	c.build(u.k)
	if u.k == "tent":
		recalc_max()
		player.hp = player.max_hp
	hud.toast("Built: %s!" % u.n)
	open_camp_menu()


func _make_main(c: Camp) -> void:
	for o in camps:
		o.set_main(o == c)
	hud.toast("%s is now your main camp." % c.cname)
	open_camp_menu()


func _pack(c: Camp) -> void:
	camps.erase(c)
	c.queue_free()
	stash.wood += 2
	recalc_max()
	hud.toast("Packed up %s. Got 2 wood back." % c.cname)
	hud.hide_menu()


## Fast travel from the world map.
func travel_to(c) -> void:
	if danger():
		hud.toast("Enemies are hunting you. Lose them first.")
		return
	if c == camp_near(player.wpos, 3.2):
		hud.toast("You're already here.")
		return
	_start_travel(c)


func open_travel_menu() -> void:
	if state != "play": return
	var here = camp_near(player.wpos, 3.2)
	var dz := danger()
	var lines := []
	if dz: lines.append("Enemies are hunting you. Lose them first.")
	if camps.size() < 2: lines.append("Set up a second camp to fast travel between them.")
	var btns := []
	for c in camps:
		if c == here: continue
		var cc = c
		btns.append(["%s%s — %d tiles away" % [c.cname, " (main)" if c.main else "", int(c.wpos.distance_to(player.wpos))], func(): _start_travel(cc), dz])
	btns.append(["Back", open_camp_menu, false])
	hud.show_menu("Fast travel", lines, btns)


func _start_travel(c: Camp) -> void:
	if danger():
		hud.toast("Can't fast travel while enemies are hunting you.")
		return
	hud.hide_menu()
	travel = {"to": c, "t": 0.0, "done": false}
	state = "travel"


## Fast travel to a discovered location from the map.
func travel_to_loc(l: Dictionary) -> void:
	if danger():
		hud.toast("Enemies are hunting you. Lose them first.")
		return
	var c: Vector2 = l.pos
	world.ensure_ready(World.chunk_of(c).x, World.chunk_of(c).y)
	c = l.pos
	var at := c + Vector2(0, l.r * 0.5)
	for ring in range(0, 40):
		var found := false
		for k in 12:
			var q: Vector2 = c + Vector2.from_angle(k * TAU / 12.0 + 0.3) * float(l.r * 0.45 + ring * 0.6)
			world.ensure_ready(World.chunk_of(q).x, World.chunk_of(q).y)
			if world.can_stand(q, 0.3, 0) and world.building_at(q.x, q.y) == 0:
				at = q; found = true; break
		if found: break
	travel = {"to": {"cname": l.name, "wpos": at - Vector2(0, 1.4)}, "t": 0.0, "done": false}
	state = "travel"
