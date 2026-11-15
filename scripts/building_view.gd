class_name BuildingView
extends Node2D
## Sprites for one building: thin wall pieces per storey, signs and awnings, upper-floor tiles,
## stairs and roofs (one roof per footprint part, so L/T/U shapes get proper cross-gables).
## update_view() does the cutaway: walk in and the roofs lift, the front walls drop to knee
## height, and storeys above you disappear. set_faded() makes it see-through when you walk behind.

const ROOF_TEX := ["shingle_%s0", "shingle_%s1", "shingle_%s2", "shingle_%s3", "shingle_%s4"]

var b: World.Bld
var walls := []        # [{seg, full, low, extras: [Sprite2D]}]
var roofs := []        # nodes hidden when you're inside
var upper := []
var stairs_up: Sprite2D
var _state := ""
var _faded := false
var front_depth := 0.0

func setup(w: World, bld: World.Bld) -> void:
	b = bld
	front_depth = b.x0 + b.w + b.y0 + b.h
	var by_seg := {}
	for sg in b.signs + b.awnings:
		if not by_seg.has(sg.seg): by_seg[sg.seg] = []
		by_seg[sg.seg].append(sg)
	for s in b.segs:
		var pal: int = 4 if s.side == "i" else b.pal
		var ax := "x" if s.axis == 0 else "y"
		var z: float = b.h0 + s.fl * World.FLOOR_H
		var pos := Iso.to_screen(s.a.x, s.a.y, z)
		var depth: float = (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5
		var full: Sprite2D
		if s.mode == "stub":
			var sv: int = posmod(s.cell.x * 7 + s.cell.y * 13 + s.axis * 5, 3)
			full = _spr("stub_%s%d%s" % [ax, pal, "" if sv == 0 else "_%d" % sv], pos, depth, 2 + s.fl * 2)
		else:
			var mode: String = s.mode if s.side != "i" else "plain"
			full = _spr("wall_%s%d%s" % [ax, pal, "" if mode == "plain" else "_" + mode], pos, depth, 2 + s.fl * 2)
		var low := _spr("low_%s%d" % [ax, pal], pos, depth, 2 + s.fl * 2)
		low.visible = false
		var extras := []
		for sg in by_seg.get(s, []):
			var is_awning: bool = sg.tex.begins_with("awning")
			var ez: float = z + (21.0 if is_awning else 21.0)
			extras.append(_spr(sg.tex, Iso.to_screen(s.a.x, s.a.y, ez), depth + 0.05, 3 + s.fl * 2))
		walls.append({"seg": s, "full": full, "low": low, "extras": extras})
	var fk: String = ["wood", "tile", "carpet", "concrete", "lino"][b.fkind]
	# roofs, per part
	for p in b.parts:
		var r: Rect2i = p.r
		var rz: float = b.h0 + p.fl * World.FLOOR_H
		var style := b.roof
		if b.ruined and style != "flat": style = "flat"
		var pdepth := float(r.end.x + r.end.y)
		match style:
			"pitched":
				_pitched(r, rz, pdepth)
			"saw":
				_saw(r, rz, pdepth)
			_:
				var tex := "roof_flat%d" % (b.rcol % 3)
				if style == "tin": tex = "roof_tin"
				if style == "canopy": tex = "roof_canopy"
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						if b.holes.has(Vector2i(x, y)): continue
						var t := _tile(tex, x, y, rz, Iso.z_for(x + y + 1.95, 6 + p.fl * 2))
						roofs.append(t)
	# parapets on flat roofs / fascia on the canopy
	if b.roof in ["flat", "canopy", "tin"] or b.ruined:
		for s in b.segs:
			if s.side == "i" or s.mode == "stub": continue
			var cf: int = b.floors_at(s.cell)
			if s.fl != cf - 1: continue
			var ax := "x" if s.axis == 0 else "y"
			var depth: float = (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5
			var p := _spr("low_%s%d" % [ax, b.pal], Iso.to_screen(s.a.x, s.a.y, b.h0 + cf * World.FLOOR_H), depth + 1.9, 7 + cf * 2)
			roofs.append(p)
	if b.roof == "canopy":
		var r: Rect2i = b.parts[0].r
		var rz: float = b.h0 + World.FLOOR_H - 5.0
		for x in range(r.position.x, r.end.x):
			for yy in [r.position.y, r.end.y]:
				roofs.append(_spr("low_x10", Iso.to_screen(x, yy, rz), x + yy + 0.5 + (1.9 if yy == r.end.y else 0.0), 8))
		for y in range(r.position.y, r.end.y):
			for xx in [r.position.x, r.end.x]:
				roofs.append(_spr("low_y10", Iso.to_screen(xx, y, rz), xx + y + 0.5 + (1.9 if xx == r.end.x else 0.0), 8))
	for rp in b.roof_props:
		var cf: int = b.floors_at(rp.cell)
		var z: float = b.h0 + maxi(cf, 1) * World.FLOOR_H
		roofs.append(_spr(rp.tex, Iso.to_screen(rp.pos.x, rp.pos.y, z), rp.pos.x + rp.pos.y + 2.0, 9 + cf * 2))
	# upper storey floor tiles
	for c in b.cells:
		if b.cells[c] < 2 or b.holes.has(c): continue
		var is_stairs: bool = c == b.stairs
		var f := _tile("stairs_down" if is_stairs else "floor_" + fk, c.x, c.y, b.h0 + World.FLOOR_H, Iso.z_for(c.x + c.y + 0.02))
		f.visible = false
		upper.append(f)
	if b.stairs.x >= 0:
		stairs_up = _tile("stairs_up", b.stairs.x, b.stairs.y, b.h0, Iso.z_for(b.stairs.x + b.stairs.y + 0.03))
		stairs_up.visible = false

func _tile(tex: String, x: int, y: int, z: float, zi: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.position = Iso.to_screen(x, y, z)
	s.offset = Assets.off(tex)
	s.z_index = zi
	add_child(s)
	return s

func _poly(pts: Array, col: Color, z: int, tex: String = "") -> Polygon2D:
	var p := Polygon2D.new()
	var arr := PackedVector2Array()
	for q in pts: arr.append(q.round())
	p.polygon = arr
	if tex != "":
		p.texture = Assets.tex(tex)
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.uv = arr
		p.color = col
	else:
		p.color = col
	p.antialiased = false
	p.z_index = z
	add_child(p)
	roofs.append(p)
	return p

func _line(a: Vector2, c: Vector2, col: Color, z: int) -> void:
	var l := Line2D.new()
	l.points = PackedVector2Array([a.round(), c.round()])
	l.width = 1.0
	l.default_color = col
	l.antialiased = false
	l.z_index = z
	add_child(l)
	roofs.append(l)

static func _P(x: float, y: float, h: float) -> Vector2:
	return Iso.to_screen(x, y, h)

func _pitched(r: Rect2i, z: float, pdepth: float) -> void:
	var e := 0.2
	var x0 := float(r.position.x)
	var x1 := float(r.end.x)
	var y0 := float(r.position.y)
	var y1 := float(r.end.y)
	var zi := Iso.z_for(pdepth + 0.5, 6 + (2 if z > b.h0 + World.FLOOR_H + 1.0 else 0))
	var dark := Color(0.72, 0.72, 0.76)
	var edge := Color("1e1622")
	if r.size.x >= r.size.y:
		var ym := (y0 + y1) * 0.5
		var zr := z + r.size.y * 4.0 + 4.0
		var st: String = ROOF_TEX[b.rcol] % "x"
		_poly([_P(x0 - e, y0 - e, z), _P(x1 + e, y0 - e, z), _P(x1 + e, ym, zr), _P(x0 - e, ym, zr)], dark, zi, st)
		_poly([_P(x0 - e, ym, zr), _P(x1 + e, ym, zr), _P(x1 + e, y1 + e, z), _P(x0 - e, y1 + e, z)], Color.WHITE, zi + 1, st)
		_poly([_P(x1, y0, z), _P(x1, y1, z), _P(x1, ym, zr)], Color.WHITE, zi + 2, "gable_y%d" % b.pal)
		_line(_P(x0 - e, ym, zr), _P(x1 + e, ym, zr), Color(1, 1, 1, 0.35), zi + 1)
		_line(_P(x0 - e, y1 + e, z), _P(x1 + e, y1 + e, z), edge, zi + 1)
		_line(_P(x1 + e, y1 + e, z), _P(x1 + e, ym, zr), edge, zi + 2)
	else:
		var xm := (x0 + x1) * 0.5
		var zr := z + r.size.x * 4.0 + 4.0
		var st: String = ROOF_TEX[b.rcol] % "y"
		_poly([_P(x0 - e, y0 - e, z), _P(xm, y0 - e, zr), _P(xm, y1 + e, zr), _P(x0 - e, y1 + e, z)], dark, zi, st)
		_poly([_P(xm, y0 - e, zr), _P(x1 + e, y0 - e, z), _P(x1 + e, y1 + e, z), _P(xm, y1 + e, zr)], Color(0.86, 0.86, 0.9), zi + 1, st)
		_poly([_P(x0, y1, z), _P(x1, y1, z), _P(xm, y1, zr)], Color.WHITE, zi + 2, "gable_x%d" % b.pal)
		_line(_P(xm, y0 - e, zr), _P(xm, y1 + e, zr), Color(1, 1, 1, 0.35), zi + 1)
		_line(_P(x1 + e, y0 - e, z), _P(x1 + e, y1 + e, z), edge, zi + 1)
		_line(_P(x0 - e, y1 + e, z), _P(xm, y1 + e, zr), edge, zi + 2)

## Factory sawtooth: strips 2 tiles wide, each sloping up toward +x with a glazed east face.
func _saw(r: Rect2i, z: float, pdepth: float) -> void:
	var zi := Iso.z_for(pdepth + 0.5, 6)
	var y0 := float(r.position.y)
	var y1 := float(r.end.y)
	var x := float(r.position.x)
	var k := 0
	while x < r.end.x - 0.01:
		var xe := minf(x + 2.0, float(r.end.x))
		var top := z + 12.0
		_poly([_P(x, y0, z), _P(xe, y0, top), _P(xe, y1, top), _P(x, y1, z)], Color("6a6e6a").lightened(0.05 * (k % 2)), zi + k * 3)
		_poly([_P(xe, y0, top), _P(xe, y1, top), _P(xe, y1, z), _P(xe, y0, z)], Color("3e5a66"), zi + k * 3 + 1)
		for t in range(1, 4):
			var yy := lerpf(y0, y1, t / 4.0)
			_line(_P(xe, yy, top), _P(xe, yy, z), Color("8aa0a8"), zi + k * 3 + 2)
		_line(_P(xe, y0, top), _P(xe, y1, top), Color("b8bcb4"), zi + k * 3 + 2)
		x = xe
		k += 1
	# front (south) faces of the teeth
	x = float(r.position.x)
	k = 0
	while x < r.end.x - 0.01:
		var xe := minf(x + 2.0, float(r.end.x))
		_poly([_P(x, y1, z), _P(xe, y1, z + 12.0), _P(xe, y1, z)], Color("8a8e86"), zi + 40)
		x = xe
		k += 1

func _spr(tex: String, pos: Vector2, depth: float, bias: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.position = pos.round()
	s.offset = Assets.off(tex)
	s.z_index = Iso.z_for(depth, bias)
	add_child(s)
	return s

## A door opened, broke or got unlocked: swap that wall piece's texture.
func refresh_seg(s: World.Seg) -> void:
	for wn in walls:
		if wn.seg == s:
			var ax := "x" if s.axis == 0 else "y"
			var tex := "wall_%s%d%s" % [ax, b.pal, "" if s.mode == "plain" else "_" + s.mode]
			wn.full.texture = Assets.tex(tex)
			return

func set_faded(f: bool) -> void:
	if f == _faded:
		return
	_faded = f
	modulate.a = 0.3 if f else 1.0

## True when this building actually covers the player on screen: some part of it stands in front of
## the player (greater depth) on the player's screen column and is tall enough to reach the sampled
## points (feet / chest / head, in screen px above the feet). Standing beside or in front never fades.
## Height (game px, absolute) of this building's outer surface at world point (x, y), or -1 if outside.
func surface_z(x: float, y: float) -> float:
	var best := -1.0
	for p in b.parts:
		var r: Rect2i = p.r
		if x < r.position.x or x > r.end.x or y < r.position.y or y > r.end.y:
			continue
		var top: float = b.h0 + p.fl * World.FLOOR_H
		if b.roof == "pitched" and not b.ruined:
			var rise := minf(r.size.x, r.size.y) * 4.0 + 4.0
			var t := 0.0
			if r.size.x >= r.size.y:
				t = 1.0 - absf(y - (r.position.y + r.size.y * 0.5)) / (r.size.y * 0.5)
			else:
				t = 1.0 - absf(x - (r.position.x + r.size.x * 0.5)) / (r.size.x * 0.5)
			top += rise * clampf(t, 0.0, 1.0)
		elif b.roof == "saw":
			top += 12.0 * fposmod(x - r.position.x, 2.0) * 0.5
		else:
			top += 2.0
		best = maxf(best, top)
	return best

## True when the building hides the player: walking the camera's line of sight through each sample point
## (screen px above the feet) on the player's screen column, some part of the building rises high enough
## to cover it. Every sample must be covered.
func occludes(pw: Vector2, offs: Array, pz: float = 0.0) -> bool:
	var pdepth := pw.x + pw.y
	var c: float = pw.x - pw.y
	for off in offs:
		var hit := false
		var dd := 0.05
		while dd < 14.0 and not hit:
			var d := pdepth + dd
			var x := (d + c) * 0.5
			var y := (d - c) * 0.5
			var sz := surface_z(x, y)
			if sz >= 0.0 and sz >= (dd * 12.0 + float(off)) / Iso.S + pz:
				hit = true
			dd += 0.1
		if not hit:
			return false
	return true

## Screen-space box of the whole building including roof (for see-through checks).
func screen_rect() -> Rect2:
	var top := b.h0 + b.floors * World.FLOOR_H + (maxi(b.w, b.h) * 2.0 + 8.0 if b.roof == "pitched" else 14.0)
	var pts := [Iso.to_screen(b.x0, b.y0, top), Iso.to_screen(b.x0 + b.w, b.y0, top), Iso.to_screen(b.x0, b.y0 + b.h, b.h0), Iso.to_screen(b.x0 + b.w, b.y0 + b.h, b.h0)]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts: r = r.expand(p)
	return r

func update_view(pb: int, pfl: int) -> void:
	var inside := pb == b.id
	var key := "%s/%d" % [inside, pfl]
	if key == _state:
		return
	_state = key
	for wn in walls:
		var s: World.Seg = wn.seg
		if not inside:
			wn.full.visible = true
			wn.low.visible = false
		elif s.fl > pfl:
			wn.full.visible = false
			wn.low.visible = false
		elif s.fl < pfl:
			wn.full.visible = s.side != "i"
			wn.low.visible = false
		else:
			var front: bool = s.side == "s" or s.side == "e" or s.side == "i"
			if front and (s.is_door or s.mode.begins_with("door")):
				# doorways stay readable from inside: the door shows at full height, see-through
				wn.full.visible = true
				wn.low.visible = false
			else:
				wn.full.visible = not front or s.mode == "stub"
				wn.low.visible = front and s.mode != "stub"
		var doorish: bool = s.is_door or s.mode.begins_with("door")
		wn.full.modulate.a = 0.55 if (inside and s.fl == pfl and doorish and (s.side == "s" or s.side == "e" or s.side == "i")) else 1.0
		for x in wn.extras:
			x.visible = wn.full.visible
	for r in roofs:
		r.visible = not inside
	for f in upper:
		f.visible = inside and pfl >= 1
	if stairs_up:
		stairs_up.visible = inside and pfl == 0
	if inside:
		set_faded(false)
