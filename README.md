# Wasteland (working title)

An isometric post-apocalyptic survival game made in **Godot 4.7**: explore one big continuous wasteland,
the Sable Wastes, loot ruined buildings, dodge (or fight) raiders and mutants, trade goods between towns,
and build bases out in the wilds.

## Opening the project

**Android (Godot editor app)**
1. Install *Godot Engine 4* from the Play Store, and a Git client such as **MGit**.
2. In MGit, clone `https://github.com/Kawana87/Wasteland` (if the repo is private, sign in with your GitHub account).
   No Git client? On GitHub tap **Code → Download ZIP** and unzip it instead.
3. In Godot tap **Import**, pick the cloned folder's `project.godot`, then press ▶ (top right) to play.
4. To get updates later: **Pull** in MGit, then reopen the project in Godot.

**PC**
1. Install Godot 4.7 (standard, not .NET) and GitHub Desktop.
2. Clone the repo, open `project.godot` in Godot, press **F5**.

The first open takes a moment while Godot imports the sprites.

## Controls

| | PC | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick | Left thumb anywhere on the left half (stick base shown bottom-left) |
| Aim | Automatic lock-on, favouring what you face (AIM: assist button for full auto-aim) | | |
| Shoot | Left click / Q | RT | FIRE (hold) |
| Melee | F / right click | B | HIT |
| Jump | Space | A | — |
| Sneak (toggle) | C | Y | SNEAK |
| Use / chop / climb / stairs | E | X | USE |
| Camp menu | B | Back | CAMP |
| Inventory / gear | I or Tab | Start | INV |
| Quick heal (1.2 s, interrupted by moving or damage) | H | LB | HEAL |
| World map | M | | MAP |
| Fast travel (costs hours and food; raiders may ambush cargo) | T | | (from the camp menu) |
| CRT filter | V | | CRT button |

## What's in the game so far

- **Art:** 48×24 px tiles at a 576×324 pixel canvas (1.5× the original detail), shaded sprites with outlines,
  cast shadows and contact shadows on the ground, smooth curved roads with faded centre lines, and glowing neon,
  street lamps and fires at night.
- **Atomic-age town:** diners with checkerboard floors and rooftop neon, gas stations with canopies and pumps,
  L/U-shaped motels, pastel ranch houses, brick shops with awnings and signs, T/U-shaped municipal offices,
  sawtooth-roof factories, water towers, billboards, vending machines, phone booths, retro street lamps.
- **Doors:** front doors can be open, closed, locked, barricaded or boarded up. Pick locks quietly with lockpicks (it can fail and snap the pick), or bash doors in with melee attacks — loud enough to bring monsters running. Some houses are sealed and can't be entered.
- **Varied layouts:** buildings are made of several parts (L, T and U shapes) and can mix storeys,
  e.g. a two-storey house with a one-storey wing.

- **The Sable Wastes — one continuous world:** 2048×2048 tiles, about ten minutes to walk edge to edge, streamed in
  32×32-tile chunks as you go (nothing is generated until you get near it, and things stay as you left them). It is
  built from the world map itself: the same hills, woods, farms, fens, salt flats, red canyons, glass crater, Lake
  Winona, the Sable River and the ruins of Port Sterling, with the same roads (interstates, highways, roads and dirt
  tracks, on causeways over the water).
- **All 50 map locations are in the world:** towns and hubs with traders, settlers and their own speciality
  (purifiers by the lake, fields in the fens, salt pans, glass furnaces...), dungeons held by raiders or ghouls with
  good loot, and roadside landmarks. Port Sterling is built block by block on a street grid from the city density.
- **You never quite know what's out there:** small sites scattered through the wilds — raider-held gas stations,
  survivors round a campfire (sometimes with a trader), wrecked caravans, mutant nests, toxic spills, scavenger
  shacks — plus roaming encounters: raider gangs, mutant packs, travelling merchants, stashes glinting in the dirt.
- **Trade goods:** water, produce, salt, crater glass, copper wire, fuel and old-world tech. Every town makes something
  cheaply and pays well for what it lacks (dry country pays most for water). Buy low, haul it, sell high. The map card
  shows what each town sells cheap and pays well for.
- **Origins:** start as a Patchwork drifter, a Clearwater water-runner, an Iron Gate ex-con, a Redwall scavenger or a
  Greenmarsh farmhand — each starts somewhere different with its own upside and catch.
- **World map:** green CRT screen with your position, camps and every place you've discovered (get within
  sight of a place to put it on the map). Zoom in on yourself, and fast travel to anywhere you've found.
- **Sound:** every effect, ambient bed and radio tune is synthesised by `tools/audio/make_audio.py` — gunshots per weapon,
  footsteps on dirt and pavement, ghoul groans, raider shouts, doors, crates, coins, wind, night insects, town chatter,
  campfire crackle, rain and thunder.
- **Sable Radio:** toggle RADIO for four original lounge tunes and a DJ whose news reacts to what you've done.
- **Weather:** dust, rain and radstorms. In a radstorm the sky turns green, the Geiger counter crackles and you take
  radiation damage outside — get under a roof.
- **Compass:** top of the screen, centred on where you're facing: undiscovered places (hollow), found places, camps,
  your job target (amber) and enemies hunting you (red).
- **Jobs:** traders post work — deliveries, clearing out dungeons, bounties on named raider bosses, supply runs.
- **XP, levels and perks:** XP for discoveries, kills, jobs, cleared sites, notes and profitable trades; pick a perk
  each level (Toughness, Gunslinger, Silver Tongue, Strong Back, Rad Skin, ...).
- **Things to find:** notes and tapes in containers (read them again from the inventory), scenes in the wilds that
  tell a story when you look closer, people who talk as you pass. Discovering a place or clearing a dungeon gets a
  title card and a mark on the map.
- **Underground:** caves in the hills, mines in the canyons, manholes down into Port Sterling's sewers and old
  civil-defense shelters set into the rock. Each is its own map (dark, lantern-lit, built the same every time from
  its entrance), with creatures thickening toward a named boss guarding a hoard at the far end. Clear one out for a
  title card and XP; the ladder by the entrance takes you back up.
- **Saving:** the game autosaves (and saves when you leave the app); **Continue** on the title screen picks up where
  you left off — your gear, camps, stash, bases, discoveries, and what you've looted and killed.
- **Wasteland feel:** rubble, toxic spills, dead bushes, bones, crows that scatter when you get close, drifting dust, a washed-out colour grade and a day/night cycle (24 minutes per day).
- **Buildings:** houses, shops, offices, garages and shacks with furnished interiors (kitchens, beds, shelves, desks, counters). Some are ruined with collapsed corners. Pitched or flat roofs. Second floors show from outside. Buildings and trees go see-through when you walk behind them.
- **Settlements:** friendly tin-shack villages with a campfire, gardens, a water pump, settlers, cattle and a trader. Pay the trader in scrap for guns, armour, ammo and med kits, or sell spare gear.
- **Inventory and gear:** guns (pipe pistol, 10mm, SMG, shotgun, hunting rifle), melee weapons, head and body armour, ammo types, med kits and food. Every container rolls its own loot: fridges hold food, medicine cabinets hold med kits, gun lockers hold guns.
- **Creatures:** fewer of them, but tougher. Ghouls lurk in ruins. Brutes throw rocks and hit hard. Shellbacks guard toxic spills and shrug off weak hits. Rats live indoors. Raiders carry real guns and drop them.
- **Raider camps on plateaus:** walk up the ramp or climb the rope round the back. Clear them out for their stash.
- **Awareness system:** `?` = suspicious, `!` = hunting you. Closeness, searching and gunfire make noise. Sneak to get close, then melee an unaware enemy for a silent takedown (brutes take triple damage instead).
- **Camps:** set up to 4 camps anywhere (4 wood + 2 scrap). They share one stash and have per-camp upgrades. Fast travel between them when nothing is hunting you. Going down sends you to the nearest camp.
- **Survivors** hide in city buildings. Recruit them and they bring back scrap and wood.
- Optional **CRT filter**, saved between sessions.

## Project layout

```
project.godot          Godot project settings (Compatibility renderer, works on phones)
scenes/main.tscn       Entry scene (just the Game node)
scripts/
  game_base.gd         All game state (members, constants, origins); the chain below extends it
  game_world.gd        Streaming, time of day, shared helpers
  game_trade.gd        Inventory, goods trading, healing
  game_combat.gd       Shooting, melee, aim, damage, death and the recovery bag
  game_camps.gd        Camps, fast travel, sleeping, underground maps
  game_save.gd         Saving (atomic write + backup), loading, migration, settings
  game.gd              class_name Game: setup, title/origin menus, game loop, HUD, input
  debug_runs.gd        Automated runs and checks (only loaded with --autostart)
  economy.gd           Prices, saturation, trader purses and stock
  world.gd             Map data + procedural generation + collision / line of sight
  terrain_mesh.gd      Builds the sloped ground mesh (lighting per triangle)
  ground_maps.gd       World-space masks for roads, sidewalks, dirt tracks and shadows
  light_layer.gd       Night-time glows (neon, lamps, fires)
  building_view.gd     Wall/roof/floor sprites for a building + the cutaway logic
  items.gd             Item database: guns, melee, armour, ammo, consumables, loot tables
  npc.gd               Friendly settlers, traders, wanderers, cattle, crows
  actor.gd, player.gd, enemy.gd, dog.gd, camp.gd
  hud.gd, touch_controls.gd, fx_layer.gd, iso.gd, assets.gd
shaders/terrain.gdshader   Dithered pixel-art terrain shading
shaders/crt.gdshader       Optional CRT effect
shaders/grade.gdshader     Wasteland colour grade + day/night
assets/sprites/        Sprites (+ assets/anchors.json: where each sprite touches the ground)
tools/render3d/        Pre-rendered art pipeline (Blender as a Python module: pip install bpy)
  port_walls.py        walls, doors, windows, broken walls (12 palettes)
  port_tiles.py        floors, flat roofs, stairs, shingle + gable textures
  port_props.py        props, trees, cars (8 directions), furniture
  character.py         8-direction people (player, survivor, settlers, trader, raider, ghoul)
  port_creatures.py    dog, rat, cattle, shellback, crow, brute
  kit.py, props.py, landmarks.py, scenes.py, world_scene.py   the render lab (look-test scenes)
tools/audit_world.gd   Headless placement audit: godot --headless --path . -s tools/audit_world.gd -- 30
tools/make_assets.py   The original pixel-art generator (refuses to run over the renders without --force)
```

## Art pipeline

All sprites are rendered in Blender at the game's exact camera (true 2:1 dimetric, 24/12 px per tile,
1.5 px per unit of height), supersampled 4x and filtered down, keeping the old sprite names, canvases and
anchors, so the game code doesn't care. People and creatures use 8-direction sheets (`<name>_r.png`: rows
are screen directions, columns are idle / walk / crouch frames); if a `_r` sheet is missing the game falls
back to the old pixel sheet. After re-rendering, open the project in the editor (or run
`godot --headless --import`) so Godot picks up the new images.

Base building: open the camp menu (B / CAMP) near a camp and pick **Build**. Choose a material and a piece, then tap or click to place one, or drag to lay a run of walls or a patch of floor (R rotates single pieces, 1-5 pick the material, Esc leaves). Pieces sit on tile edges like building walls, block movement, and doors swing shut on their own. Foundations are raised blocks that snap to the height of a foundation or claimed building they touch (sides show down to the ground), so you can build on slopes and extend at one level. Clear a raider den, then claim it from the camp menu: its walls can be knocked out with Remove (salvage scrap) and its rooms extended. Sprites: `tools/render3d/port_build.py`, preview sheet `tools/render3d/build_preview.py`.

Debug runs (desktop): `godot --path . -- --autostart --shots | --tour | --soak | --fade | --char | --bestiary | --build`
write screenshots to `user://shots`.

Checks (print PASS/FAIL per item and exit non-zero on any failure, so they can run in CI):
`--econcheck` (trade balance), `--combatcheck` (damage stacking, death), `--savecheck` (backups, corrupt saves),
`--uicheck` (toasts, speech, touch, HUD layout), `--play` (bot walks to town and fights), `--soak` (long self-play),
`--determinism` (same seed, different load orders, same world), `--reloadstate` (markets and jobs survive a reload),
`--startclear` (20 new worlds, camp in the open), `--collide` (reachable buildings, free spawns, dry doors),
`--wallcheck` (walls hold with 0.3 s frames). Any script error during a check run fails it.

World generation rule: a chunk's content (buildings, props, loot, spawns) stays 2 tiles inside the chunk and
each generation step has its own seed, so chunks come out identical whatever order they stream in.

## Next up (Milestone 2+)

Weapon mods and crafting stations, skills + Grit, survivor roles and missions,
quests from settlers, overpasses, bridges and rivers, sound and music.
