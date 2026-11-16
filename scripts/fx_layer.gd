class_name FxLayer
extends Node2D
## Draws fast-moving bits on top of the world: bullets, particles, loot sparkles,
## the red hurt flash and the fade used for fast travel / blacking out.

var fade := 0.0
var fade_text := ""
var flash := 0.0

func _draw() -> void:
	var g := Game.I
	if g == null or g.world == null:
		return
	var w := g.world
	# lock-on brackets around the auto-aim target
	if g.locked != null and is_instance_valid(g.locked) and not g.locked.dead:
		var c: Vector2 = (g.locked.position + Vector2(0, -20)).round()
		var s := 12.0 + sin(g.time * 8.0) * 1.0
		var col := Color(1.0, 0.45, 0.3, 0.9)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var k := c + Vector2(sx * s * 0.8, sy * s * 1.5)
				draw_line(k, k - Vector2(sx * 5, 0), col, 1.0)
				draw_line(k, k - Vector2(0, sy * 5), col, 1.0)
	# boss names over their heads
	for e in g.enemies:
		if not e.dead and e.visible and e.has_meta("boss"):
			var bp: Vector2 = (e.position + Vector2(0, -44)).round()
			var nm: String = e.get_meta("boss")
			var font: Font = ThemeDB.fallback_font
			draw_string(font, bp + Vector2(-nm.length() * 3, 0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.75, 0.3))
			draw_rect(Rect2(bp + Vector2(-14, 3), Vector2(28, 3)), Color(0.2, 0.05, 0.05))
			draw_rect(Rect2(bp + Vector2(-14, 3), Vector2(28 * e.hp / e.max_hp, 3)), Color(1, 0.35, 0.25))
	for b in g.bullets:
		var p := Iso.to_screen(b.pos.x, b.pos.y, b.z).round()
		draw_rect(Rect2(p, Vector2(2, 2)), Color("ff7a4a") if b.enemy else Color("f2e27a"))
	for q in g.particles:
		var p := Iso.to_screen(q.pos.x, q.pos.y, q.gz + q.z).round()
		draw_rect(Rect2(p, Vector2(1, 1)), q.col)
	var pb := g.player.building()
	var sparkle := sin(g.time * 5.0)
	for c in w.near(g.player.wpos, "crates"):
		if c.open or c.bid != pb or c.fl != g.player.fl:
			continue
		if sin(g.time * 5.0 + c.pos.x * 3.0) > 0.75:
			var p := Iso.to_screen(c.pos.x, c.pos.y, w.stand_z(c.pos.x, c.pos.y, c.fl) + 14.0).round()
			draw_rect(Rect2(p, Vector2(2, 2)), Color("f2e27a"))
	var vs := Vector2(g.vp.size)
	var tl := g.cam.get_screen_center_position() - vs * 0.5
	if flash > 0.0:
		draw_rect(Rect2(tl, vs), Color(0.8, 0.12, 0.12, flash))
	if fade > 0.0:
		draw_rect(Rect2(tl, vs), Color(0.04, 0.02, 0.06, fade))
		if fade > 0.6 and fade_text != "":
			var f := ThemeDB.fallback_font
			var ts := f.get_string_size(fade_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
			draw_string(f, (tl + vs * 0.5 - Vector2(ts.x * 0.5, 0)).round(), fade_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("f2e6c8"))
