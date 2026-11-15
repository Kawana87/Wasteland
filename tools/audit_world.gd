extends SceneTree
## Headless placement audit: generates many worlds and counts objects that break real-world logic.
## godot --headless --path . -s tools/audit_world.gd -- [worlds]

func _init() -> void:
	var n := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: n = int(args[0])
	var tot := {}
	var examples := {}
	for s in n:
		var w: World = load("res://scripts/world.gd").new()
		w.generate(1000 + s * 7919)
		var r := audit(w)
		for k in r:
			tot[k] = tot.get(k, 0) + r[k][0]
			if r[k][0] > 0 and not examples.has(k): examples[k] = "seed %d: %s" % [1000 + s * 7919, r[k][1]]
	print("AUDIT over %d worlds" % n)
	var keys := tot.keys(); keys.sort()
	for k in keys:
		print("  %-28s %5d   %s" % [k, tot[k], examples.get(k, "")])
	quit()

func near_building(w: World, p: Vector2, r: float) -> int:
	for k in 8:
		var q := p + Vector2.from_angle(k * PI / 4.0) * r
		var b := w.building_at(q.x, q.y)
		if b != 0: return b
	return w.building_at(p.x, p.y)

func audit(w: World) -> Dictionary:
	var R := {}
	var add := func(k: String, msg: String) -> void:
		if not R.has(k): R[k] = [0, msg]
		R[k][0] += 1
		var nm := msg.split(" ")[0]
		var kk := k + ":" + nm
		if not R.has(kk): R[kk] = [0, ""]
		R[kk][0] += 1
	var doors := []
	for b in w.buildings:
		doors.append(Vector2(b.out) + Vector2(0.5, 0.5))
	# decor
	for d in w.decor:
		if d.bid != 0 or d.flat or d.name in ["pillar", "fuelpump"]: continue
		if w.building_at(d.pos.x, d.pos.y) != 0:
			add.call("decor_inside_building", "%s at %s" % [d.name, str(d.pos)])
		elif d.solid and near_building(w, d.pos, d.half.x + 0.05) != 0:
			add.call("decor_touching_wall", "%s at %s" % [d.name, str(d.pos)])
		if d.solid:
			for dp in doors:
				if dp.distance_to(d.pos) < 0.9:
					add.call("decor_blocking_door", "%s at %s" % [d.name, str(d.pos)])
			if w.car_hit(d.pos, d.half.x * 0.5):
				add.call("decor_in_car", "%s at %s" % [d.name, str(d.pos)])
			var tx := int(d.pos.x); var ty := int(d.pos.y)
			if w.in_bounds(tx, ty) and w.T[w.idx(tx, ty)] == World.TREE:
				add.call("decor_on_tree", "%s at %s" % [d.name, str(d.pos)])
	# solid decor overlapping each other
	var sol := []
	for d in w.decor:
		if d.solid and d.bid == 0: sol.append(d)
	for i in sol.size():
		for j in range(i + 1, sol.size()):
			var a = sol[i]; var c = sol[j]
			if absf(a.pos.x - c.pos.x) < (a.half.x + c.half.x) * 0.8 and absf(a.pos.y - c.pos.y) < (a.half.y + c.half.y) * 0.8:
				add.call("decor_overlap", "%s / %s at %s" % [a.name, c.name, str(a.pos)])
	# cars
	for c in w.cars:
		var fw := Vector2.from_angle(c.ang)
		for u in [-1.3, 0.0, 1.3]:
			for v in [-0.45, 0.45]:
				var q: Vector2 = c.pos + fw * u + fw.orthogonal() * v
				if w.building_at(q.x, q.y) != 0:
					add.call("car_in_building", str(c.pos)); break
		for dp in doors:
			if dp.distance_to(c.pos) < 1.6: add.call("car_blocking_door", str(c.pos))
		for o in w.cars:
			if o != c and o.pos.distance_to(c.pos) < 2.0: add.call("car_overlap", str(c.pos))
	# trees against walls / blocking doors
	for y in World.N:
		for x in World.N:
			if w.T[w.idx(x, y)] != World.TREE: continue
			var p := Vector2(x + 0.5, y + 0.5)
			if near_building(w, p, 0.55) != 0: add.call("tree_against_wall", str(p))
			for dp in doors:
				if dp.distance_to(p) < 1.2: add.call("tree_blocking_door", str(p))
			if w.car_hit(p, 0.1): add.call("tree_in_car", str(p))
	# doors: outside tile must be standable and lead somewhere
	for b in w.buildings:
		var o := Vector2(b.out) + Vector2(0.5, 0.5)
		if not w.can_stand(o, 0.25, 0) and b.door_seg != null and not b.sealed:
			add.call("door_exit_blocked", "b%d %s at %s" % [b.id, b.kind, str(o)])
	# crates (loot) inside walls
	for cr in w.crates:
		if cr.bid == 0 and cr.kind != "car" and w.building_at(cr.pos.x, cr.pos.y) != 0:
			add.call("outdoor_crate_in_building", str(cr.pos))
	# furniture blocking interior doorways / outside the building
	for b in w.buildings:
		for f in b.furn:
			if w.building_at(f.pos.x, f.pos.y) != b.id:
				add.call("furniture_outside_building", "%s in b%d" % [f.name, b.id])
	# survivors/spawns in walls
	for s in w.spawns:
		if not w.can_stand(s.pos, 0.2, s.get("fl", 0)):
			add.call("spawn_in_solid", "%s %s fl=%s b=%d" % [s.type, str(s.pos), str(s.get("fl", 0)), w.building_at(s.pos.x, s.pos.y)])
	return R
