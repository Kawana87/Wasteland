class_name Camp
extends Node2D
## A camp: campfire, flag and whatever upgrades have been built here.
## All camps share one stash (kept in Game).

var wpos := Vector2.ZERO
var cname := "Camp"
var main := false
var up := {"tent": false, "bench": false, "garden": false, "tower": false}
var tower_cd := 0.0
var fire: Sprite2D
var flag: Sprite2D
var built := {}
var _ft := 0.0

const UP_OFFSET := {"tent": Vector2(-2.5, -2.5), "bench": Vector2(2.2, -2.0), "garden": Vector2(-1.6, 3.4), "tower": Vector2(2.5, 2.5)}
const UP_SPRITE := {"tent": ["tent", Vector2(-15, -24)], "bench": ["workbench", Vector2(-11, -15)], "garden": ["barrel", Vector2(-7, -12)], "tower": ["tower", Vector2(-12, -48)]}

func setup(p: Vector2, n: String, is_main: bool) -> void:
	wpos = p
	cname = n
	main = is_main
	fire = _place("campfire0", wpos, Vector2(-8, -16))
	flag = _place("flag_main" if main else "flag", wpos + Vector2(1.2, -1.2), Vector2(-1, -30))
	for k in up:
		if up[k]:
			build(k)

func _place(tex: String, at: Vector2, off: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(tex)
	s.centered = false
	s.offset = off
	s.z_as_relative = false
	s.position = Iso.to_screen(at.x, at.y, Game.I.world.hz(at.x, at.y)).round()
	s.z_index = Iso.z_for(at.x + at.y, 3)
	add_child(s)
	return s

func set_main(v: bool) -> void:
	main = v
	flag.texture = Assets.tex("flag_main" if main else "flag")

func build(k: String) -> void:
	up[k] = true
	if built.has(k):
		return
	var spec: Array = UP_SPRITE[k]
	built[k] = _place(spec[0], wpos + UP_OFFSET[k], spec[1])
	if k == "garden":
		var gx := int(floor(wpos.x)) - 4
		var gy := int(floor(wpos.y)) + 2
		for y in range(gy, gy + 2):
			for x in range(gx, gx + 2):
				var t := Sprite2D.new()
				t.texture = Assets.tex("garden")
				t.centered = false
				t.offset = Vector2(-16, 0)
				t.z_as_relative = false
				t.z_index = Iso.z_for(x + y, -2)
				t.position = Iso.to_screen(x, y, Game.I.world.vh(x, y))
				add_child(t)

func tower_pos() -> Vector2:
	return wpos + UP_OFFSET["tower"]

func _process(delta: float) -> void:
	_ft += delta
	if _ft > 0.12:
		_ft = 0.0
		fire.texture = Assets.tex("campfire1" if fire.texture == Assets.tex("campfire0") else "campfire0")
