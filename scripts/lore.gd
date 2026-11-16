class_name Lore
## Words for the world: notes and holotape transcripts found in containers, the stories told by
## scenes left where they happened, what people say as you pass, and the Sable Radio DJ.
## All original writing for the Sable Wastes.

# ------------------------------------------------------------------ notes (found in loot)
const NOTES := [
	["Shopping list, crossed out", "Milk. Bread. Batteries (D). Sandbags??\nCall Mom back.\n\n(The last line is written much harder than the rest.)"],
	["Note pinned to a fridge", "Kids — if you get home before us, go straight to the Founders Bridge shelter. Don't wait. Don't pack. We love you. Dad."],
	["Port Sterling Transit notice", "Due to the emergency, all Line 4 service to Clearwater is suspended until further notice. Sterling Transit thanks you for your patience."],
	["Water ration card", "HOLDER: M. OKAFOR — 2 GAL/WEEK\nPunched eleven times. The twelfth square is torn."],
	["Torn diary page", "Day 40. Lake still glows at night but Ruth says the purifier works if you run it twice. Tastes like pennies. Better than the river.\nDay 41. Ruth's sick."],
	["Raider tally", "Scratched into a board:\nCARAVANS ||||  ||||  ||\nSETTLERS ||||  |\nUS |||\n\n(the last row has been scratched out and rewritten three times)"],
	["Kid's drawing", "Crayon: a house, a dog, three stick people and a big orange sun. Someone has added a mushroom cloud in pencil, small, in the corner. Then tried to rub it out."],
	["Holotape: Ridgeback Dam log", "\"Turbine two is spinning again. We could light half of Port Sterling if there was a Port Sterling left to light. Logging this for whoever comes next — the manual override is behind the blue door. Don't let the raiders find it.\""],
	["Letter, unsent", "Dear Ellie, the salt flats are bigger than they look on the map. Three days walking and the horizon hasn't moved. The traders at Bonewhite say water's worth more than bullets out here. I believe them now."],
	["Greenmarsh planting guide", "GLOWBERRIES: plant at the fen's edge, not in it. POTATOES: anywhere the dog won't dig. CORN: gave up. Never plant near the old drainage pipe — things live in there."],
	["Atomic Plaza store directory", "LEVEL 1: Food Court, Pharmacy, Atomic Toys\nLEVEL 2: Fashions, Electronics, Fallout Shelter (Staff Only)\n\nSomeone has circled 'Fallout Shelter' and written: NOT ENOUGH ROOM. THEY LOCKED IT."],
	["Iron Gate inmate letter", "They opened the cells when the sirens went. Warden said we were free. Free to what? Half of us stayed. It's the only place out here with walls."],
	["Prospector's map scrap", "A rough sketch of the red canyons. An X marked 'copper — LOTS'. Another X marked 'DON'T'."],
	["Fortune from a cookie", "\"A great journey lies ahead of you.\"\nOn the back, in pen: no kidding."],
	["Mercy General memo", "To all staff: the generator will fail at approximately 03:00. Prioritise patients by likelihood of survival. I am sorry. — Dr. A. Venn"],
	["Diner order pad", "Table 4: 2x Atomic Burger, 1x coffee (black), 1x cherry pie. Paid? \n\nThey never came back for the pie."],
	["Holotape: Starwatch Observatory", "\"The flashes started at 9:41. I counted fourteen. I've been looking at the sky my whole life and I've never seen it look back.\""],
	["Militia flyer", "THE WASTES BELONG TO THE PEOPLE WHO WORK THEM. Join the Patchwork Watch. Three meals, a rifle, a roof. Ask for Mags at the gate."],
	["Bottle cap collector's note", "Sterling Cola red: 4. Dusty Root Beer: 11. Gold star: 0. Still looking. They say there's a whole case of gold stars in the Victory Stadium concessions."],
	["Water-runner's ledger", "Clearwater → Rimtown: bought 10 water @ 3, sold @ 11. Lost one to a shellback. Still worth it. Next run take the dog."],
	["Church bulletin, Our Lady of the Wastes", "Sunday: soup and blessing. All are welcome — ghouls included. Especially ghouls. They need it more than most of us."],
	["Holotape: Sable Radio, first broadcast", "\"...if you can hear this, you're not alone. This is Sable Radio. We've got records, a generator and nowhere to be. Stay tuned.\""],
	["Rattlebone recruitment slip", "WANTED: shooters, drivers, people who don't ask questions. Pay: whatever you can carry. Apply at the Rattlebone camp. Bring your own gun."],
	["Motel guest book", "Room 6 — \"Lovely stay, will return!\" (1 day before)\nRoom 2 — \"lock your doors\"\nRoom 2 — \"LOCK YOUR DOORS\""],
	["Scav's warning", "Chalk on a wall: GHOULS IN BASEMENT. TOOK MY BROTHER. DON'T GO DOWN THERE. → → →"],
	["Drive-in flyer", "MOONBEAM DRIVE-IN — DOUBLE FEATURE FRIDAY! \"Attack of the Atomic Ants\" + \"Love Among the Ruins\". Bring the whole family!"],
]

# ------------------------------------------------------------------ vignettes (scenes in the wilds)
## [title, text, props] — props are decor names placed around the spot.
const VIGNETTES := [
	["Two skeletons by a cold fire", "They were sharing the last can. It's still between them, unopened.", ["bones", "bones", "campfire_decor"]],
	["A car that didn't make it", "Keys in the ignition. A suitcase on the back seat, packed neatly. A road map with the route to the coast traced in red.", ["car", "bones", "trashbag"]],
	["A last stand", "Spent shell casings in a ring around the barrels. Whoever stood here held out a long time.", ["barrel_rust", "barrel_rust", "jersey_x", "bones"]],
	["A grave with a helmet on it", "A rifle stuck in the dirt, a helmet on top. Scratched on the stock: 'He stayed so we could go.'", ["post", "bones"]],
	["A picnic, interrupted", "A blanket, a basket, plates set for four. The plates are still set.", ["bones", "papers", "tire"]],
	["A shrine of bottle caps", "Hundreds of caps pressed into the dirt in a spiral. Someone tends this. The caps are clean.", ["rubble2", "papers"]],
	["The doghouse", "A small doghouse with a name painted over the door: DUKE. The bowl is full of water. Fresh.", ["bones", "barrel"]],
	["A wrecked caravan", "Ox bones still in harness. The cargo's long gone, but someone missed a crate under the axle.", ["bones", "bones", "car"]],
	["A message in stones", "Stones laid out large enough to read from the sky: HELP. Under it, smaller and newer: NOBODY CAME.", ["rubble1", "rubble1", "rubble2"]],
	["A scavenger's sleeping spot", "A bedroll tucked under a sheet of tin, a tin cup, a book with the last pages torn out for kindling.", ["trashbag", "papers"]],
]

# ------------------------------------------------------------------ barks
const BARKS := {
	"settler": ["Morning. Or whatever it is.", "Watch yourself past the fence.", "Water's clean today. Mostly.", "You're new. Don't stay new.", "Saw lights over the ridge last night.", "Trader's got fresh stock, if you've got scrap.", "Keep your gun where I can see it.", "Rain's coming. Can smell it."],
	"guard": ["Keep moving.", "No trouble in town.", "Raiders hit the east road again.", "I've got my eye on you.", "Quiet night. Too quiet."],
	"trader": ["Buying and selling!", "Best prices this side of the river.", "Got water? I've got caps... well, scrap.", "Come, look, everything works. Mostly."],
	"raider": ["Fresh meat!", "Get 'em!", "That's ours!", "You picked the wrong road!", "Over here!"],
	"raider_friend": ["Hey, it's one of ours.", "Good hunting out there.", "Bring us something shiny.", "Watch the ghouls downtown."],
	"wanderer": ["Long road.", "Don't drink from the river.", "They say Rimtown pays a fortune for water.", "Seen a two-headed ox? Lost mine."],
}

static func bark(kind: String) -> String:
	var l: Array = BARKS.get(kind, [])
	return l[randi() % l.size()] if l.size() else ""

# ------------------------------------------------------------------ Sable Radio
const DJ_GENERIC := [
	"This is Sable Radio, coming to you from somewhere you'll never find. Here's a little something to walk to.",
	"Good evening, Wastes! It's your old pal Rusty on Sable Radio. Keep your water clean and your powder dry.",
	"Weather report: dust in the west, rain off the lake, and a chance of radiation. Same as yesterday.",
	"A reminder from Sable Radio: ghouls are people too. Usually slower people.",
	"Trader tip of the day: salt keeps meat, glass makes lenses, and water — well, water makes everything.",
	"Somebody out there keeps stealing the copper wire off my antenna. I know it's you, Gus.",
	"This next record survived the end of the world. Some say it shouldn't have. You decide.",
	"If you're hearing this, you made it another day. That's worth a song.",
]

static func dj_line(g) -> String:
	var opts: Array = DJ_GENERIC.duplicate()
	if g != null and g.world != null and g.player != null:
		if g.player.kills > 0:
			opts.append("Word on the wind says some wanderer's put down %d nasties out there. Remind me never to borrow anything from you." % g.player.kills)
		if g.world.discovered.size() > 2:
			opts.append("Our listeners report a traveller poking around %d corners of the Wastes. Curious one, aren't you?" % g.world.discovered.size())
		if g.origin().get("raider", false):
			opts.append("Port Sterling's raiders have a new face, I hear. Settlers, lock your doors. Raiders — please don't shoot my transmitter.")
		if g.weather != null and g.weather.kind == "rad":
			opts.append("RADSTORM WARNING. Get under a roof, folks. Yes, now. I'll wait.")
		var job: Dictionary = g.jobs[0] if g.jobs.size() > 0 else {}
		if not job.is_empty():
			opts.append("Heard somebody took a job: %s. Good luck out there, friend." % job.title.to_lower())
		# market tip
		var rich: Array = ["Rimtown", "Redwall", "Bonewhite Flats"]
		opts.append("Market news: thirsty folk in %s are paying top scrap for clean water." % rich[randi() % rich.size()])
	return opts[randi() % opts.size()]
