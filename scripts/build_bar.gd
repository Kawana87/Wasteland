class_name BuildBar
extends PanelContainer
## The build-mode drawer: material tiers, pieces, rotate, done, and what the selection costs.

var base: BaseBuild
var tier_btns := {}
var piece_btns := {}
var rot_btn: Button
var info: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_theme_stylebox_override("panel", Hud.term_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	col.add_child(r1)
	for t in BaseBuild.TIERS:
		tier_btns[t] = _btn(r1, BaseBuild.NAMES[t], func(): base.select(t, ""))
	rot_btn = _btn(r1, "Rotate", func(): base.turn())
	_btn(r1, "Done", func(): base.leave())
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	col.add_child(r2)
	for p in BaseBuild.PIECES:
		piece_btns[p] = _btn(r2, BaseBuild.NAMES[p], func(): base.select("", p))
	info = Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Hud.INK)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 52)
	Hud.term_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func refresh() -> void:
	if base == null: return
	for t in tier_btns:
		_mark(tier_btns[t], t == base.tier and base.piece != "remove")
	for p in piece_btns:
		var b: Button = piece_btns[p]
		_mark(b, p == base.piece)
		b.disabled = base.tier == "fence" and not p in BaseBuild.FENCE_PIECES
	rot_btn.text = "Rotate " + ("╲" if base.axis == 0 else "╱")
	var st: Dictionary = base.g.stash
	var line := "Stash: %d scrap · %d wood · %d cloth" % [st.get("scrap", 0), st.get("wood", 0), st.get("cloth", 0)]
	if base.piece == "remove":
		line = "Tap a piece to tear it down (half the materials back).   " + line
	else:
		var c := base.cost_of(base.tier, base.piece)
		var parts := []
		for k in c: parts.append("%d %s" % [c[k], k])
		line = "%s %s: %s each.   %s" % [BaseBuild.NAMES[base.tier], BaseBuild.NAMES[base.piece].to_lower(), ", ".join(parts), line]
	info.text = line
	await get_tree().process_frame
	reset_size()
	position = Vector2(get_viewport().get_visible_rect().size.x - size.x - 8, 8)

func _mark(b: Button, on: bool) -> void:
	b.modulate = Color(1.6, 1.6, 1.0) if on else Color(1, 1, 1)
