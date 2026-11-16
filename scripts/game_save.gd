extends "res://scripts/game_camps.gd"
## Game: saving, loading and settings.


# ------------------------------------------------------------------ settings
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		set_crt(cf.get_value("video", "crt", false))


func set_crt(v: bool) -> void:
	crt_on = v
	crt.visible = v
	hud.set_crt_label(v)
	var cf := ConfigFile.new()
	cf.set_value("video", "crt", v)
	cf.save("user://settings.cfg")


func toggle_crt() -> void:
	set_crt(not crt_on)


# ------------------------------------------------------------------ saving
## One save slot. The world itself is rebuilt from its seed; the save keeps what you changed:
## you, your gear, camps, stash, everything you built (and the ground you levelled for it),
## what you've discovered, looted and killed.
func save_game() -> void:
	if world == null or player == null or state == "title": return
	var w_saved := world
	var pos_saved := player.wpos
	if under != "":
		world = ow.world
		player.wpos = ow.pos
	var cps := []
	for c in camps:
		cps.append({"x": c.wpos.x, "y": c.wpos.y, "name": c.cname, "main": c.main, "up": c.up})
	var pcs := []
	for k in base.pieces:
		var s: World.Seg = base.pieces[k].seg
		pcs.append([k.x, k.y, k.z, s.tier, s.piece])
	var fls := []
	for t in base.floors: fls.append([t.x, t.y, base.floors[t].tier])
	var fds := []
	for t in base.founds: fds.append([t.x, t.y, base.founds[t].tier, base.founds[t].top])
	var vhs := []
	for v in base.orig: vhs.append([v.x, v.y, world.vh(v.x, v.y)])
	var claimed := []
	for id in base.claimed:
		var b := world.bld(id)
		if b: claimed.append([b.x0, b.y0])
	var rec := []
	for s in survivors:
		if s.get_meta("recruited"): rec.append(s.get_meta("name"))
	var d := {"v": 1, "seed": world.seed_value, "px": player.wpos.x, "py": player.wpos.y, "hp": player.hp, "max_hp": player.max_hp,
		"kills": player.kills, "carry": player.carry, "inventory": inventory, "equip": equip, "stash": stash, "day_t": day_t,
		"camps": cps, "pieces": pcs, "floors": fls, "founds": fds, "vh": vhs, "claimed": claimed, "recruited": rec,
		"discovered": world.discovered, "opened": world.opened, "killed": world.killed, "origin": origin_id,
		"econ": econ, "days": days, "trade_xp_day": trade_xp_day, "rested": rested_t, "xp": xp, "level": level, "perks": perks, "jobs": jobs, "notes": notes_read, "examined": examined, "cleared": world.cleared}
	d["under"] = under_state
	world = w_saved
	player.wpos = pos_saved
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))


func load_game() -> void:
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		hud.toast("The save file couldn't be read. Starting a new world.")
		start_new_world()
		return
	start_new_world(d)


func _apply_save(d: Dictionary) -> void:
	for c in camps: c.queue_free()
	camps.clear()
	for cd in d.get("camps", []):
		var p := Vector2(cd.x, cd.y)
		var ck := World.chunk_of(p)
		world.ensure_ready(ck.x, ck.y)
		var c := Camp.new()
		root.add_child(c)
		for k in cd.up: c.up[k] = cd.up[k]
		c.setup(p, cd.name, cd.main)
		_light_for("campfire_decor", p, world.hz(p.x, p.y))
		camps.append(c)
	for v in d.get("vh", []):
		var key := Vector2i(int(v[0]), int(v[1]))
		base.orig[key] = world.vh(key.x, key.y)
		world.set_vh(key.x, key.y, float(v[2]))
	for cl in d.get("claimed", []):
		var id := world.building_at(cl[0] + 0.5, cl[1] + 0.5)
		if id > 0: base.claim_building(id)
	for t in d.get("founds", []): base.place_found(Vector2i(int(t[0]), int(t[1])), t[2], float(t[3]))
	for t in d.get("floors", []): base.place_floor(Vector2i(int(t[0]), int(t[1])), t[2])
	for k in d.get("pieces", []): base.place(Vector3i(int(k[0]), int(k[1]), int(k[2])), k[3], k[4])
	player.wpos = Vector2(d.px, d.py)
	player.hp = d.hp
	player.max_hp = d.max_hp
	player.kills = int(d.kills)
	for k in d.carry: player.carry[k] = int(d.carry[k])
	inventory = []
	for it in d.inventory: inventory.append({"id": it.id, "n": int(it.n)})
	equip = d.equip
	for k in d.stash: stash[k] = int(d.stash[k])
	day_t = d.day_t
	origin_id = d.get("origin", "")
	_recruited_names = d.get("recruited", [])
	rested_t = float(d.get("rested", 0.0))
	econ = d.get("econ", {"sat": {}, "purse": {}, "stock": {}})
	days = int(d.get("days", 0))
	trade_xp_day = {}
	for k in d.get("trade_xp_day", {}): trade_xp_day[int(k)] = int(d.trade_xp_day[k])
	xp = int(d.get("xp", 0)); level = int(d.get("level", 1)); perks = d.get("perks", {})
	notes_read = []
	for n in d.get("notes", []): notes_read.append(int(n))
	examined = d.get("examined", {})
	under_state = d.get("under", {})
	jobs = []
	for j in d.get("jobs", []):
		if j.has("target") and typeof(j.target) == TYPE_STRING: j.target = str_to_var("Vector2" + j.target) if not j.target.begins_with("Vector2") else str_to_var(j.target)
		for k in ["reward", "xp", "n", "si"]:
			if j.has(k): j[k] = int(j[k])
		jobs.append(j)
	var main: Camp = camps[0] if camps.size() > 0 else null
	for c in camps:
		if c.main: main = c
	for nm in _recruited_names:
		var a := Actor.new()
		root.add_child(a)
		if not a.use_rendered("survivor", 8): a.make_body("survivor", 6, 16, 24)
		a.wpos = main.wpos if main else player.wpos
		a.set_meta("name", nm)
		a.set_meta("recruited", true)
		a.set_meta("slot", survivors.size())
		survivors.append(a)
	dog.wpos = player.wpos + Vector2(-1, 0)
	player.sync()
	rebase()
	_refresh_gun()
	recalc_max()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == "play": save_game()
