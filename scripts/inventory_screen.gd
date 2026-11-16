class_name InventoryScreen
extends CanvasLayer
## Full-page inventory on the green terminal: equipped gear on the left, a grid of everything you carry
## in the middle (icons, stack counts), the selected item's stats and actions on the right.

const DESC := {
	"pipe_pistol": "A length of pipe, a spring and a prayer. Jams less than you'd think.",
	"pistol_10mm": "Pre-war service pistol. Reliable, accurate, loud.",
	"smg": "Welded together from three broken guns. Sprays more than it aims.",
	"shotgun": "Both barrels sawn short. Devastating up close, useless far away.",
	"rifle": "Bolt-action hunting rifle. One shot, one problem solved.",
	"fists": "Your own two hands.",
	"pipe": "Heavy lead pipe. Simple, dependable, satisfying.",
	"machete": "Brush-clearing blade with a wicked edge.",
	"spiked_bat": "A ball bat with nails driven through. Raider favourite.",
	"cap": "Worn leather cap. Keeps the sun and a little shrapnel off.",
	"road_helmet": "Motorcycle helmet with a scratched visor.",
	"jacket": "Thick leather jacket. Turns a knife, mostly.",
	"raider_plates": "Car-door steel strapped over leather.",
	"combat_vest": "Pre-war military vest with trauma plates.",
	"ammo_pistol": "Pistol rounds. The Wastes' small change.",
	"ammo_shell": "Hand-loaded shotgun shells.",
	"ammo_rifle": "Long rifle cartridges.",
	"medkit": "Bandages, antiseptic and a stimpak.",
	"food": "Tinned something. Still good, probably.",
	"lockpick": "A bent pick and a tension wrench.",
}
const SLOTS := ["gun", "melee", "head", "body"]
const SLOT_NAMES := {"gun": "GUN", "melee": "MELEE", "head": "HEAD", "body": "BODY"}

var game: Game
var root: Control
var header: Label
var eq_box: VBoxContainer
var grid: GridContainer
var detail: VBoxContainer
var sel := ""

func setup(g: Game) -> void:
	game = g
	layer = 7
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.035, 0.012, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var scan := ColorRect.new()                     # faint scanlines over the whole page
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float s = 0.5 + 0.5 * sin(FRAGCOORD.y * 2.2); COLOR = vec4(0.0, 0.0, 0.0, 0.18 * s); }"
	sm.shader = sh
	scan.material = sm
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + s, 18)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	header = Hud.term_label(20)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(header)
	for bd in [["  NOTES  ", func(): close_screen(); game.show_notes()], ["  PERKS & STATS  ", func(): close_screen(); game.show_stats()]]:
		var nb := Button.new()
		nb.text = bd[0]
		nb.focus_mode = Control.FOCUS_NONE
		Hud.term_button(nb)
		nb.pressed.connect(bd[1])
		top.add_child(nb)
	var close := Button.new()
	close.text = "  CLOSE  [I]  "
	close.focus_mode = Control.FOCUS_NONE
	Hud.term_button(close)
	close.pressed.connect(close_screen)
	top.add_child(close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	var left := _panel(body, 230)
	eq_box = VBoxContainer.new(); eq_box.add_theme_constant_override("separation", 8); left.add_child(eq_box)
	var mid := _panel(body, 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var right := _panel(body, 330)
	detail = VBoxContainer.new(); detail.add_theme_constant_override("separation", 8); right.add_child(detail)
	root.add_child(scan)

func _panel(parent: Control, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Hud.term_box())
	if w > 0: p.custom_minimum_size = Vector2(w, 0)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	return p

func open() -> void:
	visible = true
	refresh()

func close_screen() -> void:
	visible = false

func refresh() -> void:
	if not visible: return
	var p := game.player
	header.text = "STATUS  ·  HP %d/%d  ·  ARMOUR %d (%d%% less damage)  ·  CARRYING %d scrap · %d cloth · %d wood  ·  STASH %d scrap · %d cloth · %d wood" % [
		int(p.hp), int(p.max_hp), game.armor_total(), int(minf(0.6, game.armor_total() * 0.07) * 100),
		p.carry.scrap, p.carry.cloth, p.carry.wood, game.stash.scrap, game.stash.cloth, game.stash.wood]
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for c in eq_box.get_children(): c.queue_free()
	var t := Hud.term_label(18); t.text = "EQUIPPED"; eq_box.add_child(t)
	for s in SLOTS:
		var id: String = game.equip[s]
		var row := HBoxContainer.new()
		row.add_child(_icon(id, 56))
		var l := Hud.term_label(15)
		l.text = "%s\n%s" % [SLOT_NAMES[s], Items.iname(id) if id != "" else "—"]
		row.add_child(l)
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(200, 60)
		b.add_child(row)
		b.focus_mode = Control.FOCUS_NONE
		var sid := id
		b.pressed.connect(func(): sel = sid; refresh())
		eq_box.add_child(b)
	for c in grid.get_children(): c.queue_free()
	var vw := root.size.x
	grid.columns = clampi(int((vw - 640) / 96), 3, 8)
	for it in game.inventory:
		grid.add_child(_cell(it.id, it.n))
	if game.inventory.is_empty():
		var e := Hud.term_label(16); e.text = "Nothing in your pack."; grid.add_child(e)
	_detail()

func _icon(id: String, sz: int) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if id != "" and ResourceLoader.exists("res://assets/sprites/icon_%s.png" % id):
		tr.texture = load("res://assets/sprites/icon_%s.png" % id)
	return tr

func _cell(id: String, n: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 88)
	b.focus_mode = Control.FOCUS_NONE
	Hud.term_button(b)
	if id == sel:
		var st := Hud.term_box(); st.border_color = Hud.INK; st.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", st)
	var ic := _icon(id, 80)
	ic.position = Vector2(4, 2)
	b.add_child(ic)
	if n > 1:
		var c := Hud.term_label(14); c.text = "×%d" % n; c.position = Vector2(50, 64)
		b.add_child(c)
	var d := Items.info(id)
	if d.get("slot", "") in SLOTS and game.equip.get(d.slot, "") == id:
		var e := Hud.term_label(13); e.text = "E"; e.position = Vector2(6, 2)
		b.add_child(e)
	b.tooltip_text = Items.iname(id)
	b.pressed.connect(func(): sel = id; refresh())
	return b

func _detail() -> void:
	for c in detail.get_children(): c.queue_free()
	if sel == "" or (game.inv_count(sel) == 0 and not sel in game.equip.values()):
		var h := Hud.term_label(16); h.text = "Select an item to see its stats."; detail.add_child(h)
		return
	var d := Items.info(sel)
	detail.add_child(_icon(sel, 128))
	var n := Hud.term_label(22); n.text = Items.iname(sel).to_upper(); detail.add_child(n)
	var lines := []
	match d.get("slot", ""):
		"gun":
			lines.append("Damage  %d%s" % [d.dmg, " × %d pellets" % d.pellets if d.get("pellets", 1) > 1 else ""])
			lines.append("Fire rate  %.1f / s" % (1.0 / d.rate))
			lines.append("Accuracy  %d%%" % int(100 - d.spread * 200))
			lines.append("Range  %d tiles" % int(d.speed * d.life))
			lines.append("Ammo  %s (%d)" % [Items.iname(d.ammo), game.inv_count(d.ammo)])
		"melee": lines.append("Damage  %d" % d.dmg)
		"head", "body": lines.append("Armour  %d  (−%d%% damage)" % [d.armor, d.armor * 7])
		"use": lines.append("Heals  %d HP" % d.heal)
	if d.get("trade", false): lines.append("Trade good — prices differ town to town")
	lines.append("Value  %d scrap" % d.get("value", 0))
	if d.has("tier"): lines.append("Quality  " + ["—", "Worn", "Standard", "Fine"][clampi(d.tier, 0, 3)])
	var st := Hud.term_label(16); st.text = "\n".join(lines); detail.add_child(st)
	var ds := Hud.term_label(14); ds.text = DESC.get(sel, d.get("desc", "")); ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(290, 0); ds.add_theme_color_override("font_color", Hud.INK_DIM); detail.add_child(ds)
	var slot: String = d.get("slot", "")
	if slot == "use":
		_act("USE", func(): game.use_item(sel), game.player.hp >= game.player.max_hp)
	elif slot in SLOTS:
		if game.equip[slot] == sel:
			if slot != "melee" or sel != "fists":
				_act("UNEQUIP", func(): game.unequip(slot), false)
		else:
			_act("EQUIP", func(): game.equip_item(sel), false)
	if game.inv_count(sel) > 0 and slot != "":
		_act("DROP ONE", func(): game.drop_item(sel), false)

func _act(text: String, cb: Callable, off: bool) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = off
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	Hud.term_button(b)
	b.pressed.connect(cb)
	detail.add_child(b)
