class_name Economy
## Trade goods and what each town pays for them. Every town makes something cheaply (water by the
## lake, salt off the flats, glass from the crater, copper from the canyon mines...) and pays well for
## what it lacks — dry country pays for water most of all. Buy low, haul it across the wastes, sell high.

const GOODS := ["water", "produce", "salt", "glass", "copper", "fuel", "tech"]
const ARID := ["waste", "salt", "canyon", "crater", "gorge"]

## What a location makes, by its hook or (for plain towns) the land around it.
const MAKES_HOOK := {"lake": ["water"], "dam": ["water", "tech"], "salt flat": ["salt"], "crater rim": ["glass"],
	"canyon": ["copper"], "wetlands": ["produce"], "mall": ["tech"], "prison": ["copper", "fuel"], "stadium": ["produce", "fuel"]}
const MAKES_BIOME := {"farm": ["produce"], "woods": ["produce"], "waste": ["fuel"], "salt": ["salt"], "canyon": ["copper"],
	"crater": ["glass"], "marsh": ["produce"], "hills": ["copper"], "water": ["water"], "beach": ["water", "salt"],
	"suburb": ["tech"], "city": ["tech"]}

static func _h(s: String, k: String) -> float:
	return float(absi(hash(s + "|" + k)) % 1000) / 1000.0

## {good: {"buy": price you pay, "sell": price you get, "made": bool, "wanted": bool}}
static func market(w: World, si: int) -> Dictionary:
	var st: World.Settlement = w.settlements[si]
	var key: String = st.id if st.id != "" else st.name + str(st.pos.round())
	var bn := w.biome_name(st.pos)
	var makes: Array = MAKES_HOOK.get(st.hook, MAKES_BIOME.get(bn, []))
	if st.small: makes = []
	var out := {}
	for g in GOODS:
		var base: float = Items.info(g).value
		var f := 1.0
		var made: bool = g in makes
		var wanted := false
		if made: f = 0.5
		else:
			if g == "water" and bn in ARID: f = 1.9; wanted = true
			elif g == "produce" and bn in ["city", "suburb", "salt", "canyon", "crater"]: f = 1.6; wanted = true
			elif g == "fuel" and st.hook in ["dam", "mall", "stadium", "prison"]: f = 1.5; wanted = true
			elif g == "tech" and not st.small: f = 1.25
			elif _h(key, g) > 0.72: f = 1.45; wanted = true
		f *= 0.88 + _h(key, g + "x") * 0.24
		var buy := maxi(1, int(round(base * f)))
		var sell := maxi(1, int(round(base * f * 0.8)))
		if st.small:
			sell = maxi(1, int(round(base * 0.7)))
			buy = maxi(1, int(round(base * 1.3)))
		out[g] = {"buy": buy, "sell": sell, "made": made, "wanted": wanted, "stock": made or st.small and g in ["water", "produce"]}
	return out

## One line for the map card: what's cheap and what pays here.
static func summary(w: World, loc_id: String) -> String:
	for i in w.settlements.size():
		if w.settlements[i].id == loc_id:
			var m := market(w, i)
			var cheap := []
			var pays := []
			for g in m:
				if m[g].made: cheap.append("%s %d" % [Items.iname(g), m[g].buy])
				if m[g].wanted: pays.append("%s %d" % [Items.iname(g), m[g].sell])
			var s := ""
			if cheap.size(): s += "Sells cheap: " + ", ".join(cheap)
			if pays.size(): s += ("\n" if s != "" else "") + "Pays well: " + ", ".join(pays)
			return s
	return ""
