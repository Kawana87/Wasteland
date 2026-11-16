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
var title_layer: Control
var touch: TouchControls
var crt_btn: Button
var floaters := []

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
	stats_panel.add_theme_stylebox_override("panel", term_box())
	stats_panel.position = Vector2(10, 8)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_panel)
	stats = _label(16)
	stats_panel.add_child(stats)
	crt_btn = Button.new()
	crt_btn.text = "CRT: off"
	crt_btn.focus_mode = Control.FOCUS_NONE
	term_button(crt_btn)
	crt_btn.add_theme_font_size_override("font_size", 14)
	crt_btn.position = Vector2(14, 118)
	crt_btn.pressed.connect(func(): crt_toggled.emit())
	root.add_child(crt_btn)
	prompt_l = _label(18)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_l.position = Vector2(-300, -150)
	prompt_l.size = Vector2(600, 30)
	root.add_child(prompt_l)
	toast_box = PanelContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-330, 70)
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
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	menu.add_child(menu_box)
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

func toast(msg: String) -> void:
	toast_l.text = msg
	toast_box.visible = true
	toast_t = 3.6

func set_prompt(t: String) -> void:
	prompt_l.text = t

func set_crt_label(on: bool) -> void:
	crt_btn.text = "CRT: on" if on else "CRT: off"

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast_box.visible = false
	crt_btn.position = Vector2(12, stats.get_parent().position.y + stats.get_parent().size.y + 6)

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
		btn.pressed.connect(b[1])
		menu_box.add_child(btn)
	menu.visible = true
	await get_tree().process_frame
	menu.reset_size()
	menu.position = (get_viewport().get_visible_rect().size - menu.size) * 0.5

func hide_menu() -> void:
	menu.visible = false

func menu_open() -> bool:
	return menu.visible

func show_title(text: String, on_start: Callable) -> void:
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
	box.add_child(go)
	await get_tree().process_frame
	box.reset_size()
	box.position = (get_viewport().get_visible_rect().size - box.size) * 0.5

func float_text(txt: String, col: Color) -> Label:
	var l := _label(15)
	l.text = txt
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l
