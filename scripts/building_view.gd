class_name BuildingView
extends Node2D
## Sprites for one building: thin wall pieces per floor, upper-floor tiles, stairs and roof.
## update_view() does the cutaway: walk in and the roof lifts, the front walls drop to
## knee height, and floors above you disappear. set_faded() makes it see-through when
## you walk behind it.

const WALL_H := 28
const ROOF_COL := ["5a4a4a", "4a3c44", "3e4652", "4a4a3a", "5a4a4a", "7a6a5a"]
const GABLE_COL := ["9a7e56", "7a4a3a", "6e7f8a", "7a7a52", "b8aa8e", "6e6252"]

var b: World.Bld
var walls := []        # [{seg, full, low}]
var roofs := []        # nodes hidden when you're inside
var parapets := []
var upper := []
var stairs_up: Sprite2D
var _state := ""
var _faded := false
var front_depth := 0.0

func setup(w: World, bld: World.Bld) -> void:
	b = bld
	front_depth = b.x0 + b.w + b.y0 + b.h
	for s in b.segs:
		var pal: int = 4 if s.side == "i" else b.pal
		var ax := "x" if s.axis == 0 else "y"
		var z: float = b.h0 + s.fl * World.FLOOR_H
		var pos := Iso.to_screen(s.a.x, s.a.y, z)
		var depth: float = (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5
		var full: Sprite2D
		if s.mode == "stub":
			full = _spr("stub_%s%d" % [ax, pal], pos, ax, WALL_H, depth, s.fl)
		else:
			var suf: String = {"plain": "", "win": "_win", "broken": "_broken", "boarded": "_boarded", "cracked": "_cracked"}[s.mode]
			full = _spr("wall_%s%d%s" % [ax, pal, suf], pos, ax, WALL_H, depth, s.fl)
		var low := _spr("low_%s%d" % [ax, pal], pos, ax, 5, depth, s.fl)
		low.visible = false
		walls.append({"seg": s, "full": full, "low": low})
	var roof_z: float = b.h0 + b.floors * World.FLOOR_H
	var fk: String = ["wood", "tile", "carpet", "concrete"][b.fkind]
	var style := b.roof
	if b.ruined:
		style = "flat"
	if style == "pitched":
		_pitched_roof(roof_z)
	for y in range(b.y0, b.y0 + b.h):
		for x in range(b.x0, b.x0 + b.w):
			var hole := b.holes.has(Vector2i(x, y))
			if style != "pitched" and not hole:
				var r := Sprite2D.new()
				r.texture = Assets.tex("roof%d" % b.pal)
				r.centered = false
				r.position = Iso.to_screen(x, y, roof_z)
				r.offset = Vector2(-16, 0)
				r.z_index = Iso.z_for(x + y + 1.95, 6)
				add_child(r)
				roofs.append(r)
			if b.floors > 1 and not hole:
				var f := Sprite2D.new()
				var is_stairs := Vector2i(x, y) == b.stairs
				f.texture = Assets.tex("stairs_down" if is_stairs else "floor_" + fk)
				f.centered = false
				f.position = Iso.to_screen(x, y, b.h0 + World.FLOOR_H)
				f.offset = Vector2(-16, 0)
				f.z_index = Iso.z_for(x + y + 0.02)
				f.visible = false
				add_child(f)
				upper.append(f)
	if style == "flat" and not b.ruined:
		# a low parapet around flat roofs
		for s in b.segs:
			if s.fl != b.floors - 1 or s.side == "i": continue
			var ax := "x" if s.axis == 0 else "y"
			var depth: float = (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5
			var p := _spr("low_%s%d" % [ax, b.pal], Iso.to_screen(s.a.x, s.a.y, roof_z), ax, 5, depth + 1.9, 6)
			parapets.append(p)
	if b.stairs.x >= 0:
		stairs_up = Sprite2D.new()
		stairs_up.texture = Assets.tex("stairs_up")
		stairs_up.centered = false
		stairs_up.position = Iso.to_screen(b.stairs.x, b.stairs.y, b.h0)
		stairs_up.offset = Vector2(-16, 0)
		stairs_up.z_index = Iso.z_for(b.stairs.x + b.stairs.y + 0.03)
		stairs_up.visible = false
		add_child(stairs_up)

func _poly(pts: Array, col: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	var arr := PackedVector2Array()
	for q in pts: arr.append(q.round())
	p.polygon = arr
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

func _pitched_roof(z: float) -> void:
	var e := 0.18
	var x0 := float(b.x0)
	var x1 := float(b.x0 + b.w)
	var y0 := float(b.y0)
	var y1 := float(b.y0 + b.h)
	var base := Color(ROOF_COL[b.pal])
	var lit := base.lightened(0.12)
	var dark := base.darkened(0.25)
	var gable := Color(GABLE_COL[b.pal])
	var zi := Iso.z_for(front_depth + 0.5, 6)
	if b.w >= b.h:
		var ym := (y0 + y1) * 0.5
		var zr := z + b.h * 4.0 + 4.0
		_poly([_P(x0 - e, y0 - e, z), _P(x1 + e, y0 - e, z), _P(x1 + e, ym, zr), _P(x0 - e, ym, zr)], dark, zi)
		_poly([_P(x0 - e, ym, zr), _P(x1 + e, ym, zr), _P(x1 + e, y1 + e, z), _P(x0 - e, y1 + e, z)], lit, zi + 1)
		_poly([_P(x1, y0, z), _P(x1, y1, z), _P(x1, ym, zr)], gable, zi + 2)
		for t in [0.33, 0.66]:
			var yy := lerpf(ym, y1 + e, t)
			var zz := lerpf(zr, z, t)
			_line(_P(x0 - e, yy, zz), _P(x1 + e, yy, zz), base.darkened(0.12), zi + 1)
		_line(_P(x0 - e, ym, zr), _P(x1 + e, ym, zr), base.lightened(0.3), zi + 1)
		_line(_P(x0 - e, y1 + e, z), _P(x1 + e, y1 + e, z), Color("1e1622"), zi + 1)
	else:
		var xm := (x0 + x1) * 0.5
		var zr := z + b.w * 4.0 + 4.0
		_poly([_P(x0 - e, y0 - e, z), _P(xm, y0 - e, zr), _P(xm, y1 + e, zr), _P(x0 - e, y1 + e, z)], dark, zi)
		_poly([_P(xm, y0 - e, zr), _P(x1 + e, y0 - e, z), _P(x1 + e, y1 + e, z), _P(xm, y1 + e, zr)], lit, zi + 1)
		_poly([_P(x0, y1, z), _P(x1, y1, z), _P(xm, y1, zr)], gable, zi + 2)
		for t in [0.33, 0.66]:
			var xx := lerpf(xm, x1 + e, t)
			var zz := lerpf(zr, z, t)
			_line(_P(xx, y0 - e, zz), _P(xx, y1 + e, zz), base.darkened(0.12), zi + 1)
		_line(_P(xm, y0 - e, zr), _P(xm, y1 + e, zr), base.lightened(0.3), zi + 1)
		_line(_P(x1 + e, y0 - e, z), _P(x1 + e, y1 + e, z), Color("1e1622"), zi + 1)

func _spr(tex: String, pos: Vector2, ax: String, h: int, depth: float, bias: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.position = pos
	s.offset = Vector2(-1, -(h + 1)) if ax == "x" else Vector2(-17, -(h + 1))
	s.z_index = Iso.z_for(depth, 2 + bias)
	add_child(s)
	return s

func set_faded(f: bool) -> void:
	if f == _faded:
		return
	_faded = f
	modulate.a = 0.32 if f else 1.0

## Screen-space box of the whole building including roof (for see-through checks).
func screen_rect() -> Rect2:
	var top := b.h0 + b.floors * World.FLOOR_H + (b.h * 4.0 + 8.0 if b.roof == "pitched" else 6.0)
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
			wn.full.visible = not front or s.mode == "stub"
			wn.low.visible = front and s.mode != "stub"
	for r in roofs:
		r.visible = not inside
	for p in parapets:
		p.visible = not inside
	for f in upper:
		f.visible = inside and pfl >= 1
	if stairs_up:
		stairs_up.visible = inside and pfl == 0
	if inside:
		set_faded(false)
