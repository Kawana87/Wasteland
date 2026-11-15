"""Write docs/world-locations.md from locations.py.  python3 tools/worldmap/make_docs.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locations as L
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
G = [("hub", "Major settlements"), ("city", "Cities"), ("district", "City districts (Port Sterling)"), ("town", "Towns"),
     ("settlement", "Settlements"), ("camp", "Camps"), ("landmark", "Landmarks"), ("dungeon", "Dungeons")]
n = L.NAMES
o = ["# %s — location master list\n" % L.REGION,
     "A fictional 50s atomic-age wasteland of %d locations, laid out after Fallout 3's Capital Wasteland. The map, its data and its generator are in the repo:" % len(L.L),
     "- `tools/worldmap/locations.py`: every location, its position and the landform names; edit here.",
     "- `tools/worldmap/layout_fo3.py`: the flat layout map. `tools/worldmap/paint_fo3.py`: the painted map (`assets/worldmap/worldmap.png`, `locations.json`).",
     "- `tools/worldmap/make_docs.py`: rewrites this list.\n",
     "**Geography:**",
     "- The %s runs down the east side from %s and Ridgeback Dam; %s, the bombed city, sits on its east bank inside a beltway. South of the city the river spreads into the %s." % (n["river"], n["lake"], n["city"].title(), n["marsh"]),
     "- The %s fill the north-west and south-west; the %s and Goldenrod's farms are in the north." % (n["hills"], n["woods"]),
     "- %s fill the middle, with Bonewhite Flats, Scorch Canyon and the bomb crater (the Hollow Sun) in the south-west.\n" % n["waste"],
     "**Routes:**",
     "- An interstate runs from Hangman's Gap through Patchwork and over Founders Bridge into the city.",
     "- Highways fan out from the city to every corner; a metro line runs from Starlite Crossing to the Union Rail Yard.\n",
     "**Major settlements** each grew out of the place they were built in, and each trades in what that place gives them. Plainer towns sit in between.\n",
     "Danger levels: 1 safe … 5 deadly. Each location's map size is in tiles, and every location gets its own map.\n"]
for t, h in G:
    ls = [l for l in L.L if l["type"] == t]
    if not ls: continue
    o.append("## %s (%d)\n" % (h, len(ls)))
    for l in ls:
        extra = " **Built on:** %s. **Trades in:** %s." % (l["hook"], l["trade"]) if l.get("hook") else ""
        o.append("- **%s**: %s%s *(danger %d · %s · %d×%d tiles · %s)*" % (l["name"], l["pitch"], extra, l["danger"], l["faction"], l["size"], l["size"], l["biome"]))
        o.append("  - Plan: [ ] layout · [ ] key buildings · [ ] NPCs & quests · [ ] loot · [ ] encounters")
    o.append("")
o += ["## Random encounters\n", "Encounters generate a small map matching the terrain where they happen, with a few variations each:",
      "woods, plains, farmland, wasteland, wetland, salt flat, canyon, hills, river, ruins, and the edge of the Hollow Sun.\n"]
open(os.path.join(ROOT, "docs", "world-locations.md"), "w").write("\n".join(o))
print("ok")
