"""The Sundown Basin: every location on the world map, plus the roads and rail that link them.

Coordinates are normalised map space: x 0..1 west->east, y 0..0.75 north->south (4:3 map).
type: city | district | town | settlement | camp | landmark | dungeon
danger: 1 (safe) .. 5 (deadly)    size: suggested local map size in tiles (square)
"""

REGION = "The Sundown Basin"

L = [
    # ---------------------------------------------------------------- the start
    dict(id="haven_flats", name="Haven Flats", type="town", pos=(0.44, 0.445), biome="plains", faction="Settlers", danger=1, size=128,
         pitch="Where you start: a settlement of shacks and gardens beside the interstate, the ruins of Comet Junction just east."),
    dict(id="comet_junction", name="Comet Junction", type="landmark", pos=(0.495, 0.452), biome="ruins", faction="Ghouls", danger=2, size=96,
         pitch="A gutted crossroads town with the Orbit Diner and the Comet filling station; ghouls nest in the ruins."),
    # ---------------------------------------------------------------- New Halcyon, the dead city
    dict(id="halcyon_downtown", name="New Halcyon - Downtown", type="city", pos=(0.735, 0.415), biome="ruins", faction="Ghouls / Brotherhood of the Dial", danger=4, size=160,
         pitch="The bombed metropolis on the Kettle River: towers, barricaded avenues, City Hall and the Dial radio cult holding the Atlas Building."),
    dict(id="halcyon_docks", name="Halcyon Docks", type="district", pos=(0.705, 0.462), biome="ruins", faction="River traders", danger=3, size=128,
         pitch="Warehouses and rusting barges; river traders run a fortified market on a beached ferry."),
    dict(id="halcyon_heights", name="Halcyon Heights", type="district", pos=(0.79, 0.37), biome="suburbs", faction="Scavengers", danger=2, size=128,
         pitch="Endless cul-de-sacs of picked-over houses; scavenger families and feral dogs."),
    dict(id="halcyon_general", name="Halcyon General Hospital", type="dungeon", pos=(0.757, 0.445), biome="ruins", faction="Ghouls", danger=4, size=96,
         pitch="Eight storeys of ghouls; the pharmacy vault on the top floor is still sealed."),
    dict(id="halcyon_stadium", name="Halcyon Stadium", type="landmark", pos=(0.765, 0.398), biome="ruins", faction="Raiders (Pit Kings)", danger=3, size=96,
         pitch="Raiders run fight nights in the collapsed bowl; win and you're a legend, lose and you're dinner."),
    dict(id="big_sky_mall", name="Big Sky Mall", type="dungeon", pos=(0.808, 0.342), biome="suburbs", faction="Raiders", danger=3, size=128,
         pitch="The shopping mall with the run-down parking lot; raiders hold the department store, rats the food court."),
    dict(id="halcyon_railyard", name="Halcyon Rail Yard", type="landmark", pos=(0.7, 0.372), biome="industrial", faction="none", danger=2, size=96,
         pitch="Freight cars in rows; one locomotive still has fuel."),
    dict(id="halcyon_airfield", name="Halcyon Airfield", type="landmark", pos=(0.825, 0.475), biome="plains", faction="Robots", danger=3, size=128,
         pitch="Crashed bombers on a cracked runway, guarded by security robots that never got the stand-down order."),
    # ---------------------------------------------------------------- towns
    dict(id="millbrook", name="Millbrook", type="town", pos=(0.4, 0.29), biome="farmland", faction="Farmers' Grange", danger=1, size=128,
         pitch="The breadbasket: a farming town on the river with a grain elevator, a mill and a weekly market."),
    dict(id="cedar_falls", name="Cedar Falls", type="town", pos=(0.255, 0.155), biome="forest", faction="Loggers", danger=2, size=128,
         pitch="A lumber town at the falls; the sawmill still runs on the water wheel."),
    dict(id="prospect", name="Prospect", type="town", pos=(0.205, 0.545), biome="badlands", faction="Mine Company", danger=2, size=128,
         pitch="A mining boomtown at the foot of the mountains; saloon, assay office, company scrip."),
    dict(id="dustwater", name="Dustwater", type="town", pos=(0.505, 0.618), biome="desert", faction="Water Barons", danger=2, size=128,
         pitch="A desert town built around the last deep well; the Water Barons sell every drop."),
    dict(id="lakeview", name="Lakeview", type="town", pos=(0.79, 0.598), biome="lakeshore", faction="Fishers", danger=1, size=96,
         pitch="A lakeside resort town turned fishing village on the reservoir."),
    dict(id="harmony_ridge", name="Harmony Ridge", type="settlement", pos=(0.885, 0.215), biome="hills", faction="Children of the Sun", danger=2, size=96,
         pitch="A commune on the hill that worships the bomb's light; friendly, a little too friendly."),
    dict(id="gallows_pass", name="Gallows Pass", type="settlement", pos=(0.115, 0.445), biome="mountains", faction="Toll Raiders", danger=3, size=96,
         pitch="The only road through the mountains, and the raiders who charge for it."),
    dict(id="fort_liberty", name="Fort Liberty", type="town", pos=(0.305, 0.675), biome="desert", faction="Liberty Remnant (army)", danger=3, size=160,
         pitch="A pre-war army base held by the descendants of its garrison; strict, well armed, recruiting."),
    # ---------------------------------------------------------------- settlements, camps, traders
    dict(id="st_agnes", name="St. Agnes Mission", type="settlement", pos=(0.605, 0.3), biome="plains", faction="Sisters of St. Agnes", danger=1, size=64,
         pitch="Nuns run a clinic in an old adobe mission; they heal anyone who disarms at the gate."),
    dict(id="tumbleweed_stop", name="Tumbleweed Truck Stop", type="settlement", pos=(0.615, 0.468), biome="plains", faction="Caravaneers", danger=1, size=64,
         pitch="Caravans park their brahmin wagons by the old diesel pumps; best rumours in the basin."),
    dict(id="rustys_junkyard", name="Rusty's Junkyard", type="settlement", pos=(0.548, 0.508), biome="plains", faction="Rusty", danger=1, size=64,
         pitch="Rusty buys and sells anything metal; his dogs keep the peace."),
    dict(id="copper_kettle", name="Copper Kettle Landing", type="settlement", pos=(0.565, 0.365), biome="river", faction="River traders", danger=1, size=64,
         pitch="A riverboat trading post on stilts; ferries cross here since the bridges fell."),
    dict(id="ranger_station", name="Ranger Station 7", type="settlement", pos=(0.455, 0.1), biome="forest", faction="Pine Rangers", danger=2, size=64,
         pitch="Forest rangers who still patrol, still fight fires, still hand out maps."),
    dict(id="sundial_ranch", name="Sundial Ranch", type="settlement", pos=(0.355, 0.505), biome="plains", faction="Ranchers", danger=1, size=96,
         pitch="A cattle ranch on the open range; always hiring hands to guard the herd from brutes."),
    dict(id="cottonwood_motel", name="Cottonwood Motor Court", type="camp", pos=(0.318, 0.452), biome="plains", faction="Drifters", danger=2, size=64,
         pitch="A neon-signed motel strip on the interstate; drifters rent rooms, nobody asks questions."),
    dict(id="thunder_mesa", name="Thunder Mesa", type="settlement", pos=(0.585, 0.695), biome="desert", faction="Mesa Clans", danger=2, size=96,
         pitch="Scavenger clans living in cliff dwellings cut into a mesa; they trade in salt and glass."),
    # ---------------------------------------------------------------- landmarks
    dict(id="hollister_dam", name="Hollister Dam", type="landmark", pos=(0.86, 0.69), biome="lakeshore", faction="contested", danger=3, size=128,
         pitch="The dam still makes power; whoever holds the turbine hall lights the basin."),
    dict(id="the_glow", name="The Glow", type="dungeon", pos=(0.625, 0.595), biome="crater", faction="none", danger=5, size=96,
         pitch="The bomb's crater, still glowing green; something valuable waits at the bottom for anyone who can survive it."),
    dict(id="bright_flats", name="Bright Flats", type="landmark", pos=(0.445, 0.695), biome="salt", faction="none", danger=2, size=128,
         pitch="A blinding salt pan; rocket-car test track and the wreck of an atomic land-speed racer."),
    dict(id="shelter_17", name="Civil Defense Shelter No. 17", type="dungeon", pos=(0.315, 0.35), biome="hills", faction="unknown", danger=3, size=96,
         pitch="A sealed bomb shelter in the hills; the door opens for the first time in 80 years."),
    dict(id="kettle_point", name="Kettle Point Nuclear Plant", type="dungeon", pos=(0.66, 0.315), biome="river", faction="Ghouls", danger=4, size=128,
         pitch="Cooling towers on the river; the reactor is cold, the ghouls inside are not."),
    dict(id="starlight_drivein", name="Starlight Drive-In", type="landmark", pos=(0.53, 0.405), biome="plains", faction="Raiders", danger=2, size=96,
         pitch="Raiders project scratched reels on the giant screen on Saturday nights."),
    dict(id="silver_vein", name="Silver Vein Mine", type="dungeon", pos=(0.145, 0.615), biome="mountains", faction="Mole rats", danger=3, size=96,
         pitch="Deep shafts under the mountains; the miners dug too far."),
    dict(id="red_canyon", name="Red Canyon - the Bonepile", type="dungeon", pos=(0.245, 0.62), biome="badlands", faction="Raiders (Bonepile Gang)", danger=4, size=128,
         pitch="The raiders' stronghold in a red sandstone canyon, decorated with what's left of their enemies."),
    dict(id="ironback_tunnel", name="Ironback Tunnel", type="dungeon", pos=(0.155, 0.325), biome="mountains", faction="Shellbacks", danger=3, size=96,
         pitch="A two-mile rail tunnel through the mountains; derailed trains and shellback nests in the dark."),
    dict(id="kettle_bridge", name="Kettle River Bridge", type="landmark", pos=(0.665, 0.448), biome="river", faction="Toll raiders", danger=2, size=96,
         pitch="The broken interstate bridge; a plank walkway across the gap and a toll gang at each end."),
    dict(id="blackwood_pen", name="Blackwood Penitentiary", type="dungeon", pos=(0.375, 0.185), biome="forest", faction="Raiders (the Cons)", danger=4, size=128,
         pitch="The prison where the inmates won; now a raider fortress with its own rules."),
    dict(id="mount_vigil", name="Mount Vigil Observatory", type="landmark", pos=(0.075, 0.24), biome="mountains", faction="Stargazers", danger=2, size=64,
         pitch="A domed observatory on the peak; two old astronomers still chart the satellites."),
    dict(id="radio_kbsn", name="Radio KBSN", type="landmark", pos=(0.575, 0.215), biome="plains", faction="DJ Lucky Larry", danger=1, size=64,
         pitch="The basin's only radio station; Lucky Larry plays records and reads the news you bring him."),
    dict(id="black_gulch", name="Black Gulch Refinery", type="dungeon", pos=(0.705, 0.665), biome="desert", faction="Raiders / fuel cult", danger=4, size=128,
         pitch="Oil derricks and a burning refinery; whoever runs it controls the basin's fuel."),
    dict(id="silo_delta9", name="Missile Silo Delta-9", type="dungeon", pos=(0.375, 0.6), biome="desert", faction="Robots", danger=5, size=96,
         pitch="One missile was never launched. The silo's robots are still waiting for orders."),
    dict(id="starliner_wreck", name="Wreck of the Starliner", type="landmark", pos=(0.265, 0.485), biome="plains", faction="none", danger=2, size=64,
         pitch="A crashed atomic airliner in a field; the cargo hold was never found."),
    dict(id="paradise_lake", name="Paradise Lake Summer Camp", type="dungeon", pos=(0.555, 0.11), biome="forest", faction="unknown", danger=3, size=96,
         pitch="Cabins on a forest lake; the campers never went home."),
    dict(id="whitestone_quarry", name="Whitestone Quarry", type="landmark", pos=(0.215, 0.39), biome="hills", faction="Scavengers", danger=2, size=96,
         pitch="A flooded quarry with rusting machinery; good stone, bad water."),
    dict(id="fire_lookout", name="Pinewood Fire Lookout", type="landmark", pos=(0.665, 0.13), biome="forest", faction="Hermit", danger=1, size=64,
         pitch="A lookout tower above the trees; the hermit inside sees everything that moves in the forest."),
    dict(id="little_eden", name="Little Eden", type="landmark", pos=(0.095, 0.52), biome="mountains", faction="none", danger=3, size=96,
         pitch="A ghost town in a mountain hollow; the church bell still rings at midnight."),
    dict(id="helios_labs", name="Helios Laboratories", type="dungeon", pos=(0.915, 0.31), biome="hills", faction="Robots / scientists", danger=4, size=128,
         pitch="A pre-war research campus in the eastern hills; the experiments got out."),
    dict(id="sawtooth_camp", name="Sawtooth Raider Camp", type="camp", pos=(0.47, 0.545), biome="plains", faction="Raiders", danger=3, size=64,
         pitch="A raider camp on the plateau south of Haven Flats; they raid the interstate."),
]

# Routes: (kind, [location ids or (x, y) waypoints])
#   interstate: wide paved; highway: two-lane; road: local; track: dirt; rail: railway
ROUTES = [
    ("interstate", [(0.0, 0.448), "gallows_pass", (0.2, 0.455), "cottonwood_motel", "haven_flats", "comet_junction",
                    "tumbleweed_stop", "kettle_bridge", "halcyon_docks", (0.8, 0.455), "halcyon_airfield", (1.0, 0.47)]),
    ("highway", [(0.56, 0.0), (0.565, 0.1), "radio_kbsn", "st_agnes", (0.6, 0.38), "tumbleweed_stop", "rustys_junkyard",
                 (0.545, 0.58), "dustwater", "thunder_mesa", (0.6, 0.75)]),
    ("highway", ["haven_flats", "sundial_ranch", (0.3, 0.57), "fort_liberty", (0.29, 0.75)]),
    ("highway", ["halcyon_downtown", (0.77, 0.5), (0.78, 0.56), "lakeview", "hollister_dam", (0.9, 0.75)]),
    ("highway", ["halcyon_heights", "harmony_ridge", (1.0, 0.18)]),
    ("road", ["haven_flats", (0.42, 0.37), "millbrook", (0.33, 0.22), "cedar_falls"]),
    ("road", ["millbrook", "copper_kettle", (0.62, 0.36), "halcyon_railyard", "halcyon_downtown"]),
    ("road", ["cedar_falls", "blackwood_pen", "ranger_station", "paradise_lake", "fire_lookout", (0.75, 0.2), "halcyon_heights"]),
    ("road", ["prospect", (0.18, 0.5), "gallows_pass"]),
    ("road", ["prospect", "red_canyon"]),
    ("road", ["dustwater", "bright_flats"]),
    ("road", ["dustwater", (0.6, 0.64), "black_gulch", (0.78, 0.66), "hollister_dam"]),
    ("road", ["halcyon_heights", "big_sky_mall"]),
    ("road", ["halcyon_downtown", "halcyon_stadium", "halcyon_heights"]),
    ("road", ["kettle_point", "st_agnes"]),
    ("road", ["helios_labs", (0.86, 0.33), "big_sky_mall"]),
    ("track", ["haven_flats", "sawtooth_camp"]),
    ("track", ["comet_junction", "starlight_drivein", "copper_kettle"]),
    ("track", ["prospect", "silver_vein"]),
    ("track", ["gallows_pass", "little_eden"]),
    ("track", ["cottonwood_motel", "starliner_wreck"]),
    ("track", ["sundial_ranch", "silo_delta9", "bright_flats"]),
    ("track", ["millbrook", "shelter_17", "whitestone_quarry", "ironback_tunnel"]),
    ("track", ["mount_vigil", (0.1, 0.3), "ironback_tunnel"]),
    ("track", ["dustwater", "the_glow"]),
    ("rail", [(0.0, 0.34), "ironback_tunnel", "whitestone_quarry", (0.3, 0.33), (0.45, 0.335), (0.56, 0.345), (0.64, 0.355), "halcyon_railyard", (0.8, 0.395), (1.0, 0.4)]),
    ("rail", [(0.3, 0.33), (0.31, 0.5), (0.31, 0.62), "fort_liberty"]),
]

# Kettle River: from the north-west mountains through the plains and the city into the reservoir.
RIVER = [(0.165, 0.09), (0.22, 0.13), (0.26, 0.16), (0.31, 0.22), (0.38, 0.27), (0.45, 0.31), (0.52, 0.35),
         (0.57, 0.362), (0.63, 0.38), (0.68, 0.41), (0.69, 0.445), (0.705, 0.48), (0.74, 0.52), (0.77, 0.565), (0.8, 0.6)]
RIVER_OUT = [(0.865, 0.695), (0.88, 0.72), (0.9, 0.75)]
LAKE = dict(center=(0.825, 0.635), rx=0.05, ry=0.042)
LAKES_SMALL = [((0.555, 0.105), 0.016), ((0.29, 0.1), 0.012), ((0.215, 0.39), 0.008), ((0.66, 0.06), 0.014)]
CITY = dict(center=(0.745, 0.415), r=0.07)        # dense ruins
SUBURBS = [((0.8, 0.355), 0.045), ((0.72, 0.36), 0.03), ((0.7, 0.47), 0.03)]
CRATER = dict(center=(0.625, 0.595), r=0.028)
SALT = dict(center=(0.445, 0.69), rx=0.07, ry=0.04)

# painted landform names: (text, x, y, font size, rotation deg)
FEATURES = [
    ("IRON SPINE MOUNTAINS", 0.085, 0.36, 22, 80),
    ("PINEWOOD FOREST", 0.38, 0.06, 22, 0),
    ("Kettle River", 0.47, 0.335, 16, -24),
    ("OCHRE DESERT", 0.36, 0.735, 22, 0),
    ("Lake Mercy", 0.83, 0.64, 16, 0),
    ("Red Canyon Badlands", 0.25, 0.58, 14, -48),
    ("The Plains", 0.42, 0.52, 18, 0),
    ("Sunrise Hills", 0.89, 0.27, 15, 0),
]
