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
var base: BaseBuild
var terrain: TerrainMesh
var wmap: WorldMap
var invs: InventoryScreen
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
var decor_nodes := {}             # Decor -> Sprite2D
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
		var oid := "drifter"
		for a in args:
			if a.begins_with("--origin="): oid = a.substr(9)
		if "--continue" in args: load_game.call_deferred()
		else: start_new_world.call_deferred({}, oid)
		if "--under" in args:
			_debug_under.call_deferred()
		if "--imm" in args:
			_debug_immersion.call_deferred()
		if "--play" in args:
			_debug_play.call_deferred()
		if "--econ" in args:
			_debug_econ.call_deferred()
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
		if "--walk" in args:
			_debug_walk.call_deferred()
		if "--bestiary" in args:
			_debug_bestiary.call_deferred()
		if "--upstairs" in args:
			_debug_upstairs.call_deferred()
		if "--desks" in args:
			_debug_desks.call_deferred()
		if "--ruins" in args:
			_debug_ruins.call_deferred()
		if "--inv" in args:
			_debug_inv.call_deferred()
		if "--map" in args:
			_debug_map.call_deferred()
		if "--build" in args:
			_debug_build.call_deferred()
		return
	hud.show_title("The Sable Wastes: one great wasteland, ten minutes edge to edge on foot — lakes, fens, salt flats, red canyons,\na glass crater and the ruins of Port Sterling. Fifty places on the map, and plenty more nobody wrote down.\nTowns trade gear, and each pays well for goods from far away: buy cheap, haul it across the wastes, sell high.\nSet up camps anywhere, build bases, claim raider dens, and fast travel to anywhere you've found.\n\nAiming is automatic: you lock on to the nearest enemy in range (orange brackets). Just fire.\nPC: WASD move · left click / Q fire · F melee · C sneak · E use · I inventory · M map · B camp · H heal · V CRT\nGamepad: left stick move · RT fire · B melee · X use · Y sneak\nTouch: left thumb moves · FIRE (hold) · HIT · USE · SNEAK · INV · MAP · CAMP", choose_origin, load_game if FileAccess.file_exists(SAVE_PATH) else Callable())

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

# ------------------------------------------------------------------ origins
## Where you start and who you were. Each has an upside and a catch.
const ORIGINS := [
	{"id": "drifter", "name": "Road-worn Drifter", "loc": "patchwork",
		"pro": "Starts at Patchwork, the friendliest town in the Wastes, with extra med kits and food.",
		"con": "Nothing special about you. Yet.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 18], ["medkit", 2], ["food", 3], ["lockpick", 3]]},
	{"id": "water_runner", "name": "Clearwater Water-runner", "loc": "clearwater",
		"pro": "Starts by Lake Winona with 6 water and 20 scrap. Trade goods sell for 15% more.",
		"con": "Grew up soft by the lake: 16 max health.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 14], ["medkit", 1], ["water", 6], ["lockpick", 2]], "scrap": 20, "sell": 1.15, "hp": 16},
	{"id": "ex_con", "name": "Iron Gate Ex-con", "loc": "iron_gate_pen",
		"pro": "Melee hits 50% harder. Starts with a machete and 6 lockpicks.",
		"con": "Traders don't trust you: everything costs 20% more. Only 6 rounds.",
		"kit": [["machete", 1], ["pipe_pistol", 1], ["ammo_pistol", 6], ["food", 2], ["lockpick", 6]], "melee": 1.5, "buy": 1.2, "equip": {"melee": "machete"}},
	{"id": "scavenger", "name": "Redwall Scavenger", "loc": "redwall",
		"pro": "Finds an extra scrap in every container and can haul 15 more trade goods.",
		"con": "No gun to start with, just a lead pipe — out in the red canyons of the south-west.",
		"kit": [["pipe", 1], ["medkit", 1], ["food", 2], ["copper", 3], ["lockpick", 4]], "scav": true, "cap": 15, "equip": {"melee": "pipe", "gun": ""}},
	{"id": "farmhand", "name": "Greenmarsh Farmhand", "loc": "greenmarsh",
		"pro": "Food, water and produce heal twice as much. Starts with 8 produce and a jacket.",
		"con": "Far down in the southern fens, a long walk from anywhere. Only 8 rounds.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 8], ["produce", 8], ["jacket", 1]], "food": 2.0, "equip": {"body": "jacket"}},
	{"id": "raider", "name": "Port Sterling Raider", "loc": "sterling_downtown",
		"pro": "Best gear of any start (10mm pistol, raider plates, spiked bat). Raiders leave you alone unless you start trouble, and the fence at your hideout pays 25% more for gear and stocks better guns.",
		"con": "Town traders charge 35% more and pay 20% less; small camps and scavengers won't deal with you, and survivors won't join a raider. You start downtown among the ghouls, a long way from any friendly town.",
		"kit": [["pistol_10mm", 1], ["ammo_pistol", 30], ["raider_plates", 1], ["spiked_bat", 1], ["medkit", 2], ["lockpick", 4]],
		"scrap": 15, "raider": true, "buy": 1.35, "sell": 0.8, "equip": {"gun": "pistol_10mm", "melee": "spiked_bat", "body": "raider_plates"}},
]

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
var origin_id := "drifter"

func origin() -> Dictionary:
	for o in ORIGINS:
		if o.id == origin_id: return o
	return ORIGINS[0]

func choose_origin() -> void:
	var btns := []
	var lines := ["Who were you before you walked into the Sable Wastes?"]
	for o in ORIGINS:
		lines.append("%s — + %s  − %s" % [o.name, o.pro, o.con])
		var oid: String = o.id
		btns.append([o.name, func(): hud.hide_menu(); start_new_world({}, oid), false])
	hud.show_menu("Choose your start", lines, btns)

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
		xp = 0; level = 1; perks = {}; jobs = []; notes_read = []; examined = {}; under_state = {}
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

# ------------------------------------------------------------------ streaming
## Chunks within LOAD_R tiles of the player are shown; chunks beyond KEEP_R are dropped (their data
## stays in World, so walking back finds things as you left them). Content is generated a ring ahead.
const LOAD_R := 34.0
const KEEP_R := 62.0
const AHEAD_R := 80.0
var loaded := {}                 # chunk key -> {node, terrain, trees, crates, furn, decor, views}
var terrain_root: Node2D
var _parent: Node2D
var _light_tag := -1
var encounter_t := 0.0
# ---- immersion systems
var audio: Audio
var weather: Weather
var xp := 0
var level := 1
var perks := {}
var jobs: Array = []
var notes_read: Array = []
var examined := {}
var step_t := 0.0
var bark_t := 0.0
var greeted := {}

func perk(id: String) -> int:
	return int(perks.get(id, 0))

func gain_xp(n: int, why: String = "") -> void:
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
var save_t := 0.0
var _recruited_names := []
const SAVE_PATH := "user://save.json"

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

var _pending_props: Array = []

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

const LIGHTS := {   # decor name -> [height (logical px), screen x offset, colour, radius, flicker]
	"lamp": [58.0, 14.0, Color(1.0, 0.85, 0.55), 46.0, false],
	"crystal": [8.0, 0.0, Color(0.45, 1.0, 0.6), 40.0, false],
	"mine_support": [16.0, 0.0, Color(1.0, 0.75, 0.4), 36.0, true],
	"ladder_up": [60.0, 0.0, Color(0.9, 0.9, 0.75), 40.0, false],
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
		lights.add(Iso.to_screen(p.x, p.y, z + L[0]) + Vector2(L[1], 0), L[2], L[3], L[4], _light_tag)

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
	player.max_hp = 20 + (4 if any_up("tent") else 0) + 4 * perk("toughness") + int(origin().get("hp", 20)) - 20
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
		var hl: float = d.heal * ((1.0 + 0.5 * perk("medic")) if id == "medkit" else float(origin().get("food", 1.0)) * (1.0 + 0.5 * perk("lead_belly")))
		audio.play("heal" if id == "medkit" else "eat", Vector2.INF, -4.0)
		player.hp = minf(player.max_hp, player.hp + hl)
		add_text(player.wpos, "+%d hp" % int(hl), Color("9fd08a"))
	if hud.menu_open() or invs.visible: open_inventory()

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
	audio.play("pipboy", Vector2.INF, -6.0, 0.0)
	if invs.visible: invs.refresh()
	else: invs.open()

func unequip(slot: String) -> void:
	equip[slot] = "fists" if slot == "melee" else ""
	_refresh_gun()
	open_inventory()

## Drop one of an item on the ground as a bag you can pick back up.
func drop_item(id: String) -> void:
	var slot: String = Items.info(id).get("slot", "")
	if slot in ["gun", "melee", "head", "body"] and equip[slot] == id and inv_count(id) <= 1:
		unequip(slot)
	if not inv_take(id): return
	var cr := World.Crate.new()
	cr.pos = player.wpos + Vector2(0.4, 0.4)
	cr.kind = "bag"
	cr.fl = player.fl
	cr.set_meta("loot", [[id, 1]])
	_place_crate(cr)
	hud.toast("Dropped %s." % Items.iname(id))
	open_inventory()

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
	var fence := npc.has_meta("fence")
	if origin().get("raider", false) and not fence:
		var small: bool = npc.settlement < 0 or (npc.settlement < world.settlements.size() and world.settlements[npc.settlement].small)
		if small:
			add_text(npc.wpos + Vector2(0, -0.2), ["Not trading with raiders. Move along.", "I know that look. Get lost.", "We've got nothing for your kind."][randi() % 3], Color("e8a090"), 2.6)
			return
	if not npc.has_meta("stock"):
		var stock := []
		for t in (5 if fence else 3):
			stock.append(Items.gear_of_tier(rng.randi_range(2, 3) if fence else rng.randi_range(1, 3), rng))
		npc.set_meta("stock", stock)
	var stock: Array = npc.get_meta("stock")
	var lines := ["You have %d scrap (carried %d + stash %d)." % [_scrap_total(), player.carry.scrap, stash.scrap], "Buy:"]
	var btns := []
	for e in SHOP:
		var id: String = e[0]
		var n: int = e[1]
		var cost: int = e[2]
		cost = maxi(1, int(round(cost * (1.0 if npc.has_meta("fence") else float(origin().get("buy", 1.0))))))
		btns.append(["Buy %s ×%d — %d scrap" % [Items.iname(id), n, cost], func(): _buy(npc, id, n, cost), _scrap_total() < cost])
	for i in stock.size():
		var id: String = stock[i]
		if id == "": continue
		var cost: int = maxi(1, int(round(Items.info(id).value * (1.0 if npc.has_meta("fence") else float(origin().get("buy", 1.0))))))
		var ii := i
		btns.append(["Buy %s — %d scrap" % [Items.iname(id), cost], func(): _buy_stock(npc, ii, cost), _scrap_total() < cost])
	for it in inventory:
		var d := Items.info(it.id)
		if d.get("slot", "") in ["gun", "melee", "head", "body"] and it.id != equip[d.slot]:
			var id: String = it.id
			var val: int = maxi(1, int(d.value / 2.0 * (1.25 if npc.has_meta("fence") else float(origin().get("sell", 1.0)))))
			btns.append(["Sell %s — +%d scrap" % [d.name, val], func(): _sell(npc, id, val), false])
	if npc.settlement >= 0 and npc.settlement < world.settlements.size():
		btns.insert(0, ["Trade goods (water, salt, glass…) »", func(): open_goods(npc), false])
		if not world.settlements[npc.settlement].small:
			btns.insert(1, ["Jobs »", func(): open_jobs(npc), false])
	btns.append(["Leave", hud.hide_menu, false])
	hud.show_menu("The fence" if fence else ("Trader" if npc.type == "trader" else "Travelling merchant"), lines, btns)

func goods_carried() -> int:
	var n := 0
	for it in inventory:
		if Items.info(it.id).get("trade", false): n += it.n
	return n

func goods_cap() -> int:
	return 30 + int(origin().get("cap", 0)) + (10 if any_up("tent") else 0) + 15 * perk("strong_back")

## Commodity trading: this town's prices, buy 1 / 5, sell 1 / all.
func open_goods(npc: Npc) -> void:
	var st: World.Settlement = world.settlements[npc.settlement]
	var m := Economy.market(world, npc.settlement)
	var lines := ["%s market. You have %d scrap. Hauling %d / %d trade goods." % [st.name, _scrap_total(), goods_carried(), goods_cap()]]
	var pm: float = float(origin().get("buy", 1.0)) * (1.0 - 0.08 * perk("barter"))
	var sm: float = float(origin().get("sell", 1.0)) * (1.0 + 0.08 * perk("barter"))
	var btns := []
	for gd in m:
		var e: Dictionary = m[gd]
		var have := inv_count(gd)
		var buy := maxi(1, int(round(e.buy * pm)))
		var sell := maxi(1, int(round(e.sell * sm)))
		var tag := " (local, cheap)" if e.made else (" (in demand)" if e.wanted else "")
		lines.append("%s%s — buy %d · sell %d · you have %d" % [Items.iname(gd), tag, buy, sell, have])
		var id: String = gd
		if e.stock:
			var room := goods_cap() - goods_carried()
			btns.append(["Buy %s — %d" % [Items.iname(gd), buy], func(): _buy_good(npc, id, 1, buy), _scrap_total() < buy or room < 1])
			btns.append(["Buy 5 %s — %d" % [Items.iname(gd), buy * 5], func(): _buy_good(npc, id, 5, buy), _scrap_total() < buy * 5 or room < 5])
		if have > 0:
			btns.append(["Sell %s — +%d" % [Items.iname(gd), sell], func(): _sell_good(npc, id, 1, sell), false])
			if have > 1: btns.append(["Sell all %d %s — +%d" % [have, Items.iname(gd), sell * have], func(): _sell_good(npc, id, have, sell), false])
	btns.append(["« Back", func(): open_trade(npc), false])
	btns.append(["Leave", hud.hide_menu, false])
	hud.show_menu("Trade goods", lines, btns)

func _buy_good(npc: Npc, id: String, n: int, each: int) -> void:
	if goods_carried() + n <= goods_cap() and _pay(each * n):
		inv_add(id, n)
		audio.play("coins", Vector2.INF, -6.0)
	open_goods(npc)

func _sell_good(npc: Npc, id: String, n: int, each: int) -> void:
	if inv_take(id, n):
		player.carry.scrap += each * n
		add_text(player.wpos, "+%d scrap" % (each * n), Color("f2e27a"))
		audio.play("coins", Vector2.INF, -6.0)
		if each > Items.info(id).value: gain_xp(maxi(1, (each - Items.info(id).value) * n / 2), "")
	open_goods(npc)

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

## Auto-aim: the nearest enemy you can see and hit, within your gun's range. Sticks to the current
## target while it stays valid, so it doesn't flick between enemies mid-fight.
var locked: Enemy = null

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
	var bd := rng_
	for e in enemies:
		if e.dead or not e.visible or e.fl != p.fl or e.friendly(): continue
		var d: float = e.wpos.distance_to(p.wpos)
		if d < bd and world.los(p.wpos, e.wpos, p.fl):
			bd = d; locked = e

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

# ------------------------------------------------------------------ underground
## Entering a cave/mine/sewer/shelter swaps the World for that place's own map; the overworld is kept
## as it was and put back when you climb out.
var under := ""                 # portal id while underground
var under_state := {}           # portal id -> {opened, killed, cleared, visited}
var ow := {}                    # overworld kept while underground: world, pos, lights

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

# ------------------------------------------------------------------ jobs and cleared sites
func _check_cleared(loc_id: String) -> void:
	var l := world.loc_by_id(loc_id)
	if l.is_empty() or l.get("cleared", false): return
	for s in world.spawns:
		if s.get("loc", "") == loc_id and not s.get("dead", false): return
	l.cleared = true
	world.cleared[loc_id] = true
	hud.show_card("%s\nCLEARED" % l.name.to_upper())
	audio.play("discover", Vector2.INF, -3.0, 0.0)
	gain_xp(80, "")
	for j in jobs:
		if j.kind == "clear" and j.loc == loc_id: _complete_job(j)

func _complete_job(j: Dictionary) -> void:
	if j.get("done", false): return
	j.done = true
	stash.scrap += int(j.reward)
	audio.play("coins", Vector2.INF, -3.0)
	hud.toast("Job done: %s. +%d scrap (in your stash), +%d XP." % [j.title, j.reward, j.xp])
	gain_xp(int(j.xp), "")
	jobs.erase(j)

func open_jobs(npc: Npc) -> void:
	var si := npc.settlement
	var lines := ["Active jobs: %d / 3" % jobs.size()]
	var btns := []
	for j in jobs:
		lines.append("• %s (from %s)" % [j.title, j.from])
		if j.kind == "deliver" and world.settlements[si].id == j.loc:
			var jj = j
			btns.append(["Hand over the package — +%d" % j.reward, func(): _complete_job(jj); open_jobs(npc), false])
		if j.kind == "supply" and j.si == si:
			var jj = j
			btns.append(["Hand over %d %s — +%d" % [j.n, Items.iname(j.good), j.reward], func():
				if inv_take(jj.good, jj.n): _complete_job(jj)
				open_jobs(npc), inv_count(j.good) < j.n])
	if not npc.has_meta("job") or float(npc.get_meta("job_t", -999.0)) < time - 300.0:
		npc.set_meta("job", Jobs.offer(self, si))
		npc.set_meta("job_t", time)
	var off: Dictionary = npc.get_meta("job")
	if not off.is_empty() and not off.get("taken", false):
		lines.append("")
		lines.append("OFFER: %s" % off.title)
		lines.append(off.desc)
		lines.append("Pays %d scrap, %d XP." % [off.reward, off.xp])
		btns.append(["Take the job", func():
			off.taken = true
			jobs.append(off)
			audio.play("pipboy", Vector2.INF, -6.0, 0.0)
			hud.toast("Job taken: %s. It's on your compass and map." % off.title)
			open_jobs(npc), jobs.size() >= 3])
	btns.append(["« Back", func(): open_trade(npc), false])
	hud.show_menu("Jobs board", lines, btns)

func _update_jobs() -> void:
	for j in jobs:
		if j.kind == "bounty" and not j.get("spawned", false) and player.wpos.distance_to(j.target) < 45.0:
			j.spawned = true
			var at: Vector2 = j.target
			var ck := World.chunk_of(at)
			world.ensure_ready(ck.x, ck.y)
			for t in 30:
				if world.can_stand(at, 0.4, 0) and world.building_at(at.x, at.y) == 0: break
				at += Vector2(randf_range(-3, 3), randf_range(-3, 3))
			var key := World.ckey(ck.x, ck.y)
			for k in 4:
				var sp := {"type": "raider", "pos": at + Vector2.from_angle(k * 1.6) * (0.0 if k == 0 else 2.0), "home": at, "home_r": 4.0, "chunk": key}
				var e := _spawn_enemy(sp)
				if k == 0:
					e.set_meta("boss", j.boss)
					e.hp *= 6.0
					e.max_hp = e.hp
					e.weapon = "smg"
			hud.toast("You've found %s's camp." % j.boss)

func _find_note() -> void:
	var unread := []
	for i in Lore.NOTES.size():
		if i not in notes_read: unread.append(i)
	if unread.is_empty(): return
	var i: int = unread[randi() % unread.size()]
	notes_read.append(i)
	gain_xp(5, "")
	show_note(i)

func show_note(i: int) -> void:
	var n: Array = Lore.NOTES[i]
	audio.play("pickup", Vector2.INF, -6.0)
	hud.show_menu(n[0], [n[1]], [["Keep it  (notes are in your inventory)", hud.hide_menu, false]])

func show_stats() -> void:
	var lines := ["%s · Level %d · %d / %d XP to next" % [origin().name, level, xp, Perks.xp_needed(level)],
		"Kills %d · Places found %d / %d · Sites cleared %d · Notes %d / %d" % [player.kills, world.discovered.size(), world.locs.size(), world.cleared.size(), notes_read.size(), Lore.NOTES.size()],
		"Camps %d · Stash: %d scrap, %d cloth, %d wood" % [camps.size(), stash.scrap, stash.cloth, stash.wood], "", "PERKS:"]
	if perks.is_empty(): lines.append("None yet — level up to choose one.")
	for k in perks:
		lines.append("%s %d/%d — %s" % [Perks.LIST[k].name, perks[k], Perks.LIST[k].max, Perks.LIST[k].desc])
	if jobs.size():
		lines.append("")
		lines.append("JOBS:")
		for j in jobs: lines.append("• %s — %s" % [j.title, j.desc])
	hud.show_menu("Your story so far", lines, [["Close", hud.hide_menu, false]])

func show_notes() -> void:
	var btns := []
	for i in notes_read:
		var ii: int = i
		btns.append([Lore.NOTES[i][0], func(): show_note(ii), false])
	btns.append(["Close", hud.hide_menu, false])
	hud.show_menu("Notes & holotapes", ["You've found %d of %d." % [notes_read.size(), Lore.NOTES.size()]], btns)

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
		var dir := Vector2.from_angle(base + randf_range(-0.13, 0.13) + randf_range(-g.spread, g.spread) * 0.5)
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

func hurt_player(from: Vector2, dmg: float = 3.0) -> void:
	var p := player
	if p.inv > 0.0 or state != "play":
		return
	var taken := maxf(1.0, round(dmg * (1.0 - _reduction())))
	p.hp -= taken
	p.inv = 0.7
	p.flash = 0.3
	audio.play("hurt", Vector2.INF, -4.0)
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
	if under != "": _swap_out()
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
	p.sync()
	rebase()
	_stream(true)
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

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
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
			_discover()
		if travel.t >= 1.0:
			state = "play"
			if travel.has("swap"): hud.show_card(travel.to.cname.to_upper())
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
		"xp": xp, "level": level, "perks": perks, "jobs": jobs, "notes": notes_read, "examined": examined, "cleared": world.cleared}
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

func _world_life(delta: float) -> void:
	var p := player
	# day / night colour grade — a full day takes 8 minutes
	day_t = fmod(day_t + delta / 480.0, 1.0)
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

func _update_hud() -> void:
	var p := player
	var g := gun_info()
	var gun_s := ("%s  %d" % [g.name, inv_count(g.ammo)]) if not g.is_empty() else "unarmed"
	var hh := int(day_t * 24.0 + 6.0) % 24
	var nrec := 0
	for s in survivors:
		if s.get_meta("recruited"): nrec += 1
	var wx: String = {"dust": "  · dust", "rain": "  · rain", "rad": "  · RADSTORM"}.get(weather.kind, "") if weather and weather.amt > 0.2 else ""
	hud.stats.text = "%s   ARM %d   %02d:00%s\nScrap %d  ·  Med %d  ·  Goods %d/%d%s" % [
		gun_s, armor_total(), hh, wx, p.carry.scrap + stash.scrap, inv_count("medkit"), goods_carried(), goods_cap(), "   [SNEAKING]" if p.crouch else ""]
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
	for j in jobs:
		if under != "": break
		var tgt: Vector2 = j.target
		if j.kind == "supply": tgt = world.settlements[j.si].pos
		if tgt.distance_to(p.wpos) > 4.0: mk.append([(tgt - p.wpos).angle(), "job"])
	for e in enemies:
		if not e.dead and e.aw > 60.0 and e.wpos.distance_to(p.wpos) < 30.0 and not e.friendly(): mk.append([(e.wpos - p.wpos).angle(), "enemy"])
	hud.marks = mk
	hud.job_l.text = ("JOB: " + jobs[0].title + ("  (+%d more)" % (jobs.size() - 1) if jobs.size() > 1 else "")) if jobs.size() else ""
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
				var cmk := "MELEE" if using_touch else "[F]"
				match t.o.door:
					"closed": msg = "%s Open door" % k
					"locked": msg = ("%s Pick lock (%d)   %s Bash (loud)" % [k, inv_count("lockpick"), cmk]) if inv_count("lockpick") > 0 else "Locked — %s Bash it in (loud)" % cmk
					"barred": msg = "Barricaded — %s Bash (loud)" % cmk
					"sealed": msg = "Boarded up"
			"camp": msg = "%s Camp menu" % ("CAMP" if using_touch else "[B]")
			"examine": msg = "%s Look: %s" % [k, t.o.info.get_slice("|", 0)]
			"portal":
				if t.o.portal == "exit": msg = "%s Climb back up to the surface" % k
				else:
					var ui := Underground.info(t.o.portal)
					var cl: bool = under_state.get(t.o.portal, {}).get("cleared", false)
					msg = "%s Enter %s%s" % [k, ui.name, "  (cleared)" if cl else ""]
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
	# Visual QA over the streamed world: towns and sample spots in every biome, with timings.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	await _snap(out + "/w_start.png")
	var stops := []
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var xy := a.substr(5).split(",")
			stops.append(["at_%s_%s" % [xy[0], xy[1]], Vector2(float(xy[0]), float(xy[1]))])
	for l in world.locs:
		if only == "" or l.id in only.split(","): stops.append([l.id, l.pos + Vector2(0, l.r * 0.3)])
	if only == "" or "biomes" in only.split(","):
		var seen := {}
		var r := RandomNumberGenerator.new()
		r.seed = 3
		for t in 4000:
			var q := Vector2(r.randf_range(40, World.N - 40), r.randf_range(40, World.N - 40))
			var bn := world.biome_name(q)
			if seen.get(bn, 0) >= 1: continue
			seen[bn] = seen.get(bn, 0) + 1
			stops.append(["biome_" + bn, q])
	for st in stops:
		var t0 := Time.get_ticks_msec()
		var p: Vector2 = st[1]
		world.ensure_ready(World.chunk_of(p).x, World.chunk_of(p).y)
		for ring in 30:
			if world.can_stand(p, 0.25, 0) and world.building_at(p.x, p.y) == 0: break
			p += Vector2(randf_range(-2, 2), randf_range(-2, 2)) * (1 + ring * 0.3)
		player.fl = 0
		player.wpos = p
		player.sync()
		rebase()
		_stream(true)
		var t1 := Time.get_ticks_msec()
		for e in enemies: e.aw = 0.0; e.st = 0
		await get_tree().create_timer(0.3).timeout
		await _snap(out + "/w_%s.png" % st[0])
		print("TOUR %s at %s: %d ms, loaded %d chunks, %d enemies, %d npcs, %d views, %d trees" % [st[0], str(p.round()), t1 - t0, loaded.size(), enemies.size(), npcs.size(), views.size(), tree_nodes.size()])
	get_tree().quit()

## Playtest bot: walks from the home camp into town, then fights at a dungeon with auto-aim, logging
## what happens (for tuning).
func _debug_play() -> void:
	await get_tree().create_timer(1.0).timeout
	var plog := []
	var orig_toast := hud.toast_l.text
	var t0 := time
	var goal: Vector2 = world.loc_by_id(origin().loc).pos
	var steps := 0
	var stuck := 0
	var last := player.wpos
	while player.wpos.distance_to(goal) > 6.0 and steps < 60 * 50:
		steps += 1
		var dir := (goal - player.wpos).normalized()
		# steer around obstacles
		var mv := dir
		if stuck > 20: mv = dir.rotated(PI * 0.5 * (1 if (steps / 60) % 2 == 0 else -1))
		var sd := Vector2((mv.x - mv.y), (mv.x + mv.y) * 0.5).normalized()   # world -> screen-ish stick
		Input.action_release("fire")
		_bot_move = sd
		await get_tree().process_frame
		if _wants_fire_bot(): shoot()
		if steps % 30 == 0:
			stuck = stuck + 1 if player.wpos.distance_to(last) < 0.3 else 0
			last = player.wpos
		if hud.toast_l.text != orig_toast:
			orig_toast = hud.toast_l.text
			plog.append("t=%.0fs toast: %s" % [time - t0, orig_toast]); print("PLAY ", plog[-1])
	_bot_move = Vector2.ZERO
	plog.append("walk to town: %.0f s, reached=%s, hp %d/%d, kills %d" % [time - t0, str(player.wpos.distance_to(goal) <= 6.0), player.hp, player.max_hp, player.kills])
	await _snap("user://shots/play_town.png")
	# open-ground fight: a few ghouls and raiders come at you; stand and shoot with auto-aim
	var at := player.wpos + Vector2(14, 6)
	for t in 40:
		if world.can_stand(at, 0.3, 0) and world.settlement_at(at, 10.0) < 0: break
		at += Vector2(6, 3)
	player.wpos = at
	player.sync(); rebase(); _stream(true)
	for e in enemies: e.queue_free()
	enemies.clear()
	inv_add("ammo_pistol", 40); inv_add("medkit", 3)
	for k in 6:
		var sp := {"type": "ghoul" if k < 4 else "raider", "pos": at + Vector2.from_angle(k * 1.05) * 9.0, "home": at, "home_r": 12.0}
		var e := _spawn_enemy(sp)
		e.aw = 100.0; e.last = at
	var hp0 := player.hp
	var k0 := player.kills
	var a0 := inv_count("ammo_pistol")
	var locks := 0
	var first_lock := -1.0
	t0 = time
	for i in 60 * 20:
		await get_tree().process_frame
		if locked != null:
			locks += 1
			if first_lock < 0: first_lock = time - t0
			shoot()
		if player.hp < player.max_hp * 0.4 and inv_count("medkit") > 0: use_item("medkit")
		if state != "play": plog.append("went down at t=%.0f" % (time - t0)); break
		if i == 200: await _snap("user://shots/play_fight.png")
		if enemies.filter(func(e): return not e.dead).is_empty():
			plog.append("all dead at t=%.1f s" % (time - t0)); break
	plog.append("fight: kills %d/6, ammo used %d, hp %d -> %d, first lock %.1f s, frames locked %d, medkits used %d" % [player.kills - k0, a0 - inv_count("ammo_pistol"), hp0, player.hp, first_lock, locks, 3 + 0 - inv_count("medkit") + (2 if origin_id == "drifter" else 0)])
	for l in plog: print("PLAY ", l)
	get_tree().quit()

var _bot_move := Vector2.ZERO
func _wants_fire_bot() -> bool:
	return locked != null

## Trade + save round trip: buy goods at the start town, save, reload, check they're still there.
func _debug_econ() -> void:
	await get_tree().create_timer(1.0).timeout
	var tr: Npc = null
	for n in npcs:
		if n.type == "trader" and n.settlement >= 0: tr = n; break
	stash.scrap = 200
	if tr:
		open_goods(tr)
		await get_tree().create_timer(0.3).timeout
		await _snap("user://shots/econ_goods.png")
		var m := Economy.market(world, tr.settlement)
		for gd in m:
			if m[gd].stock: _buy_good(tr, gd, 5, m[gd].buy)
		print("ECON market ", world.settlements[tr.settlement].name, " ", m)
	hud.hide_menu()
	print("ECON carried goods ", goods_carried(), " scrap ", _scrap_total(), " inv ", inventory)
	wmap.open()
	await get_tree().create_timer(0.3).timeout
	await _snap("user://shots/econ_map.png")
	wmap.zoom = 4.0
	wmap._layout()
	await get_tree().create_timer(0.3).timeout
	await _snap("user://shots/econ_map_zoom.png")
	wmap.close()
	save_game()
	var inv_before := str(inventory)
	load_game()
	await get_tree().create_timer(1.0).timeout
	print("ECON reload same inv: ", str(inventory) == inv_before, " origin ", origin_id, " pos ", player.wpos)
	get_tree().quit()

## Immersion check: weather, radio line, compass, a job, a note, a level up.
func _debug_immersion() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await get_tree().create_timer(1.0).timeout
	var tr: Npc = null
	for n in npcs:
		if n.type == "trader" and n.settlement >= 0: tr = n; break
	if tr:
		player.wpos = tr.wpos + Vector2(0.8, 0.8)
		player.sync()
		open_jobs(tr)
		await get_tree().create_timer(0.3).timeout
		await _snap("user://shots/imm_jobs.png")
		var off: Dictionary = tr.get_meta("job")
		off.taken = true
		jobs.append(off)
		hud.hide_menu()
	audio.toggle_radio()
	weather.kind = "rad"; weather.amt = 0.9; weather.target = 0.9; weather.t_left = 99
	hud.show_card("PATCHWORK\nDISCOVERED")
	await get_tree().create_timer(1.0).timeout
	await _snap("user://shots/imm_rad.png")
	weather.kind = "rain"
	await get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_rain.png")
	weather.kind = "dust"
	await get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_dust.png")
	weather.amt = 0.0; weather.target = 0.0
	gain_xp(500, "test")
	await get_tree().create_timer(0.5).timeout
	await _snap("user://shots/imm_level.png")
	hud.hide_menu()
	_find_note()
	await get_tree().create_timer(0.3).timeout
	await _snap("user://shots/imm_note.png")
	hud.hide_menu()
	print("IMM jobs ", jobs.size(), " level ", level, " perks ", perks, " notes ", notes_read, " radio ", audio.radio_on, " beds ", audio.bed_target)
	get_tree().quit()

## Underground check: go down into one of each kind, look around, fight a little, climb out.
func _debug_under() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await get_tree().create_timer(1.0).timeout
	for kind in ["cave", "mine", "sewer", "vault"]:
		var t0 := Time.get_ticks_msec()
		var portal := "%s:%d_%d" % [kind, 500 + kind.length(), 700]
		_swap_under(portal, player.wpos)
		var t1 := Time.get_ticks_msec()
		await get_tree().create_timer(0.5).timeout
		await _snap("user://shots/under_%s.png" % kind)
		var boss = null
		for s in world.spawns:
			if s.has("boss"): boss = s
		# jump next to the boss
		player.wpos = boss.pos + Vector2(-3, -3)
		for t in 20:
			if world.can_stand(player.wpos, 0.3, 0): break
			player.wpos += Vector2(randf_range(-1, 1), randf_range(-1, 1))
		player.sync(); _stream(true)
		await get_tree().create_timer(0.6).timeout
		await _snap("user://shots/under_%s_boss.png" % kind)
		print("UNDER %s: %s, built in %d ms, %d spawns, %d crates, %d decor, start %s, boss %s at %s, enemies active %d" % [kind, Underground.info(portal).name, t1 - t0, world.spawns.size(), world.crates.size(), world.decor.size(), str(world.start), boss.boss, str(boss.pos), enemies.size()])
		_swap_out()
		await get_tree().create_timer(0.3).timeout
	print("UNDER back on surface at ", player.wpos, " world interior=", world.interior, " loaded ", loaded.size())
	await _snap("user://shots/under_back.png")
	get_tree().quit()

## Walk along the interstate for a while, measuring frame times while chunks stream in.
func _debug_walk() -> void:
	await get_tree().create_timer(1.0).timeout
	var worst := 0.0
	var sum := 0.0
	var n := 0
	var dir := Vector2(1, 0.15).normalized()
	for i in 900:
		var t0 := Time.get_ticks_usec()
		player.wpos += dir * 3.4 / 60.0 * 4.0
		player.sync()
		await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt); sum += dt; n += 1
		if i % 150 == 0:
			print("WALK %d at %s: avg %.1f ms worst %.1f ms, loaded %d, nodes %d, enemies %d" % [i, str(player.wpos.round()), sum / n, worst, loaded.size(), root.get_child_count(), enemies.size()])
			await _snap("user://shots/walk_%d.png" % i)
			worst = 0.0; sum = 0.0; n = 0
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

func _debug_build() -> void:
	# Base building check: lays out a compound by hand and through the pointer code path, tests
	# collision, shots through windows, a door, removal, the ghost, and takes screenshots.
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.0).timeout
	for e in enemies: e.visible = false; e.aw = 0.0; e.wpos = Vector2(2, 2)
	stash = {"scrap": 400, "cloth": 50, "wood": 400}
	var o := Vector2(floor(world.start.x) + 2.0, floor(world.start.y) - 3.0)
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
		var why := base.edge_problem(k)
		if why == "":
			base._level(BaseBuild.edge_verts(k)); base.place(k, p[1], p[2]); ok += 1
		else:
			bad.append("%s %s: %s" % [str(k), p[2], why])
	for y in 3:
		for x in 3:
			var t := Vector2i(int(o.x) + x, int(o.y) + y)
			if base.floor_problem(t) == "": base._level(BaseBuild.tile_verts(t)); base.place_floor(t, "wood" if x == 0 else "concrete")
	base._relevel_done()
	print("BUILD placed %d, refused %d %s" % [ok, bad.size(), str(bad)])
	# collision: can't stand on a wall, can inside the room
	print("BUILD stand-on-wall=%s stand-inside=%s" % [str(world.can_stand(o + Vector2(0.5, 0.0), 0.25, 0)), str(world.can_stand(o + Vector2(1.5, 1.5), 0.25, 0))])
	# shots: window lets shots through, wall stops them
	print("BUILD shot-through-window=%s shot-through-wall=%s" % [str(not world.blocks_shot(o + Vector2(1.5, 0.0), 10.0, 0)), str(not world.blocks_shot(o + Vector2(0.5, 0.0), 10.0, 0))])
	# pointer path: drag a run of scrap walls along x via screen coordinates
	base.enter()
	base.select("scrap", "wall")
	var a := o + Vector2(5.2, 0.0); var b := o + Vector2(8.6, 0.1)
	base.press(to_hud(Iso.to_screen(a.x, a.y, world.hz(a.x, a.y))))
	base.move(to_hud(Iso.to_screen(b.x, b.y, world.hz(b.x, b.y))))
	print("BUILD drag targets: %s" % str(base.targets(base.drag_a, base.drag_b)))
	base.release(to_hud(Iso.to_screen(b.x, b.y, world.hz(b.x, b.y))))
	print("BUILD pieces now %d, floors %d, stash %s" % [base.pieces.size(), base.floors.size(), str(stash)])
	# door
	var dk := Vector3i(int(o.x) + 1, int(o.y) + 3, 0)
	var dseg: World.Seg = base.pieces[dk].seg
	open_door(dseg)
	print("BUILD door opened=%s solid=%s" % [dseg.door, str(dseg.solid)])
	player.wpos = o + Vector2(1.5, 4.5)
	await get_tree().create_timer(0.5).timeout
	await _snap(out + "/build_front.png")
	player.wpos = o + Vector2(4.5, 4.5)
	await get_tree().create_timer(3.0).timeout
	print("BUILD door after waiting=%s" % dseg.door)
	# ghost: hover a run and screenshot
	base.select("wood", "wall")
	var ga := o + Vector2(-2.0, 7.0); var gb := o + Vector2(-2.0, 10.4)
	base.press(to_hud(Iso.to_screen(ga.x, ga.y, world.hz(ga.x, ga.y))))
	base.move(to_hud(Iso.to_screen(gb.x, gb.y, world.hz(gb.x, gb.y))))
	player.wpos = o + Vector2(2.5, 7.5)
	await get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_ghost.png")
	base.release(to_hud(Iso.to_screen(gb.x, gb.y, world.hz(gb.x, gb.y))))
	# behind the compound: walls in front should fade
	player.wpos = o + Vector2(1.5, -0.7)
	await get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_behind.png")
	player.wpos = o + Vector2(1.5, 1.5)
	await get_tree().create_timer(0.4).timeout
	await _snap(out + "/build_inside.png")
	# remove
	base.select("", "remove")
	var rk := Vector3i(int(o.x) + 2, int(o.y), 0)
	base.remove(rk)
	print("BUILD removed=%s stash %s" % [str(not base.pieces.has(rk)), str(stash)])
	# foundations on a slope: find a sloped patch near camp, lay a 3x3 concrete foundation, wall it
	var best := Vector2i(-1, -1); var bslope := 0.0
	for y in range(int(world.start.y) - 9, int(world.start.y) + 10):
		for x in range(int(world.start.x) - 9, int(world.start.x) + 10):
			var okp := true; var lo := INF; var hi := -INF
			for yy in 3:
				for xx in 3:
					var t := Vector2i(x + xx, y + yy)
					if not world.in_bounds(t.x, t.y) or world.building_at(t.x + 0.5, t.y + 0.5) != 0 or world.T[world.idx(t.x, t.y)] == World.TREE or base.founds.has(t) or base.floors.has(t): okp = false
					for v in BaseBuild.tile_verts(t):
						lo = minf(lo, world.vh(v.x, v.y)); hi = maxf(hi, world.vh(v.x, v.y))
					for vv in BaseBuild.tile_verts(t):
						if base.vgroup.has(vv): okp = false
			if okp and x > 3 and y > 3 and hi - lo > bslope and hi - lo < 30.0 and base.in_base(Vector2(x + 1.5, y + 1.5)):
				bslope = hi - lo; best = Vector2i(x, y)
	print("BUILD slope patch %s drop %.1f px" % [str(best), bslope])
	if best.x >= 0:
		base.select("concrete", "foundation")
		base.drag_a = Vector2(best.x + 0.5, best.y + 0.5); base.drag_b = Vector2(best.x + 2.5, best.y + 2.5)
		base._commit()
		base.select("wood", "wall")
		base.drag_a = Vector2(best.x + 0.2, best.y + 0.0); base.drag_b = Vector2(best.x + 2.8, best.y + 0.0); base._commit()
		base.drag_a = Vector2(best.x + 0.0, best.y + 0.2); base.drag_b = Vector2(best.x + 0.0, best.y + 2.8); base._commit()
		base.select("wood", "door")
		base.drag_a = Vector2(best.x + 3.0, best.y + 1.5); base.drag_b = base.drag_a; base.axis = 1; base._commit()
		var mid := Vector2(best.x + 1.5, best.y + 1.5)
		for t in base.founds: print("BUILD found %s top %.1f faces %d" % [str(t), base.founds[t].top, base.founds[t].faces.size()])
		print("BUILD foundations %d top %.1f stand_z %.1f ground %.1f walls %d" % [base.founds.size(), base.founds[best].top if base.founds.has(best) else -1.0, world.stand_z(mid.x, mid.y, 0), world.hz(mid.x, mid.y), base.pieces.size()])
		player.wpos = mid + Vector2(2.2, 2.2)
		for v in views: v.visible = false            # debug framing only: nothing in front of the patch
		await get_tree().create_timer(0.4).timeout
		await _snap(out + "/build_foundation.png")
		for v in views: v.visible = true
		player.wpos = mid
		await get_tree().create_timer(0.4).timeout
		print("BUILD player z on foundation %.1f" % player.ground_z())
	# claim a raider den, knock out a wall, extend it
	if not world.rcamps.is_empty():
		var rc = world.rcamps[0]
		for e in enemies:
			if e.camp == 0: e.dead = true; e.visible = false
		rc.cleared = true
		player.wpos = rc.pos + Vector2(0, 4.0)
		claim_den(rc)
		var bb: World.Bld = world.buildings[rc.bid - 1]
		var wall: World.Seg = null
		for s in bb.segs:
			if s.fl == 0 and s.side == "s" and not s.is_door: wall = s; break
		var n0 := bb.segs.size()
		if wall: base.remove(wall)
		print("BUILD den b%d h0 %.1f segs %d -> %d, edge free=%s" % [bb.id, bb.h0, n0, bb.segs.size(), str(wall != null and not world.edge_taken(int(wall.a.x), int(wall.a.y), wall.axis))])
		if wall:
			# a foundation patch south of the gap, snapped to the den floor, walled on its sides
			var t0 := Vector2i(int(wall.a.x), int(wall.a.y))
			base.select("stone", "foundation")
			base.drag_a = Vector2(t0.x + 0.5, t0.y + 0.5); base.drag_b = Vector2(t0.x + 0.5, t0.y + 1.5); base._commit()
			base.select("scrap", "wall")
			base.drag_a = Vector2(t0.x, t0.y + 0.2); base.drag_b = Vector2(t0.x, t0.y + 1.8); base._commit()
			base.drag_a = Vector2(t0.x + 1, t0.y + 0.2); base.drag_b = Vector2(t0.x + 1, t0.y + 1.8); base._commit()
			base.drag_a = Vector2(t0.x + 0.5, t0.y + 2); base.drag_b = base.drag_a; base.axis = 0; base._commit()
			print("BUILD den extension founds top %s" % str(base.founds.get(t0, {}).get("top", -1)))
			for kk in [Vector3i(t0.x, t0.y, 1), Vector3i(t0.x, t0.y + 1, 1), Vector3i(t0.x + 1, t0.y, 1), Vector3i(t0.x, t0.y + 2, 0)]:
				print("BUILD den edge %s built=%s why=%s" % [str(kk), str(base.pieces.has(kk)), base.edge_problem(kk)])
		player.wpos = Vector2(bb.x0 + bb.w * 0.5 + 1.0, bb.y0 + bb.h + 3.0)
		for t in base.founds:
			if t.y >= bb.y0 + bb.h: print("BUILD den found %s top %.1f spr %s vis %s faces %d" % [str(t), base.founds[t].top, str(base.founds[t].spr.position), str(base.founds[t].spr.visible), base.founds[t].faces.size()])
		for v in views:
			v.visible = v.b.id == rc.bid
			if v.visible: print("BUILD den view at x0 %d y0 %d w %d h %d kind %s walls %d faded %s; player %s" % [bb.x0, bb.y0, bb.w, bb.h, bb.kind, v.walls.size(), str(v._faded), str(player.wpos)])
		await get_tree().create_timer(0.5).timeout
		await _snap(out + "/build_den.png")
		for v in views: v.visible = true
	get_tree().quit()

func _debug_inv() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await get_tree().create_timer(1.0).timeout
	for k in ["pistol_10mm", "shotgun", "rifle", "smg", "machete", "spiked_bat", "road_helmet", "combat_vest", "jacket", "ammo_shell", "ammo_rifle"]:
		inv_add(k, 1 if not k.begins_with("ammo") else 12)
	equip_item("pistol_10mm")
	invs.sel = "shotgun"
	open_inventory()
	await get_tree().create_timer(0.5).timeout
	await _snap("user://shots/inventory.png")
	get_tree().quit()

func _debug_map() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await get_tree().create_timer(1.0).timeout
	await _snap("user://shots/hud.png")
	wmap.open()
	await get_tree().create_timer(0.6).timeout
	await _snap("user://shots/worldmap.png")
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
