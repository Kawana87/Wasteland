class_name Game
extends Node
## Main controller: builds the scene, owns the world, runs the game loop, handles input,
## camps / fast travel, loot, combat and the HUD.

static var I: Game

const SHRINK := 3                 # game pixels -> screen: the world renders at 1/3 of the UI size
const RES := ["scrap", "cloth", "wood"]
const UPG := [
	{"k": "tent", "n": "Shelter", "d": "+1 max health", "c": {"scrap": 2, "cloth": 3, "wood": 4}},
	{"k": "bench", "n": "Workbench", "d": "Pistol mod: faster fire, more ammo from crates", "c": {"scrap": 6, "wood": 4}},
	{"k": "garden", "n": "Garden + water barrel", "d": "Heal much faster at this camp", "c": {"scrap": 4, "cloth": 2, "wood": 2}},
	{"k": "tower", "n": "Watchtower", "d": "A lookout shoots enemies near this camp", "c": {"scrap": 10, "cloth": 2, "wood": 8}},
]

var world: World
var vp: SubViewport
var vpc: SubViewportContainer
var root: Node2D
var cam: Camera2D
var hud: Hud
var crt: ColorRect
var crt_on := false
var fx: FxLayer

var player: Player
var dog: Dog
var enemies: Array = []
var camps: Array = []
var survivors: Array = []
var views: Array = []
var crate_nodes := {}            # Crate -> Sprite2D
var tree_nodes := {}             # tile index -> Sprite2D
var chop_hits := {}
var stash := {"scrap": 0, "cloth": 0, "wood": 0}
var bullets: Array = []          # {pos, vel, z, fl, life, enemy, src}
var particles: Array = []
var floaters: Array = []
var time := 0.0
var state := "title"             # title, play, down, travel
var down_t := 0.0
var travel := {}
var spawn_t := 0.0
var patrol_t := 0.0
var income_t := 0.0
var using_touch := false
var _last_pb := -1
var _last_pfl := -1

# ------------------------------------------------------------------ setup
func _ready() -> void:
	I = self
	_setup_input()
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
	hud.touch.action.connect(_on_touch_action)
	_load_settings()
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args:
		start_new_world.call_deferred()
		if "--shots" in args:
			_debug_shots.call_deferred()
		if "--soak" in args:
			_debug_soak.call_deferred()
		return
	hud.show_title("A new world is generated every time: rolling hills and cliffs out west, a ruined city to the east.\nRaiders hold camps on top of plateaus — walk up the ramp, or climb the rope round the back.\nMutant hounds hunt in packs, but fear campfires. Set up camps anywhere and fast travel between them.\n\nPC: WASD move · mouse aim · left click shoot · F / right click melee · Space jump · C sneak\nE use / chop / climb / stairs · B camp menu · T fast travel · V CRT filter\nGamepad: left stick move · right stick aim · RT shoot · A jump · X use · B melee · Y sneak\nTouch: left thumb move · right thumb aim and shoot · buttons on the right", start_new_world)

func _setup_input() -> void:
	var keys := {
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "melee": [KEY_F], "use": [KEY_E], "sneak": [KEY_C], "camp": [KEY_B],
		"travel": [KEY_T], "crt": [KEY_V], "close": [KEY_ESCAPE],
	}
	var pads := {"jump": JOY_BUTTON_A, "use": JOY_BUTTON_X, "melee": JOY_BUTTON_B, "sneak": JOY_BUTTON_Y, "camp": JOY_BUTTON_BACK, "travel": JOY_BUTTON_START}
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

func start_new_world() -> void:
	for c in vp.get_children():
		if c is Node2D:
			c.queue_free()
	enemies.clear(); camps.clear(); survivors.clear(); views.clear(); bullets.clear(); particles.clear()
	crate_nodes.clear(); tree_nodes.clear(); chop_hits.clear()
	for f in floaters: f.label.queue_free()
	floaters.clear()
	stash = {"scrap": 0, "cloth": 0, "wood": 0}
	world = World.new()
	world.generate(randi() % 1000000)
	root = Node2D.new()
	vp.add_child(root)
	var terrain := TerrainMesh.new()
	terrain.build(world)
	root.add_child(terrain)
	for b in world.buildings:
		var v := BuildingView.new()
		v.setup(world, b)
		root.add_child(v)
		views.append(v)
	_spawn_props()
	var c := Camp.new()
	root.add_child(c)
	c.setup(world.start, "Home Camp", true)
	camps.append(c)
	player = Player.new()
	root.add_child(player)
	player.wpos = world.start + Vector2(0, 1.5)
	dog = Dog.new()
	root.add_child(dog)
	dog.wpos = player.wpos + Vector2(-1, 0)
	for s in world.spawns:
		_spawn_enemy(s)
	for s in world.survivors:
		var a := Actor.new()
		root.add_child(a)
		a.make_body("survivor", 6, 16, 24)
		a.wpos = s.pos
		a.set_meta("name", s.name)
		a.set_meta("recruited", false)
		a.set_meta("slot", survivors.size())
		survivors.append(a)
	fx = FxLayer.new()
	fx.z_index = 4095
	fx.z_as_relative = false
	root.add_child(fx)
	cam = Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	time = 0.0; spawn_t = 0.0; patrol_t = 0.0; income_t = 0.0
	_last_pb = -1
	state = "play"
	hud.toast("Hills to the west, a ruined city to the east. Raiders hold the plateaus — and hounds roam the wilds.")

func _spawn_enemy(s: Dictionary) -> Enemy:
	var e := Enemy.new()
	root.add_child(e)
	e.setup(s)
	enemies.append(e)
	return e

func _sprite(tex: String, at: Vector2, z: float, off: Vector2, depth_bias: float = 0.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.offset = off
	s.position = Iso.to_screen(at.x, at.y, z).round()
	s.z_index = Iso.z_for(at.x + at.y + depth_bias, 3)
	root.add_child(s)
	return s

func _spawn_props() -> void:
	var w := world
	for y in World.N:
		for x in World.N:
			if w.T[w.idx(x, y)] == World.TREE:
				var v := w.V[w.idx(x, y)]
				var tex := "tree_dead" if (v == 3 and (x * 7 + y) % 3 == 0) else "tree%d" % (v % 3)
				var p := Vector2(x + 0.5, y + 0.5)
				tree_nodes[w.idx(x, y)] = _sprite(tex, p, w.hz(p.x, p.y), Vector2(-12, -36))
	for c in w.cars:
		_sprite("car_%s_%s" % [c.spr, c.axis], c.pos, w.hz(c.pos.x, c.pos.y), Vector2(-40, -30))
	for cr in w.crates:
		if cr.kind == "car":
			continue
		var z := w.stand_z(cr.pos.x, cr.pos.y, cr.fl)
		var s := _sprite(cr.kind, cr.pos, z, Vector2(-8, -12), 0.1)
		s.z_index = Iso.z_for(cr.pos.x + cr.pos.y, 3 + cr.fl * 2)
		crate_nodes[cr] = s
	for p in w.posts:
		_sprite("post", p, w.hz(p.x, p.y), Vector2(-1, -14))
	for p in w.raider_flags:
		_sprite("flag_raider", p, w.hz(p.x, p.y), Vector2(-1, -30))
	for r in w.ropes:
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
		root.add_child(l)
		var hook := Line2D.new()
		hook.width = 1.0
		hook.default_color = Color("9a9a9a")
		hook.points = PackedVector2Array([(a + Vector2(-2, 0)).round(), (a + Vector2(2, -2)).round()])
		hook.z_index = l.z_index
		root.add_child(hook)

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

func add_text(p: Vector2, txt: String, col: Color = Color("f2e6c8")) -> void:
	floaters.append({"pos": p, "z": 18.0, "t": 1.4, "label": hud.float_text(txt, col)})

func noise(at: Vector2, rad: float, amt: float) -> void:
	for e in enemies:
		if not e.dead:
			e.hear(at, rad, amt)

## world pixel position -> HUD (UI) coordinates
func to_hud(px: Vector2) -> Vector2:
	var vs := Vector2(vp.size)
	return (px - cam.get_screen_center_position() + vs * 0.5) * SHRINK

func recalc_max() -> void:
	player.max_hp = 5 + (1 if any_up("tent") else 0)
	player.hp = mini(player.hp, player.max_hp)

# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		using_touch = true
	if ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		using_touch = false
	if ev.is_action_pressed("crt"):
		toggle_crt()
	if ev.is_action_pressed("close") and hud.menu_open():
		hud.hide_menu()
	if state != "play" or hud.menu_open():
		return
	if ev.is_action_pressed("use"): interact()
	elif ev.is_action_pressed("melee"): melee()
	elif ev.is_action_pressed("jump"): player.start_jump()
	elif ev.is_action_pressed("sneak"): toggle_sneak()
	elif ev.is_action_pressed("camp"): open_camp_menu()
	elif ev.is_action_pressed("travel"): open_travel_menu()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		melee()

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

func _read_move() -> Vector2:
	var v := Vector2(Input.get_action_strength("right") - Input.get_action_strength("left"), Input.get_action_strength("down") - Input.get_action_strength("up"))
	var j := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if j.length() > 0.2: v += j
	v += hud.touch.move_vec()
	return v

func _read_aim() -> Vector2:
	var t := hud.touch.aim_vec()
	if t.length() > 0.2: return t
	var j := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if j.length() > 0.3: return j
	if not using_touch:
		var mouse_vp := get_viewport().get_mouse_position() / SHRINK
		var m := cam.get_screen_center_position() - Vector2(vp.size) * 0.5 + mouse_vp
		return m - (player.position + Vector2(0, -9))
	return Vector2.ZERO

func _wants_fire() -> bool:
	if hud.touch.firing(): return true
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5: return true
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
		for r in world.ropes:
			for end in [["top", r.top], ["bottom", r.bottom]]:
				var d: float = p.wpos.distance_to(end[1])
				if d < 1.0 and d < bd: bd = d; best = {"k": "rope", "o": r, "end": end[0]}
	if pb > 0:
		var b := world.bld(pb)
		if b.stairs.x >= 0:
			var d := p.wpos.distance_to(Vector2(b.stairs) + Vector2(0.5, 0.5))
			if d < 0.9 and d < bd: bd = d; best = {"k": "stairs", "o": b}
	for c in world.crates:
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
			s.set_meta("recruited", true)
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
					spr.offset = Vector2(-7, -8)
				var wd := randi_range(2, 4)
				p.carry.wood += wd
				add_text(tp, "+%d wood" % wd, Color("d8b880"))
		"crate":
			_loot(t.o)

func _loot(c: World.Crate) -> void:
	var p := player
	c.open = true
	if crate_nodes.has(c):
		crate_nodes[c].texture = Assets.tex(("cache" if c.kind == "cache" else "crate") + "_open") if c.kind != "bag" else null
	var q := 0.55 if p.crouch else 1.0
	noise(c.pos, (5.0 if c.kind == "car" else 4.5) * q, (35.0 if c.kind == "car" else 28.0) * q)
	var s := 0; var cl := 0; var a := 0; var wd := 0
	match c.kind:
		"car": s = randi_range(1, 3); a = randi_range(0, 3)
		"bag": s = randi_range(1, 2); a = randi_range(2, 5)
		"cache":
			s = randi_range(3, 6); cl = randi_range(1, 3); a = randi_range(4, 8); wd = randi_range(0, 3)
			if randf() < 0.35: p.hp = p.max_hp; add_text(c.pos + Vector2(0, -0.4), "medkit! healed", Color("ff8a8a"))
		_:
			s = randi_range(1, 4); cl = randi_range(0, 2); a = randi_range(1, 4)
			if randf() < 0.12: p.hp = p.max_hp; add_text(c.pos + Vector2(0, -0.4), "medkit! healed", Color("ff8a8a"))
	if any_up("bench"): a += 2
	p.carry.scrap += s; p.carry.cloth += cl; p.carry.wood += wd; p.ammo += a
	var parts := []
	if s: parts.append("+%d scrap" % s)
	if cl: parts.append("+%d cloth" % cl)
	if wd: parts.append("+%d wood" % wd)
	if a: parts.append("+%d ammo" % a)
	add_text(c.pos, " ".join(parts) if parts.size() else "empty")

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
	for e in enemies:
		if e.dead or e.fl != p.fl:
			continue
		var to: Vector2 = e.wpos - p.wpos
		var d := to.length()
		if d < 1.3 and to.normalized().dot(wa) > 0.1:
			if p.crouch and e.aw < 35.0:
				add_text(e.wpos, "silent takedown", Color("9fd08a"))
				kill_enemy(e, true)
			else:
				loud = true
				e.damage(1, p.wpos)
	if loud or not p.crouch:
		noise(p.wpos, 2.5, 12.0)

func shoot() -> void:
	var p := player
	if p.cd > 0.0 or not p.climb.is_empty():
		return
	if p.ammo <= 0:
		melee()
		return
	p.ammo -= 1
	p.cd = 0.17 if any_up("bench") else 0.3
	var wa := p.world_aim()
	bullets.append({"pos": p.wpos + wa * 0.4, "vel": wa * 15.0, "z": p.ground_z() + 10.0, "fl": p.fl, "life": 1.0, "enemy": false})
	burst(p.wpos + wa * 0.5, 3, [Color("f2d06b"), Color("f28c28")], 9.0, p.fl)
	noise(p.wpos, 10.0, 70.0)

func enemy_shoot(e: Enemy, at: Vector2) -> void:
	var a := (at - e.wpos).angle() + randf_range(-0.13, 0.13)
	var dir := Vector2.from_angle(a)
	bullets.append({"pos": e.wpos + dir * 0.4, "vel": dir * 8.0, "z": e.ground_z() + 10.0, "fl": e.fl, "life": 1.4, "enemy": true, "src": e.wpos})
	burst(e.wpos, 2, [Color("f2d06b")], 9.0, e.fl)
	for o in enemies:
		if o.type == "raider" and not o.dead and o.wpos.distance_to(e.wpos) < 8.0:
			o.aw = maxf(o.aw, 80.0)
			o.last = player.wpos

func hurt_player(from: Vector2) -> void:
	var p := player
	if p.inv > 0.0 or state != "play":
		return
	p.hp -= 1
	p.inv = 0.9
	p.flash = 0.3
	var d := p.wpos - from
	if d.length() > 0.01:
		p.move(d.normalized() * 0.4)
	if p.hp <= 0:
		state = "down"
		down_t = 2.8
		p.climb = {}

func kill_enemy(e: Enemy, silent: bool) -> void:
	if e.dead:
		return
	e.dead = true
	player.kills += 1
	var cols := [Color("8a3a3a"), Color("b07a6a"), Color("3a2a2a")] if e.type == "hound" else [Color("a83a2a"), Color("5a3a2a"), Color("3a2a2a")]
	burst(e.wpos, 10, cols, 9.0, e.fl)
	if e.type == "raider":
		var c := World.Crate.new()
		c.pos = e.wpos
		c.kind = "bag"
		c.bid = e.building()
		c.fl = e.fl
		world.crates.append(c)
		var s := _sprite("bag", c.pos, world.stand_z(c.pos.x, c.pos.y, c.fl), Vector2(-4, -8), 0.1)
		crate_nodes[c] = s
		if e.camp >= 0:
			var left := false
			for o in enemies:
				if not o.dead and o.camp == e.camp: left = true
			if not left:
				world.rcamps[e.camp].cleared = true
				hud.toast("Raider camp cleared! Its stash is yours.")
	e.visible = false

func respawn() -> void:
	var p := player
	var lost: int = p.carry.scrap + p.carry.cloth + p.carry.wood
	p.carry = {"scrap": 0, "cloth": 0, "wood": 0}
	var c: Camp = camps[0]
	var bd := 1e9
	for o in camps:
		var d: float = o.wpos.distance_to(p.wpos)
		if d < bd: bd = d; c = o
	p.wpos = c.wpos + Vector2(0, 1.4)
	p.fl = 0
	p.hp = p.max_hp
	p.inv = 2.0
	dog.wpos = p.wpos + Vector2(-1, 0)
	for e in enemies:
		if e.wpos.distance_to(c.wpos) < 12.0:
			e.aw = 0.0
			if e.camp < 0: kill_enemy(e, true)
	state = "play"
	hud.toast(("You came to at %s. Dropped %d items you were carrying." % [c.cname, lost]) if lost else "You came to at %s." % c.cname)

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
	if world.hz(p.wpos.x, p.wpos.y) > 26.0: n = "Hilltop Camp"
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

func open_camp_menu() -> void:
	if state != "play": return
	var c = camp_near(player.wpos, 3.2)
	var line := "Shared stash: %d scrap · %d cloth · %d wood" % [stash.scrap, stash.cloth, stash.wood]
	var btns := []
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

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if state == "title" or world == null:
		return
	time += delta
	if state == "travel":
		travel.t += delta / 1.4
		if travel.t >= 0.5 and not travel.done:
			travel.done = true
			var c: Camp = travel.to
			player.wpos = c.wpos + Vector2(0, 1.4)
			player.fl = 0
			player.climb = {}
			dog.wpos = player.wpos + Vector2(-1, 0)
			for e in enemies: e.aw = 0.0
		if travel.t >= 1.0:
			state = "play"
			hud.toast("Arrived at %s. A few hours pass." % travel.to.cname)
		fx.fade = 1.0 - absf(travel.t * 2.0 - 1.0)
		fx.fade_text = "Traveling to %s…" % travel.to.cname
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
	if hud.menu_open():
		_update_camera()
		return
	var p := player
	p.step(delta, _read_move(), _read_aim())
	if _wants_fire():
		shoot()
	dog.step(delta, p)
	var here = camp_near(p.wpos, 3.2)
	if here != null:
		if p.carry.scrap + p.carry.cloth + p.carry.wood > 0:
			for k in RES: stash[k] += p.carry[k]
			hud.toast("Stashed %d scrap, %d cloth, %d wood. Press %s to build." % [p.carry.scrap, p.carry.cloth, p.carry.wood, "CAMP" if using_touch else "B"])
			p.carry = {"scrap": 0, "cloth": 0, "wood": 0}
		p.regen += delta
		if p.regen > (1.0 if here.up.garden else 3.5) and p.hp < p.max_hp:
			p.regen = 0.0
			p.hp += 1
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
			if not e.dead and e.fl == 0 and d < td: td = d; tgt = e
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
	spawn_t += delta
	if spawn_t > 25.0:
		spawn_t = 0.0
		var hounds := 0
		for e in enemies:
			if e.type == "hound": hounds += 1
		if hounds < 9:
			var cps := []
			for c in camps: cps.append(c.wpos)
			var before := world.spawns.size()
			world.add_pack(2, p.wpos, 18.0, cps)
			for i in range(before, world.spawns.size()): _spawn_enemy(world.spawns[i])
	patrol_t += delta
	if patrol_t > 70.0:
		patrol_t = 0.0
		var has := false
		for e in enemies:
			if e.patrol.size() > 0: has = true
		if not has:
			var before := world.spawns.size()
			world.add_patrol()
			for i in range(before, world.spawns.size()): _spawn_enemy(world.spawns[i])
	_update_bullets(delta)
	_update_visibility()
	_update_camera()
	_update_hud()

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
					hurt_player(b.src)
					b.life = 0.0
			else:
				for e in enemies:
					if not e.dead and e.fl == b.fl and b.pos.distance_to(e.wpos) < 0.42:
						e.damage(1, player.wpos)
						b.life = 0.0
						break
		b.life -= delta
	bullets = bullets.filter(func(b): return b.life > 0.0)
	for q in particles:
		q.pos += q.vel * delta
		q.z += q.vz * delta
		q.vz -= 90.0 * delta
		if q.z < 0.0:
			q.z = 0.0; q.vel *= 0.5; q.vz = 0.0
		q.life -= delta
	particles = particles.filter(func(q): return q.life > 0.0)

func _update_visibility() -> void:
	var p := player
	var pb := p.building()
	if pb != _last_pb or p.fl != _last_pfl:
		_last_pb = pb
		_last_pfl = p.fl
		for v in views:
			v.update_view(pb, p.fl)
	var vis := func(x: float, y: float, fl: int) -> bool:
		var b := world.building_at(x, y)
		return (b == 0 and fl == 0) or (b == pb and fl == p.fl)
	for e in enemies:
		e.visible = not e.dead and vis.call(e.wpos.x, e.wpos.y, e.fl)
	for c in crate_nodes:
		var s: Sprite2D = crate_nodes[c]
		s.visible = vis.call(c.pos.x, c.pos.y, c.fl) and s.texture != null
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
		s.body.frame = 0
		s.body.flip_h = (main.wpos.x - s.wpos.x) < 0 if s.get_meta("recruited") else (p.wpos.x - p.wpos.y) < (s.wpos.x - s.wpos.y)
		s.sync()
	dog.visible = dog.fl == p.fl or pb == 0

func _update_camera() -> void:
	cam.position = (player.position + Vector2(0, -12)).round()
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

func _update_hud() -> void:
	var p := player
	var hearts := "♥".repeat(maxi(0, p.hp)) + "♡".repeat(maxi(0, p.max_hp - p.hp))
	var nrec := 0
	for s in survivors:
		if s.get_meta("recruited"): nrec += 1
	hud.stats.text = "HP %s   AMMO %d%s\nCarrying: %d scrap, %d cloth, %d wood\nShared stash: %d scrap, %d cloth, %d wood\nCamps: %d   Survivors: %d   Kills: %d   %s" % [
		hearts, p.ammo, "   [SNEAKING]" if p.crouch else "", p.carry.scrap, p.carry.cloth, p.carry.wood,
		stash.scrap, stash.cloth, stash.wood, camps.size(), 1 + nrec, p.kills, "Floor 2" if p.fl == 1 else ""]
	var t := find_target()
	var k := "USE" if using_touch else "[E]"
	var msg := ""
	if not t.is_empty() and p.climb.is_empty():
		match t.k:
			"rope": msg = "%s Climb %s the rope" % [k, "up" if t.end == "bottom" else "down"]
			"tree": msg = "%s Chop tree (%d/3)" % [k, chop_hits.get(world.idx(t.x, t.y), 0)]
			"survivor": msg = "%s Recruit %s" % [k, t.o.get_meta("name")]
			"stairs": msg = "%s Go %s" % [k, "downstairs" if p.fl == 1 else "upstairs"]
			"crate": msg = "%s Search %s" % [k, {"car": "car trunk", "bag": "raider loot", "cache": "raider stash", "crate": "crate"}[t.o.kind]]
			"camp": msg = "%s Camp menu" % ("CAMP" if using_touch else "[B]")
	hud.set_prompt(msg)
	hud.touch.queue_redraw()
	if p.flash > 0.0:
		fx.flash = p.flash
	else:
		fx.flash = 0.0

# ------------------------------------------------------------------ debug (used for automated screenshots)
func _debug_shots() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	_snap(out + "/1_start.png")
	var rc: World.RaiderCamp = world.rcamps[0]
	player.wpos = rc.pos + Vector2.from_angle(rc.ang) * 6.5
	await get_tree().create_timer(0.6).timeout
	_snap(out + "/2_ramp.png")
	var r: World.Rope = world.ropes[0]
	player.wpos = r.bottom
	interact()
	await get_tree().create_timer(1.6).timeout
	_snap(out + "/3_rope_top.png")
	for b in world.buildings:
		if b.floors == 2 and not b.raider:
			for e in enemies: e.aw = 0.0
			player.wpos = Vector2(b.stairs) + Vector2(0.5, 0.5)
			player.fl = 0
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/4_inside_ground.png")
			interact()
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/5_upstairs.png")
			player.fl = 0
			player.wpos = Vector2(b.out) + Vector2(0.5, 1.8)
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/6_outside_building.png")
			break
	player.wpos = Vector2(40, 40)
	await get_tree().create_timer(0.6).timeout
	_snap(out + "/7_city.png")
	print("SHOTS DONE ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _debug_soak() -> void:
	# Plays itself for a while to shake out runtime errors: wanders, fights, loots, builds a camp, travels.
	await get_tree().create_timer(0.5).timeout
	stash = {"scrap": 40, "cloth": 20, "wood": 40}
	var steps := 0
	for e in enemies:
		if e.type == "raider" and e.camp >= 0:
			player.wpos = e.wpos + Vector2(3, 0)
			break
	for i in 400:
		await get_tree().process_frame
		player.aim = Vector2(cos(i * 0.05), sin(i * 0.05))
		if i % 20 == 0: shoot()
		if i % 45 == 0: melee()
		if i % 30 == 0: interact()
	player.wpos = world.start + Vector2(12, 0)
	for e in enemies:
		e.aw = 0.0
		e.st = 0
	print("camp problem: ", camp_problem())
	new_camp()
	hud.hide_menu()
	await get_tree().create_timer(0.3).timeout
	_build(camps[0], UPG[3])
	hud.hide_menu()
	_start_travel(camps[0])
	await get_tree().create_timer(2.0).timeout
	for i in 300:
		await get_tree().process_frame
		player.step(get_process_delta_time(), Vector2(cos(i * 0.02), sin(i * 0.03)), Vector2.ZERO)
		if i % 50 == 0: player.start_jump()
	print("SOAK DONE state=%s hp=%d kills=%d camps=%d enemies=%d" % [state, player.hp, player.kills, camps.size(), enemies.size()])
	get_tree().quit()
