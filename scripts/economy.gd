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

## Where each good is made (world positions of the towns that make it), for distance pricing.
static var _makers := {}
static var _makers_world: World = null

static func makes_at(w: World, hook: String, pos: Vector2) -> Array:
	return MAKES_HOOK.get(hook, MAKES_BIOME.get(w.biome_name(pos), []))

static func _maker_dist(w: World, good: String, pos: Vector2) -> float:
	if _makers_world != w:
		_makers_world = w
		_makers = {}
		for l in w.locs:
			if not (l.type in ["town", "hub", "settlement", "camp"]): continue
			for g in makes_at(w, l.hook, l.pos):
				if not _makers.has(g): _makers[g] = []
				_makers[g].append(l.pos)
	var best := 2000.0
	for p in _makers.get(good, []):
		best = minf(best, pos.distance_to(p))
	return best

const PURSE := {"hub": 420, "town": 260, "settlement": 180, "camp": 140}

## Base prices before the player's own trading moves them:
## {good: {"buy", "sell", "made", "wanted", "stock"}}. Goods are cheap where they're made and fetch
## more the further you are from anywhere that makes them (so long, dangerous hauls pay best).
static func market(w: World, si: int) -> Dictionary:
	var st: World.Settlement = w.settlements[si]
	var key: String = st.id if st.id != "" else st.name + str(st.pos.round())
	var bn := w.biome_name(st.pos)
	var makes: Array = makes_at(w, st.hook, st.pos)
	if st.small: makes = []
	var out := {}
	for g in GOODS:
		var v: float = Items.info(g).value
		var made: bool = g in makes
		var wanted := false
		var buy: float
		var sell: float
		var jitter := 0.9 + _h(key, g + "x") * 0.2
		if made:
			buy = v * 0.6 * jitter
			sell = v * 0.45 * jitter
		else:
			var df := clampf(_maker_dist(w, g, st.pos) / 700.0, 0.0, 1.0)
			var want := 1.0
			if g == "water" and bn in ARID: want = 1.25; wanted = true
			elif g == "produce" and bn in ["city", "suburb", "salt", "canyon", "crater"]: want = 1.2; wanted = true
			elif g == "fuel" and st.hook in ["dam", "mall", "stadium", "prison"]: want = 1.2; wanted = true
			elif _h(key, g) > 0.8: want = 1.15; wanted = true
			sell = v * (0.7 + 0.9 * df) * want * jitter
			buy = v * 1.35 * jitter
		if st.small:
			sell = minf(sell, v * 0.75)
			buy = v * 1.3
		out[g] = {"buy": maxi(1, int(round(buy))), "sell": maxi(1, int(round(sell))), "made": made, "wanted": wanted,
			"stock": made or (st.small and g in ["water", "produce"])}
	return out

# ------------------------------------------------------------------ the player's effect on markets
## econ = {"sat": {"si|good": [sold_minus_bought, day]}, "purse": {si: [scrap, day]}, "stock": {"si|good": [units, day]}}
## Selling floods a market (each unit sold drops that town's price 3%, down to 40%); buying drains it
## (each unit bought raises the price 3%, up to +60%). Both drift back over a day or two. Traders
## have a purse that refills daily, and only so many units of what they make.
const SAT_TAU := 0.7            # days for saturation to fall to ~37%

static func _sat(econ: Dictionary, si: int, g: String, now: float) -> float:
	var k := "%d|%s" % [si, g]
	var e = econ.sat.get(k)
	if e == null: return 0.0
	var s: float = float(e[0]) * exp(-(now - float(e[1])) / SAT_TAU)
	econ.sat[k] = [s, now]
	return s

static func sell_price(econ: Dictionary, si: int, g: String, base: int, now: float, k: int = 0) -> int:
	var s := maxf(0.0, _sat(econ, si, g, now)) + k
	return maxi(1, int(round(base * maxf(0.4, pow(0.97, s)))))

static func buy_price(econ: Dictionary, si: int, g: String, base: int, now: float, k: int = 0) -> int:
	var s := maxf(0.0, -_sat(econ, si, g, now)) + k
	return maxi(1, int(round(base * minf(1.6, pow(1.03, s)))))

static func add_sat(econ: Dictionary, si: int, g: String, n: float, now: float) -> void:
	var s := _sat(econ, si, g, now) + n
	econ.sat["%d|%s" % [si, g]] = [s, now]

static func purse_cap(w: World, si: int) -> int:
	var st: World.Settlement = w.settlements[si]
	if st.small: return 70
	var l := w.loc_by_id(st.id)
	return PURSE.get(l.get("type", "town"), 200)

static func purse(econ: Dictionary, w: World, si: int, now: float) -> int:
	var cap := purse_cap(w, si)
	var e = econ.purse.get(str(si))
	if e == null: return cap
	var v: float = minf(cap, float(e[0]) + cap * (now - float(e[1])))      # refills in a day
	econ.purse[str(si)] = [v, now]
	return int(v)

static func spend_purse(econ: Dictionary, w: World, si: int, n: int, now: float) -> void:
	econ.purse[str(si)] = [purse(econ, w, si, now) + n, now]

static func stock_cap(w: World, si: int) -> int:
	return 12 if w.settlements[si].small else 25

static func stock(econ: Dictionary, w: World, si: int, g: String, now: float) -> int:
	var cap := stock_cap(w, si)
	var k := "%d|%s" % [si, g]
	var e = econ.stock.get(k)
	if e == null: return cap
	var v: float = minf(cap, float(e[0]) + cap * (now - float(e[1])))
	econ.stock[k] = [v, now]
	return int(v)

static func take_stock(econ: Dictionary, w: World, si: int, g: String, n: int, now: float) -> void:
	econ.stock["%d|%s" % [si, g]] = [stock(econ, w, si, g, now) - n, now]

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
