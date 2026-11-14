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
  building_view.gd     Wall/roof/floor sprites for a building + the cutaway logic
  items.gd             Item database: guns, melee, armour, ammo, consumables, loot tables
  npc.gd               Friendly settlers, traders, wanderers, cattle, crows
  actor.gd, player.gd, enemy.gd, dog.gd, camp.gd
  hud.gd, touch_controls.gd, fx_layer.gd, iso.gd, assets.gd
shaders/terrain.gdshader   Dithered pixel-art terrain shading
shaders/crt.gdshader       Optional CRT effect
shaders/grade.gdshader     Wasteland colour grade + day/night
assets/sprites/        Generated placeholder sprites
tools/make_assets.py   Regenerates the sprites (python3 tools/make_assets.py, needs Pillow)
```

To swap in real art later, replace PNGs in `assets/sprites/` keeping the same names and sizes.

## Next up (Milestone 2+)

Save/load and sleeping, weapon mods and crafting stations, skills + Grit, survivor roles and missions,
quests from settlers, overpasses, bridges and rivers, sound and music.
