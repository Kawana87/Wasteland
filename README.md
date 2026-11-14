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
| Fast travel | T | Start | (from the camp menu) |
| CRT filter | V | | CRT button |

## What's in Milestone 1

- **New world every start:** sloped hills and cliffs in the west, a flat ruined city in the east, roads, cars, forests.
- **Buildings with thin walls and up to two floors:** walk in and the roof lifts, the front walls drop and floors above disappear. Use the stairs with E.
- **Raider camps on plateaus:** walk up the ramp or climb the rope round the back. Clear them out for their stash.
- **Threats:** raiders (keep distance, strafe, shoot), patrols on the roads, mutant hound packs (fast, scared of campfires), rats indoors.
- **Awareness system:** `?` = suspicious, `!` = hunting you. Closeness, searching and gunfire make noise. Sneak to get close; melee an unaware enemy for a silent takedown.
- **Looting and chopping:** crates, car trunks, raider bags and stashes; chop trees (3 swings) for wood.
- **Camps:** set up to 4 camps anywhere (4 wood + 2 scrap), one shared stash, per-camp upgrades (shelter, workbench, garden, watchtower), make any camp your main camp, pack camps up, **fast travel** between them when nothing is hunting you. Going down sends you to the nearest camp.
- **Survivors** hiding in city buildings you can recruit; they bring back scrap and wood.
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
  actor.gd, player.gd, enemy.gd, dog.gd, camp.gd
  hud.gd, touch_controls.gd, fx_layer.gd, iso.gd, assets.gd
shaders/terrain.gdshader   Dithered pixel-art terrain shading
shaders/crt.gdshader       Optional CRT effect
assets/sprites/        Generated placeholder sprites
tools/make_assets.py   Regenerates the sprites (python3 tools/make_assets.py, needs Pillow)
```

To swap in real art later, replace PNGs in `assets/sprites/` keeping the same names and sizes.

## Next up (Milestone 2+)

Save/load and sleeping, day/night, more weapons and crafting stations, skills + Grit, survivor roles and missions,
settlements (friendly / traders), overpasses, bridges and rivers, sound and music.
