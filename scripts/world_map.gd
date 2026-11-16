class_name WorldMap
extends CanvasLayer
## The Sable Wastes world map on a green phosphor screen. Tap a location for its card; places you can
## travel to (this region and your camps) get a Travel button. Other locations are not built yet.

const GREEN := Color("6cff86")
const DIM := Color("2f8a42")
var game: Game
var locs: Array = []
var root: Control
var map_rect: TextureRect
var card: PanelContainer
var card_box: VBoxContainer
var here := "patchwork"              # the region the current playable map stands for

func setup(g: Game) -> void:
	game = g
	layer = 7
	visible = false
	var f := FileAccess.open("res://assets/worldmap/locations.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d: locs = d.locations
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.04, 0.01, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	map_rect = TextureRect.new()
	map_rect.texture = load("res://assets/worldmap/worldmap.png")
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pipboy.gdshader")
	map_rect.material = mat
	root.add_child(map_rect)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Hud.term_box())
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 8)
	card.add_child(card_box)
	root.add_child(card)
	root.resized.connect(_layout)

func open() -> void:
	visible = true
	_layout()
	_show_card(_loc(here))

func close() -> void:
	visible = false

func _loc(id: String) -> Dictionary:
	for l in locs:
		if l.id == id: return l
	return {}

func _layout() -> void:
	if not visible: return
	var vs := root.size
	var side := minf(vs.y - 24.0, vs.x * 0.62)
	map_rect.position = Vector2(16, (vs.y - side) * 0.5)
	map_rect.size = Vector2(side, side)
	for c in map_rect.get_children(): c.queue_free()
	for l in locs:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var hub: bool = l.type in ["hub", "city"]
		var r := 9.0 if hub else 6.0
		b.size = Vector2(r * 2 + 10, r * 2 + 10)
		b.position = Vector2(l.pos[0], l.pos[1]) * side - b.size * 0.5
		b.draw.connect(func():
			var col := GREEN if (hub or l.id == here) else DIM
			b.draw_arc(b.size * 0.5, r, 0, TAU, 20, col, 2.0)
			b.draw_circle(b.size * 0.5, 2.5, col)
			if l.id == here:
				b.draw_arc(b.size * 0.5, r + 5, 0, TAU, 20, Color(1, 1, 0.6), 2.0))
		var lid: String = l.id
		b.pressed.connect(func(): _show_card(_loc(lid)))
		map_rect.add_child(b)
	card.position = Vector2(map_rect.position.x + side + 16, map_rect.position.y)
	card.custom_minimum_size = Vector2(vs.x - card.position.x - 16, 0)

func _show_card(l: Dictionary) -> void:
	for c in card_box.get_children(): c.queue_free()
	var t := Hud.term_label(24); t.text = "SABLE WASTES · WORLD MAP"; card_box.add_child(t)
	if not l.is_empty():
		var n := Hud.term_label(22); n.text = l.name.to_upper(); card_box.add_child(n)
		var meta := Hud.term_label(15)
		meta.text = "%s · danger %d · %s" % [l.type.capitalize(), int(l.danger), l.faction]
		card_box.add_child(meta)
		if l.get("trade", "") != "":
			var tr := Hud.term_label(15); tr.text = "Trades in: " + l.trade; card_box.add_child(tr)
		var p := Hud.term_label(15); p.text = l.pitch
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size = Vector2(320, 0)
		card_box.add_child(p)
		if l.id == here:
			var hl := Hud.term_label(15); hl.text = "> You are here."; card_box.add_child(hl)
			for c in game.camps:
				var cc = c
				_btn("Fast travel: " + c.cname, func(): close(); game.travel_to(cc), game.camps.size() < 2)
		else:
			var nl := Hud.term_label(15); nl.text = "> No map of this place yet: not reachable."; card_box.add_child(nl)
	_btn("Close map  [M]", close, false)

func _btn(text: String, cb: Callable, off: bool) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = off
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 46)
	Hud.term_button(b)
	b.pressed.connect(cb)
	card_box.add_child(b)
