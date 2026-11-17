class_name Game
extends "res://scripts/game_save.gd"
## Main controller: setup, input, the game loop, the HUD and immersion systems. Its state lives in
## game_base.gd and the systems in the game_*.gd files it extends.


# ------------------------------------------------------------------ setup
func _ready() -> void:
	I = self
	_setup_input()
	_error_overlay.call_deferred()
	vpc = SubViewportContainer.new()
	vpc.stretch = true
	vpc.stretch_shrink = SHRINK
	vpc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vpc)
	vp = SubViewport.new()
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	vpc.add_child(vp)
	var bg := CanvasLayer.new()
	bg.layer = -10
	var bgr := ColorRect.new()
	bgr.color = Color("2e2440")
	bgr.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(bgr)
	vp.add_child(bg)
	var gl := CanvasLayer.new()
	gl.layer = 1
	var gr := ColorRect.new()
	gr.set_anchors_preset(Control.PRESET_FULL_RECT)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade = ShaderMaterial.new()
	grade.shader = load("res://shaders/grade.gdshader")
	gr.material = grade
	gl.add_child(gr)
	vp.add_child(gl)
	var ll := CanvasLayer.new()
	ll.layer = 2
	ll.follow_viewport_enabled = true
	lights = LightLayer.new()
	ll.add_child(lights)
	vp.add_child(ll)
	var crt_layer := CanvasLayer.new()
	crt_layer.layer = 2
	add_child(crt_layer)
	crt = ColorRect.new()
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/crt.gdshader")
	crt.material = sm
	crt.visible = false
	crt_layer.add_child(crt)
	hud = Hud.new()
	add_child(hud)
	hud.crt_toggled.connect(toggle_crt)
	audio = Audio.new()
	add_child(audio)
	hud.radio_toggled.connect(func():
		audio.toggle_radio()
		hud.radio_btn.text = "RADIO: on" if audio.radio_on else "RADIO: off")
	hud.touch.action.connect(_on_touch_action)
	wmap = WorldMap.new()
	add_child(wmap)
	wmap.setup(self)
	invs = InventoryScreen.new()
	add_child(invs)
	invs.setup(self)
	_load_settings()
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args:
		var dscript = load("res://scripts/debug_runs.gd")
		if dscript == null or not dscript.can_instantiate():
			print("FAIL debug_runs.gd doesn't compile"); get_tree().quit(1); return
		dbg = dscript.new(self)
		var oid := "drifter"
		for a in args:
			if a.begins_with("--origin="): oid = a.substr(9)
		if "--continue" in args: load_game.call_deferred()
		if "--r3spots" in args:
			dbg._debug_r3spots.call_deferred()
		else: start_new_world.call_deferred({}, oid)
		if "--snapstart" in args:
			dbg._debug_snapstart.call_deferred()
		if "--wallcheck" in args:
			dbg._debug_wall_check.call_deferred()
		if "--collide" in args:
			dbg._debug_collide.call_deferred()
		if "--determinism" in args:
			dbg._debug_determinism.call_deferred()
		if "--startclear" in args:
			dbg._debug_start_clear.call_deferred()
		if "--reloadstate" in args:
			dbg._debug_reload_state.call_deferred()
		if "--uicheck" in args:
			dbg._debug_ui_check.call_deferred()
		if "--savecheck" in args:
			dbg._debug_save_check.call_deferred()
		if "--combatcheck" in args:
			dbg._debug_combat_check.call_deferred()
		if "--econcheck" in args:
			dbg._debug_econ_check.call_deferred()
		if "--sleep" in args:
			dbg._debug_sleep.call_deferred()
		if "--under" in args:
			dbg._debug_under.call_deferred()
		if "--imm" in args:
			dbg._debug_immersion.call_deferred()
		if "--play" in args:
			dbg._debug_play.call_deferred()
		if "--econ" in args:
			dbg._debug_econ.call_deferred()
		if "--shots" in args:
			dbg._debug_shots.call_deferred()
		if "--soak" in args:
			dbg._debug_soak.call_deferred()
		if "--char" in args:
			dbg._debug_char.call_deferred()
		if "--fade" in args:
			dbg._debug_fade.call_deferred()
		if "--tour" in args:
			dbg._debug_tour.call_deferred()
		if "--walk" in args:
			dbg._debug_walk.call_deferred()
		if "--bestiary" in args:
			dbg._debug_bestiary.call_deferred()
		if "--upstairs" in args:
			dbg._debug_upstairs.call_deferred()
		if "--desks" in args:
			dbg._debug_desks.call_deferred()
		if "--ruins" in args:
			dbg._debug_ruins.call_deferred()
		if "--inv" in args:
			dbg._debug_inv.call_deferred()
		if "--map" in args:
			dbg._debug_map.call_deferred()
		if "--build" in args:
			dbg._debug_build.call_deferred()
		return
	_show_title()


func _show_title() -> void:
	var touch := DisplayServer.is_touchscreen_available()
	var ctl := ("Touch: left thumb moves (a stick appears where you touch) · hold FIRE to shoot — aim locks on by itself\nHIT melee · USE talk, loot, doors · SNEAK · HEAL · INV inventory · MAP world map · CAMP camp menu"
		if touch else "Move WASD · fire left click or Q — aim locks on by itself · F melee · E use · C sneak\nH heal · I inventory · M map · B camp menu · V CRT filter\nGamepad: left stick move · RT fire · B melee · X use · Y sneak")
	hud.show_title("One great wasteland to walk across, from Lake Winona to the ruins of Port Sterling.\nTrade, scavenge and build your way from nobody to somebody.", new_game_flow, load_game if FileAccess.file_exists(SAVE_PATH) else Callable(), ctl)


func _setup_input() -> void:
	var keys := {
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "melee": [KEY_F], "use": [KEY_E], "sneak": [KEY_C], "camp": [KEY_B],
		"travel": [KEY_T], "crt": [KEY_V], "close": [KEY_ESCAPE], "inventory": [KEY_I, KEY_TAB], "heal": [KEY_H],
		"fire": [KEY_Q, KEY_ENTER],
	}
	var pads := {"jump": JOY_BUTTON_A, "use": JOY_BUTTON_X, "melee": JOY_BUTTON_B, "sneak": JOY_BUTTON_Y, "camp": JOY_BUTTON_BACK, "inventory": JOY_BUTTON_START, "heal": JOY_BUTTON_LEFT_SHOULDER}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		if pads.has(a):
			var j := InputEventJoypadButton.new()
			j.button_index = pads[a]
			InputMap.action_add_event(a, j)


## New game: confirm first if it would replace a saved character, then pick an origin.
func new_game_flow() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		hud.show_menu("Start over?", ["This will replace your saved character. (The current save is kept as a backup until your next save.)"],
			[["Yes, start a new character", func(): hud.hide_menu(); choose_origin(), false], ["Back", func(): hud.hide_menu(); _show_title(), false]])
	else:
		choose_origin()

## One card per origin: name, upside, catch — tap the card to start.
func choose_origin() -> void:
	var btns := []
	for o in ORIGINS:
		var oid: String = o.id
		btns.append(["%s\n  + %s\n  − %s" % [o.name.to_upper(), o.get("pro_s", o.pro), o.get("con_s", o.con)], func(): hud.hide_menu(); start_new_world({}, oid), false])
	btns.append(["Back", func(): hud.hide_menu(); _show_title(), false])
	hud.show_menu("Who were you before the Wastes?", [], btns)


func start_new_world(save: Dictionary = {}, oid: String = "drifter") -> void:
	for c in vp.get_children():
		if c is Node2D:
			c.queue_free()
	enemies.clear(); camps.clear(); survivors.clear(); views.clear(); bullets.clear(); particles.clear()
	crate_nodes.clear(); tree_nodes.clear(); chop_hits.clear(); npcs.clear(); furn_nodes.clear(); decor_nodes.clear()
	smoke_spots.clear(); faded_trees.clear(); dust.clear(); lights.lights.clear(); loaded.clear()
	inventory = [{"id": "pipe_pistol", "n": 1}, {"id": "ammo_pistol", "n": 18}, {"id": "medkit", "n": 1}, {"id": "food", "n": 2}, {"id": "lockpick", "n": 3}]
	equip = {"gun": "pipe_pistol", "melee": "fists", "head": "", "body": ""}
	day_t = 0.3
	busy = {}
	rng.randomize()
	for f in floaters: f.label.queue_free()
	floaters.clear()
	stash = {"scrap": 0, "cloth": 0, "wood": 0}
	world = World.new()
	if not save.is_empty():
		world.opened = save.get("opened", {})
		world.killed = save.get("killed", {})
		world.discovered = save.get("discovered", {})
		world.cleared = save.get("cleared", {})
	origin_id = save.get("origin", oid)
	world.load_data(int(save.get("seed", randi() % 1000000)), origin().loc)
	Iso.origin = world.start.x + world.start.y
	root = Node2D.new()
	vp.add_child(root)
	terrain_root = Node2D.new()
	root.add_child(terrain_root)
	_parent = root
	# home camp: a cleared spot on the road west of Patchwork
	world._flatten(world.start, 3.5, world.hz(world.start.x, world.start.y), true)
	for y in range(int(world.start.y) - 4, int(world.start.y) + 5):
		for x in range(int(world.start.x) - 4, int(world.start.x) + 5):
			if world.T[world.idx(x, y)] == World.TREE: world.T[world.idx(x, y)] = World.GRASS
	var c := Camp.new()
	root.add_child(c)
	c.setup(world.start, "Home Camp", true)
	if save.is_empty():
		var o := origin()
		inventory = []
		for it in o.kit: inventory.append({"id": it[0], "n": it[1]})
		for k in o.get("equip", {}): equip[k] = o.equip[k]
		stash.scrap = int(o.get("scrap", 0))
	_light_for("campfire_decor", world.start, world.hz(world.start.x, world.start.y))
	camps.append(c)
	base = BaseBuild.new()
	root.add_child(base)
	base.setup(self, world)
	player = Player.new()
	root.add_child(player)
	player.wpos = world.start + Vector2(0, 1.5)
	var pf := world.nearest_free(player.wpos, 0.3, 0, 6.0, false)
	if pf != Vector2.INF: player.wpos = pf
	if origin().get("raider", false):
		c.cname = "Raider Hideout"
		var fp := world.start + Vector2(2.2, 0.6)
		var fn := _spawn_npc({"type": "trader", "pos": fp, "home": fp})
		fn.set_meta("fence", true)
		for k in 2:
			var gp := world.start + Vector2.from_angle(k * 2.6 + 0.8) * 2.4
			var sp := {"type": "raider", "pos": gp, "home": world.start, "home_r": 2.5}
			_spawn_enemy(sp)
	if save.is_empty() and origin().has("hp"):
		player.max_hp = origin().hp
		player.hp = player.max_hp
	dog = Dog.new()
	root.add_child(dog)
	dog.wpos = player.wpos + Vector2(-1, 0)
	under = ""; ow = {}
	if save.is_empty():
		econ = {"sat": {}, "purse": {}, "stock": {}}; days = 0; trade_xp_day = {}; recovery = {}; bruised_t = 0.0
	if save.is_empty():
		xp = 0; level = 1; perk_points = 0; perks = {}; jobs = []; notes_read = []; examined = {}; under_state = {}
	greeted = {}
	weather = Weather.new()
	root.add_child(weather)
	fx = FxLayer.new()
	fx.z_index = 4095
	fx.z_as_relative = false
	root.add_child(fx)
	cam = Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	if not save.is_empty():
		_apply_save(save)
	_stream(true)
	var wps := [world.road_point_near(player.wpos), world.road_point_near(player.wpos), world.road_point_near(player.wpos), world.road_point_near(player.wpos)]
	_spawn_npc({"type": "wanderer", "pos": wps[0], "patrol": wps})
	time = 0.0; spawn_t = 0.0; patrol_t = 0.0; income_t = 0.0; encounter_t = 0.0
	_last_pb = -99999
	state = "play"
	_discover()
	if not save.is_empty():
		hud.toast("Welcome back. Your camps and stash are as you left them.")
		return
	var sl := world.loc_by_id(origin().loc)
	if origin().get("raider", false):
		hud.toast("Downtown Port Sterling. The gang's hideout — the fence will buy what you take. Towns won't love you. Press M for the map.")
		return
	hud.toast("The Sable Wastes. %s is just over there — press M for the map, I for your inventory." % sl.get("name", "Town"))


# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		using_touch = true
	if ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		using_touch = false
	if ev.is_action_pressed("crt"):
		toggle_crt()
	if hud.menu_open() and (ev.is_action_pressed("close") or ev.is_action_pressed("inventory")):
		hud.hide_menu()
		get_viewport().set_input_as_handled()
		return
	if invs and invs.visible:
		if ev is InputEventKey and ev.pressed and ev.keycode in [KEY_I, KEY_ESCAPE, KEY_TAB]:
			invs.close_screen(); get_viewport().set_input_as_handled()
		return
	if wmap and wmap.visible:
		if (ev is InputEventKey and ev.pressed and ev.keycode in [KEY_M, KEY_ESCAPE]):
			wmap.close(); get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_M and state == "play" and not hud.menu_open():
		wmap.open(); return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_P and state == "play" and not hud.menu_open() and perk_points > 0:
		_offer_perk(); return
	if state != "play" or hud.menu_open():
		return
	if base and base.active and _build_input(ev):
		get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("use"): interact()
	elif ev.is_action_pressed("melee"): melee()
	elif ev.is_action_pressed("jump"): player.start_jump()
	elif ev.is_action_pressed("sneak"): toggle_sneak()
	elif ev.is_action_pressed("camp"): open_camp_menu()
	elif ev.is_action_pressed("travel"): open_travel_menu()
	elif ev.is_action_pressed("inventory"): open_inventory()
	elif ev.is_action_pressed("heal"): quick_heal()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		melee()


## Build mode: the mouse places pieces, R rotates, 1-5 pick the tier, Esc leaves.
func _build_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ev.pressed: base.press(ev.position)
		else: base.release(ev.position)
		return true
	if ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		base.move(ev.position)
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_R: base.turn(); return true
			KEY_ESCAPE: base.leave(); return true
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				base.select(BaseBuild.TIERS[ev.keycode - KEY_1], ""); return true
	if ev.is_action_pressed("camp"):
		base.leave(); return true
	return false


func _on_touch_action(n: String) -> void:
	using_touch = true
	if state != "play" or hud.menu_open():
		return
	match n:
		"use": interact()
		"melee": melee()
		"jump": player.start_jump()
		"sneak": toggle_sneak()
		"camp": open_camp_menu()
		"inv": open_inventory()
		"heal": quick_heal()
		"map": wmap.open()
		"fire": shoot()


func _read_move() -> Vector2:
	var v := Vector2(Input.get_action_strength("right") - Input.get_action_strength("left"), Input.get_action_strength("down") - Input.get_action_strength("up"))
	var j := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if j.length() > 0.2: v += j
	v += hud.touch.move_vec()
	v += _bot_move
	return v


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	delta = minf(delta, 0.1)    # a long hitch (chunk load, app resume) must not teleport anything
	var t_us := Time.get_ticks_usec()
	_process_inner(delta)
	proc_ms = (Time.get_ticks_usec() - t_us) / 1000.0


func _process_inner(delta: float) -> void:
	if state == "title" or world == null:
		return
	time += delta
	if state == "travel":
		travel.t += delta / 1.4
		if travel.t >= 0.5 and not travel.done and travel.has("swap"):
			travel.done = true
			travel.swap.call()
		elif travel.t >= 0.5 and not travel.done:
			travel.done = true
			var c = travel.to
			player.wpos = c.wpos + Vector2(0, 1.4)
			player.fl = 0
			player.climb = {}
			dog.wpos = player.wpos + Vector2(-1, 0)
			player.sync()
			rebase()
			_stream(true)
			for e in enemies: e.aw = 0.0
			if travel.get("ambush", false):
				# the ambush happens part-way along the road
				var mid: Vector2 = travel.get("from", player.wpos).lerp(player.wpos, randf_range(0.35, 0.65))
				world.ensure_ready(World.chunk_of(mid).x, World.chunk_of(mid).y)
				for t in 40:
					if world.can_stand(mid, 0.3, 0) and world.building_at(mid.x, mid.y) == 0: break
					mid += Vector2(randf_range(-2, 2), randf_range(-2, 2))
				player.wpos = mid
				player.sync(); rebase(); _stream(true)
			_arrive_trip()
			_discover()
		if travel.t >= 1.0:
			state = "play"
			if travel.has("msg"): hud.toast(travel.msg)
			elif travel.has("swap"): hud.show_card(travel.to.cname.to_upper())
			else: hud.toast("Arrived at %s. A few hours pass." % travel.to.cname)
		fx.fade = 1.0 - absf(travel.t * 2.0 - 1.0)
		fx.fade_text = travel.get("text", "Traveling to %s…" % travel.to.cname)
		_update_camera()
		return
	fx.fade = 0.0
	if state == "down":
		down_t -= delta
		fx.fade = clampf((2.8 - down_t) * 0.5, 0.0, 0.85)
		fx.fade_text = "You blacked out… your dog drags you to safety."
		if down_t <= 0.0:
			respawn()
		_update_camera()
		return
	if hud.menu_open() or (wmap and wmap.visible) or (invs and invs.visible):
		_update_camera()
		return
	var p := player
	if absf(p.wpos.x + p.wpos.y - Iso.origin) > 48.0:
		rebase()
	_stream(false)
	_discover()
	save_t += delta
	if save_t > 45.0:
		save_t = 0.0
		save_game()
	var mv := _read_move()
	update_lock()
	_apply_pending_hits()
	_update_busy(delta, mv.length() > 0.2)
	if not busy.is_empty(): mv = Vector2.ZERO
	p.step(delta, mv, _read_aim())
	if _wants_fire():
		shoot()
	dog.step(delta, p)
	var here = camp_near(p.wpos, 3.2)
	if here != null:
		if p.carry.cloth + p.carry.wood > 0:
			hud.toast("Stashed %d cloth, %d wood. Scrap stays in your pocket — deposit it from the camp menu (%s)." % [p.carry.cloth, p.carry.wood, "CAMP" if using_touch else "B"])
			stash.cloth += p.carry.cloth; stash.wood += p.carry.wood
			p.carry.cloth = 0; p.carry.wood = 0
		p.regen += delta * (0.5 if bruised_t > 0.0 else 1.0)
		if p.regen > (1.0 if here.up.garden else 3.5) and p.hp < p.max_hp:
			p.regen = 0.0
			p.hp = minf(p.max_hp, p.hp + 1.0)
			add_text(p.wpos, "+1 hp", Color("9fd08a"))
	var nrec := 0
	for s in survivors:
		if s.get_meta("recruited"): nrec += 1
	if nrec > 0:
		income_t += delta
		if income_t > 20.0:
			income_t = 0.0
			stash.scrap += nrec
			stash.wood += nrec
			hud.toast("Your survivors brought back +%d scrap, +%d wood." % [nrec, nrec])
	for c in camps:
		if not c.up.tower: continue
		c.tower_cd -= delta
		if c.tower_cd > 0.0: continue
		var tp: Vector2 = c.tower_pos()
		var tgt = null
		var td := 8.0
		for e in enemies:
			var d: float = e.wpos.distance_to(tp)
			if not e.dead and e.fl == 0 and d < td and not e.friendly(): td = d; tgt = e
		if tgt != null:
			var dir: Vector2 = (tgt.wpos - tp).normalized()
			bullets.append({"pos": tp, "vel": dir * 15.0, "z": world.hz(tp.x, tp.y) + 12.0, "fl": 0, "life": 1.0, "enemy": false, "tower": true})
			c.tower_cd = 1.1
		else:
			c.tower_cd = 0.3
	var p_at_camp := here != null
	for e in enemies:
		if not e.dead:
			e.think(delta, p, p_at_camp)
	_separate()
	for e in enemies:
		if e.dead: e.queue_free()
	enemies = enemies.filter(func(e): return not e.dead)
	for n in npcs: n.step(delta, p)
	noise_level = maxf(0.0, noise_level - delta * 30.0)
	_world_life(delta)
	spawn_t += delta
	if spawn_t > 40.0 and under == "":
		spawn_t = 0.0
		var mutants := 0
		for e in enemies:
			if e.type != "raider": mutants += 1
		if mutants < 12 and world.settlement_at(p.wpos, 12.0) < 0:
			var cps := []
			for c in camps: cps.append(c.wpos)
			var before := world.spawns.size()
			world.add_monster(p.wpos, 22.0, cps)
			for i in range(before, world.spawns.size()): _spawn_enemy(world.spawns[i])
	patrol_t += delta
	if patrol_t > 90.0 and under == "":
		patrol_t = 0.0
		var has := false
		for e in enemies:
			if e.patrol.size() > 0: has = true
		if not has and world.settlement_at(p.wpos, 20.0) < 0 and randf() < 0.6:
			var before := world.spawns.size()
			world.add_patrol(p.wpos)
			for i in range(before, world.spawns.size()): _spawn_enemy(world.spawns[i])
	if under == "":
		_encounters(delta)
		_update_jobs()
	_immersion(delta)
	_update_bullets(delta)
	_update_visibility()
	_update_camera()
	_update_hud()


## Sound beds, footsteps, weather, people talking as you pass, enemies shouting when they spot you.
func _immersion(delta: float) -> void:
	var p := player
	if under == "": weather.step(delta, self)
	else:
		weather.amt = 0.0; weather.target = 0.0; weather.kind = "clear"
		audio.set_bed("amb_rain", 0.0)
	var sun := sin(day_t * TAU)
	var night := clampf(-sun * 1.6 + 0.3, 0.0, 1.0)
	var inside := world.building_at(p.wpos.x, p.wpos.y) != 0 or under != ""
	var wet: bool = weather.kind == "rain" or weather.kind == "rad"
	var storm: float = weather.amt if weather.kind in ["dust", "rad"] else 0.0
	audio.set_bed("amb_wind", (0.15 if inside else 0.45 + storm * 0.5) * (0.7 if night > 0.5 else 1.0))
	audio.set_bed("amb_night", 0.0 if inside or wet else night * 0.55)
	audio.set_bed("amb_town", 0.5 if in_settlement >= 0 and not world.settlements[in_settlement].small else 0.0)
	var fire := 0.0
	for s in smoke_spots:
		fire = maxf(fire, 1.0 - s.distance_to(p.wpos) / 7.0)
	audio.set_bed("amb_fire", clampf(fire, 0.0, 1.0) * 0.6)
	audio.set_bed("amb_inside", 0.5 if inside else 0.0)
	# footsteps
	if p.moving and p.climb.is_empty():
		step_t -= delta * (0.65 if p.crouch else 1.0)
		if step_t <= 0.0:
			step_t = 0.36
			var t := world.tile(p.wpos.x, p.wpos.y)
			var hard := inside or t == World.ROAD or t == World.SIDE
			audio.play("step_%s%d" % ["hard" if hard else "dirt", randi() % 3], Vector2.INF, -16.0 if p.crouch else -11.0, 0.1)
	# barks
	bark_t -= delta
	if bark_t <= 0.0:
		bark_t = 0.6
		for n in npcs:
			if not n.visible or n.has_meta("barked") and time - float(n.get_meta("barked")) < 30.0: continue
			if n.wpos.distance_to(p.wpos) < 3.2 and randf() < 0.35:
				n.set_meta("barked", time)
				var kind: String = {"trader": "trader", "wanderer": "wanderer", "settler": "settler"}.get(n.type, "")
				if kind != "": add_text(n.wpos + Vector2(0, -0.3), Lore.bark(kind), Color("e8e0c8"), 2.6)
				break
	for e in enemies:
		if e.dead: continue
		if e.aw >= 99.0 and not e.has_meta("alerted"):
			e.set_meta("alerted", true)
			match e.type:
				"raider":
					audio.play("raider_shout", e.wpos, -2.0, 0.15)
					if randf() < 0.6: add_text(e.wpos + Vector2(0, -0.4), Lore.bark("raider"), Color("ffb0a0"), 2.0)
				"ghoul", "brute": audio.play("ghoul_groan", e.wpos, -2.0, 0.2)
				"rat": audio.play("rat_squeak", e.wpos, -4.0, 0.2)
			if dog and dog.wpos.distance_to(e.wpos) < 14.0: audio.play("dog_bark", dog.wpos, -6.0)
		elif e.aw < 20.0 and e.has_meta("alerted"):
			e.remove_meta("alerted")
		elif e.friendly() and e.wpos.distance_to(p.wpos) < 2.5 and not e.has_meta("barked"):
			e.set_meta("barked", true)
			add_text(e.wpos + Vector2(0, -0.4), Lore.bark("raider_friend"), Color("e8e0c8"), 2.4)
	# ghouls groan now and then
	if randf() < delta * 0.25:
		for e in enemies:
			if not e.dead and e.type == "ghoul" and e.wpos.distance_to(p.wpos) < 16.0:
				audio.play("ghoul_groan", e.wpos, -8.0, 0.25); break


func _update_hud() -> void:
	var p := player
	var g := gun_info()
	var gun_s := ("%s  %d" % [g.name, inv_count(g.ammo)]) if not g.is_empty() else "unarmed"
	var hh := int(day_t * 24.0 + 6.0) % 24
	var nrec := 0
	for s in survivors:
		if s.get_meta("recruited"): nrec += 1
	var wx: String = {"dust": "  · dust", "rain": "  · rain", "rad": "  · RADSTORM"}.get(weather.kind, "") if weather and weather.amt > 0.2 else ""
	if rested_t > 0.0: wx += "  · Rested"
	hud.stats.text = "%s   ARM %d   %02d:00%s\nScrap %d  ·  Med %d  ·  Goods %d/%d%s" % [
		gun_s, armor_total(), hh, wx, p.carry.scrap + stash.scrap, inv_count("medkit"), goods_carried(), goods_cap(), ("   [SNEAKING]" if p.crouch else "")]
	hud.hp = p.hp
	hud.hp_max = p.max_hp
	hud.level = level
	hud.xp_frac = clampf(float(xp) / Perks.xp_needed(level), 0.0, 1.0)
	var wa := p.world_aim()
	if p.moving and locked == null: wa = p.walk_dir
	hud.facing = lerp_angle(hud.facing, wa.angle(), 0.15)
	var mk := []
	for l in world.locs:
		var d: float = p.wpos.distance_to(l.pos)
		if d < 8.0: continue
		var known := world.discovered.has(l.id)
		if known and d < 400.0: mk.append([(l.pos - p.wpos).angle(), "loc"])
		elif not known and d < 160.0: mk.append([(l.pos - p.wpos).angle(), "loc_new"])
	if under != "":
		mk.clear()
		var ex: Vector2 = world.start - Vector2(1, 1)
		if ex.distance_to(p.wpos) > 3.0: mk.append([(ex - p.wpos).angle(), "camp"])
	for c in camps:
		if under != "": break
		if c.wpos.distance_to(p.wpos) > 6.0: mk.append([(c.wpos - p.wpos).angle(), "camp"])
	if not recovery.is_empty() and recovery.get("under", "") == under and recovery.pos.distance_to(p.wpos) > 2.0:
		mk.append([(recovery.pos - p.wpos).angle(), "bag"])
	for j in jobs:
		if under != "": break
		var tgt: Vector2 = j.target   # supply jobs carry their town's position too
		if tgt.distance_to(p.wpos) > 4.0: mk.append([(tgt - p.wpos).angle(), "job"])
	for e in enemies:
		if not e.dead and e.aw > 60.0 and e.wpos.distance_to(p.wpos) < 30.0 and not e.friendly(): mk.append([(e.wpos - p.wpos).angle(), "enemy"])
	hud.marks = mk
	hud.job_l.text = ("JOB: " + jobs[0].title + ("  (+%d more)" % (jobs.size() - 1) if jobs.size() > 1 else "")) if jobs.size() else ""
	var t := find_target()
	var k := "Tap USE to" if using_touch else "[E]"
	var msg := ""
	if not t.is_empty() and p.climb.is_empty():
		match t.k:
			"rope": msg = "%s Climb %s the rope" % [k, "up" if t.end == "bottom" else "down"]
			"tree": msg = "%s Chop tree (%d/3)" % [k, chop_hits.get(world.idx(t.x, t.y), 0)]
			"survivor": msg = "%s Recruit %s" % [k, t.o.get_meta("name")]
			"stairs": msg = "%s Go %s" % [k, "downstairs" if p.fl == 1 else "upstairs"]
			"crate": msg = "%s Search %s" % [k, {"car": "car trunk", "bag": "remains", "brute": "remains", "cache": "raider stash", "crate": "crate"}.get(t.o.kind, t.o.kind.replace("_", " "))]
			"npc": msg = "%s %s" % [k, "Talk" if t.o.type == "settler" else "Trade"]
			"door":
				var cmk := "Tap HIT to" if using_touch else "[F]"
				match t.o.door:
					"closed": msg = "%s Open door" % k
					"locked": msg = ("%s Pick lock (%d)   %s Bash (loud)" % [k, inv_count("lockpick"), cmk]) if inv_count("lockpick") > 0 else "Locked — %s Bash it in (loud)" % cmk
					"barred": msg = "Barricaded — %s Bash (loud)" % cmk
					"sealed": msg = "Boarded up"
			"camp": msg = "Tap CAMP for the camp menu" if using_touch else "[B] Camp menu"
			"examine": msg = "%s Look: %s" % [k, t.o.info.get_slice("|", 0)]
			"bed":
				if t.b.settlement >= 0 and not base.claimed.has(t.b.id): msg = "Someone's bed — sleep in your own, or claim a place"
				else: msg = "%s Sleep" % k
			"portal":
				if t.o.portal == "exit": msg = "%s Climb back up to the surface" % k
				else:
					var ui := Underground.info(t.o.portal)
					var cl: bool = under_state.get(t.o.portal, {}).get("cleared", false)
					msg = "%s Enter %s%s" % [k, ui.name, "  (cleared)" if cl else ""]
	if not busy.is_empty():
		msg = ("Healing… %d%%" if busy.get("kind", "") == "heal" else "Picking lock… %d%%") % int(100.0 * busy.t / busy.total)
	if using_touch:
		msg = _touch_case(msg)
	hud.set_prompt(msg)
	hud.touch.queue_redraw()
	if p.flash > 0.0:
		fx.flash = p.flash
	else:
		fx.flash = 0.0


## "Tap USE to Open door" -> "Tap USE to open door".
func _touch_case(msg: String) -> String:
	for b: String in ["Tap USE to ", "Tap HIT to "]:
		var i := msg.find(b)
		while i >= 0:
			var j: int = i + (b as String).length()
			if j < msg.length():
				msg = msg.substr(0, j) + msg[j].to_lower() + msg.substr(j + 1)
			i = msg.find(b, j)
	return msg


## Red line at the bottom of the screen with the first script error (any build, incl. phones).
func _error_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	var l := Label.new()
	l.visible = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -64
	l.offset_left = 12
	l.offset_right = -12
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(l)
	OS.add_logger(ErrorOverlay.new(l))
