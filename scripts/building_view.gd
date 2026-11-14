class_name BuildingView
extends Node2D
## Sprites for one building: thin wall pieces per floor, upper-floor tiles, stairs and roof.
## update_view() does the cutaway: walk in and the roof lifts, the front walls drop to
## knee height, and floors above you disappear.

const WALL_H := 28

var b: World.Bld
var walls := []        # [{seg, full, low}]
var roofs := []
var upper := []
var stairs_up: Sprite2D
var stairs_down: Sprite2D
var _state := ""

func setup(w: World, bld: World.Bld) -> void:
	b = bld
	for s in b.segs:
		var pal: int = 4 if s.side == "i" else b.pal
		var ax := "x" if s.axis == 0 else "y"
		var z: float = b.h0 + s.fl * World.FLOOR_H
		var pos := Iso.to_screen(s.a.x, s.a.y, z)
		var depth: float = (s.a.x + s.b.x) * 0.5 + (s.a.y + s.b.y) * 0.5
		var full := _spr("wall_%s%d%s" % [ax, pal, "_win" if s.window else ""], pos, ax, WALL_H, depth, s.fl)
		var low := _spr("low_%s%d" % [ax, pal], pos, ax, 5, depth, s.fl)
		low.visible = false
		walls.append({"seg": s, "full": full, "low": low})
	var roof_z: float = b.h0 + b.floors * World.FLOOR_H
	var fk: String = ["wood", "tile", "carpet", "concrete"][b.fkind]
	for y in range(b.y0, b.y0 + b.h):
		for x in range(b.x0, b.x0 + b.w):
			var r := Sprite2D.new()
			r.texture = Assets.tex("roof%d" % b.pal)
			r.centered = false
			r.position = Iso.to_screen(x, y, roof_z)
			r.offset = Vector2(-16, 0)
			r.z_index = Iso.z_for(x + y + 1.95, 6)
			add_child(r)
			roofs.append(r)
			if b.floors > 1:
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
	if b.stairs.x >= 0:
		stairs_up = Sprite2D.new()
		stairs_up.texture = Assets.tex("stairs_up")
		stairs_up.centered = false
		stairs_up.position = Iso.to_screen(b.stairs.x, b.stairs.y, b.h0)
		stairs_up.offset = Vector2(-16, 0)
		stairs_up.z_index = Iso.z_for(b.stairs.x + b.stairs.y + 0.03)
		stairs_up.visible = false
		add_child(stairs_up)

func _spr(tex: String, pos: Vector2, ax: String, h: int, depth: float, fl: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.position = pos
	s.offset = Vector2(-1, -(h + 1)) if ax == "x" else Vector2(-17, -(h + 1))
	s.z_index = Iso.z_for(depth, 2 + fl)
	add_child(s)
	return s

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
			# storeys below you: keep the outer walls so the building still looks solid
			wn.full.visible = s.side != "i"
			wn.low.visible = false
		else:
			var front: bool = s.side == "s" or s.side == "e" or s.side == "i"
			wn.full.visible = not front
			wn.low.visible = front
	for r in roofs:
		r.visible = not inside
	for f in upper:
		f.visible = inside and pfl >= 1
	if stairs_up:
		stairs_up.visible = inside and pfl == 0
