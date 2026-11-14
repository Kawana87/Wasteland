class_name LightLayer
extends Node2D
## Additive glows drawn above the colour grade, so neon signs, street lamps and fires
## light up at night. strength (0..1) follows the time of day.

var strength := 0.0
var lights := []       # [{pos: Vector2 (screen), col: Color, r: float, flicker: bool}]
var _tex: Texture2D

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_tex = t
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m

func add(pos: Vector2, col: Color, r: float, flicker: bool = false) -> void:
	lights.append({"pos": pos, "col": col, "r": r, "flicker": flicker})

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if strength <= 0.02:
		return
	var g := Game.I
	var view := Rect2(g.cam.get_screen_center_position() - Vector2(g.vp.size) * 0.6, Vector2(g.vp.size) * 1.2)
	var t := Time.get_ticks_msec() * 0.001
	for l in lights:
		var p: Vector2 = l.pos
		if not view.has_point(p): continue
		var r: float = l.r
		var a := strength
		if l.flicker:
			a *= 0.8 + 0.2 * sin(t * 13.0 + p.x) * sin(t * 7.0 + p.y)
		var c: Color = l.col
		c.a = a
		draw_texture_rect(_tex, Rect2(p - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false, c)
