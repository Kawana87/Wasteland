"""Generates all pixel-art sprites for Wasteland (1.5x art: 48x24 tiles).

Run from the repo root:   python3 tools/make_assets.py
Needs Pillow (pip install pillow). Output: assets/sprites/*.png and assets/anchors.json
(the anchor of each sprite = the pixel that sits on its world position).
"""
import os, sys, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(os.path.join(HERE, "..", "assets", "rendered_anchors.json")) and "--force" not in sys.argv:
    sys.exit("The sprites are now pre-rendered in Blender (tools/render3d/port_*.py, character.py).\n"
             "Running this would replace them with the old pixel art. Use --force if you really want that.")
sys.path.insert(0, HERE)
import px2
OUT = os.path.join(HERE, "..", "assets", "sprites")
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):            # start clean (keeps .import files Godot will refresh)
    if f.endswith(".png"):
        os.remove(os.path.join(OUT, f))
px2.OUT_DIR = OUT
import art_chars, art_world, art_build
art_chars.build()
art_world.build()
art_build.build()
px2.write_anchors()
print(len(px2.ANCHORS), "sprites")
