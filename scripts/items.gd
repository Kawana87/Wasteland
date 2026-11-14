class_name Items
## Item database: guns, melee weapons, armour, ammo and consumables, plus loot tables.

const DB := {
	# guns: dmg per bullet, rate = seconds between shots, spread (radians), speed (tiles/s), life (s), pellets, ammo type
	"pipe_pistol": {"name": "Pipe Pistol", "slot": "gun", "dmg": 2, "rate": 0.34, "spread": 0.10, "speed": 14.0, "life": 0.9, "pellets": 1, "ammo": "ammo_pistol", "len": 6, "value": 12, "tier": 1},
	"pistol_10mm": {"name": "10mm Pistol", "slot": "gun", "dmg": 3, "rate": 0.28, "spread": 0.06, "speed": 16.0, "life": 1.0, "pellets": 1, "ammo": "ammo_pistol", "len": 6, "value": 25, "tier": 2},
	"smg": {"name": "Scrap SMG", "slot": "gun", "dmg": 2, "rate": 0.11, "spread": 0.14, "speed": 15.0, "life": 0.9, "pellets": 1, "ammo": "ammo_pistol", "len": 8, "value": 40, "tier": 3},
	"shotgun": {"name": "Sawed-off Shotgun", "slot": "gun", "dmg": 2, "rate": 0.8, "spread": 0.35, "speed": 13.0, "life": 0.4, "pellets": 5, "ammo": "ammo_shell", "len": 7, "value": 35, "tier": 2},
	"rifle": {"name": "Hunting Rifle", "slot": "gun", "dmg": 8, "rate": 0.95, "spread": 0.02, "speed": 22.0, "life": 1.2, "pellets": 1, "ammo": "ammo_rifle", "len": 10, "value": 45, "tier": 3},
	# melee
	"fists": {"name": "Fists", "slot": "melee", "dmg": 1, "value": 0, "tier": 0},
	"pipe": {"name": "Lead Pipe", "slot": "melee", "dmg": 3, "value": 8, "tier": 1},
	"machete": {"name": "Machete", "slot": "melee", "dmg": 4, "value": 18, "tier": 2},
	"spiked_bat": {"name": "Spiked Bat", "slot": "melee", "dmg": 5, "value": 26, "tier": 3},
	# armour: each point = 7% less damage taken (max 60%)
	"cap": {"name": "Leather Cap", "slot": "head", "armor": 1, "value": 8, "tier": 1},
	"road_helmet": {"name": "Road Helmet", "slot": "head", "armor": 2, "value": 20, "tier": 2},
	"jacket": {"name": "Leather Jacket", "slot": "body", "armor": 2, "value": 14, "tier": 1},
	"raider_plates": {"name": "Raider Plates", "slot": "body", "armor": 3, "value": 28, "tier": 2},
	"combat_vest": {"name": "Combat Vest", "slot": "body", "armor": 5, "value": 50, "tier": 3},
	# ammo + consumables (stack)
	"ammo_pistol": {"name": "Pistol rounds", "slot": "ammo", "value": 1},
	"ammo_shell": {"name": "Shotgun shells", "slot": "ammo", "value": 1},
	"ammo_rifle": {"name": "Rifle rounds", "slot": "ammo", "value": 2},
	"medkit": {"name": "Med Kit", "slot": "use", "heal": 12, "value": 10},
	"food": {"name": "Canned Food", "slot": "use", "heal": 4, "value": 3},
}

static func info(id: String) -> Dictionary:
	return DB.get(id, {})

static func iname(id: String) -> String:
	return DB.get(id, {}).get("name", id)

static func gear_of_tier(tier: int, rng: RandomNumberGenerator) -> String:
	var pool := []
	for k in DB:
		var d: Dictionary = DB[k]
		if d.get("tier", -1) == tier and d.slot in ["gun", "melee", "head", "body"]:
			pool.append(k)
	return pool[rng.randi_range(0, pool.size() - 1)] if pool.size() > 0 else ""

## Returns an Array of [id, count] for a container kind.
static func roll_loot(kind: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	var r := rng.randf()
	var ammo: String = ["ammo_pistol", "ammo_pistol", "ammo_shell", "ammo_rifle"][rng.randi_range(0, 3)]
	match kind:
		"cache":
			out.append([ammo, rng.randi_range(6, 14)])
			if r < 0.55: out.append([gear_of_tier(rng.randi_range(2, 3), rng), 1])
			if rng.randf() < 0.5: out.append(["medkit", 1])
		"bag":
			out.append([ammo, rng.randi_range(3, 8)])
			if r < 0.35: out.append([gear_of_tier(rng.randi_range(1, 2), rng), 1])
		"car":
			if r < 0.5: out.append([ammo, rng.randi_range(2, 6)])
			if rng.randf() < 0.15: out.append([gear_of_tier(1, rng), 1])
		"brute":
			out.append([gear_of_tier(3, rng), 1])
			out.append(["medkit", 1])
		"fridge", "counter", "stove":
			if r < 0.6: out.append(["food", rng.randi_range(1, 2)])
		"shopcounter", "shopshelf":
			if r < 0.5: out.append([ammo, rng.randi_range(3, 9)])
			if rng.randf() < 0.3: out.append(["food", 1])
			if rng.randf() < 0.12: out.append([gear_of_tier(rng.randi_range(1, 2), rng), 1])
		"dresser", "bed", "mattress":
			if r < 0.25: out.append([["cap", "jacket"][rng.randi_range(0, 1)], 1])
			elif r < 0.45: out.append(["medkit", 1])
		"workbench":
			if r < 0.3: out.append([["pipe", "pipe_pistol", "machete"][rng.randi_range(0, 2)], 1])
		_:
			if r < 0.35: out.append([ammo, rng.randi_range(2, 6)])
			if rng.randf() < 0.12: out.append(["medkit", 1])
			if rng.randf() < 0.06: out.append([gear_of_tier(1, rng), 1])
	return out

## What a container gives in raw materials: [scrap, cloth, wood]
static func roll_materials(kind: String, rng: RandomNumberGenerator) -> Array:
	match kind:
		"cache": return [rng.randi_range(3, 6), rng.randi_range(1, 3), rng.randi_range(0, 3)]
		"car": return [rng.randi_range(1, 3), 0, 0]
		"bag": return [rng.randi_range(1, 2), rng.randi_range(0, 1), 0]
		"dresser", "bed", "mattress": return [0, rng.randi_range(1, 3), 0]
		"workbench", "filing", "desk": return [rng.randi_range(1, 3), 0, rng.randi_range(0, 1)]
		"bookshelf", "barrel": return [rng.randi_range(0, 1), 0, rng.randi_range(1, 2)]
	return [rng.randi_range(0, 2), rng.randi_range(0, 1), 0]
