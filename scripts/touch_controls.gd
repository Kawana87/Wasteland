class_name TouchControls
extends Control
## Touch controls: left thumb moves; aiming is automatic (the game locks on to the nearest enemy in
## range) and the big FIRE button shoots while held. Round action buttons on the right.
## Only shown once the screen is touched.

signal action(name: String)

const STICK_R := 70.0
var enabled := false
var build_mode := false               # right-side touches drive the build cursor instead of aiming
var build_touch := -1
var sticks := {"L": {}, "R": {}}      # side -> {id, origin, vec}
var held := {}                        # touch index -> button name
var buttons := [
	{"name": "fire", "label": "FIRE", "pos": Vector2(-130, -150), "r": 66.0},
	{"name": "melee", "label": "HIT", "pos": Vector2(-275, -105)},
	{"name": "use", "label": "USE", "pos": Vector2(-75, -295)},
	{"name": "sneak", "label": "SNEAK", "pos": Vector2(-290, -235)},
	{"name": "camp", "label": "CAMP", "pos": Vector2(-190, -335)},
	{"name": "inv", "label": "INV", "pos": Vector2(-75, -415)},
	{"name": "map", "label": "MAP", "pos": Vector2(-305, -365)},
	{"name": "heal", "label": "HEAL", "pos": Vector2(-188, -238), "r": 36.0},
]
const BTN_R := 44.0

func move_vec() -> Vector2:
	return sticks.L.get("vec", Vector2.ZERO)

func aim_vec() -> Vector2:
	return sticks.R.get("vec", Vector2.ZERO)

func firing() -> bool:
	return "fire" in held.values()

func _btn_center(b: Dictionary) -> Vector2:
	var s := size
	return Vector2(s.x + b.pos.x, s.y + b.pos.y)

func _btn_at(p: Vector2) -> String:
	for b in buttons:
		if p.distance_to(_btn_center(b)) < b.get("r", BTN_R):
			return b.name
	return ""

func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if not enabled:
			enabled = true
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * ev.position
		if build_mode and Game.I and Game.I.base:
			var bar: Control = Game.I.base.bar
			if ev.pressed and p.x >= size.x * 0.5 and build_touch < 0 and not (bar and bar.visible and bar.get_global_rect().has_point(ev.position)):
				build_touch = ev.index
				Game.I.base.press(ev.position)
				return
			if not ev.pressed and ev.index == build_touch:
				build_touch = -1
				Game.I.base.release(ev.position)
				return
		if ev.pressed:
			if Game.I and Game.I.hud.menu_open():
				return
			var bn := "" if build_mode else _btn_at(p)
			if bn != "":
				held[ev.index] = bn
				action.emit(bn)
			else:
				var side := "L" if p.x < size.x * 0.5 else "R"
				if side == "L" and sticks[side].is_empty():
					sticks[side] = {"id": ev.index, "origin": p, "vec": Vector2.ZERO, "pos": p}
		else:
			held.erase(ev.index)
			queue_redraw()
			for side in sticks:
				if not sticks[side].is_empty() and sticks[side].id == ev.index:
					sticks[side] = {}
		queue_redraw()
	elif ev is InputEventScreenDrag:
		if build_mode and ev.index == build_touch and Game.I and Game.I.base:
			Game.I.base.move(ev.position)
			return
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * ev.position
		for side in sticks:
			var st: Dictionary = sticks[side]
			if not st.is_empty() and st.id == ev.index:
				var v: Vector2 = (p - st.origin) / STICK_R
				if v.length() > 1.0:
					v = v.normalized()
				st.vec = v
				st.pos = st.origin + v * STICK_R
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	var font := get_theme_default_font()
	for b in ([] if build_mode else buttons):
		var c := _btn_center(b)
		var r: float = b.get("r", BTN_R)
		var down: bool = b.name in held.values()
		var fs := 22 if b.name == "fire" else 16
		draw_circle(c, r, Color(0.1, 0.5, 0.2, 0.45 if down else 0.22) if b.name != "fire" else Color(0.55, 0.15, 0.1, 0.5 if down else 0.28))
		draw_arc(c, r, 0, TAU, 40, Color(0.55, 1.0, 0.63, 0.85) if b.name != "fire" else Color(1.0, 0.6, 0.45, 0.9), 2.5 if b.name == "fire" else 2.0)
		var ts := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.38), b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color("8dffa0") if b.name != "fire" else Color("ffc0a8"))
	for side in sticks:
		var st: Dictionary = sticks[side]
		if st.is_empty():
			continue
		draw_arc(st.origin, STICK_R, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
		draw_circle(st.pos, 22, Color(1, 1, 1, 0.4))
