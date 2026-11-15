class_name Actor
extends Node2D
## Anything that walks around the map: player, enemies, dog, survivors.
## wpos is the world position in tiles; fl is the storey (0 = ground/outside).

var wpos := Vector2.ZERO
var fl := 0
var jz := 0.0          # jump height in pixels
var vz := 0.0
var radius := 0.25
var body: Sprite2D
var shadow_w := 8

func world() -> World:
	return Game.I.world

func building() -> int:
	return world().building_at(wpos.x, wpos.y)

func ground_z() -> float:
	return world().stand_z(wpos.x, wpos.y, fl)

## Try to move by d (tiles). Slides along walls. Returns true if it moved at all.
func move(d: Vector2) -> bool:
	var w := world()
	var moved := false
	var nx := wpos + Vector2(d.x, 0)
	if w.can_stand(nx, radius, fl) and w.slope_ok(wpos, nx, fl, jz):
		wpos = nx
		moved = true
	var ny := wpos + Vector2(0, d.y)
	if w.can_stand(ny, radius, fl) and w.slope_ok(wpos, ny, fl, jz):
		wpos = ny
		moved = true
	return moved

func update_jump(delta: float) -> void:
	if jz > 0.0 or vz > 0.0:
		vz -= 300.0 * delta
		jz = maxf(0.0, jz + vz * delta)
		if jz == 0.0:
			vz = 0.0

func sync() -> void:
	position = Iso.to_screen(wpos.x, wpos.y, ground_z()).round()
	z_index = Iso.z_for(wpos.x + wpos.y, 4 + fl * 2)
	if body:
		body.position.y = -round(jz)
	queue_redraw()

func make_body(tex_name: String, frames: int, fw: int, fh: int, rows: int = 1) -> void:
	body = Sprite2D.new()
	body.texture = Assets.tex(tex_name)
	body.hframes = frames
	body.vframes = rows
	body.centered = false
	body.offset = Assets.off(tex_name)   # anchor = feet of the first frame
	add_child(body)

func _draw() -> void:
	var sw := shadow_w * Iso.S
	draw_rect(Rect2(-sw * 0.5, -1, sw, 3), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-sw * 0.5 + 2, -2, sw - 4, 5), Color(0, 0, 0, 0.2))
