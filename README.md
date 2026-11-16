# Wasteland (working title)

A cozy isometric 16-bit post-apocalyptic survival game made in **Godot 4.7**: explore a procedurally generated
region, loot ruined buildings, dodge (or fight) raiders and mutants, chop wood, and grow a network of camps.

This is **Milestone 1**: the core loop running in Godot with placeholder art.

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
| Move | WASD / arrows | Left stick | Left thumb anywhere on the left half |
| Aim | Mouse | Right stick | Right thumb on the right half |
| Shoot | Left click | RT | Push the right thumb far |
| Melee | F / right click | B | HIT |
| Jump | Space | A | JUMP |
| Sneak (toggle) | C | Y | SNEAK |
| Use / chop / climb / stairs | E | X | USE |
| Camp menu | B | Back | CAMP |
| Inventory / gear | I or Tab | Start | INV |
| Quick heal (med kit, then food) | H | LB | HEAL |
| Fast travel | T | | (from the camp menu) |
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

- **New world every start:** sloped hills and cliffs in the west, a ruined city in the east. Highways, streets and dirt tracks wind and curve, with wrecked cars at every angle, power lines, jersey barriers and roadside junk.
- **Wasteland feel:** rubble, toxic spills, dead bushes, bones, crows that scatter when you get close, drifting dust, a washed-out colour grade and a day/night cycle (8 minutes per day).
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
  game.gd              Main controller: scene setup, game loop, input, combat, loot, camps, menus
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

Base building: open the camp menu (B / CAMP) near a camp and pick **Build**. Choose a material and a piece, then tap or click to place one, or drag to lay a run of walls or a patch of floor (R rotates single pieces, 1-5 pick the material, Esc leaves). Pieces sit on tile edges like building walls, block movement, and doors swing shut on their own. Sprites: `tools/render3d/port_build.py`, preview sheet `tools/render3d/build_preview.py`.

Debug runs (desktop): `godot --path . -- --autostart --shots | --tour | --soak | --fade | --char | --bestiary | --build`
write screenshots to `user://shots`.

## Next up (Milestone 2+)

Save/load and sleeping, weapon mods and crafting stations, skills + Grit, survivor roles and missions,
quests from settlers, overpasses, bridges and rivers, sound and music.
