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

var clip: Control
var zoom := 1.0
var marker: Control
var _blink := 0.0

func open() -> void:
	visible = true
	_layout()
	var near := game.world.nearest_loc(game.player.wpos, 20.0)
	_show_card(_loc(near.id) if not near.is_empty() else {})

func close() -> void:
	visible = false

func _process(d: float) -> void:
	if not visible or marker == null: return
	_blink += d
	marker.queue_redraw()

func _loc(id: String) -> Dictionary:
	for l in locs:
		if l.id == id: return l
	return {}

func _known(id: String) -> bool:
	return game.world.discovered.has(id)

func _layout() -> void:
	if not visible: return
	var vs := root.size
	var side := minf(vs.y - 24.0, vs.x * 0.62)
	if clip == null:
		clip = Control.new()
		clip.clip_contents = true
		root.add_child(clip)
		map_rect.reparent(clip)
	clip.position = Vector2(16, (vs.y - side) * 0.5)
	clip.size = Vector2(side, side)
	var big := side * zoom
	var pp: Vector2 = game.player.wpos / float(World.N) * big
	var off := Vector2.ZERO
	if zoom > 1.0:
		off = (Vector2(side, side) * 0.5 - pp).clamp(Vector2(side - big, side - big), Vector2.ZERO)
	map_rect.position = off
	map_rect.size = Vector2(big, big)
	for c in map_rect.get_children(): c.queue_free()
	for l in locs:
		var known := _known(l.id)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var hub: bool = l.type in ["hub", "city"]
		var r := (9.0 if hub else 6.0) * (1.0 if zoom == 1.0 else 1.3)
		b.size = Vector2(r * 2 + 10, r * 2 + 10)
		b.position = Vector2(l.pos[0], l.pos[1]) * big - b.size * 0.5
		b.draw.connect(func():
			var col := GREEN if known else DIM * Color(1, 1, 1, 0.55)
			if known:
				b.draw_arc(b.size * 0.5, r, 0, TAU, 20, col, 2.0)
				b.draw_circle(b.size * 0.5, 2.5, col)
			else:
				b.draw_arc(b.size * 0.5, r * 0.6, 0, TAU, 12, col, 1.0))
		var lid: String = l.id
		b.pressed.connect(func(): _show_card(_loc(lid)))
		map_rect.add_child(b)
	for c in game.camps:
		var cm := Control.new()
		cm.size = Vector2(14, 14)
		cm.position = c.wpos / float(World.N) * big - cm.size * 0.5
		cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cm.draw.connect(func():
			cm.draw_rect(Rect2(2, 2, 10, 10), Color(1, 0.85, 0.4), false, 2.0))
		map_rect.add_child(cm)
	marker = Control.new()
	marker.size = Vector2(20, 20)
	marker.position = pp - marker.size * 0.5
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(func():
		var on := fmod(_blink, 0.8) < 0.55
		var col := Color(1, 1, 0.7) if on else Color(0.6, 1, 0.6)
		marker.draw_circle(Vector2(10, 10), 4.0, col)
		marker.draw_arc(Vector2(10, 10), 8.0, 0, TAU, 16, col, 1.5))
	map_rect.add_child(marker)
	card.position = Vector2(clip.position.x + side + 16, clip.position.y)
	card.custom_minimum_size = Vector2(vs.x - card.position.x - 16, 0)

func _show_card(l: Dictionary) -> void:
	for c in card_box.get_children(): c.queue_free()
	var t := Hud.term_label(24); t.text = "SABLE WASTES · WORLD MAP"; card_box.add_child(t)
	var w: World = game.world
	var p := game.player.wpos
	var bl := Hud.term_label(15)
	var here := w.nearest_loc(p, 6.0)
	bl.text = "> %s · %s" % [("near " + here.name) if not here.is_empty() else "in the wilds", w.biome_name(p).capitalize()]
	card_box.add_child(bl)
	if not l.is_empty():
		var known := _known(l.id)
		var n := Hud.term_label(22); n.text = l.name.to_upper() if known else "??? (unexplored)"; card_box.add_child(n)
		var wl := w.loc_by_id(l.id)
		var dist := int(p.distance_to(wl.pos)) if not wl.is_empty() else 0
		var meta := Hud.term_label(15)
		meta.text = "%s · danger %d · %s · %d tiles away" % [l.type.capitalize(), int(l.danger), l.faction, dist]
		card_box.add_child(meta)
		if known:
			if l.get("trade", "") != "":
				var tr := Hud.term_label(15); tr.text = "Trades in: " + l.trade; card_box.add_child(tr)
			var ec := Economy.summary(w, l.id)
			if ec != "":
				var el := Hud.term_label(15); el.text = ec; el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; el.custom_minimum_size = Vector2(320, 0); card_box.add_child(el)
			var pt := Hud.term_label(15); pt.text = l.pitch
			pt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			pt.custom_minimum_size = Vector2(320, 0)
			card_box.add_child(pt)
			if not wl.is_empty() and dist > wl.r + 6:
				_btn("Fast travel here", func(): close(); game.travel_to_loc(wl), game.danger())
		else:
			var nl := Hud.term_label(15); nl.text = "> Get within sight of it to put it on your map."; card_box.add_child(nl)
	for c in game.camps:
		var cc = c
		if c.wpos.distance_to(p) > 8.0:
			_btn("Fast travel: " + c.cname, func(): close(); game.travel_to(cc), false)
	_btn("Zoom out" if zoom > 1.0 else "Zoom in on me", func(): zoom = 1.0 if zoom > 1.0 else 4.0; _layout(), false)
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
