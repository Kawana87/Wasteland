"""Renders labelled catalogue sheets of the prop library: interior, city/wasteland debris, nature."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P
import bpy
from bpy_extras.object_utils import world_to_camera_view
from PIL import Image, ImageDraw
from post import fallout_grade

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
WHICH = sys.argv[2] if len(sys.argv) > 2 else "all"
os.makedirs(OUT, exist_ok=True)


def sheet(name, items, cols, cell=160, ground=None, samples=32, rot=0, cell_h=None):
    cell_h = cell_h or cell
    """Each item rendered alone (same pixel scale as the game: 64 px per tile) with a shadow catcher,
    then laid out in a labelled grid."""
    sc = reset()
    P._MC.clear()
    kit.materials()
    sc.render.film_transparent = True
    lights()
    cam = camera(0, 0, cell, cell_h, 0.55 + (cell_h - cell) / 2 / 39.2)
    sc.cycles.samples = samples
    sprites = []
    for i, (label, fn, kw) in enumerate(items):
        for ob in list(bpy.data.objects):
            if ob.type in ('MESH', 'CURVE'):
                bpy.data.objects.remove(ob, do_unlink=True)
        g = box(-3, -3, -0.05, 3, 3, 0.0, kit.mat_flat("sc", '#808080'))
        g.is_shadow_catcher = True
        rng = random.Random(1000 + i * 17)
        kw = dict(kw)
        fn(0, 0, kw.pop("rot", rot), rng, **kw)
        sc.render.filepath = os.path.join(OUT, "_spr.png")
        bpy.ops.render.render(write_still=True)
        sprites.append((label, Image.open(sc.render.filepath).copy()))
    rows = (len(sprites) + cols - 1) // cols
    LH = 14
    sheet_im = Image.new("RGBA", (cols * cell, rows * (cell_h + LH)), (92, 80, 64, 255))
    for i, (label, im) in enumerate(sprites):
        x, y = (i % cols) * cell, (i // cols) * (cell_h + LH)
        sheet_im.alpha_composite(im, (x, y))
    out = fallout_grade(sheet_im.convert("RGB"))
    d = ImageDraw.Draw(out)
    for i, (label, im) in enumerate(sprites):
        x, y = (i % cols) * cell, (i // cols) * (cell_h + LH)
        d.rectangle([x, y + cell_h, x + cell - 1, y + cell_h + LH - 1], fill=(28, 24, 20))
        d.text((x + 4, y + cell_h + 1), label, fill=(242, 214, 120))
    out.save(os.path.join(OUT, name + ".png"))
    print("sheet", name, out.size)


I = [("wood chair", P.chair, {"style": "wood"}), ("diner chair", P.chair, {"style": "diner"}), ("office chair", P.chair, {"style": "office"}),
     ("couch", P.couch, {}), ("couch", P.couch, {"w": 1.8}), ("armchair", P.armchair, {}), ("bed", P.bed, {"size": 1.4}),
     ("cot", P.bed, {"size": 0.95, "frame": False}), ("bunk bed", P.bunkbed, {}), ("mattress", P.mattress, {}),
     ("table", P.table, {"shape": "rect"}), ("round table", P.table, {"shape": "round"}), ("coffee table", P.coffee_table, {}),
     ("bookshelf", P.bookshelf, {}), ("bookshelf", P.bookshelf, {"w": 1.2}), ("dresser", P.dresser, {}), ("dresser", P.dresser, {}),
     ("wardrobe", P.wardrobe, {}), ("filing cab.", P.filing_cabinet, {}), ("lockers", P.locker_row, {}), ("footlocker", P.footlocker, {}),
     ("safe", P.safe, {}), ("fridge", P.fridge, {}), ("fridge", P.fridge, {}), ("stove", P.stove, {}), ("counter", P.counter, {"sink": True}),
     ("counter", P.counter, {"sink": False}), ("toilet", P.toilet, {}), ("bathtub", P.bathtub, {}), ("sink", P.sink_stand, {}),
     ("console TV", P.tv, {"style": "console"}), ("TV set", P.tv, {"style": "set"}), ("radio", P.radio, {}), ("terminal", P.terminal, {}),
     ("floor lamp", P.lamp, {}), ("rug", P.rug, {}), ("boxes", P.cardboard_boxes, {}), ("ammo crate", P.ammo_crate, {}),
     ("jukebox", P.jukebox, {}), ("vending", P.vending, {}), ("booth", P.booth, {}), ("workbench", P.workbench, {})]

C = [("dumpster", P.dumpster, {"lid": "open"}), ("dumpster", P.dumpster, {"lid": "closed"}), ("trash can", P.trash_can, {"tipped": False}),
     ("trash can", P.trash_can, {"tipped": True}), ("trash bags", P.trash_bags, {}), ("litter", P.litter, {"r": 0.9}),
     ("rubble", P.rubble_pile, {"size": 0.8}), ("rubble", P.rubble_pile, {"size": 1.2}), ("barrel", P.barrel, {"kind": "rust"}),
     ("toxic barrel", P.barrel, {"kind": "toxic"}), ("barrel", P.barrel, {"kind": "blue"}), ("tyres", P.tire_stack, {}),
     ("pallet", P.pallet, {}), ("crate", P.crate, {}), ("sandbags", P.sandbags, {}), ("barricade", P.barricade, {}),
     ("jersey barrier", P.jersey, {}), ("chain-link", P.chainlink, {"n": 2}), ("wood fence", P.wood_fence, {"n": 2}),
     ("street sign", P.street_sign, {}), ("traffic light", P.traffic_light, {"fallen": False}), ("fallen light", P.traffic_light, {"fallen": True}),
     ("parking meter", P.parking_meter, {}), ("cart", P.shopping_cart, {}), ("news box", P.newsbox, {}), ("bench", P.bench, {}),
     ("skeleton", P.skeleton, {}), ("scrap heap", P.junk_pile, {}), ("scrap heap", P.junk_pile, {}), ("generator", P.generator, {}),
     ("water tank", P.water_tank, {}), ("fire pit", P.campfire_pit, {}), ("lean-to", P.lean_to, {}), ("mailbox", P.mailbox, {}),
     ("hydrant", P.hydrant, {}), ("phone booth", P.phone_booth, {}), ("sedan", P.car_wreck, {"style": "sedan"}),
     ("truck", P.car_wreck, {"style": "truck"}), ("burned car", P.car_wreck, {"style": "burned"}), ("sedan", P.car_wreck, {"style": "sedan"}),
     ("lamp post", P.lamp_post, {}), ("billboard", P.billboard, {})]

N = [("dead tree", P.tree, {"kind": "dead"}) for _ in range(6)] + [("sparse tree", P.tree, {"kind": "sparse"}) for _ in range(4)] + \
    [("scrub", P.tree, {"kind": "scrub"}) for _ in range(2)] + [("pine", P.tree, {"kind": "pine"}) for _ in range(2)] + \
    [("joshua tree", P.joshua_tree, {}) for _ in range(2)] + [("cactus", P.cactus, {}) for _ in range(2)] + \
    [("shrub", P.shrub, {}) for _ in range(3)] + [("dead bush", P.deadbush, {}) for _ in range(3)] + \
    [("tumbleweed", P.tumbleweed, {}) for _ in range(2)] + [("grass", P.grass_tuft, {}) for _ in range(3)] + \
    [("rock", P.rock, {"size": s}) for s in (0.2, 0.35, 0.5, 0.7, 0.3, 0.55)] + [("pebbles", P.pebbles, {})]

if WHICH in ("all", "interior"):
    sheet("cat_interior", I, 7, 150)
if WHICH in ("all", "city"):
    sheet("cat_city", C, 7, 190)
if WHICH in ("all", "nature"):
    sheet("cat_nature", N, 8, 160, cell_h=230)
