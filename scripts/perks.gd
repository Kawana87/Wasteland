class_name Perks
## Experience and perks. You earn XP for discoveries, kills, jobs, cleared sites, profitable trades
## and things you find; each level lets you pick one of three perks.

const LIST := {
	"toughness": {"name": "Toughness", "desc": "+4 max health.", "max": 3},
	"gunslinger": {"name": "Gunslinger", "desc": "Guns do 20% more damage.", "max": 3},
	"steady": {"name": "Steady Aim", "desc": "30% tighter spread.", "max": 2},
	"scrounger": {"name": "Scrounger", "desc": "Find extra ammo in containers.", "max": 2},
	"strong_back": {"name": "Strong Back", "desc": "Carry 15 more trade goods.", "max": 3},
	"barter": {"name": "Silver Tongue", "desc": "Buy 8% cheaper, sell 8% higher.", "max": 3},
	"medic": {"name": "Field Medic", "desc": "Med kits heal 50% more.", "max": 2},
	"lead_belly": {"name": "Lead Belly", "desc": "Food and water heal 50% more.", "max": 2},
	"pathfinder": {"name": "Pathfinder", "desc": "Walk 8% faster.", "max": 2},
	"shadow": {"name": "Shadow", "desc": "Enemies notice you 25% slower.", "max": 2},
	"rad_skin": {"name": "Rad Skin", "desc": "Radstorms hurt half as much.", "max": 1},
	"lucky": {"name": "Lucky Shot", "desc": "15% chance for double damage.", "max": 2},
	"brawler": {"name": "Brawler", "desc": "Melee does 40% more damage.", "max": 2},
}

static func xp_needed(level: int) -> int:
	return 60 * level * (level + 1) / 2 + 40 * level

static func choices(have: Dictionary) -> Array:
	var opts := []
	for k in LIST:
		if int(have.get(k, 0)) < int(LIST[k].max): opts.append(k)
	opts.shuffle()
	return opts.slice(0, 3)
