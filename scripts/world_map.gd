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
var center := Vector2.ZERO        # world position at the middle of the map view
var marker: Control
var _blink := 0.0
const ZMIN := 1.0
const ZMAX := 12.0
var _touches := {}                # finger index -> screen position
var _pinch0 := 0.0                # finger distance when the pinch started
var _zoom0 := 1.0
var _moved := 0.0                 # how far the current touch has dragged (to tell a tap from a pan)
var _built := false

func open() -> void:
	if game.under != "":
		game.hud.toast("No signal underground. The map works again on the surface.")
		return
	visible = true
	game.audio.play("pipboy", Vector2.INF, -6.0, 0.0)
	center = game.player.wpos
	_touches.clear()
	_built = false
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

func _side() -> float:
	var vs := root.size
	return minf(vs.y - 24.0, vs.x * 0.62)

## Build the map view and its markers (once per opening), then place them for the current zoom.
func _layout() -> void:
	if not visible: return
	var vs := root.size
	var side := _side()
	if clip == null:
		clip = Control.new()
		clip.clip_contents = true
		root.add_child(clip)
		map_rect.reparent(clip)
	clip.position = Vector2(16, (vs.y - side) * 0.5)
	clip.size = Vector2(side, side)
	card.position = Vector2(clip.position.x + side + 16, clip.position.y)
	card.custom_minimum_size = Vector2(vs.x - card.position.x - 16, 0)
	if not _built:
		_build_markers()
		_built = true
	_place()

func _mark(c: Control, w: Vector2) -> void:
	c.set_meta("w", w)
	map_rect.add_child(c)

func _build_markers() -> void:
	for c in map_rect.get_children(): c.queue_free()
	for l in locs:
		var known := _known(l.id)
		var lid: String = l.id
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS     # let drags through to pan the map
		var hub: bool = l.type in ["hub", "city"]
		var r := 9.0 if hub else 6.0
		b.size = Vector2(r * 2 + 14, r * 2 + 14)
		b.draw.connect(func():
			var col := GREEN if known else DIM * Color(1, 1, 1, 0.55)
			if known:
				b.draw_arc(b.size * 0.5, r, 0, TAU, 20, col, 2.0)
				b.draw_circle(b.size * 0.5, 2.5, col)
				if game.world.cleared.has(lid):
					var c2 := b.size * 0.5
					b.draw_line(c2 - Vector2(r, r) * 0.7, c2 + Vector2(r, r) * 0.7, col, 2.0)
					b.draw_line(c2 + Vector2(-r, r) * 0.7, c2 + Vector2(r, -r) * 0.7, col, 2.0)
			else:
				b.draw_arc(b.size * 0.5, r * 0.6, 0, TAU, 12, col, 1.0))
		b.pressed.connect(func():
			if _moved < 12.0: _show_card(_loc(lid)))
		_mark(b, Vector2(l.pos[0], l.pos[1]) * World.N)
	for c in game.camps:
		var cm := Control.new()
		cm.size = Vector2(14, 14)
		cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cm.draw.connect(func():
			cm.draw_rect(Rect2(2, 2, 10, 10), Color(1, 0.85, 0.4), false, 2.0))
		_mark(cm, c.wpos)
	for j in game.jobs:
		var jm := Control.new()
		jm.size = Vector2(18, 18)
		jm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		jm.draw.connect(func():
			jm.draw_colored_polygon(PackedVector2Array([Vector2(2, 2), Vector2(16, 2), Vector2(9, 16)]), Color(1.0, 0.75, 0.25)))
		_mark(jm, j.target)
	if not game.recovery.is_empty() and game.recovery.get("under", "") == "":
		var bm := Control.new()
		bm.size = Vector2(16, 16)
		bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bm.draw.connect(func(): bm.draw_circle(Vector2(8, 8), 5.0, Color(1.0, 0.55, 0.3)))
		_mark(bm, game.recovery.pos)
	marker = Control.new()
	marker.size = Vector2(20, 20)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(func():
		var on := fmod(_blink, 0.8) < 0.55
		var col := Color(1, 1, 0.7) if on else Color(0.6, 1, 0.6)
		marker.draw_circle(Vector2(10, 10), 4.0, col)
		marker.draw_arc(Vector2(10, 10), 8.0, 0, TAU, 16, col, 1.5))
	_mark(marker, game.player.wpos)

## Position the map and every marker for the current zoom and centre (cheap: runs every pinch step).
func _place() -> void:
	var side := _side()
	zoom = clampf(zoom, ZMIN, ZMAX)
	var big := side * zoom
	var half := float(World.N) * 0.5 / zoom
	center = center.clamp(Vector2(half, half), Vector2(World.N - half, World.N - half))
	map_rect.size = Vector2(big, big)
	map_rect.position = Vector2(side, side) * 0.5 - center / float(World.N) * big
	for c in map_rect.get_children():
		if c.has_meta("w"):
			c.position = (c.get_meta("w") as Vector2) / float(World.N) * big - c.size * 0.5

## Zoom by factor f keeping the world point under screen point `at` (local to the map view) still.
func _zoom_at(f: float, at: Vector2) -> void:
	var side := _side()
	var before := _screen_to_world(at, side)
	zoom = clampf(zoom * f, ZMIN, ZMAX)
	center = before - (at - Vector2(side, side) * 0.5) / (side * zoom) * World.N
	_place()

func _screen_to_world(at: Vector2, side: float) -> Vector2:
	return center + (at - Vector2(side, side) * 0.5) / (side * zoom) * World.N

func _pan(screen_d: Vector2) -> void:
	center -= screen_d / (_side() * zoom) * World.N
	_place()

## Pinch with two fingers to zoom, drag with one to pan; mouse wheel and drag on desktop.
func _input(ev: InputEvent) -> void:
	if not visible or clip == null: return
	var r := clip.get_global_rect()
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if not r.has_point(ev.position) and _touches.is_empty(): return
			_touches[ev.index] = ev.position
			if _touches.size() == 1: _moved = 0.0
			if _touches.size() == 2:
				var ps: Array = _touches.values()
				_pinch0 = maxf(1.0, (ps[0] as Vector2).distance_to(ps[1]))
				_zoom0 = zoom
				_moved = 99.0   # a pinch is never a tap
		else:
			_touches.erase(ev.index)
			if _touches.size() < 2: _pinch0 = 0.0
	elif ev is InputEventScreenDrag and _touches.has(ev.index):
		var prev: Vector2 = _touches[ev.index]
		_touches[ev.index] = ev.position
		if _touches.size() >= 2 and _pinch0 > 0.0:
			var ps: Array = _touches.values()
			var a: Vector2 = ps[0]
			var b: Vector2 = ps[1]
			var mid := (a + b) * 0.5 - r.position
			var want := clampf(_zoom0 * a.distance_to(b) / _pinch0, ZMIN, ZMAX)
			_zoom_at(want / zoom, mid)
			_pan((ev.position - prev) * 0.5)    # moving the pinch pans too
			get_viewport().set_input_as_handled()
		elif _touches.size() == 1:
			_moved += (ev.position - prev).length()
			if _moved > 12.0:
				_pan(ev.position - prev)
				get_viewport().set_input_as_handled()
	elif ev is InputEventMagnifyGesture and r.has_point(ev.position):
		_zoom_at(ev.factor, ev.position - r.position)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and r.has_point(ev.position) and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom_at(1.25 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, ev.position - r.position)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed and r.has_point(ev.position) and not game.using_touch:
		_moved = 0.0
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and not game.using_touch and r.has_point(ev.position):
		_moved += ev.relative.length()
		if _moved > 12.0: _pan(ev.relative)

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
	_btn("Zoom in on me  (or pinch the map)", func():
		zoom = maxf(zoom, 4.0)
		center = game.player.wpos
		_place(), false)
	_btn("Whole map", func():
		zoom = 1.0
		_place(), false)
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
