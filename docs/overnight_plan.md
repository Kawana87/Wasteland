# Overnight push: one continuous Sable Wastes (working notes)

Goal: replace the single 64x64 test map with one seamless 2048x2048-tile world that matches the world map
(~10 min to walk edge to edge at 3.4 tiles/s), streamed in chunks, with pre-made towns at their map spots,
random small sites in the wasteland, a Pip-Boy style map with discovery + fast travel, and a cleaner UI.

## Decisions
- World.N = 2048, chunk = 32x32 tiles (64x64 chunks). Arrays stay global (simple, ~60 MB), filled lazily.
- Data from the Blender world-map pipeline at 1 px per tile: assets/worldmap/data/
  - height.png (16-bit) + meta.json (min/max/scale), biome.png (R biome id, G city density, B wash/gorge, A road kind)
  - roads + locations come from assets/worldmap/locations.json (already there).
- Chunk generation (World.gen_chunk): base terrain (heights, water, roads, trees by biome) then content
  (towns stamped once per location, city blocks from density, POIs by hash, critters/enemies).
  Items created during content are bucketed by chunk for node spawning (Game.load_chunk / unload_chunk).
- Draw order: Iso.z_for uses Iso.origin (rebased as the player travels; Game walks nodes and shifts z).
- Terrain: one TerrainMesh + GroundMaps per chunk (uv offset uniform).
- Persistence: data stays in memory once generated; enemy spawn dicts get "dead" when killed.
- World map: player marker, discovered locations (within 40 tiles), fast travel to discovered ones.
- UI: no HEAL / JUMP touch buttons; full-page grid inventory with rendered item icons.

## Status
(see bottom; updated as work lands)

### Done (overnight)
- Streamed 2048² world from `assets/worldmap/data/world_data.res` (pack with `python3 tools/pack/export_raw.py` then
  `godot --headless --script tools/pack/pack_world.gd` after re-rendering the world map).
- Chunk base (terrain, water, roads, city grid) / content (towns, buildings, props, people) / ready rules; per-chunk
  ground mesh + ground maps; z-index rebasing (`Game.rebase`).
- 50 locations stamped (`World._gen_location`), wasteland POIs (`_chunk_poi`), roaming encounters (`Game._encounters`).
- Biome materials (salt, red rock, marsh, glass, fields, sand, forest floor, concrete lots, water) and scatter props.
- World map: discovery, zoom, fast travel to discovered places. Trade goods economy (`scripts/economy.gd`).
- Origins (`Game.ORIGINS`), save/continue (`user://save.json`).

### Next ideas
- Make each hub look like its Blender village render (layout recipes per town).
- Biome edges are tile-stepped; a dithered blend in the shader would soften them.
- Phones: watch frame time in Port Sterling and the woods (most sprites); `LOAD_R` / tree density are the knobs.
