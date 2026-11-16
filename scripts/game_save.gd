extends "res://scripts/game_camps.gd"
## Game: saving, loading and settings.


# ------------------------------------------------------------------ settings
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		set_crt(cf.get_value("video", "crt", false))
		set_aim_assist(cf.get_value("play", "aim_assist", false))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "crt", crt_on)
	cf.set_value("play", "aim_assist", aim_assist)
	cf.save("user://settings.cfg")


func set_crt(v: bool) -> void:
	crt_on = v
	crt.visible = v
	hud.set_crt_label(v)
	_save_settings()


## Aim assist: full auto-aim (always the nearest target, no penalty for shooting on the move).
## Standard aim prefers what you're facing and spreads wider while moving.
func set_aim_assist(v: bool) -> void:
	aim_assist = v
	hud.aim_btn.text = "AIM: assist" if v else "AIM: standard"
	_save_settings()


func toggle_crt() -> void:
	set_crt(not crt_on)


# ------------------------------------------------------------------ saving
## One save slot. The world itself is rebuilt from its seed; the save keeps what you changed:
## you, your gear, camps, stash, everything you built (and the ground you levelled for it),
## what you've discovered, looted and killed.
func save_game() -> void:
	if world == null or player == null or state == "title": return
	if state == "travel" and not travel.has("from"): return      # underground swaps, sleeping: next save catches it
	var w_saved := world
	var pos_saved := player.wpos
	if state == "travel": player.wpos = travel.from
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
	var d := {"v": SAVE_VERSION, "seed": world.seed_value, "px": player.wpos.x, "py": player.wpos.y, "hp": player.hp, "max_hp": player.max_hp,
		"kills": player.kills, "carry": player.carry, "inventory": inventory, "equip": equip, "stash": stash, "day_t": day_t,
		"camps": cps, "pieces": pcs, "floors": fls, "founds": fds, "vh": vhs, "claimed": claimed, "recruited": rec,
		"discovered": world.discovered, "opened": world.opened, "killed": world.killed, "origin": origin_id,
		"recovery": {"pos": [recovery.pos.x, recovery.pos.y], "under": recovery.under, "items": recovery.items, "mats": recovery.mats} if not recovery.is_empty() else {}, "bruised": bruised_t, "econ": econ, "days": days, "trade_xp_day": trade_xp_day, "rested": rested_t, "xp": xp, "level": level, "perk_points": perk_points, "perks": perks, "jobs": jobs, "notes": notes_read, "examined": examined, "cleared": world.cleared}
	d["under"] = under_state
	world = w_saved
	player.wpos = pos_saved
	_write_save(JSON.stringify(d))


## Saves are written to a temp file and renamed into place, so an app killed mid-save (Android does
## this right after the app loses focus) never leaves a half-written save. The previous save is kept
## as save.bak.json.
func _write_save(txt: String) -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_string(txt)
	f.flush()
	f.close()
	if typeof(JSON.parse_string(FileAccess.get_file_as_string(tmp))) != TYPE_DICTIONARY: return
	var real := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(real, ProjectSettings.globalize_path(BAK_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real)


static func _read_save(path: String):
	if not FileAccess.file_exists(path): return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else null


## Bring an older save up to date (bump SAVE_VERSION whenever save fields change).
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("v", 1))
	if v < 2:
		# v2: markets, day counter, recovery bag, bruised, underground state
		for k in ["econ", "trade_xp_day", "recovery", "under"]:
			if not d.has(k): d[k] = {}
		if not d.has("days"): d.days = 0
		if not d.has("bruised"): d.bruised = 0.0
	if v < 3:
		# v3: markets and jobs keyed by town id. v2 keyed them by settlements[] index, which
		# changes with streaming order, so the old market state can't be trusted: let it reset
		# (it recovers in a day anyway). Supply jobs keep their target position to find the town.
		d.econ = {"sat": {}, "purse": {}, "stock": {}}
		d.trade_xp_day = {}
		for j in d.get("jobs", []):
			j.erase("si")
	d.v = SAVE_VERSION
	return d


## Never silently replace a broken save: fall back to the backup, and if that fails too, ask.
func load_game() -> void:
	var d = _read_save(SAVE_PATH)
	if d == null:
		var b = _read_save(BAK_PATH)
		if b != null:
			hud.toast("Your last save couldn't be read — loaded the backup from just before it.")
			start_new_world(migrate(b))
			return
		_broken_save_menu()
		return
	start_new_world(migrate(d))

func _broken_save_menu() -> void:
	var btns := []
	if FileAccess.file_exists(BAK_PATH):
		btns.append(["Try the backup", func():
			var b = _read_save(BAK_PATH)
			hud.hide_menu()
			if b != null: start_new_world(migrate(b))
			else: _broken_save_menu(), false])
	btns.append(["Start a new world (old save kept as save.broken.json)", func():
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path("user://save.broken.json"))
		hud.hide_menu()
		choose_origin(), false])
	btns.append(["Quit", func(): get_tree().quit(), false])
	hud.show_menu("Save problem", ["Your save file couldn't be read, and there's no working backup.", "Nothing has been overwritten."], btns)


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
	bruised_t = float(d.get("bruised", 0.0))
	recovery = {}
	var rc: Dictionary = d.get("recovery", {})
	if not rc.is_empty():
		recovery = {"pos": Vector2(rc.pos[0], rc.pos[1]), "under": rc.under, "items": rc.items, "mats": rc.mats, "crate": null}
		if rc.under == "":
			var cr := World.Crate.new()
			cr.pos = recovery.pos
			cr.kind = "bag"
			cr.set_meta("loot", rc.items)
			cr.set_meta("mats", rc.mats)
			cr.set_meta("recovery", true)
			var ck := World.chunk_of(cr.pos)
			world.ensure_ready(ck.x, ck.y)
			_place_crate(cr)
			recovery.crate = cr
	days = int(d.get("days", 0))
	trade_xp_day = {}
	for k in d.get("trade_xp_day", {}): trade_xp_day[str(k)] = int(d.trade_xp_day[k])
	xp = int(d.get("xp", 0)); level = int(d.get("level", 1)); perk_points = int(d.get("perk_points", 0)); perks = d.get("perks", {})
	notes_read = []
	for n in d.get("notes", []): notes_read.append(int(n))
	examined = d.get("examined", {})
	under_state = d.get("under", {})
	jobs = []
	for j in d.get("jobs", []):
		if j.has("target") and typeof(j.target) == TYPE_STRING: j.target = str_to_var("Vector2" + j.target) if not j.target.begins_with("Vector2") else str_to_var(j.target)
		for k in ["reward", "xp", "n"]:
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
		if state == "play" or state == "travel": save_game()
