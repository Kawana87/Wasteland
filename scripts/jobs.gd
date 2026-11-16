class_name Jobs
## Odd jobs from town traders — the reason to cross the map. Each has a target on the compass and
## the world map, and pays scrap and XP.
##   deliver : carry a package to another town's trader
##   clear   : wipe out a hostile site (dungeon) from the map
##   bounty  : hunt down a named raider boss camped out in the wilds
##   supply  : bring the trader some trade goods

const BOSS_FIRST := ["Red", "Mad", "One-Eye", "Big", "Lucky", "Rusty", "Slick", "Dutch", "Granny", "Hacksaw", "Smiling"]
const BOSS_LAST := ["Jack", "Marlo", "Sue", "Dawes", "Kettle", "Vance", "Molly", "Teeth", "Boone", "Ricks"]

static func offer(g, si: int) -> Dictionary:
	var w: World = g.world
	var st: World.Settlement = w.settlements[si]
	var r := randf()
	var here: Vector2 = st.pos
	var towns := []
	var dungeons := []
	for l in w.locs:
		var d: float = here.distance_to(l.pos)
		if d < 60.0 or d > 900.0: continue
		if l.type in ["town", "hub", "settlement"] and l.faction != "Raiders": towns.append(l)
		elif l.type == "dungeon" and not l.get("cleared", false): dungeons.append(l)
	if r < 0.35 and towns.size():
		var l: Dictionary = towns[randi() % towns.size()]
		var d := int(here.distance_to(l.pos))
		return {"kind": "deliver", "title": "Deliver a package to %s" % l.name, "target": l.pos, "loc": l.id,
			"reward": 20 + d / 8, "xp": 30 + d / 6, "from": st.name, "desc": "Sealed and heavy. Don't open it. %s is about %d tiles away." % [l.name, d]}
	elif r < 0.6 and dungeons.size():
		var l: Dictionary = dungeons[randi() % dungeons.size()]
		return {"kind": "clear", "title": "Clear out %s" % l.name, "target": l.pos, "loc": l.id,
			"reward": 60 + int(l.danger) * 20, "xp": 90 + int(l.danger) * 30, "from": st.name, "desc": "Whatever holds %s has been raiding our caravans. Make it stop." % l.name}
	elif r < 0.85:
		var a := randf() * TAU
		var tp: Vector2 = here + Vector2.from_angle(a) * randf_range(120.0, 260.0)
		tp = tp.clamp(Vector2(60, 60), Vector2(World.N - 60, World.N - 60))
		var nm: String = "%s %s" % [BOSS_FIRST[randi() % BOSS_FIRST.size()], BOSS_LAST[randi() % BOSS_LAST.size()]]
		return {"kind": "bounty", "title": "Bounty: %s" % nm, "target": tp, "boss": nm, "spawned": false,
			"reward": 70, "xp": 110, "from": st.name, "desc": "%s and their crew hit our traders. Last seen out in the wilds — it's marked on your map." % nm}
	else:
		var goods := ["water", "produce", "salt", "glass", "copper", "fuel", "tech"]
		var m := Economy.market(w, si)
		var want := []
		for gd in goods:
			if not m[gd].made: want.append(gd)
		var gd: String = want[randi() % want.size()] if want.size() else "water"
		var n := randi_range(5, 10)
		return {"kind": "supply", "title": "Bring %d %s to %s" % [n, Items.iname(gd), st.name], "target": here, "good": gd, "n": n, "st": st.id,
			"reward": int(Items.info(gd).value * n * 1.6), "xp": 40 + n * 4, "from": st.name, "desc": "We're short on %s. Bring %d and I'll pay well over the odds." % [Items.iname(gd).to_lower(), n]}
