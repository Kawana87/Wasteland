extends Node
## Game state: every member variable and constant of Game lives here so the system files above it can share them.

## Main controller: builds the scene, owns the world, runs the game loop, handles input,
## camps / fast travel, loot, combat and the HUD.

static var I: Game
var dbg = null                   # DebugRuns, only with --autostart
var hurt_calls := 0              # hits that reached hurt_player / were swallowed by the grace window (checks)
var hurt_blocked := 0
var pending_hits: Array = []     # [from, dmg, time]: hits that arrived during the 0.15 s grace
var proc_ms := 0.0               # time spent in Game._process last frame (perf check)
const SAVE_VERSION := 3
const BAK_PATH := "user://save.bak.json"
var econ := {"sat": {}, "purse": {}, "stock": {}}   # the player's effect on markets (see Economy)
var days := 0                    # whole days passed
var trade_xp_day := {}           # settlement id -> day trade XP was last given there
var last_trade_si := -1
var recovery := {}               # the bag you dropped when you last went down: {pos, under, crate, items, mats}
var bruised_t := 0.0             # after going down: slower camp healing for an in-game hour
var aim_assist := false          # full auto-aim (no movement penalty), a setting


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

const DAY_LEN := 1440.0           # real seconds per game day: one minute per hour

var rested_t := 0.0               # Well Rested time left (game seconds)

var grade: ShaderMaterial

var lights: LightLayer

var noise_level := 0.0

var in_settlement := -1

var dust: Array = []

var rng := RandomNumberGenerator.new()


# ------------------------------------------------------------------ origins
## Where you start and who you were. Each has an upside and a catch.
const ORIGINS := [
	{"id": "drifter", "name": "Road-worn Drifter", "loc": "patchwork",
		"pro": "Starts at Patchwork, the friendliest town in the Wastes, with extra med kits and food.",
		"pro_s": "Friendly start town, extra meds and food", "con_s": "No special edge",
		"con": "Nothing special about you. Yet.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 18], ["medkit", 2], ["food", 3], ["lockpick", 3]]},
	{"id": "water_runner", "name": "Clearwater Water-runner", "loc": "clearwater",
		"pro": "Starts by Lake Winona with 6 water and 20 scrap. Trade goods sell for 15% more.",
		"pro_s": "Trade goods sell for 15% more, 20 scrap", "con_s": "16 max health",
		"con": "Grew up soft by the lake: 16 max health.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 14], ["medkit", 1], ["water", 6], ["lockpick", 2]], "scrap": 20, "sell": 1.15, "hp": 16},
	{"id": "ex_con", "name": "Iron Gate Ex-con", "loc": "iron_gate_pen",
		"pro": "Melee hits 50% harder. Starts with a machete and 6 lockpicks.",
		"pro_s": "Melee +50%, machete, 6 lockpicks", "con_s": "Everything costs 20% more, 6 rounds",
		"con": "Traders don't trust you: everything costs 20% more. Only 6 rounds.",
		"kit": [["machete", 1], ["pipe_pistol", 1], ["ammo_pistol", 6], ["food", 2], ["lockpick", 6]], "melee": 1.5, "buy": 1.2, "equip": {"melee": "machete"}},
	{"id": "scavenger", "name": "Redwall Scavenger", "loc": "redwall",
		"pro": "Finds an extra scrap in every container and can haul 15 more trade goods.",
		"pro_s": "+1 scrap per container, +15 cargo", "con_s": "No gun, remote south-west start",
		"con": "No gun to start with, just a lead pipe — out in the red canyons of the south-west.",
		"kit": [["pipe", 1], ["medkit", 1], ["food", 2], ["copper", 3], ["lockpick", 4]], "scav": true, "cap": 15, "equip": {"melee": "pipe", "gun": ""}},
	{"id": "farmhand", "name": "Greenmarsh Farmhand", "loc": "greenmarsh",
		"pro": "Food, water and produce heal twice as much. Starts with 8 produce and a jacket.",
		"pro_s": "Food heals double, 8 produce, jacket", "con_s": "Remote southern start, 8 rounds",
		"con": "Far down in the southern fens, a long walk from anywhere. Only 8 rounds.",
		"kit": [["pipe_pistol", 1], ["ammo_pistol", 8], ["produce", 8], ["jacket", 1]], "food": 2.0, "equip": {"body": "jacket"}},
	{"id": "raider", "name": "Port Sterling Raider", "loc": "sterling_downtown",
		"pro": "Best gear of any start (10mm pistol, raider plates, spiked bat). Raiders leave you alone unless you start trouble, and the fence at your hideout pays 25% more for gear and stocks better guns.",
		"pro_s": "Best gear, raiders leave you alone", "con_s": "Towns charge 35% more, camps refuse you",
		"con": "Town traders charge 35% more and pay 20% less; small camps and scavengers won't deal with you, and survivors won't join a raider. You start downtown among the ghouls, a long way from any friendly town.",
		"kit": [["pistol_10mm", 1], ["ammo_pistol", 30], ["raider_plates", 1], ["spiked_bat", 1], ["medkit", 2], ["lockpick", 4]],
		"scrap": 15, "raider": true, "buy": 1.35, "sell": 0.8, "equip": {"gun": "pistol_10mm", "melee": "spiked_bat", "body": "raider_plates"}},
]

var origin_id := "drifter"


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
var perk_points := 0             # levels gained but not yet spent on a perk

var perks := {}

var jobs: Array = []

var notes_read: Array = []

var examined := {}

var step_t := 0.0

var bark_t := 0.0

var greeted := {}

var save_t := 0.0

var _recruited_names := []

const SAVE_PATH := "user://save.json"


var _pending_props: Array = []


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


const TREES_LEAFY := ["tree0", "tree1", "tree2", "tree5", "tree7"]

const TREES_PINE := ["tree3", "tree4", "tree3"]

const TREES_DRY := ["tree6", "tree5", "tree_dead2"]

const TREES_DEAD := ["tree_dead", "tree_dead1", "tree_dead2"]


# ------------------------------------------------------------------ trading
const SHOP := [["ammo_pistol", 10, 3], ["ammo_shell", 6, 4], ["ammo_rifle", 5, 5], ["medkit", 1, 6], ["food", 2, 2]]


## Auto-aim: the nearest enemy you can see and hit, within your gun's range. Sticks to the current
## target while it stays valid, so it doesn't flick between enemies mid-fight.
var locked: Enemy = null


# ------------------------------------------------------------------ underground
## Entering a cave/mine/sewer/shelter swaps the World for that place's own map; the overworld is kept
## as it was and put back when you climb out.
var under := ""                 # portal id while underground

var under_state := {}           # portal id -> {opened, killed, cleared, visited}

var ow := {}                    # overworld kept while underground: world, pos, lights


# ------------------------------------------------------------------ doors
var busy := {}   # lockpicking in progress: {door, t, total}


var _bot_move := Vector2.ZERO

# ---- forward declarations: these are defined further up the chain (game_*.gd, game.gd); declared
# here so earlier system files can call them.
func _check_under_cleared() -> void:
	pass
func _place_crate(c: World.Crate) -> void:
	pass
func _swap_out() -> void:
	pass
func enter_under(portal: String, at: Vector2) -> void:
	pass
func exit_under() -> void:
	pass
func open_camp_menu() -> void:
	pass
func open_sleep(at_camp: bool) -> void:
	pass
func start_new_world(save: Dictionary = {}, oid: String = "drifter") -> void:
	pass
func save_game() -> void:
	pass
func choose_origin() -> void:
	pass
