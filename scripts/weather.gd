class_name Weather
extends Node2D
## Weather that rolls in and out: clear skies, dust, rain (by the lake and in the woods and fens more
## often) and radstorms — green skies, thunder, the Geiger counter crackling, and radiation damage if
## you stay out in it. Get under a roof. Drawn as a screen overlay above the world.

var kind := "clear"          # clear, dust, rain, rad
var amt := 0.0               # 0..1 how strong right now
var target := 0.0
var t_left := 120.0
var flash := 0.0
var thunder_t := 8.0
var geiger_t := 0.0
var rad_t := 0.0
var drops := []

func _ready() -> void:
	z_index = 4094
	z_as_relative = false
	for i in 110:
		drops.append(Vector2(randf(), randf()))

func step(delta: float, g) -> void:
	t_left -= delta
	if t_left <= 0.0:
		if target > 0.0:
			target = 0.0            # fade out, then a clear spell
			t_left = randf_range(90.0, 200.0)
		else:
			_roll(g)
	amt = move_toward(amt, target, delta / 12.0)
	if amt <= 0.01 and target == 0.0: kind = "clear"
	var a: Audio = g.audio
	a.set_bed("amb_rain", amt * 0.8 if kind == "rain" or kind == "rad" else 0.0)
	if kind == "rain" or kind == "rad":
		thunder_t -= delta
		if thunder_t < 0.0 and amt > 0.5:
			thunder_t = randf_range(9.0, 25.0) if kind == "rain" else randf_range(5.0, 12.0)
			flash = 1.0
			a.play("thunder", Vector2.INF, -4.0 - randf() * 6.0, 0.15)
	flash = maxf(0.0, flash - delta * 3.0)
	if kind == "rad" and amt > 0.4:
		var p = g.player
		var covered: bool = g.world.building_at(p.wpos.x, p.wpos.y) != 0
		geiger_t -= delta
		if geiger_t < 0.0:
			geiger_t = randf_range(0.03, 0.25) if not covered else randf_range(0.5, 1.5)
			a.play("geiger", Vector2.INF, -10.0, 0.3)
		if not covered and g.state == "play":
			rad_t += delta * amt
			var every: float = 5.0 * (2.0 if g.perk("rad_skin") > 0 else 1.0)
			if rad_t > every:
				rad_t = 0.0
				p.hp = maxf(0.0, p.hp - 1.0)
				g.add_text(p.wpos, "-1 rads", Color("9fe870"), 1.4)
				if p.hp <= 0.0:
					g.hurt_player(p.wpos, 1.0)
	queue_redraw()

func _roll(g) -> void:
	var bn: String = g.world.biome_name(g.player.wpos)
	var r := randf()
	var wet := bn in ["woods", "marsh", "water", "beach", "farm"]
	var dry := bn in ["waste", "salt", "canyon", "crater", "gorge"]
	if r < (0.12 if dry else 0.07):
		kind = "rad"
		g.hud.toast("The sky's turning green. RADSTORM — get under a roof!")
	elif r < (0.45 if dry else 0.2):
		kind = "dust"
	elif r < (0.7 if wet else 0.42):
		kind = "rain"
	else:
		kind = "clear"
		t_left = randf_range(100.0, 220.0)
		return
	target = randf_range(0.6, 1.0)
	t_left = randf_range(70.0, 160.0)

## Colour grade multipliers for the world (applied by Game with the day/night grade).
func tint() -> Vector3:
	match kind:
		"dust": return Vector3(1.0, 0.93, 0.78).lerp(Vector3.ONE, 1.0 - amt)
		"rain": return Vector3(0.85, 0.9, 0.98).lerp(Vector3.ONE, 1.0 - amt)
		"rad": return Vector3(0.82, 1.08, 0.72).lerp(Vector3.ONE, 1.0 - amt)
	return Vector3.ONE

func dim() -> float:
	match kind:
		"rain": return 1.0 - 0.25 * amt
		"rad": return 1.0 - 0.2 * amt
		"dust": return 1.0 - 0.1 * amt
	return 1.0

func _draw() -> void:
	if amt <= 0.01 and flash <= 0.0: return
	var cam = Game.I.cam
	if cam == null: return
	var vs: Vector2 = get_viewport_rect().size
	var tl: Vector2 = cam.get_screen_center_position() - vs * 0.5
	var t: float = Game.I.time
	match kind:
		"rain", "rad":
			var col := Color(0.75, 0.82, 0.9, 0.45 * amt) if kind == "rain" else Color(0.7, 1.0, 0.6, 0.4 * amt)
			var n := int(drops.size() * amt)
			for i in n:
				var d: Vector2 = drops[i]
				var x := fposmod(d.x * vs.x + t * 60.0 + i * 13.0, vs.x)
				var y := fposmod(d.y * vs.y + t * 420.0 * (0.8 + d.x * 0.4), vs.y)
				var p := tl + Vector2(x, y)
				draw_line(p, p + Vector2(-2, 9), col, 1.0)
			if kind == "rad":
				draw_rect(Rect2(tl, vs), Color(0.4, 0.9, 0.2, 0.08 * amt))
		"dust":
			draw_rect(Rect2(tl, vs), Color(0.75, 0.62, 0.4, 0.16 * amt))
			for i in int(70 * amt):
				var d: Vector2 = drops[i]
				var x := fposmod(d.x * vs.x + t * 90.0 * (0.6 + d.y), vs.x)
				var y := fposmod(d.y * vs.y + sin(t + i) * 8.0, vs.y)
				draw_rect(Rect2(tl + Vector2(x, y), Vector2(2, 1)), Color(0.85, 0.72, 0.5, 0.5 * amt))
	if flash > 0.0:
		draw_rect(Rect2(tl, vs), Color(1, 1, 1, flash * 0.35) if kind == "rain" else Color(0.7, 1.0, 0.6, flash * 0.35))
