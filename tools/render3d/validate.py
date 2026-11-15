"""Pre-render sanity pass: every prop instance is a tagged group (props.prop); every building
registers its volume (kit.SOLIDS). Before a scene renders this checks real-world logic and fixes it:
  1. outdoor props may not intersect a building (a tree trunk inside a house, a crate through a wall)
  2. rooftop props must sit fully inside the roof (inside the parapet) and not overlap each other
  3. solid outdoor props may not interpenetrate each other: the lower-priority one is removed
     (scatter < random placement inside a builder < placed by hand); hand-placed clashes are reported
  4. props sitting on the ground are dropped onto the terrain so nothing floats or sinks
Flat decals (stains, litter, pebbles, grass) may overlap other props but not buildings."""
import bpy
from mathutils import Vector
import kit, props as P

WALL_HALF = kit.WALL_T * 0.5
NATURE = {"tree", "joshua_tree", "cactus", "shrub", "deadbush", "rock", "grass_tuft", "tumbleweed_", "pebbles_"}
GROUND_ONLY = {"crater"}       # ground decals: may lap onto ruins, only get draped onto the terrain
CANOPY = {"tree": 0.45, "joshua_tree": 0.45, "cactus": 0.2, "shrub": 0.15}      # extra clearance from walls


def _groups():
    dg = bpy.context.evaluated_depsgraph_get()
    G = {}
    for o in bpy.data.objects:
        if "grp" not in o or o.type != 'MESH':
            continue
        oe = o.evaluated_get(dg)
        pts = [oe.matrix_world @ Vector(c) for c in oe.bound_box]
        xs = [p.x for p in pts]; ys = [-p.y for p in pts]; zs = [p.z for p in pts]
        g = G.setdefault(o["grp"], {"obs": [], "name": o["pname"], "zone": o["zone"], "prio": o["prio"],
                                    "bb": [1e9, 1e9, 1e9, -1e9, -1e9, -1e9]})
        g["obs"].append(o)
        b = g["bb"]
        b[0] = min(b[0], min(xs)); b[1] = min(b[1], min(ys)); b[2] = min(b[2], min(zs))
        b[3] = max(b[3], max(xs)); b[4] = max(b[4], max(ys)); b[5] = max(b[5], max(zs))
    return G


def _obj_bb(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    xs = [p.x for p in pts]; ys = [-p.y for p in pts]; zs = [p.z for p in pts]
    return [min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)]


def _ov(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def _hits_solid(b, s, pad):
    x0, y0, x1, y1, ztop, kind = s
    ox = _ov(b[0], b[3], x0 - pad, x1 + pad)
    oy = _ov(b[1], b[4], y0 - pad, y1 + pad)
    return ox > 0.02 and oy > 0.02 and b[2] < ztop - 0.05


def _nudge(b, solids, others, step=0.15, reach=1.5):
    """Smallest slide (dx, dy) that clears every solid without landing on another prop; None if none fits."""
    cands = []
    n = int(reach / step)
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            if i or j:
                cands.append((abs(i) + abs(j), i * step, j * step))
    cands.sort()
    for _, dx, dy in cands:
        nb = [b[0] + dx, b[1] + dy, b[2], b[3] + dx, b[4] + dy, b[5]]
        if any(_hits_solid(nb, s, WALL_HALF) for s in solids):
            continue
        if any(h["name"] not in P.DECALS and _ov(nb[0], nb[3], h["bb"][0], h["bb"][3]) > 0.05 and _ov(nb[1], nb[4], h["bb"][1], h["bb"][4]) > 0.05
               for h in others):
            continue
        return (dx, dy)
    return None


def _base_xy(g):
    """Where a prop meets the ground: centre of its lowest parts (a tree's trunk, not its canopy)."""
    zmin = g["bb"][2]
    pts = []
    for o in g["obs"]:
        bb = _obj_bb(o)
        if bb[2] < zmin + 0.1:
            pts.append(((bb[0] + bb[3]) / 2, (bb[1] + bb[4]) / 2))
    if not pts:
        return ((g["bb"][0] + g["bb"][3]) / 2, (g["bb"][1] + g["bb"][4]) / 2)
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


_PENDING = []


def _remove(g):
    _PENDING.extend(g["obs"])
    g["dead"] = True


def run(scene_name=""):
    G = _groups()
    solids = kit.SOLIDS
    log = {"in_building": [], "roof": [], "overlap": [], "placed_clash": [], "grounded": 0, "decal_bits": 0, "nudged": [], "on_pavement": []}
    order = sorted(G.items())
    # 1 + 2: buildings and roofs
    for gid, g in order:
        b = g["bb"]
        if g["zone"] == "int":
            continue
        if g["name"] in GROUND_ONLY:
            continue
        if g["zone"] == "roof":
            ok = any(s[0] + 0.2 <= b[0] and b[3] <= s[2] - 0.2 and s[1] + 0.2 <= b[1] and b[4] <= s[3] - 0.2 and b[2] > 0.5
                     for s in solids)
            if not ok:
                log["roof"].append(g["name"]); _remove(g)
            continue
        if g["name"] in P.DECALS:
            # scattered decals (litter, stains): drop only the pieces that land in a building or wall
            keep = []
            for o in g["obs"]:
                if o.get("batch"):
                    keep.append(o); continue
                ob = _obj_bb(o)
                if any(_hits_solid(ob, s, WALL_HALF) for s in solids):
                    _PENDING.append(o); log["decal_bits"] += 1
                else:
                    keep.append(o)
            g["obs"] = keep
            if not keep: g["dead"] = True
            continue
        if g["name"] in NATURE:
            cx, cy = _base_xy(g)
            if any(p[0] <= cx <= p[2] and p[1] <= cy <= p[3] for p in kit.PAVED):
                log["on_pavement"].append(g["name"]); _remove(g); continue
        hit = [s for s in solids if _hits_solid(b, s, WALL_HALF + CANOPY.get(g["name"], 0.0))]
        if hit and g["prio"] == 2:
            mv = _nudge(b, solids, [h for _, h in order if h is not g and not h.get("dead") and h["zone"] != "roof"])
            if mv:
                for o in g["obs"]:
                    o.location.x += mv[0]; o.location.y -= mv[1]
                b[0] += mv[0]; b[3] += mv[0]; b[1] += mv[1]; b[4] += mv[1]
                log["nudged"].append("%s by %.2f,%.2f" % (g["name"], mv[0], mv[1]))
                continue
        for s in hit:
            if True:
                log["in_building"].append(g["name"]); _remove(g)
                if g["prio"] == 2:
                    log["placed_clash"].append("%s hits %s %s at %.1f,%.1f-%.1f,%.1f -> dropped" % (g["name"], s[5], tuple(round(v, 1) for v in s[:4]), b[0], b[1], b[3], b[4]))
                break
    # roof props vs each other
    roofs = [g for _, g in order if g["zone"] == "roof" and not g.get("dead")]
    for i, a in enumerate(roofs):
        for c in roofs[:i]:
            if c.get("dead"): continue
            A, C = a["bb"], c["bb"]
            if _ov(A[0], A[3], C[0], C[3]) > 0 and _ov(A[1], A[4], C[1], C[4]) > 0:
                log["roof"].append(a["name"]); _remove(a); break
    # 3: outdoor props vs each other
    solid_g = [(gid, g) for gid, g in order if g["zone"] == "ext" and not g.get("dead") and g["name"] not in P.DECALS and g["name"] not in GROUND_ONLY]
    # spatial hash (4-tile cells) so big worlds don't need every pair compared
    CELL = 4.0
    grid = {}
    def cells(B):
        for cx in range(int(B[0] // CELL), int(B[3] // CELL) + 1):
            for cy in range(int(B[1] // CELL), int(B[4] // CELL) + 1):
                yield (cx, cy)
    for i, (gid, a) in enumerate(solid_g):
        a["_i"] = i
    for i, (gid, a) in enumerate(solid_g):
        if a.get("dead"): continue
        A = a["bb"]
        near = {}
        for c_ in cells(A):
            for (gid2, c) in grid.get(c_, []):
                near[gid2] = c
        for c_ in cells(A):
            grid.setdefault(c_, []).append((gid, a))
        for gid2, c in sorted(near.items()):
            if c.get("dead"): continue
            C = c["bb"]
            ox, oy, oz = _ov(A[0], A[3], C[0], C[3]), _ov(A[1], A[4], C[1], C[4]), _ov(A[2], A[5], C[2], C[5])
            if ox <= 0 or oy <= 0 or oz <= 0:
                continue
            area = ox * oy
            small = min((A[3] - A[0]) * (A[4] - A[1]), (C[3] - C[0]) * (C[4] - C[1]))
            if area < 0.25 * small:
                continue
            if a["prio"] == c["prio"] == 2:
                # two hand-placed props clash: keep the bigger one, report it
                aa, ca = (A[3] - A[0]) * (A[4] - A[1]), (C[3] - C[0]) * (C[4] - C[1])
                loser = a if aa <= ca else c
                log["placed_clash"].append("%s vs %s @ %.1f,%.1f -> dropped %s" % (c["name"], a["name"], A[0], A[1], loser["name"]))
            else:
                loser = a if a["prio"] <= c["prio"] else c
            log["overlap"].append(loser["name"]); _remove(loser)
            if loser is a: break
    # 4: ground props follow the terrain
    if kit.TERRAIN.get("amp", 0) > 0:
        for gid, g in order:
            if g.get("dead") or g["zone"] != "ext": continue
            if g["name"] in GROUND_ONLY:
                # drape: decal meshes follow the terrain vertex by vertex, loose parts by their own centre
                for o in g["obs"]:
                    if o.name.startswith("crater"):
                        mw = o.matrix_world
                        for v in o.data.vertices:
                            w = mw @ v.co
                            v.co.z += kit.ground_z(w.x, -w.y) + 0.02
                    else:
                        ob_ = _obj_bb(o)
                        o.location.z += kit.ground_z((ob_[0] + ob_[3]) / 2, (ob_[1] + ob_[4]) / 2)
                log["grounded"] += 1
                continue
            b = g["bb"]
            if b[2] > 0.15: continue
            gz = kit.ground_z((b[0] + b[3]) / 2, (b[1] + b[4]) / 2)
            if abs(gz) > 0.005:
                for o in g["obs"]:
                    o.location.z += gz
                log["grounded"] += 1
    if _PENDING:
        bpy.data.batch_remove(ids=list({o.name: o for o in _PENDING}.values()))
        _PENDING.clear()
    from collections import Counter
    print("[validate %s] groups=%d removed: in-building %d %s | roof %d %s | overlap %d %s | decal bits %d | grounded %d"
          % (scene_name, len(G), len(log["in_building"]), dict(Counter(log["in_building"])), len(log["roof"]), dict(Counter(log["roof"])),
             len(log["overlap"]), dict(Counter(log["overlap"])), log["decal_bits"], log["grounded"]))
    if log["on_pavement"]:
        print("  off pavement:", dict(Counter(log["on_pavement"])))
    if kit.DOOR_FIXES:
        print("  doors moved to a real outside wall:", len(kit.DOOR_FIXES)); kit.DOOR_FIXES.clear()
    if log["nudged"]:
        print("  nudged clear:", ", ".join(log["nudged"]))
    for c in log["placed_clash"]:
        print("  placed clash:", c)
    return log
