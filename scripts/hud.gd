class_name Hud
extends CanvasLayer
## On-screen UI drawn at full resolution on top of the pixel-art world:
## stats, interaction prompt, toasts, menus, title screen, floating text, touch controls.

signal crt_toggled

var stats: Label
var prompt_l: Label
var toast_box: PanelContainer
var toast_l: Label
var toast_t := 0.0
var menu: PanelContainer
var menu_box: VBoxContainer
var menu_scroll: ScrollContainer
var title_layer: Control
var touch: TouchControls
var crt_btn: Button
var floaters := []
var bars: Control
var compass: Control
var job_l: Label
var card_l: Label
var card_t := 0.0
var radio_box: PanelContainer
var radio_l: Label
var radio_t := 0.0
var radio_btn: Button
var aim_btn: Button
var perk_btn: Button
signal radio_toggled
# filled by Game each frame
var hp := 20.0
var hp_max := 20.0
var xp_frac := 0.0
var level := 1
var ammo_s := ""
var facing := 0.0
var marks: Array = []      # [world angle, kind]

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	touch = TouchControls.new()
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch)
	var stats_panel := PanelContainer.new()
	var sb := term_box()
	sb.set_content_margin_all(8)
	stats_panel.add_theme_stylebox_override("panel", sb)
	stats_panel.position = Vector2(10, 8)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.add_child(sv)
	bars = Control.new()
	bars.custom_minimum_size = Vector2(230, 30)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars)
	sv.add_child(bars)
	stats = _label(14)
	sv.add_child(stats)
	# compass strip, top centre
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-200, 8)
	compass.size = Vector2(400, 34)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)
	job_l = _label(14)
	job_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	job_l.position = Vector2(-300, 44)
	job_l.size = Vector2(600, 20)
	job_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(job_l)
	# big centred card for discoveries and level ups
	card_l = Label.new()
	card_l.add_theme_font_size_override("font_size", 30)
	card_l.add_theme_color_override("font_color", INK)
	card_l.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.01))
	card_l.add_theme_constant_override("outline_size", 8)
	card_l.set_anchors_preset(Control.PRESET_CENTER)
	card_l.position = Vector2(-400, 60)        # just below the player: clear of toasts, speech above heads and the prompt
	card_l.size = Vector2(800, 90)
	card_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_l.modulate.a = 0.0
	root.add_child(card_l)
	# radio subtitle
	radio_box = PanelContainer.new()
	radio_box.add_theme_stylebox_override("panel", term_box())
	radio_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	radio_box.position = Vector2(-300, -120)
	radio_box.custom_minimum_size = Vector2(600, 0)
	radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_l = _label(15)
	radio_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	radio_box.add_child(radio_l)
	radio_box.visible = false
	root.add_child(radio_box)
	crt_btn = Button.new()
	crt_btn.text = "CRT: off"
	crt_btn.focus_mode = Control.FOCUS_NONE
	term_button(crt_btn)
	crt_btn.add_theme_font_size_override("font_size", 14)
	crt_btn.position = Vector2(14, 118)
	crt_btn.pressed.connect(func(): crt_toggled.emit())
	root.add_child(crt_btn)
	radio_btn = Button.new()
	radio_btn.text = "RADIO: off"
	radio_btn.focus_mode = Control.FOCUS_NONE
	term_button(radio_btn)
	radio_btn.add_theme_font_size_override("font_size", 14)
	radio_btn.pressed.connect(func(): radio_toggled.emit())
	root.add_child(radio_btn)
	aim_btn = Button.new()
	aim_btn.text = "AIM: standard"
	aim_btn.focus_mode = Control.FOCUS_NONE
	term_button(aim_btn)
	aim_btn.add_theme_font_size_override("font_size", 14)
	aim_btn.pressed.connect(func(): Game.I.set_aim_assist(not Game.I.aim_assist))
	root.add_child(aim_btn)
	perk_btn = Button.new()
	perk_btn.text = "PERK"
	perk_btn.focus_mode = Control.FOCUS_NONE
	term_button(perk_btn)
	perk_btn.add_theme_font_size_override("font_size", 14)
	perk_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	perk_btn.pressed.connect(func(): Game.I._offer_perk())
	perk_btn.visible = false
	root.add_child(perk_btn)
	prompt_l = _label(18)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_l.position = Vector2(-300, -150)
	prompt_l.size = Vector2(600, 30)
	root.add_child(prompt_l)
	toast_box = PanelContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-330, 172)    # below the CRT / RADIO / AIM row, clear of the compass
	toast_box.custom_minimum_size = Vector2(660, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.14, 0.85)))
	toast_l = _label(17)
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_box.add_child(toast_l)
	toast_box.visible = false
	root.add_child(toast_box)
	menu = PanelContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.custom_minimum_size = Vector2(440, 0)
	menu.add_theme_stylebox_override("panel", _box(Color(0.17, 0.13, 0.25, 0.97)))
	menu_scroll = ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(menu_scroll)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	menu_scroll.add_child(menu_box)
	menu.visible = false
	root.add_child(menu)
	title_layer = Control.new()
	title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_layer)

# ---- terminal look (green phosphor, like a wrist computer): shared by every panel, menu and the map
const INK := Color("8dffa0")
const INK_DIM := Color("4fb866")
const PANEL := Color(0.02, 0.09, 0.04, 0.92)

static func term_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.border_color = INK_DIM
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0.2, 1.0, 0.4, 0.18)
	s.shadow_size = 8
	return s

static func term_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.01))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func term_button(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = {"normal": Color(0.03, 0.14, 0.06, 0.95), "hover": Color(0.06, 0.24, 0.1, 0.95), "pressed": Color(0.1, 0.36, 0.15, 0.95), "disabled": Color(0.02, 0.07, 0.03, 0.8)}[st]
		s.border_color = INK_DIM if st != "hover" else INK
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.set_content_margin_all(8)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(0.85, 1, 0.88))
	b.add_theme_color_override("font_disabled_color", Color(0.25, 0.5, 0.3))
	b.add_theme_font_size_override("font_size", 16)

func _box(_c: Color) -> StyleBoxFlat:
	return term_box()

func _label(size: int) -> Label:
	return term_label(size)

## Toasts queue up: each shows for at least 2 s (longer for long text) and
## repeats of the same message merge into one with a count.
var toast_q: Array = []
var toast_cur := ""
var toast_n := 1

func toast(msg: String) -> void:
	if msg == toast_cur and toast_t > 0.0:
		toast_n += 1
		toast_l.text = "%s  (x%d)" % [msg, toast_n]
		toast_t = maxf(toast_t, 2.0)
		return
	for q in toast_q:
		if q.msg == msg:
			q.n += 1
			return
	toast_q.append({"msg": msg, "n": 1})
	if toast_t <= 0.0:
		_next_toast()

func _next_toast() -> void:
	if toast_q.is_empty():
		toast_box.visible = false
		toast_cur = ""
		return
	var q: Dictionary = toast_q.pop_front()
	toast_cur = q.msg
	toast_n = q.n
	toast_l.text = q.msg if q.n == 1 else "%s  (x%d)" % [q.msg, q.n]
	toast_box.visible = true
	# 2 s minimum, more for long messages; hurry along when others are waiting
	toast_t = clampf(1.6 + q.msg.length() * 0.035, 2.0, 5.5)
	if toast_q.size() > 2:
		toast_t = 2.0

func clear_toasts() -> void:
	toast_q.clear()
	toast_t = 0.0
	toast_cur = ""
	toast_box.visible = false

func show_card(t: String) -> void:
	card_l.text = t
	card_t = 3.2

func radio_line(t: String) -> void:
	radio_l.text = "SABLE RADIO 88.1 — " + t
	radio_t = 8.0
	radio_box.visible = true

func _draw_bars() -> void:
	var f: Font = ThemeDB.fallback_font
	# health bar
	var w := 150.0
	bars.draw_rect(Rect2(0, 2, w, 11), Color(0.05, 0.15, 0.07))
	var fr := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	var col := INK if fr > 0.35 else Color(1.0, 0.45, 0.35)
	bars.draw_rect(Rect2(0, 2, w * fr, 11), col)
	for k in range(1, int(hp_max / 5.0) + 1):
		bars.draw_line(Vector2(w * k * 5.0 / hp_max, 2), Vector2(w * k * 5.0 / hp_max, 13), Color(0, 0.1, 0.02, 0.8), 1.0)
	bars.draw_rect(Rect2(0, 2, w, 11), INK_DIM, false, 1.0)
	bars.draw_string(f, Vector2(w + 8, 13), "HP %d/%d" % [int(ceil(hp)), int(hp_max)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	# xp bar
	bars.draw_rect(Rect2(0, 19, w, 5), Color(0.05, 0.15, 0.07))
	bars.draw_rect(Rect2(0, 19, w * xp_frac, 5), Color(0.95, 0.85, 0.4))
	bars.draw_string(f, Vector2(w + 8, 27), "LVL %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.85, 0.4))

## Fallout-style compass: centred on the way you're facing; places you haven't found yet are hollow,
## found places filled, camps square, the current job an amber arrow, enemies hunting you red ticks.
func _draw_compass() -> void:
	var W := compass.size.x
	var f: Font = ThemeDB.fallback_font
	compass.draw_rect(Rect2(0, 0, W, 30), Color(0.02, 0.09, 0.04, 0.75))
	compass.draw_rect(Rect2(0, 0, W, 30), INK_DIM, false, 1.0)
	var span := deg_to_rad(110.0)
	var px := func(a: float) -> float:
		return W * 0.5 + wrapf(a - facing, -PI, PI) / span * W * 0.5
	for k in 24:
		var a := k * TAU / 24.0 - PI * 0.5
		var x: float = px.call(a)
		if x < 4 or x > W - 4: continue
		var card: String = ["N", "", "", "", "", "", "E", "", "", "", "", "", "S", "", "", "", "", "", "W", "", "", "", "", ""][k]
		if card != "":
			compass.draw_string(f, Vector2(x - 5, 21), card, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
		else:
			compass.draw_line(Vector2(x, 4), Vector2(x, 8 if k % 3 else 11), INK_DIM, 1.0)
	for m in marks:
		var x: float = px.call(m[0])
		if x < 6 or x > W - 6: continue
		match m[1]:
			"loc_new": compass.draw_polyline(PackedVector2Array([Vector2(x, 18), Vector2(x + 5, 23), Vector2(x, 28), Vector2(x - 5, 23), Vector2(x, 18)]), INK, 1.5)
			"loc": compass.draw_colored_polygon(PackedVector2Array([Vector2(x, 19), Vector2(x + 4, 23), Vector2(x, 27), Vector2(x - 4, 23)]), INK_DIM)
			"camp": compass.draw_rect(Rect2(x - 3, 20, 7, 7), Color(1, 0.85, 0.4), false, 1.5)
			"job": compass.draw_colored_polygon(PackedVector2Array([Vector2(x - 6, 17), Vector2(x + 6, 17), Vector2(x, 28)]), Color(1.0, 0.75, 0.25))
			"enemy": compass.draw_rect(Rect2(x - 1, 2, 3, 10), Color(1.0, 0.35, 0.3))
			"bag": compass.draw_circle(Vector2(x, 23), 4.5, Color(1.0, 0.55, 0.3))
	compass.draw_line(Vector2(W * 0.5, 0), Vector2(W * 0.5, 4), INK, 2.0)

func set_prompt(t: String) -> void:
	prompt_l.text = t

func set_crt_label(on: bool) -> void:
	crt_btn.text = "CRT: on" if on else "CRT: off"

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			_next_toast()
	var sp := stats.get_parent().get_parent() as Control
	crt_btn.position = Vector2(12, sp.position.y + sp.size.y + 6)
	radio_btn.position = Vector2(crt_btn.position.x + crt_btn.size.x + 8, crt_btn.position.y)
	aim_btn.position = Vector2(radio_btn.position.x + radio_btn.size.x + 8, crt_btn.position.y)
	perk_btn.position = Vector2(aim_btn.position.x + aim_btn.size.x + 8, crt_btn.position.y)
	perk_btn.visible = Game.I.perk_points > 0 and Game.I.state == "play"
	perk_btn.text = "PERK (%d)" % Game.I.perk_points if Game.I.perk_points > 1 else "PERK"
	if card_t > 0.0:
		card_t -= delta
		card_l.modulate.a = clampf(card_t, 0.0, 1.0) * clampf((3.2 - card_t) * 3.0, 0.0, 1.0)
	if radio_t > 0.0:
		radio_t -= delta
		radio_box.visible = radio_t > 0.0
	bars.queue_redraw()
	compass.queue_redraw()

## buttons: Array of [label, Callable, disabled(bool)]
func show_menu(title: String, lines: Array, buttons: Array) -> void:
	for c in menu_box.get_children():
		c.queue_free()
	var t := _label(22)
	t.text = title
	t.add_theme_color_override("font_color", Color(0.85, 1, 0.88))
	menu_box.add_child(t)
	for ln in lines:
		var l := _label(15)
		l.text = ln
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(400, 0)
		menu_box.add_child(l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.disabled = b[2]
		btn.focus_mode = Control.FOCUS_NONE
		term_button(btn)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(400, 40)
		if "\n" in btn.text:
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.custom_minimum_size = Vector2(480, 0)
		btn.pressed.connect(b[1])
		menu_box.add_child(btn)
	menu.visible = true
	menu_scroll.custom_minimum_size = Vector2.ZERO
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	var want := menu_box.get_combined_minimum_size()
	menu_scroll.custom_minimum_size = Vector2(want.x + 12, minf(want.y, vs.y - 60))
	menu_scroll.scroll_vertical = 0
	menu.reset_size()
	menu.position = (vs - menu.size) * 0.5

func hide_menu() -> void:
	menu.visible = false

func menu_open() -> bool:
	return menu.visible

func show_title(text: String, on_start: Callable, on_continue: Callable = Callable(), controls: String = "") -> void:
	for c in title_layer.get_children():
		c.queue_free()
	title_layer.visible = true
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.05, 0.02, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	title_layer.add_child(box)
	var h := _label(46)
	h.text = "WASTELAND"
	h.add_theme_color_override("font_color", INK)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)
	var body := _label(16)
	body.text = text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(760, 0)
	box.add_child(body)
	var go := Button.new()
	go.text = "  Start a new world  "
	term_button(go)
	go.add_theme_font_size_override("font_size", 22)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func():
		title_layer.visible = false
		on_start.call())
	if on_continue.is_valid():
		var cont := Button.new()
		cont.text = "  Continue  "
		term_button(cont)
		cont.add_theme_font_size_override("font_size", 22)
		cont.focus_mode = Control.FOCUS_NONE
		cont.pressed.connect(func():
			title_layer.visible = false
			on_continue.call())
		box.add_child(cont)
		go.text = "  Start over (new character)  "
		go.add_theme_font_size_override("font_size", 16)
	box.add_child(go)
	if controls != "":
		var cb := Button.new()
		cb.text = "  Controls  "
		term_button(cb)
		cb.add_theme_font_size_override("font_size", 16)
		cb.focus_mode = Control.FOCUS_NONE
		cb.pressed.connect(func():
			body.text = controls if body.text == text else text
			cb.text = "  Back  " if body.text == controls else "  Controls  "
			await get_tree().process_frame
			box.reset_size()
			box.position = (get_viewport().get_visible_rect().size - box.size) * 0.5)
		box.add_child(cb)
	await get_tree().process_frame
	box.reset_size()
	box.position = (get_viewport().get_visible_rect().size - box.size) * 0.5

func float_text(txt: String, col: Color) -> Label:
	var l := _label(15)
	l.text = txt
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l
