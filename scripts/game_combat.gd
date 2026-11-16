extends "res://scripts/game_trade.gd"
## Game: aiming, shooting, melee, bullets, damage, death, doors, interaction and looting.


## A raider player hurt one of the gang: every raider nearby turns on them.
func provoke_raiders(at: Vector2) -> void:
	var any := false
	for e in enemies:
		if e.type == "raider" and not e.provoked and e.wpos.distance_to(at) < 14.0:
			e.provoked = true
			e.aw = 100.0
			e.last = player.wpos
			any = true
	if any: hud.toast("You turned on your own. The gang won't forget it.")


func gun_range() -> float:
	var g := gun_info()
	if g.is_empty() or inv_count(g.ammo) <= 0: return 1.6
	return g.speed * g.life * 0.92


func update_lock() -> void:
	var p := player
	var rng_ := gun_range()
	if locked != null and (not is_instance_valid(locked) or locked.dead or not locked.visible or locked.fl != p.fl or locked.friendly()
			or locked.wpos.distance_to(p.wpos) > rng_ * 1.15 or not world.los(p.wpos, locked.wpos, p.fl)):
		locked = null
	if locked != null: return
	var bd := 1e9
	var face := p.walk_dir
	for e in enemies:
		if e.dead or not e.visible or e.fl != p.fl or e.friendly(): continue
		var to: Vector2 = e.wpos - p.wpos
		var d := to.length()
		if d > rng_ or not world.los(p.wpos, e.wpos, p.fl): continue
		# with standard aim, prefer what you're facing over what's merely closest
		var score := d if aim_assist else d * (1.0 + (1.0 - face.dot(to / maxf(d, 0.01))) * 0.8)
		if score < bd:
			bd = score; locked = e


func _read_aim() -> Vector2:
	if locked != null:
		return (locked.position + Vector2(0, -10)) - (player.position + Vector2(0, -14))
	var j := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if j.length() > 0.3: return j
	if not using_touch:
		var mouse_vp := get_viewport().get_mouse_position() / SHRINK
		var m := cam.get_screen_center_position() - Vector2(vp.size) * 0.5 + mouse_vp
		return m - (player.position + Vector2(0, -14))
	return Vector2.ZERO


func _wants_fire() -> bool:
	if base and base.active: return false
	if hud.touch.firing(): return true
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5: return true
	if Input.is_action_pressed("fire"): return true
	return not using_touch and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


# ------------------------------------------------------------------ actions
func find_target() -> Dictionary:
	var p := player
	var pb := p.building()
	var best := {}
	var bd := 9.0
	for s in survivors:
		if s.get_meta("recruited") or world.building_at(s.wpos.x, s.wpos.y) != pb or p.fl != 0:
			continue
		var d: float = p.wpos.distance_to(s.wpos)
		if d < 1.5 and d < bd: bd = d; best = {"k": "survivor", "o": s}
	if p.fl == 0:
		for r in world.near(p.wpos, "ropes"):
			for end in [["top", r.top], ["bottom", r.bottom]]:
				var d: float = p.wpos.distance_to(end[1])
				if d < 1.0 and d < bd: bd = d; best = {"k": "rope", "o": r, "end": end[0]}
	if pb > 0:
		var b := world.bld(pb)
		if b.stairs.x >= 0:
			var d := p.wpos.distance_to(Vector2(b.stairs) + Vector2(0.5, 0.5))
			if d < 0.9 and d < bd: bd = d; best = {"k": "stairs", "o": b}
	for c in world.near(p.wpos, "crates"):
		if c.open or c.bid != pb or c.fl != p.fl:
			continue
		var d: float = p.wpos.distance_to(c.pos)
		if d < 1.2 and d < bd: bd = d; best = {"k": "crate", "o": c}
	if best.is_empty() and pb == 0:
		var tx := int(floor(p.wpos.x))
		var ty := int(floor(p.wpos.y))
		for yy in range(ty - 1, ty + 2):
			for xx in range(tx - 1, tx + 2):
				if not world.in_bounds(xx, yy) or world.T[world.idx(xx, yy)] != World.TREE: continue
				var d := p.wpos.distance_to(Vector2(xx + 0.5, yy + 0.5))
				if d < 1.1 and d < bd: bd = d; best = {"k": "tree", "x": xx, "y": yy}
	if p.fl == 0:
		for n in npcs:
			if n.type in ["trader", "wanderer", "settler"] and n.visible:
				var d: float = p.wpos.distance_to(n.wpos)
				if d < 1.4 and d < bd: bd = d; best = {"k": "npc", "o": n}
	var dn := door_near(p.wpos, 1.15)
	if dn != null:
		var dd := p.wpos.distance_to((dn.a + dn.b) * 0.5)
		if dd < bd: bd = dd; best = {"k": "door", "o": dn}
	if pb != 0:
		var hb := world.bld(pb)
		if hb:
			for f in hb.furn:
				if f.name == "bed" and f.fl == p.fl:
					var dd: float = p.wpos.distance_to(f.pos)
					if dd < 1.5 and dd < bd: bd = dd; best = {"k": "bed", "o": f, "b": hb}
	if p.fl == 0 and pb == 0:
		for d in world.near(p.wpos, "decor"):
			if d.portal != "":
				var dd: float = p.wpos.distance_to(d.pos)
				if dd < 1.9 and dd < bd: bd = dd; best = {"k": "portal", "o": d}
			if d.info != "":
				var dd: float = p.wpos.distance_to(d.pos)
				if dd < 1.8 and dd < bd: bd = dd; best = {"k": "examine", "o": d}
	if best.is_empty() and camp_near(p.wpos, 3.2) != null:
		best = {"k": "camp"}
	return best


func interact() -> void:
	var t := find_target()
	if t.is_empty():
		return
	var p := player
	match t.k:
		"survivor":
			var s: Actor = t.o
			if origin().get("raider", false):
				add_text(s.wpos + Vector2(0, -0.2), "Run with raiders? I'd rather starve.", Color("e8a090"), 2.6)
				return
			s.set_meta("recruited", true)
			if s.has_meta("sp"): s.get_meta("sp").recruited = true
			hud.toast("%s joined your group and heads to your main camp." % s.get_meta("name"))
		"camp":
			open_camp_menu()
		"rope":
			var r: World.Rope = t.o
			p.climb = {"from": p.wpos, "to": r.top if t.end == "bottom" else r.bottom, "t": 0.0}
		"stairs":
			var b: World.Bld = t.o
			p.fl = 1 - p.fl
			hud.toast("Upstairs." if p.fl == 1 else "Downstairs.")
		"tree":
			if p.mcd > 0.0: return
			p.mcd = 0.4
			p.swing = 0.16
			var i: int = world.idx(t.x, t.y)
			var n: int = chop_hits.get(i, 0) + 1
			chop_hits[i] = n
			var tp := Vector2(t.x + 0.5, t.y + 0.5)
			burst(tp, 5, [Color("c8a070"), Color("8a6a44"), Color("5f9448")], 10.0)
			audio.play("chop", tp, -4.0)
			noise(tp, 3.0 if p.crouch else 5.0, 8.0 if p.crouch else 16.0)
			var spr: Sprite2D = tree_nodes.get(i)
			if spr:
				var tw := create_tween()
				tw.tween_property(spr, "offset:x", spr.offset.x + 1.5, 0.05)
				tw.tween_property(spr, "offset:x", spr.offset.x - 1.5, 0.05)
				tw.tween_property(spr, "offset:x", spr.offset.x, 0.05)
			if n >= 3:
				world.T[i] = World.STUMP
				chop_hits.erase(i)
				if spr:
					spr.texture = Assets.tex("stump")
					spr.offset = Assets.off("stump")
				var wd := randi_range(2, 4)
				p.carry.wood += wd
				add_text(tp, "+%d wood" % wd, Color("d8b880"))
		"crate":
			_loot(t.o)
		"bed":
			if t.b.settlement >= 0 and not base.claimed.has(t.b.id):
				add_text(player.wpos, "That bed belongs to someone.", Color("e8a090"), 2.0)
			else:
				open_sleep(false)
		"portal":
			var pd: World.Decor = t.o
			if pd.portal == "exit": exit_under()
			else: enter_under(pd.portal, pd.pos)
		"examine":
			var d: World.Decor = t.o
			hud.show_menu(d.info.get_slice("|", 0), [d.info.get_slice("|", 1)], [["Move on", hud.hide_menu, false]])
			var key := World.pkey(d.pos)
			if not examined.has(key):
				examined[key] = true
				gain_xp(10, "")
		"door":
			open_door(t.o)
		"npc":
			var n: Npc = t.o
			if n.type == "settler":
				add_text(n.wpos + Vector2(0, -0.2), Lore.bark("settler"), Color("e8e0c8"), 2.6)
			else:
				open_trade(n)


func _loot(c: World.Crate) -> void:
	var p := player
	c.open = true
	if not c.has_meta("loot") and c.kind != "bag" and c.kind != "brute": world.opened[World.pkey(c.pos)] = true
	if crate_nodes.has(c):
		var spr: Sprite2D = crate_nodes[c]
		if c.kind == "crate" or c.kind == "cache":
			spr.texture = Assets.tex(c.kind + "_open")
		else:
			spr.texture = null
	audio.play("crate" if c.kind in ["crate", "cache", "car"] else "pickup", c.pos, -4.0)
	var q := 0.55 if p.crouch else 1.0
	noise(c.pos, (5.0 if c.kind == "car" else 4.5) * q, (35.0 if c.kind == "car" else 24.0) * q)
	var mats := Items.roll_materials(c.kind, rng)
	var items := Items.roll_loot(c.kind, rng)
	if c.has_meta("loot"):                       # something you dropped: exactly that comes back
		mats = [0, 0, 0]; items = c.get_meta("loot")
	if c.has_meta("mats"):
		var mm: Dictionary = c.get_meta("mats")
		mats = [int(mm.scrap), int(mm.cloth), int(mm.wood)]
	if c.has_meta("recovery"):
		recovery = {}
		hud.toast("Got your pack back.")
	if c.has_meta("extra"): items.append([c.get_meta("extra"), 1])
	if any_up("bench") and rng.randf() < 0.5:
		items.append([gun_info().get("ammo", "ammo_pistol"), 2])
	if origin().get("scav", false) and c.kind != "bag" and not c.has_meta("loot"): mats[0] += 1
	if perk("scrounger") > 0 and randf() < 0.35 * perk("scrounger") and not c.has_meta("loot"):
		items.append([gun_info().get("ammo", "ammo_pistol"), randi_range(2, 5)])
	if not c.has_meta("loot") and c.kind not in ["car", "bag", "brute"] and randf() < (0.3 if under != "" else 0.13):
		_find_note.call_deferred()
	p.carry.scrap += mats[0]; p.carry.cloth += mats[1]; p.carry.wood += mats[2]
	var parts := []
	if mats[0]: parts.append("+%d scrap" % mats[0])
	if mats[1]: parts.append("+%d cloth" % mats[1])
	if mats[2]: parts.append("+%d wood" % mats[2])
	var found_gear := ""
	for it in items:
		if it[0] == "": continue
		inv_add(it[0], it[1])
		var d := Items.info(it[0])
		parts.append(("%s ×%d" % [d.name, it[1]]) if it[1] > 1 else d.name)
		if d.get("slot", "") in ["gun", "melee", "head", "body"]: found_gear = d.name
	add_text(c.pos, " · ".join(parts) if parts.size() else "empty", Color("f2e6c8"), 2.2)
	if found_gear != "":
		hud.toast("Found %s! Press %s to open your inventory and equip it." % [found_gear, "INV" if using_touch else "I"])


func toggle_sneak() -> void:
	player.crouch = not player.crouch
	hud.toast("Sneaking: slower, but enemies barely notice you. Melee an unaware enemy for a silent takedown." if player.crouch else "Standing up.")


func melee() -> void:
	var p := player
	if p.mcd > 0.0 or not p.climb.is_empty():
		return
	p.mcd = 0.45
	p.swing = 0.16
	var wa := p.world_aim()
	var loud := false
	var dmg: float = Items.info(equip.melee).get("dmg", 1) * float(origin().get("melee", 1.0)) * (1.0 + 0.4 * perk("brawler"))
	audio.play("swing", Vector2.INF, -8.0)
	for e in enemies:
		if e.dead or e.fl != p.fl:
			continue
		var to: Vector2 = e.wpos - p.wpos
		var d := to.length()
		if d < 1.3 and to.normalized().dot(wa) > 0.1:
			if p.crouch and e.aw < 35.0:
				if e.type == "brute":
					add_text(e.wpos, "sneak attack!", Color("9fd08a"))
					e.damage(dmg * 3.0, p.wpos)
				else:
					add_text(e.wpos, "silent takedown", Color("9fd08a"))
					kill_enemy(e, true)
			else:
				loud = true
				e.damage(dmg, p.wpos)
				audio.play("hit_flesh", e.wpos, -3.0)
	if not loud:
		var ds := door_near(p.wpos, 1.3, wa)
		if ds != null:
			bash_door(ds, dmg)
			return
	if loud or not p.crouch:
		noise(p.wpos, 2.5, 12.0)


## Closest closed/locked/barred/sealed door within r (optionally roughly in direction dir).
func door_near(pos: Vector2, r: float, dir: Vector2 = Vector2.ZERO) -> World.Seg:
	if player.fl != 0:
		return null
	var best: World.Seg = null
	var bd := r
	var tx := int(floor(pos.x))
	var ty := int(floor(pos.y))
	for yy in range(ty - 1, ty + 2):
		for xx in range(tx - 1, tx + 2):
			if not world.in_bounds(xx, yy): continue
			for sg in world.seg_grid.get(yy * World.N + xx, []):
				if not sg.is_door or sg.mode == "stub" or not sg.door in ["closed", "locked", "barred", "sealed"]: continue
				var mid: Vector2 = (sg.a + sg.b) * 0.5
				var d := pos.distance_to(mid)
				if dir != Vector2.ZERO and d > 0.3 and (mid - pos).normalized().dot(dir) < 0.2: continue
				if d < bd: bd = d; best = sg
	return best


func _view_of(bid: int) -> BuildingView:
	for v in views:
		if v.b.id == bid: return v
	return null


func set_door(sg: World.Seg, st: String) -> void:
	if audio and sg.door != st and (st == "open" or st == "closed"): audio.play("door", (sg.a + sg.b) * 0.5, -6.0)
	world.set_door(sg, st)
	if sg.bid == -1:
		base.refresh(sg)
		return
	var v := _view_of(sg.bid)
	if v: v.refresh_seg(sg)


func open_door(sg: World.Seg) -> void:
	match sg.door:
		"closed":
			set_door(sg, "open")
			noise((sg.a + sg.b) * 0.5, 1.5, 8.0)
		"locked":
			if inv_count("lockpick") > 0:
				busy = {"door": sg, "t": 0.0, "total": 2.4}
				hud.toast("Picking the lock… stay still. (%d lockpicks)" % inv_count("lockpick"))
			else:
				hud.toast("Locked. You need a lockpick — or bash it in with melee attacks (loud, draws attention).")
		"barred":
			hud.toast("Barricaded from the inside. Bash it down with melee attacks — it'll be loud.")
		"sealed":
			hud.toast("Boarded up tight. There's no getting in here.")


func bash_door(sg: World.Seg, dmg: float) -> void:
	var mid: Vector2 = (sg.a + sg.b) * 0.5
	if sg.door == "sealed":
		hud.toast("These boards are nailed solid. You won't get through.")
		return
	sg.door_hp -= maxf(1.0, dmg)
	burst(mid, 6, [Color("8a6a44"), Color("5a3e28"), Color("c8a070")], 12.0, 0)
	noise(mid, 9.0, 85.0)
	if sg.door_hp <= 0.0:
		set_door(sg, "broken")
		noise(mid, 12.0, 100.0)
		add_text(mid, "the door gives way!", Color("f2c36b"))
	else:
		add_text(mid, "bang!", Color("e8e0c8"), 0.8)


func _update_busy(delta: float, moving: bool) -> void:
	if busy.is_empty():
		return
	if busy.get("kind", "") == "heal":
		# moving stops it; so does a beating (a third of your health) — a scratch doesn't
		if moving or player.hp < busy.hp0 - player.max_hp * 0.33:
			busy = {}
			hud.toast("Interrupted — stand still to heal." if moving else "Interrupted — that hit knocked the kit out of your hands.")
			return
		busy.t += delta
		if busy.t >= busy.total:
			var id: String = busy.id
			busy = {}
			_apply_heal(id)
		return
	var sg: World.Seg = busy.door
	if moving or player.inv > 0.0 or sg.door != "locked":
		busy = {}
		hud.toast("Stopped picking the lock.")
		return
	busy.t += delta
	if busy.t >= busy.total:
		var mid: Vector2 = (sg.a + sg.b) * 0.5
		var chance := 0.6 + (0.15 if player.crouch else 0.0)
		if rng.randf() < chance:
			set_door(sg, "open")
			add_text(mid, "click — unlocked", Color("9fd08a"))
		else:
			inv_take("lockpick")
			noise(mid, 2.0, 10.0)
			add_text(mid, "the pick snapped", Color("e88a6a"))
			if inv_count("lockpick") > 0:
				busy = {"door": sg, "t": 0.0, "total": 2.4}
				return
		busy = {}


func shoot() -> void:
	var p := player
	if p.cd > 0.0 or not p.climb.is_empty():
		return
	var g := gun_info()
	if g.is_empty() or inv_count(g.ammo) <= 0:
		melee()
		if not g.is_empty() and time - float(p.get_meta("noammo", -10.0)) > 3.0:
			hud.toast("Out of %s. Melee still works — or switch guns in the inventory (I)." % Items.iname(g.ammo).to_lower())
			p.set_meta("noammo", time)
		return
	inv_take(g.ammo)
	p.cd = g.rate * (0.8 if any_up("bench") else 1.0)
	var wa := p.world_aim()
	var spread: float = g.spread * (1.0 - 0.3 * perk("steady"))
	# positioning matters: shots spread wider on the move, tighter standing still or crouched
	if not aim_assist:
		spread *= 0.6 if p.crouch else (1.9 if p.moving else 1.0)
	var dmg_m := 1.0 + 0.2 * perk("gunslinger")
	for k in g.pellets:
		var dir := wa.rotated(randf_range(-spread, spread))
		var dm: float = g.dmg * dmg_m * (2.0 if randf() < 0.15 * perk("lucky") else 1.0)
		bullets.append({"pos": p.wpos + wa * 0.4, "vel": dir * g.speed, "z": p.ground_z() + 10.0, "fl": p.fl, "life": g.life, "enemy": false, "dmg": dm})
	var gsnd: String = {"shotgun": "gun_shotgun", "rifle": "gun_rifle", "pistol_10mm": "gun_heavy"}.get(equip.gun, "gun_pistol")
	audio.play(gsnd, Vector2.INF, -3.0)
	burst(p.wpos + wa * 0.5, 3, [Color("f2d06b"), Color("f28c28")], 9.0, p.fl)
	noise(p.wpos, 10.0, 70.0)


func enemy_shoot(e: Enemy, at: Vector2, weapon: String = "pipe_pistol") -> void:
	var g := Items.info(weapon)
	var base := (at - e.wpos).angle()
	for k in g.get("pellets", 1):
		var dir := Vector2.from_angle(base + randf_range(-0.1, 0.1) + randf_range(-g.spread, g.spread) * 0.5)
		bullets.append({"pos": e.wpos + dir * 0.4, "vel": dir * 8.0, "z": e.ground_z() + 10.0, "fl": e.fl, "life": 1.4 if g.pellets == 1 else 0.6, "enemy": true, "src": e.wpos, "dmg": 3.0 if g.pellets == 1 else 2.0})
	burst(e.wpos, 2, [Color("f2d06b")], 9.0, e.fl)
	audio.play("enemy_gun", e.wpos, -4.0)
	for o in enemies:
		if o.type == "raider" and not o.dead and o.wpos.distance_to(e.wpos) < 8.0:
			o.aw = maxf(o.aw, 80.0)
			o.last = player.wpos


func throw_rock(e: Enemy, at: Vector2) -> void:
	var dir := (at - e.wpos).normalized()
	bullets.append({"pos": e.wpos + dir * 0.5, "vel": dir * 6.0, "z": e.ground_z() + 18.0, "fl": e.fl, "life": 1.6, "enemy": true, "src": e.wpos, "dmg": 4.0, "rock": true})


## Each attacker has its own attack cooldown (Enemy.atk_cd), so several enemies hurt you that much
## faster; the short global window only stops two hits landing on the same frame.
func _apply_pending_hits() -> void:
	if pending_hits.is_empty() or player.inv > 0.0 or state != "play": return
	var h: Array = pending_hits.pop_front()
	if time - float(h[2]) < 0.6: hurt_player(h[0], h[1])

func hurt_player(from: Vector2, dmg: float = 3.0) -> void:
	var p := player
	hurt_calls += 1
	if state != "play": return
	if p.inv > 0.0:
		# two hits inside the 0.15 s grace window: the second lands right after it, not never
		# (spawn protection and the wake-up grace still block outright)
		hurt_blocked += 1
		if p.inv <= 0.15 and pending_hits.size() < 4:
			pending_hits.append([from, dmg, time])
		return
	var taken := maxf(1.0, round(dmg * (1.0 - _reduction())))
	p.hp = maxf(0.0, p.hp - taken)
	p.inv = 0.15
	p.flash = 0.3
	audio.play("hurt", Vector2.INF, -4.0)
	var d := p.wpos - from
	if d.length() > 0.01:
		p.move(d.normalized() * (0.9 if dmg >= 6.0 else 0.12))
	if p.hp <= 0.0:
		state = "down"
		down_t = 2.8
		p.climb = {}


func _drop(pos: Vector2, kind: String, fl: int) -> World.Crate:
	var c := World.Crate.new()
	c.pos = pos
	c.kind = kind
	c.bid = world.building_at(pos.x, pos.y)
	c.fl = fl
	_place_crate(c)
	return c


## A crate made during play (drops, bags): filed with its chunk so it survives unloading.
func _place_crate(c: World.Crate) -> void:
	world.crates.append(c)
	var ck := World.chunk_of(c.pos)
	var key := World.ckey(ck.x, ck.y)
	world._bucket(key).crates.append(c)
	var rec = loaded.get(key)
	_parent = rec.node if rec != null else root
	var s := _sprite("bag", c.pos, world.stand_z(c.pos.x, c.pos.y, c.fl), Vector2(-4, -8), 0.1)
	_parent = root
	crate_nodes[c] = s
	if rec != null: rec.crates.append(c)


func kill_enemy(e: Enemy, silent: bool) -> void:
	if e.dead:
		return
	e.dead = true
	var sp = e.get_meta("sp") if e.has_meta("sp") else null
	if sp != null:
		sp.dead = true
		if sp.has("key"): world.killed[sp.key] = true
	player.kills += 1
	audio.play({"ghoul": "ghoul_die", "brute": "ghoul_die", "rat": "rat_squeak"}.get(e.type, "hit_flesh"), e.wpos, -2.0)
	var boss := e.has_meta("boss")
	gain_xp(60 if boss else {"rat": 3, "ghoul": 6, "raider": 8, "shellback": 10, "brute": 25, "robot": 15}.get(e.type, 5), "")
	if sp != null and sp.has("loc"):
		if under != "": _check_under_cleared()
		else: _check_cleared(sp.loc)
	if boss:
		for j in jobs:
			if j.kind == "bounty" and j.get("boss") == e.get_meta("boss"): _complete_job(j)
		var bc := _drop(e.wpos, "cache", e.fl)
		bc.set_meta("extra", Items.gear_of_tier(3, rng))
	var cols := [Color("8a6a4a"), Color("5a3a24"), Color("3a2a2a")] if e.type == "shellback" else ([Color("6a8a4a"), Color("8a3a3a"), Color("3a2a2a")] if e.type in ["ghoul", "brute"] else [Color("a83a2a"), Color("5a3a2a"), Color("3a2a2a")])
	burst(e.wpos, 12, cols, 9.0, e.fl)
	if e.type == "raider":
		var c := _drop(e.wpos, "bag", e.fl)
		if randf() < 0.4: c.set_meta("extra", e.weapon)
		if e.camp >= 0:
			var left := false
			for o in enemies:
				if not o.dead and o.camp == e.camp: left = true
			if not left:
				world.rcamps[e.camp].cleared = true
				hud.toast("Raider camp cleared! Its stash is yours.")
	elif e.type == "brute":
		_drop(e.wpos, "brute", e.fl)
		hud.toast("The brute goes down hard. It was carrying something…")
	elif e.type == "ghoul" and randf() < 0.3:
		_drop(e.wpos, "bag", e.fl)
	e.visible = false


func respawn() -> void:
	var p := player
	hud.clear_toasts()
	pending_hits.clear()
	_drop_recovery_bag()
	if under != "": _swap_out()
	var c: Camp = camps[0]
	var bd := 1e9
	for o in camps:
		var d: float = o.wpos.distance_to(p.wpos)
		if d < bd: bd = d; c = o
	p.wpos = c.wpos + Vector2(0, 1.4)
	p.fl = 0
	p.hp = ceil(p.max_hp * 0.5)
	p.inv = 2.0
	bruised_t = DAY_LEN / 24.0
	advance_time(3.0)
	dog.wpos = p.wpos + Vector2(-1, 0)
	p.sync()
	rebase()
	_stream(true)
	for e in enemies:
		e.aw = 0.0
	state = "play"
	save_game()
	hud.toast("You came to at %s, bruised, three hours later.%s" % [c.cname, " Your pack is where you fell — it's on your compass." if not recovery.is_empty() else ""])

## On going down: carried scrap and materials and all trade goods go into a bag where you fell.
## Get back to it and it's yours again; go down again first and the old bag is gone.
func _drop_recovery_bag() -> void:
	var p := player
	var items_ := []
	for it in inventory:
		if Items.info(it.id).get("trade", false): items_.append([it.id, it.n])
	var mats: Dictionary = p.carry.duplicate()
	if items_.is_empty() and mats.scrap + mats.cloth + mats.wood == 0:
		recovery = {}
		return
	for it in items_: inv_take(it[0], it[1])
	p.carry = {"scrap": 0, "cloth": 0, "wood": 0}
	if not recovery.is_empty() and recovery.get("crate") != null:
		var old = recovery.crate
		if crate_nodes.has(old):
			crate_nodes[old].queue_free(); crate_nodes.erase(old)
		old.open = true
	var cr := World.Crate.new()
	cr.pos = p.wpos
	cr.kind = "bag"
	cr.fl = p.fl
	cr.set_meta("loot", items_)
	cr.set_meta("mats", mats)
	cr.set_meta("recovery", true)
	if under == "": _place_crate(cr)
	recovery = {"pos": p.wpos, "under": under, "crate": cr if under == "" else null, "items": items_, "mats": mats}


func _update_bullets(delta: float) -> void:
	for b in bullets:
		for s in 4:
			if b.life <= 0.0: break
			b.pos += b.vel * delta / 4.0
			if b.get("tower", false):
				b.z = maxf(world.hz(b.pos.x, b.pos.y) + 10.0, b.z - delta * 30.0)
			if world.blocks_shot(b.pos, b.z, b.fl):
				b.life = 0.0
				burst(b.pos, 3, [Color("c9c0a0"), Color("8a8a8a")], 10.0, b.fl)
				break
			if b.enemy:
				if b.pos.distance_to(player.wpos) < 0.33 and player.climb.is_empty() and player.fl == b.fl:
					hurt_player(b.src, b.get("dmg", 3.0))
					b.life = 0.0
			else:
				for e in enemies:
					if not e.dead and e.fl == b.fl and b.pos.distance_to(e.wpos) < 0.42:
						e.damage(b.get("dmg", 2.0), player.wpos)
						b.life = 0.0
						break
		b.life -= delta
	bullets = bullets.filter(func(b): return b.life > 0.0)
	for q in particles:
		q.pos += q.vel * delta
		q.z += q.vz * delta
		if not q.get("smoke", false): q.vz -= 90.0 * delta
		if q.z < 0.0:
			q.z = 0.0; q.vel *= 0.5; q.vz = 0.0
		q.life -= delta
	particles = particles.filter(func(q): return q.life > 0.0)
