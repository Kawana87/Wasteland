class_name Game
extends Node
## Main controller: builds the scene, owns the world, runs the game loop, handles input,
## camps / fast travel, loot, combat and the HUD.

static var I: Game

const SHRINK := 2                 # game pixels -> screen: the world renders at 1/2 of the UI size
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
var _last_pb := -99999
var _last_pfl := -1
var npcs: Array = []
var furn_nodes := {}             # Furn -> Sprite2D
var decor_nodes: Array = []      # [Decor, Sprite2D]
var smoke_spots: Array = []      # Vector2 world positions that puff smoke
var faded_trees := {}
var inventory: Array = []        # [{id, n}]
var equip := {"gun": "pipe_pistol", "melee": "fists", "head": "", "body": ""}
var day_t := 0.3                 # 0..1 time of day (0.25 = morning)
var grade: ShaderMaterial
var lights: LightLayer
var noise_level := 0.0
var in_settlement := -1
var dust: Array = []
var rng := RandomNumberGenerator.new()

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
	hud.touch.action.connect(_on_touch_action)
	_load_settings()
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args:
		start_new_world.call_deferred()
		if "--shots" in args:
			_debug_shots.call_deferred()
		if "--soak" in args:
			_debug_soak.call_deferred()
		if "--char" in args:
			_debug_char.call_deferred()
		if "--fade" in args:
			_debug_fade.call_deferred()
		if "--tour" in args:
			_debug_tour.call_deferred()
		if "--bestiary" in args:
			_debug_bestiary.call_deferred()
		if "--upstairs" in args:
			_debug_upstairs.call_deferred()
		if "--desks" in args:
			_debug_desks.call_deferred()
		if "--ruins" in args:
			_debug_ruins.call_deferred()
		return
	hud.show_title("A new world is generated every time: rolling hills and cliffs out west, a ruined city to the east.\nRaiders hold plateau camps; feral ghouls haunt the ruins; brutes and shellbacks roam the wilds.\nFriendly settlements trade gear for scrap. Set up camps anywhere and fast travel between them.\n\nPC: WASD move · mouse aim · left click shoot · F / right click melee · Space jump · C sneak\nE use / talk / chop / climb / stairs · I inventory · H heal · B camp menu · T fast travel · V CRT filter\nGamepad: left stick move · right stick aim · RT shoot · A jump · X use · B melee · Y sneak\nTouch: left thumb move · right thumb aim and shoot · buttons on the right", start_new_world)

func _setup_input() -> void:
	var keys := {
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "melee": [KEY_F], "use": [KEY_E], "sneak": [KEY_C], "camp": [KEY_B],
		"travel": [KEY_T], "crt": [KEY_V], "close": [KEY_ESCAPE], "inventory": [KEY_I, KEY_TAB], "heal": [KEY_H],
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

func start_new_world() -> void:
	for c in vp.get_children():
		if c is Node2D:
			c.queue_free()
	enemies.clear(); camps.clear(); survivors.clear(); views.clear(); bullets.clear(); particles.clear()
	crate_nodes.clear(); tree_nodes.clear(); chop_hits.clear(); npcs.clear(); furn_nodes.clear(); decor_nodes.clear()
	smoke_spots.clear(); faded_trees.clear(); dust.clear(); lights.lights.clear()
	inventory = [{"id": "pipe_pistol", "n": 1}, {"id": "ammo_pistol", "n": 18}, {"id": "medkit", "n": 1}, {"id": "food", "n": 2}, {"id": "lockpick", "n": 3}]
	equip = {"gun": "pipe_pistol", "melee": "fists", "head": "", "body": ""}
	day_t = 0.3
	busy = {}
	rng.randomize()
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
		for rp in b.roof_props:
			_light_for(rp.tex, rp.pos, b.h0 + b.floors_at(rp.cell) * World.FLOOR_H)
		var v := BuildingView.new()
		v.setup(world, b)
		root.add_child(v)
		views.append(v)
	_spawn_props()
	var c := Camp.new()
	root.add_child(c)
	c.setup(world.start, "Home Camp", true)
	_light_for("campfire_decor", world.start, world.hz(world.start.x, world.start.y))
	camps.append(c)
	player = Player.new()
	root.add_child(player)
	player.wpos = world.start + Vector2(0, 1.5)
	dog = Dog.new()
	root.add_child(dog)
	dog.wpos = player.wpos + Vector2(-1, 0)
	for s in world.spawns:
		_spawn_enemy(s)
	for d in world.critters:
		_spawn_npc(d)
	var wps := [world.road_point(), world.road_point(), world.road_point(), world.road_point()]
	_spawn_npc({"type": "wanderer", "pos": wps[0], "patrol": wps})
	for s in world.survivors:
		var a := Actor.new()
		root.add_child(a)
		if not a.use_rendered("survivor", 8): a.make_body("survivor", 6, 16, 24)
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
	_last_pb = -99999
	state = "play"
	hud.toast("Hills to the west, a ruined city to the east. Find a settlement to trade — and press I for your inventory.")

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
	enemies.append(e)
	return e

func _sprite(tex: String, at: Vector2, z: float, off: Vector2, depth_bias: float = 0.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.offset = Assets.off(tex)
	s.position = Iso.to_screen(at.x, at.y, z).round()
	s.z_index = Iso.z_for(at.x + at.y + depth_bias, 3)
	root.add_child(s)
	return s

const LIGHTS := {   # decor name -> [height (logical px), screen x offset, colour, radius, flicker]
	"lamp": [58.0, 14.0, Color(1.0, 0.85, 0.55), 46.0, false],
	"campfire_decor": [6.0, 0.0, Color(1.0, 0.55, 0.2), 54.0, true],
	"sign_motel": [70.0, 18.0, Color(0.35, 0.95, 0.9), 60.0, false],
	"sign_gas": [78.0, 0.0, Color(0.4, 0.85, 0.8), 56.0, false],
	"sign_diner": [26.0, 0.0, Color(1.0, 0.45, 0.4), 62.0, false],
	"vending_x": [16.0, 0.0, Color(1.0, 0.4, 0.3), 20.0, false],
	"vending_y": [16.0, 0.0, Color(1.0, 0.4, 0.3), 20.0, false],
	"pillar": [26.0, 0.0, Color(0.95, 0.95, 0.85), 30.0, false],
	"phonebooth": [20.0, 0.0, Color(0.9, 0.95, 1.0), 18.0, false],
}

func _light_for(nm: String, p: Vector2, z: float) -> void:
	if LIGHTS.has(nm):
		var L: Array = LIGHTS[nm]
		lights.add(Iso.to_screen(p.x, p.y, z + L[0]) + Vector2(L[1], 0), L[2], L[3], L[4])

const TREES_LEAFY := ["tree0", "tree1", "tree2", "tree5", "tree7"]
const TREES_PINE := ["tree3", "tree4", "tree3"]
const TREES_DRY := ["tree6", "tree5", "tree_dead2"]
const TREES_DEAD := ["tree_dead", "tree_dead1", "tree_dead2"]

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

func _spawn_props() -> void:
	var w := world
	for y in World.N:
		for x in World.N:
			if w.T[w.idx(x, y)] == World.TREE:
				var v := w.V[w.idx(x, y)]
				var tex := _tree_tex(x, y, v)
				var p := Vector2(x + 0.5, y + 0.5)
				tree_nodes[w.idx(x, y)] = _sprite(tex, p, w.hz(p.x, p.y), Vector2(-12, -36))
	for c in w.cars:
		_sprite("car_%s_%d" % [c.spr, c.k], c.pos, w.hz(c.pos.x, c.pos.y), Vector2(-40, -34))
	for b in w.buildings:
		for f in b.furn:
			var s := _sprite("furn_%s_%s" % [f.name, f.orient], f.pos, w.stand_z(f.pos.x, f.pos.y, f.fl), Vector2(-24, -40))
			s.z_index = Iso.z_for(f.pos.x + f.pos.y, 3 + f.fl * 2)
			furn_nodes[f] = s
	for d in w.decor:
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
				s.z_index = -3000
			_:
				s = _sprite(d.name, d.pos, z, Vector2.ZERO)
				if d.flat:
					s.z_index = -3000 if d.name.begins_with("tuft") or d.name == "puddle_toxic" else Iso.z_for(d.pos.x + d.pos.y - 0.6, 0)
		decor_nodes.append([d, s])
		_light_for(d.name, d.pos, z)
	for line in w.pole_lines:
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
				root.add_child(l)
	for cr in w.crates:
		if cr.kind != "crate" and cr.kind != "cache":
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
	player.max_hp = 20 + (4 if any_up("tent") else 0)
	player.hp = minf(player.hp, player.max_hp)

# ------------------------------------------------------------------ inventory
func inv_count(id: String) -> int:
	for it in inventory:
		if it.id == id: return it.n
	return 0

func inv_add(id: String, n: int = 1) -> void:
	if id == "": return
	for it in inventory:
		if it.id == id:
			it.n += n
			return
	inventory.append({"id": id, "n": n})

func inv_take(id: String, n: int = 1) -> bool:
	for it in inventory:
		if it.id == id and it.n >= n:
			it.n -= n
			if it.n <= 0: inventory.erase(it)
			return true
	return false

func armor_total() -> int:
	var a := 0
	for slot in ["head", "body"]:
		if equip[slot] != "": a += Items.info(equip[slot]).get("armor", 0)
	return a

func gun_info() -> Dictionary:
	return Items.info(equip.gun) if equip.gun != "" else {}

func equip_item(id: String) -> void:
	var slot: String = Items.info(id).slot
	if slot in ["gun", "melee", "head", "body"]:
		equip[slot] = id
		hud.toast("Equipped %s." % Items.iname(id))
		_refresh_gun()
	open_inventory()

func use_item(id: String) -> void:
	var d := Items.info(id)
	if d.get("heal", 0) > 0 and player.hp < player.max_hp and inv_take(id):
		player.hp = minf(player.max_hp, player.hp + d.heal)
		add_text(player.wpos, "+%d hp" % d.heal, Color("9fd08a"))
	if hud.menu_open(): open_inventory()

func quick_heal() -> void:
	if player.hp >= player.max_hp: return
	if inv_count("medkit") > 0 and player.max_hp - player.hp >= 8: use_item("medkit")
	elif inv_count("food") > 0: use_item("food")
	elif inv_count("medkit") > 0: use_item("medkit")
	else: hud.toast("Nothing to heal with. Look for food and med kits.")

func _refresh_gun() -> void:
	var g := gun_info()
	player.gun_len = g.get("len", 6) if not g.is_empty() else 0

func open_inventory() -> void:
	if state != "play": return
	var lines := ["HP %d/%d   ·   Armour %d (%d%% less damage)" % [int(player.hp), int(player.max_hp), armor_total(), int(_reduction() * 100)],
		"Gun: %s   ·   Melee: %s   ·   Head: %s   ·   Body: %s" % [Items.iname(equip.gun) if equip.gun != "" else "none", Items.iname(equip.melee), Items.iname(equip.head) if equip.head != "" else "none", Items.iname(equip.body) if equip.body != "" else "none"],
		"Carrying: %d scrap · %d cloth · %d wood" % [player.carry.scrap, player.carry.cloth, player.carry.wood]]
	var ammo_line := []
	var btns := []
	for it in inventory:
		var d := Items.info(it.id)
		var nm: String = d.get("name", it.id)
		match d.get("slot", ""):
			"ammo": ammo_line.append("%s ×%d" % [nm, it.n])
			"use":
				var iid: String = it.id
				btns.append(["Use %s ×%d  (+%d hp)" % [nm, it.n, d.heal], func(): use_item(iid), player.hp >= player.max_hp])
			"gun", "melee", "head", "body":
				var iid: String = it.id
				var on: bool = equip[d.slot] == iid
				var stat := ("dmg %d · %s" % [d.dmg * d.get("pellets", 1), Items.iname(d.ammo)]) if d.slot == "gun" else (("dmg %d" % d.dmg) if d.slot == "melee" else ("armour %d" % d.armor))
				btns.append([("✓ " if on else "Equip ") + "%s  (%s)" % [nm, stat], func(): equip_item(iid), on])
	if ammo_line.size(): lines.append("Ammo: " + "  ·  ".join(ammo_line))
	if equip.melee != "fists":
		btns.append(["Put away melee weapon (fists)", func(): equip_item("fists"), false])
	btns.append(["Close", hud.hide_menu, false])
	hud.show_menu("Inventory", lines, btns)

func _reduction() -> float:
	return minf(0.6, armor_total() * 0.07)

# ------------------------------------------------------------------ trading
const SHOP := [["ammo_pistol", 10, 3], ["ammo_shell", 6, 4], ["ammo_rifle", 5, 5], ["medkit", 1, 6], ["food", 2, 2]]

func _buy(npc: Npc, id: String, n: int, cost: int) -> void:
	if _pay(cost): inv_add(id, n)
	open_trade(npc)

func _buy_stock(npc: Npc, i: int, cost: int) -> void:
	var stock: Array = npc.get_meta("stock")
	if _pay(cost):
		inv_add(stock[i])
		stock[i] = ""
	open_trade(npc)

func _sell(npc: Npc, id: String, val: int) -> void:
	if inv_take(id): player.carry.scrap += val
	open_trade(npc)

func _scrap_total() -> int:
	return player.carry.scrap + stash.scrap

func _pay(n: int) -> bool:
	if _scrap_total() < n: return false
	var from_carry := mini(n, player.carry.scrap)
	player.carry.scrap -= from_carry
	stash.scrap -= n - from_carry
	return true

func open_trade(npc: Npc) -> void:
	if not npc.has_meta("stock"):
		var stock := []
		for t in 3:
			stock.append(Items.gear_of_tier(rng.randi_range(1, 3), rng))
		npc.set_meta("stock", stock)
	var stock: Array = npc.get_meta("stock")
	var lines := ["You have %d scrap (carried %d + stash %d)." % [_scrap_total(), player.carry.scrap, stash.scrap], "Buy:"]
	var btns := []
	for e in SHOP:
		var id: String = e[0]
		var n: int = e[1]
		var cost: int = e[2]
		btns.append(["Buy %s ×%d — %d scrap" % [Items.iname(id), n, cost], func(): _buy(npc, id, n, cost), _scrap_total() < cost])
	for i in stock.size():
		var id: String = stock[i]
		if id == "": continue
		var cost: int = Items.info(id).value
		var ii := i
		btns.append(["Buy %s — %d scrap" % [Items.iname(id), cost], func(): _buy_stock(npc, ii, cost), _scrap_total() < cost])
	for it in inventory:
		var d := Items.info(it.id)
		if d.get("slot", "") in ["gun", "melee", "head", "body"] and it.id != equip[d.slot]:
			var id: String = it.id
			var val: int = maxi(1, int(d.value / 2))
			btns.append(["Sell %s — +%d scrap" % [d.name, val], func(): _sell(npc, id, val), false])
	btns.append(["Leave", hud.hide_menu, false])
	hud.show_menu("Trader" if npc.type == "trader" else "Travelling merchant", lines, btns)

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
	if state != "play" or hud.menu_open():
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
		return m - (player.position + Vector2(0, -14))
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
	if p.fl == 0:
		for n in npcs:
			if n.type in ["trader", "wanderer", "settler"] and n.visible:
				var d: float = p.wpos.distance_to(n.wpos)
				if d < 1.4 and d < bd: bd = d; best = {"k": "npc", "o": n}
	var dn := door_near(p.wpos, 1.15)
	if dn != null:
		var dd := p.wpos.distance_to((dn.a + dn.b) * 0.5)
		if dd < bd: bd = dd; best = {"k": "door", "o": dn}
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
					spr.offset = Assets.off("stump")
				var wd := randi_range(2, 4)
				p.carry.wood += wd
				add_text(tp, "+%d wood" % wd, Color("d8b880"))
		"crate":
			_loot(t.o)
		"door":
			open_door(t.o)
		"npc":
			var n: Npc = t.o
			if n.type == "settler":
				add_text(n.wpos + Vector2(0, -0.2), Npc.BARKS[randi() % Npc.BARKS.size()], Color("e8e0c8"), 2.6)
			else:
				open_trade(n)

func _loot(c: World.Crate) -> void:
	var p := player
	c.open = true
	if crate_nodes.has(c):
		var spr: Sprite2D = crate_nodes[c]
		if c.kind == "crate" or c.kind == "cache":
			spr.texture = Assets.tex(c.kind + "_open")
		else:
			spr.texture = null
	var q := 0.55 if p.crouch else 1.0
	noise(c.pos, (5.0 if c.kind == "car" else 4.5) * q, (35.0 if c.kind == "car" else 24.0) * q)
	var mats := Items.roll_materials(c.kind, rng)
	var items := Items.roll_loot(c.kind, rng)
	if c.has_meta("extra"): items.append([c.get_meta("extra"), 1])
	if any_up("bench") and rng.randf() < 0.5:
		items.append([gun_info().get("ammo", "ammo_pistol"), 2])
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
	var dmg: float = Items.info(equip.melee).get("dmg", 1)
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
	if not loud:
		var ds := door_near(p.wpos, 1.3, wa)
		if ds != null:
			bash_door(ds, dmg)
			return
	if loud or not p.crouch:
		noise(p.wpos, 2.5, 12.0)

# ------------------------------------------------------------------ doors
var busy := {}   # lockpicking in progress: {door, t, total}

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
	world.set_door(sg, st)
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
	for k in g.pellets:
		var dir := wa.rotated(randf_range(-g.spread, g.spread))
		bullets.append({"pos": p.wpos + wa * 0.4, "vel": dir * g.speed, "z": p.ground_z() + 10.0, "fl": p.fl, "life": g.life, "enemy": false, "dmg": float(g.dmg)})
	burst(p.wpos + wa * 0.5, 3, [Color("f2d06b"), Color("f28c28")], 9.0, p.fl)
	noise(p.wpos, 10.0, 70.0)

func enemy_shoot(e: Enemy, at: Vector2, weapon: String = "pipe_pistol") -> void:
	var g := Items.info(weapon)
	var base := (at - e.wpos).angle()
	for k in g.get("pellets", 1):
		var dir := Vector2.from_angle(base + randf_range(-0.13, 0.13) + randf_range(-g.spread, g.spread) * 0.5)
		bullets.append({"pos": e.wpos + dir * 0.4, "vel": dir * 8.0, "z": e.ground_z() + 10.0, "fl": e.fl, "life": 1.4 if g.pellets == 1 else 0.6, "enemy": true, "src": e.wpos, "dmg": 3.0 if g.pellets == 1 else 2.0})
	burst(e.wpos, 2, [Color("f2d06b")], 9.0, e.fl)
	for o in enemies:
		if o.type == "raider" and not o.dead and o.wpos.distance_to(e.wpos) < 8.0:
			o.aw = maxf(o.aw, 80.0)
			o.last = player.wpos

func throw_rock(e: Enemy, at: Vector2) -> void:
	var dir := (at - e.wpos).normalized()
	bullets.append({"pos": e.wpos + dir * 0.5, "vel": dir * 6.0, "z": e.ground_z() + 18.0, "fl": e.fl, "life": 1.6, "enemy": true, "src": e.wpos, "dmg": 4.0, "rock": true})

func hurt_player(from: Vector2, dmg: float = 3.0) -> void:
	var p := player
	if p.inv > 0.0 or state != "play":
		return
	var taken := maxf(1.0, round(dmg * (1.0 - _reduction())))
	p.hp -= taken
	p.inv = 0.7
	p.flash = 0.3
	var d := p.wpos - from
	if d.length() > 0.01:
		p.move(d.normalized() * (0.9 if dmg >= 6.0 else 0.4))
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
	world.crates.append(c)
	var s := _sprite("bag", c.pos, world.stand_z(c.pos.x, c.pos.y, c.fl), Vector2(-4, -8), 0.1)
	crate_nodes[c] = s
	return c

func kill_enemy(e: Enemy, silent: bool) -> void:
	if e.dead:
		return
	e.dead = true
	player.kills += 1
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
			if e.camp < 0 and e.type != "brute": kill_enemy(e, true)
	state = "play"
	hud.toast(("You came to at %s. Dropped %d materials you were carrying." % [c.cname, lost]) if lost else "You came to at %s." % c.cname)

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
	var mv := _read_move()
	_update_busy(delta, mv.length() > 0.2)
	if not busy.is_empty(): mv = Vector2.ZERO
	p.step(delta, mv, _read_aim())
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
	for n in npcs: n.step(delta, p)
	noise_level = maxf(0.0, noise_level - delta * 30.0)
	_world_life(delta)
	spawn_t += delta
	if spawn_t > 40.0:
		spawn_t = 0.0
		var mutants := 0
		for e in enemies:
			if e.type != "raider": mutants += 1
		if mutants < 10:
			var cps := []
			for c in camps: cps.append(c.wpos)
			var before := world.spawns.size()
			world.add_monster(p.wpos, 20.0, cps)
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

func _world_life(delta: float) -> void:
	var p := player
	# day / night colour grade — a full day takes 8 minutes
	day_t = fmod(day_t + delta / 480.0, 1.0)
	var sun := sin(day_t * TAU)          # 0.25 = noon, 0.75 = midnight
	var dayness := clampf(sun * 1.6 + 0.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(sun) * 3.0, 0.0, 1.0)
	var tint := Vector3(1.0, 0.97, 0.9).lerp(Vector3(0.62, 0.72, 1.0), 1.0 - dayness)
	tint = tint.lerp(Vector3(1.12, 0.86, 0.7), dusk * 0.6)
	if grade:
		grade.set_shader_parameter("tint", tint)
		grade.set_shader_parameter("bright", lerpf(0.58, 1.0, dayness))
		grade.set_shader_parameter("sat", lerpf(0.55, 0.82, dayness))
	lights.strength = clampf((1.0 - dayness) * 1.1, 0.0, 0.9)
	# settlement greeting
	var si := world.settlement_at(p.wpos)
	if si != in_settlement:
		in_settlement = si
		if si >= 0:
			hud.toast("%s — a settlement. Folks here are friendly. Look for the trader." % world.settlements[si].name)
	# campfires flicker and smoke
	var fr := int(time * 6.0) % 2
	for pair in decor_nodes:
		var spr: Sprite2D = pair[1]
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
	for pair in decor_nodes:
		var d: World.Decor = pair[0]
		if d.bid > 0:
			(pair[1] as Sprite2D).visible = (d.bid == pb and p.fl == 0) or (d.bid != pb and world.open_from_outside(d.pos.x, d.pos.y, 0))
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

func _update_hud() -> void:
	var p := player
	var g := gun_info()
	var gun_s := ("%s  %d" % [g.name, inv_count(g.ammo)]) if not g.is_empty() else "unarmed"
	var hh := int(day_t * 24.0 + 6.0) % 24
	var nrec := 0
	for s in survivors:
		if s.get_meta("recruited"): nrec += 1
	hud.stats.text = "HP %d/%d   %s   ARMOUR %d   %02d:00%s\nMedkits %d  Food %d   Carrying: %d scrap, %d cloth, %d wood\nShared stash: %d scrap, %d cloth, %d wood\nCamps: %d   Survivors: %d   Kills: %d   %s" % [
		int(ceil(p.hp)), int(p.max_hp), gun_s, armor_total(), hh, "   [SNEAKING]" if p.crouch else "", inv_count("medkit"), inv_count("food"), p.carry.scrap, p.carry.cloth, p.carry.wood,
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
			"crate": msg = "%s Search %s" % [k, {"car": "car trunk", "bag": "remains", "brute": "remains", "cache": "raider stash", "crate": "crate"}.get(t.o.kind, t.o.kind.replace("_", " "))]
			"npc": msg = "%s %s" % [k, "Talk" if t.o.type == "settler" else "Trade"]
			"door":
				var mk := "MELEE" if using_touch else "[F]"
				match t.o.door:
					"closed": msg = "%s Open door" % k
					"locked": msg = ("%s Pick lock (%d)   %s Bash (loud)" % [k, inv_count("lockpick"), mk]) if inv_count("lockpick") > 0 else "Locked — %s Bash it in (loud)" % mk
					"barred": msg = "Barricaded — %s Bash (loud)" % mk
					"sealed": msg = "Boarded up"
			"camp": msg = "%s Camp menu" % ("CAMP" if using_touch else "[B]")
	if not busy.is_empty():
		msg = "Picking lock… %d%%" % int(100.0 * busy.t / busy.total)
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
	for e in enemies: e.aw = 0.0
	_snap(out + "/1_start.png")
	await get_tree().create_timer(0.3).timeout
	if world.settlements.size() > 0:
		player.wpos = world.settlements[0].pos + Vector2(2.5, 2.5)
		await get_tree().create_timer(0.8).timeout
		_snap(out + "/2_settlement.png")
	var done_in := false
	for b in world.buildings:
		if b.floors == 2 and not b.raider and not done_in:
			done_in = true
			player.fl = 0
			player.wpos = Vector2(b.out) + Vector2(0.5, 2.5)
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/3_outside_2floor.png")
			player.wpos = Vector2(b.stairs) + Vector2(0.5, 0.5)
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/4_inside_ground.png")
			interact()
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/5_upstairs.png")
			player.fl = 0
			player.wpos = Vector2(b.x0 + b.w * 0.5, b.y0 - 1.2)
			await get_tree().create_timer(0.6).timeout
			_snap(out + "/6_behind_building.png")
	for e in enemies:
		if e.type in ["brute", "ghoul"]:
			player.wpos = e.wpos + Vector2(2.5, 2.5)
			player.fl = e.fl
			await get_tree().create_timer(0.5).timeout
			_snap(out + "/7_%s.png" % e.type)
			break
	player.fl = 0
	player.wpos = Vector2(44, 40)
	await get_tree().create_timer(0.6).timeout
	_snap(out + "/8_city.png")
	for kind in ["diner", "canopy", "motel", "factory", "office", "house"]:
		for b in world.buildings:
			if b.kind == kind:
				player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
				player.fl = 0
				for e in enemies: e.aw = 0.0
				await get_tree().create_timer(0.5).timeout
				_snap(out + "/k_%s.png" % kind)
				break
	var seen := {}
	for b in world.buildings:
		var sg: World.Seg = b.door_seg
		if sg == null or seen.has(sg.door) or sg.side in ["n", "w"]: continue
		seen[sg.door] = true
		player.fl = 0
		player.wpos = Vector2(b.out) + Vector2(0.5, 0.5) + Vector2(World.DIRS[b.door_side]) * 1.2
		await get_tree().create_timer(0.4).timeout
		_snap(out + "/door_%s.png" % sg.door)
	inv_add("shotgun"); inv_add("road_helmet"); inv_add("ammo_shell", 8)
	open_inventory()
	await get_tree().create_timer(0.4).timeout
	_snap(out + "/9_inventory.png")
	hud.hide_menu()
	day_t = 0.7
	player.wpos = Vector2(44, 40)
	await get_tree().create_timer(0.6).timeout
	_snap(out + "/10_night_city.png")
	for b in world.buildings:
		if b.kind == "canopy" or b.kind == "diner" or b.kind == "motel":
			player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
			await get_tree().create_timer(0.5).timeout
			_snap(out + "/11_night_%s.png" % b.kind)
			break
	print("SHOTS DONE ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _debug_ruins() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.aw = 0.0
	var n := 0
	for b in world.buildings:
		if not b.ruined or n >= 8: continue
		player.fl = 0
		player.wpos = Vector2(b.x0 + b.w + 1.5, b.y0 + b.h + 1.5)
		for t in 20:
			if world.can_stand(player.wpos, 0.25, 0): break
			player.wpos += Vector2(0.5, 0.3)
		await get_tree().create_timer(0.4).timeout
		await _snap(out + "/r_%d_f%d.png" % [n, b.floors]); n += 1
	get_tree().quit()

func _debug_desks() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.visible = false; e.aw = 0.0
	var n := 0
	for b in world.buildings:
		for f in b.furn:
			if f.name == "chair" and n < 4:
				player.fl = f.fl
				player.wpos = f.pos + Vector2(1.2, 0.6)
				await get_tree().create_timer(0.4).timeout
				await _snap(out + "/d_%d.png" % n); n += 1
	get_tree().quit()

func _debug_upstairs() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.visible = false; e.aw = 0.0
	var n := 0
	for b in world.buildings:
		if b.floors < 2 or n >= 10: continue
		for c in b.cells:
			if b.cells[c] >= 2 and not b.holes.has(c):
				player.fl = 1
				player.wpos = Vector2(c) + Vector2(0.5, 0.5)
				await get_tree().create_timer(0.4).timeout
				print("UP shot %d: b%d %s ruined=%s parts=%s" % [n, b.id, b.kind, str(b.ruined), str(b.parts)])
				await _snap(out + "/u_%02d_%s.png" % [n, b.kind]); n += 1
				break
	get_tree().quit()

func _debug_bestiary() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	player.hp = 9999.0; player.max_hp = 9999.0
	var done := {}
	for e in enemies:
		if done.has(e.type): continue
		done[e.type] = true
		for o in enemies: o.aw = 0.0; o.st = 0
		player.fl = e.fl
		player.wpos = e.wpos + Vector2(1.6, 1.6)
		e.st = 2; e.aw = 1.0
		await get_tree().create_timer(0.6).timeout
		await _snap(out + "/b_%s.png" % e.type)
	get_tree().quit()

func _debug_tour() -> void:
	# Visual QA: a grid of camera stops over the whole map plus every building interior kind.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.aw = 0.0
	var n := 0
	for gy in range(6, World.N, 13):
		for gx in range(6, World.N, 13):
			var p := Vector2(gx, gy)
			var ok := false
			for t in 30:
				if world.can_stand(p, 0.25, 0) and world.building_at(p.x, p.y) == 0: ok = true; break
				p += Vector2(randf_range(-2, 2), randf_range(-2, 2)); p = p.clamp(Vector2(1, 1), Vector2(World.N - 2, World.N - 2))
			player.fl = 0
			player.wpos = p
			for e in enemies: e.aw = 0.0; e.st = 0
			await get_tree().create_timer(0.35).timeout
			for v in views:
				if v._faded: print("FADED shot %d: b%d %s parts=%s player=%s" % [n, v.b.id, v.b.kind, str(v.b.parts), str(player.wpos)])
			await _snap(out + "/t_%02d.png" % n); n += 1
	var seen := {}
	for b in world.buildings:
		if seen.has(b.kind) or b.raider: continue
		seen[b.kind] = true
		player.fl = 0
		player.wpos = Vector2(b.x0 + b.w * 0.5, b.y0 + b.h * 0.5)
		await get_tree().create_timer(0.35).timeout
		await _snap(out + "/i_%s.png" % b.kind)
	get_tree().quit()

func _debug_fade() -> void:
	# See-through check around one house: front, beside, behind, inside.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.visible = false; e.aw = 0.0
	var bld: World.Bld = null
	for b in world.buildings:
		if b.floors == 1 and b.w >= 4 and b.h >= 4 and not b.raider and b.door_seg != null:
			bld = b; break
	if bld == null: bld = world.buildings[0]
	var spots := {"front": Vector2(bld.x0 + bld.w + 1.2, bld.y0 + bld.h + 1.2),
		"beside": Vector2(bld.x0 + bld.w + 1.0, bld.y0 - 0.8),
		"behind": Vector2(bld.x0 + bld.w * 0.5, bld.y0 - 0.9),
		"behind_corner": Vector2(bld.x0 - 0.8, bld.y0 + bld.h * 0.5),
		"inside": Vector2(bld.x0 + bld.w * 0.5, bld.y0 + bld.h * 0.5)}
	for k in spots:
		player.fl = 0
		player.wpos = spots[k]
		await get_tree().create_timer(0.5).timeout
		var pscr := player.position + Vector2(0, -18)
		for v in views:
			if v.screen_rect().has_point(pscr):
				print("FADEDBG %s pb=%d pz=%.1f p=%s | b%d %s h0=%.1f roof=%s parts=%s front=%.1f occ=%s faded=%s" % [k, player.building(), player.ground_z(), str(player.wpos), v.b.id, v.b.kind, v.b.h0, v.b.roof, str(v.b.parts), v.front_depth, str(v.occludes(player.wpos, [6.0, 20.0], player.ground_z())), str(v._faded)])
		await _snap(out + "/fade_%s.png" % k)
	get_tree().quit()

func _debug_char() -> void:
	# Player sprite check: every facing, idle / walk / crouch, snapped in the live scene.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.visible = false; e.aw = 0.0
	set_process(false)
	player.set_process(false)
	player.set_physics_process(false)
	for mode in ["idle", "walk", "crouch"]:
		for k in 8:
			player.aim = Vector2.from_angle(k * PI / 4.0)
			player.crouch = mode == "crouch"
			player.moving = mode == "walk"
			player.walk_i = k % 4
			player._visual()
			_update_camera()
			await get_tree().process_frame
			await _snap(out + "/char_%s_%d.png" % [mode, k])
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
	var tr: Npc = null
	for n in npcs:
		if n.type == "trader": tr = n
	if tr:
		open_trade(tr); hud.hide_menu()
	open_inventory(); hud.hide_menu()
	inv_add("shotgun"); inv_add("ammo_shell", 10); inv_add("combat_vest"); equip_item("shotgun"); equip_item("combat_vest")
	for i in 30:
		await get_tree().process_frame
		if i % 8 == 0: shoot()
	quick_heal()
	day_t = 0.7
	await get_tree().create_timer(0.3).timeout
	# doors: pick a lock, bash a barricade
	var picked := 0
	var bashed := 0
	var sealed_n := 0
	for b in world.buildings:
		if b.sealed: sealed_n += 1
		var sg: World.Seg = b.door_seg
		if sg == null: continue
		if sg.door == "locked" and picked == 0:
			player.wpos = Vector2(b.out) + Vector2(0.5, 0.5)
			for a in ["left", "right", "up", "down"]: Input.action_release(a)
			player.inv = 0.0
			hud.hide_menu()
			open_door(sg)
			for i in 200:
				await get_tree().process_frame
				if busy.is_empty(): break
			picked = 1 if sg.door == "open" else -1
		if sg.door == "barred" and bashed == 0:
			player.wpos = Vector2(b.out) + Vector2(0.5, 0.5)
			for i in 30:
				bash_door(sg, 2.0)
				if sg.door == "broken": break
			bashed = 1 if sg.door == "broken" else -1
	print("DOORS picked=%d bashed=%d sealed=%d lockpicks=%d" % [picked, bashed, sealed_n, inv_count("lockpick")])
	print("SOAK DONE state=%s hp=%d kills=%d camps=%d enemies=%d" % [state, player.hp, player.kills, camps.size(), enemies.size()])
	get_tree().quit()
