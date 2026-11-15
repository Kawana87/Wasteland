# The Sable Wastes — location master list

A fictional 50s atomic-age wasteland of 50 locations, laid out after Fallout 3's Capital Wasteland. The map, its data and its generator are in the repo:
- `tools/worldmap/locations.py`: every location, its position and the landform names; edit here.
- `tools/worldmap/layout_fo3.py`: the flat layout map. `tools/worldmap/paint_fo3.py`: the painted map (`assets/worldmap/worldmap.png`, `locations.json`).
- `tools/worldmap/make_docs.py`: rewrites this list.

**Geography:**
- The Sable River runs down the east side from Lake Winona and Ridgeback Dam; Port Sterling, the bombed city, sits on its east bank inside a beltway. South of the city the river spreads into the Sable Fens.
- The Gravel Hills fill the north-west and south-west; the Deadpine Woods and Goldenrod's farms are in the north.
- The Wastes fill the middle, with Bonewhite Flats, Scorch Canyon and the bomb crater (the Hollow Sun) in the south-west.

**Routes:**
- An interstate runs from Hangman's Gap through Patchwork and over Founders Bridge into the city.
- Highways fan out from the city to every corner; a metro line runs from Starlite Crossing to the Union Rail Yard.

**Major settlements** each grew out of the place they were built in, and each trades in what that place gives them. Plainer towns sit in between.

Danger levels: 1 safe … 5 deadly. Each location's map size is in tiles, and every location gets its own map.

## Major settlements (9)

- **Victory Stadium**: A loud town in the bleachers of the collapsed stadium; shacks fill the stands, the field is a market by day and fight nights pack the bowl. Win in the ring and you're a legend. **Built on:** stadium. **Trades in:** entertainment, betting. *(danger 2 · the Stadium Bosses · 192×192 tiles · ruins)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Atomic Plaza**: A whole town living inside the giant mall: storefronts are homes and shops, the food court is the market, the department store is the council hall, and a wall of stacked cars rings the parking lot. **Built on:** mall. **Trades in:** everything (market town). *(danger 1 · the Plaza Merchants · 192×192 tiles · suburbs)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Clearwater**: Built around Lake Winona's old marina. Rows of solar stills, filter towers and cisterns turn lake water into the cleanest water in the Wastes; water caravans leave every morning and Clearwater's tokens are the closest thing to money. **Built on:** lake. **Trades in:** clean water. *(danger 1 · the Water Guild · 192×192 tiles · lakeshore)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Ridgeback Dam**: Engineers live inside the dam's galleries and keep two turbines spinning. They sell charged batteries and run power lines to anyone who pays, which makes them the richest people in the valley and the biggest target. **Built on:** dam. **Trades in:** electric power, batteries. *(danger 2 · the Turbine Guild · 160×160 tiles · lakeshore)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Bonewhite Flats**: Salt harvesters live in the hangars of an old rocket-car test track. They rake salt, cure meat for half the Wastes and race patched-up atomic cars on the flats every month. **Built on:** salt flat. **Trades in:** salt, preserved meat, racing. *(danger 2 · the Salt Riders · 160×160 tiles · salt)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Redwall**: A town carved into both walls of Scorch Canyon: cliff homes, rope bridges, cargo lifts and hanging gardens watered by a spring at the bottom. The only way in is the lift, so nobody has ever taken it. **Built on:** canyon. **Trades in:** stone, salt, defence. *(danger 1 · the Redwall Families · 192×192 tiles · badlands)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Iron Gate**: Guards' and inmates' grandchildren live together in the old penitentiary: cell blocks are apartments, the yard is a farm, the guard towers still watch. Strict laws, fair trials, and the best bounty board in the Wastes. **Built on:** prison. **Trades in:** law, bounties, labour. *(danger 2 · the Warden's Council · 192×192 tiles · forest)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Greenmarsh**: Stilt houses and boardwalks over the river marshes. The Co-op floods paddies, farms fish ponds and cranberry bogs, and feeds more people than anywhere else in the Wastes. Watch for gulpers in the reeds. **Built on:** wetlands. **Trades in:** food (rice, fish, cranberries). *(danger 1 · the Marsh Co-op · 192×192 tiles · wetland)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Rimtown**: Ghouls who don't mind the radiation live on the rim of the Hollow Sun and dig the fused glowing glass out of the crater; their glass lamps light homes across the Wastes. **Built on:** crater rim. **Trades in:** glowing glass, lamps. *(danger 2 · Ghoul glassworkers · 160×160 tiles · crater)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Cities (1)

- **Port Sterling - Downtown**: The bombed river city: towers, barricaded avenues, City Hall, and a radio cult holding the Atlas Building. *(danger 4 · Ghouls / the Signal cult · 160×160 tiles · ruins)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## City districts (Port Sterling) (2)

- **Sterling Waterfront**: Warehouses and rusting barges; river traders run a fortified market on a beached ferry. *(danger 3 · River traders · 128×128 tiles · ruins)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Maple Grove**: Endless cul-de-sacs of picked-over houses; scavenger families and feral dogs. *(danger 2 · Scavengers · 128×128 tiles · suburbs)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Towns (6)

- **Patchwork**: Where you start: a town of scrap shacks and gardens bolted together around an old motor court on the interstate. *(danger 1 · Settlers · 128×128 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Goldenrod**: The breadbasket: a farming town with a grain elevator, a mill and a weekly market. *(danger 1 · Farmers' Grange · 128×128 tiles · farmland)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Splinter Creek**: A lumber town on the creek; the sawmill still runs on the water wheel. *(danger 2 · Loggers · 128×128 tiles · forest)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Copperhead**: A mining town in the southern hills; saloon, assay office, company scrip. *(danger 2 · Mine Company · 128×128 tiles · badlands)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Wellspring**: A plain crossroads town where the southern roads meet: a deep well, a general store, a saloon and the safest bed in the south. *(danger 1 · Townsfolk · 128×128 tiles · desert)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Fort Steadfast**: A pre-war army base held by the grandchildren of its garrison; strict, well armed, recruiting. *(danger 3 · Steadfast Remnant (army) · 160×160 tiles · desert)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Settlements (8)

- **Sunbeam Commune**: A commune on the hill that worships the bomb's light; friendly, a little too friendly. *(danger 2 · Children of the Sun · 96×96 tiles · hills)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Hangman's Gap**: Where the interstate leaves the valley, and the raiders who charge for it. *(danger 3 · Toll raiders · 96×96 tiles · mountains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Our Lady of the Sands Mission**: Nuns run a clinic in an old adobe mission; they heal anyone who disarms at the gate. *(danger 1 · the Sisters · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Big Wheel Truck Stop**: Caravans park their brahmin wagons by the old diesel pumps; the best rumours in the valley. *(danger 1 · Caravaneers · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Gus's Salvage**: Gus buys and sells anything metal; his dogs keep the peace. *(danger 1 · Gus · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Ferryman's Landing**: A trading post on stilts; ferries cross here since the bridges fell. *(danger 1 · River traders · 64×64 tiles · river)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Lookout Station 3**: Rangers who still patrol the dead woods and hand out maps. *(danger 2 · Rangers · 64×64 tiles · forest)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Double-Bar Ranch**: A cattle ranch on the open range, always hiring hands to guard the herd from brutes. *(danger 1 · Ranchers · 96×96 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Camps (2)

- **Bluebird Motor Lodge**: A neon-signed motel on the interstate; drifters rent rooms, nobody asks questions. *(danger 2 · Drifters · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Rattlebone Camp**: A raider camp south of Patchwork that preys on the interstate. *(danger 3 · Raiders · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Landmarks (11)

- **Starlite Crossing**: A gutted crossroads town just east of Patchwork, with the Orbit Diner and a filling station; ghouls nest in the ruins. *(danger 2 · Ghouls · 96×96 tiles · ruins)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Union Rail Yard**: Freight cars in rows; one locomotive still has fuel. *(danger 2 · none · 96×96 tiles · industrial)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Sterling Municipal Airfield**: Crashed bombers on a cracked runway, guarded by robots that never got the stand-down order. *(danger 3 · Robots · 128×128 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Moonbeam Drive-In**: Raiders show scratched reels on the giant screen on Saturday nights. *(danger 2 · Raiders · 96×96 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Founders Bridge**: The broken interstate bridge into the city; a plank walkway across the gap and a toll gang at each end. *(danger 2 · Toll raiders · 96×96 tiles · river)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Starwatch Observatory**: A domed observatory on the highest hill; two old astronomers still chart the satellites. *(danger 2 · Stargazers · 64×64 tiles · mountains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Radio KZAP**: The valley's only radio station; Lucky Larry plays records and reads the news you bring him. *(danger 1 · DJ Lucky Larry · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Wreck of the Silver Comet**: A crashed atomic airliner in a field; the cargo hold was never found. *(danger 2 · none · 64×64 tiles · plains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Granite Bowl Quarry**: A flooded quarry with rusting machinery; good stone, bad water. *(danger 2 · Scavengers · 96×96 tiles · hills)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Owl's Perch Tower**: A fire tower above the dead trees; the hermit inside sees everything that moves. *(danger 1 · Hermit · 64×64 tiles · forest)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Hushwood**: A ghost town in a hollow; the church bell still rings at midnight. *(danger 3 · none · 96×96 tiles · mountains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Dungeons (11)

- **Mercy General Hospital**: Eight storeys of ghouls; the pharmacy vault on the top floor is still sealed. *(danger 4 · Ghouls · 96×96 tiles · ruins)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Buzzard Mesa - the Grinder**: The raiders' stronghold on top of a sheer mesa, decorated with what's left of their enemies; one switchback road up. *(danger 4 · Raiders (the Grinders) · 128×128 tiles · desert)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **The Hollow Sun**: The bomb's crater, still glowing; something valuable waits at the bottom for anyone who survives it. *(danger 5 · none · 96×96 tiles · crater)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Civil Defense Bunker Echo**: A sealed bomb shelter next door to Patchwork; the door opens for the first time in 80 years. *(danger 3 · unknown · 96×96 tiles · hills)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Bright Hope Power Station**: Cooling towers on the river; the reactor is cold, the ghouls inside are not. *(danger 4 · Ghouls · 128×128 tiles · river)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Deep Seven Mine**: Deep shafts under the hills; the miners dug too far. *(danger 3 · Mole rats · 96×96 tiles · mountains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Devil's Throat Tunnel**: A rail tunnel through the hills; derailed trains and shellback nests in the dark. *(danger 3 · Shellbacks · 96×96 tiles · mountains)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Blackrock Refinery**: Oil tanks and a burning refinery on the river; whoever runs it controls the fuel. *(danger 4 · Raiders / fuel cult · 128×128 tiles · desert)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Launch Site Zulu**: One missile was never launched. The silo's robots are still waiting for orders. *(danger 5 · Robots · 96×96 tiles · desert)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Camp Whispering Pines**: Cabins in the dead woods; the campers never went home. *(danger 3 · unknown · 96×96 tiles · forest)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters
- **Prometheus Research Center**: A pre-war research campus in the eastern hills; the experiments got out. *(danger 4 · Robots / scientists · 128×128 tiles · hills)*
  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters

## Random encounters

Encounters generate a small map matching the terrain where they happen, with a few variations each:
woods, plains, farmland, wasteland, wetland, salt flat, canyon, hills, river, ruins, and the edge of the Hollow Sun.
