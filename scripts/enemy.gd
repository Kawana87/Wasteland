class_name Enemy
extends Actor
## Raiders and mutants. All share the awareness system:
## 0-35 unaware (wander/patrol), 35-75 suspicious "?" (go check the last noise), 75+ alert "!".

const STATS := {
	#           hp  chase  dmg  windup sense  fears fire
	"rat":       [2,  1.3,  1,   0.55,  0.7,   true],
	"ghoul":     [6,  2.0,  3,   0.40,  1.15,  true],
	"shellback": [14, 0.8,  4,   0.50,  0.9,   true],
	"brute":     [24, 1.05, 6,   0.80,  1.0,   false],
	"raider":    [6,  1.3,  3,   0.0,   1.0,   false],
}

var type := "ghoul"
var hp := 6.0
var max_hp := 6.0
var dmg := 3
var aw := 0.0
var st := 0
var head := Vector2.RIGHT
var target := Vector2.ZERO
var last := Vector2.ZERO
var home := Vector2.ZERO
var home_r := 4.0
var wander_t := 0.0
var pause := 0.0
var wind := 0.0
var shoot_cd := 1.5
var charge_t := 0.0
var strafe := 1.0
var hit_t := 0.0
var patrol: Array = []
var pi := 0
var camp := -1
var dead := false
var seed_off := 0.0
var walk_t := 0.0
var walk_f := 0
var last_vis := Vector2.ZERO
var weapon := "pipe_pistol"
var icon: Sprite2D
var gun: Line2D
var hpbar := 0.0

func setup(spawn: Dictionary) -> void:
	type = spawn["type"]
	wpos = spawn["pos"]
	fl = spawn.get("fl", 0)
	home = spawn.get("home", wpos)
	home_r = spawn.get("home_r", 4.0)
	patrol = spawn.get("patrol", [])
	pi = 1 if patrol.size() > 1 else 0
	camp = spawn.get("camp", -1)
	var s: Array = STATS[type]
	hp = s[0]; max_hp = s[0]; dmg = s[2]
	seed_off = randf() * 10.0
	shoot_cd = randf_range(1.0, 2.0)
	strafe = 1.0 if randf() < 0.5 else -1.0
	head = Vector2.from_angle(randf() * TAU)
	last = wpos
	match type:
		"raider":
			if not use_rendered("raider", 8): make_body("raider", 6, 16, 24)
			weapon = ["pipe_pistol", "pipe_pistol", "pistol_10mm", "shotgun"][randi_range(0, 3)]
			gun = Line2D.new()
			gun.width = 1.0
			gun.default_color = Color("2a2a2a")
			gun.antialiased = false
			add_child(gun)
		"ghoul":
			if not use_rendered("ghoul", 8): make_body("ghoul", 6, 16, 24)
		"brute":
			if not use_rendered("brute", 8): make_body("brute", 4, 20, 26)
			shadow_w = 14
			radius = 0.35
		"shellback":
			if not use_rendered("shellback", 2): make_body("shellback", 2, 22, 11)
			shadow_w = 18
			radius = 0.38
		"rat":
			if not use_rendered("rat", 2): make_body("rat", 2, 8, 6)
			shadow_w = 6
			radius = 0.18
	icon = Sprite2D.new()
	icon.centered = false
	icon.visible = false
	add_child(icon)

func fears_fire() -> bool:
	return STATS[type][5]

## Raiders leave a raider-origin player alone until someone in their crew gets hurt.
var provoked := false

func friendly() -> bool:
	return type == "raider" and not provoked and Game.I.origin().get("raider", false)

func hear(at: Vector2, rad: float, amt: float) -> void:
	if friendly(): return
	var r: float = rad * STATS[type][4]
	var d := wpos.distance_to(at)
	if d < r:
		aw = minf(100.0, aw + amt * (1.0 - 0.6 * d / r))
		last = at + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))

func damage(n: float, from: Vector2) -> void:
	if type == "shellback" and n < 6.0:
		n *= 0.5          # the shell shrugs off small arms; rifles and big hits get through
	hp -= n
	if friendly():
		Game.I.provoke_raiders(wpos)
	aw = 100.0
	last = from
	hit_t = 0.15
	hpbar = 2.0
	if hp <= 0.0:
		Game.I.kill_enemy(self, false)
	else:
		Game.I.burst(wpos, 4, [Color("a83a2a") if type != "shellback" else Color("8a6a4a")], 9.0, fl)
		queue_redraw()

func think(delta: float, p: Player, p_safe: bool) -> void:
	var g := Game.I
	var w := world()
	var to_p := p.wpos - wpos
	var d := to_p.length()
	var same := (building() == p.building() and fl == p.fl) or (d < 2.2 and fl == p.fl)
	same = same and g.state == "play" and p.climb.is_empty()
	var k: float = STATS[type][4]
	var gain := 0.0
	if same:
		if p.crouch:
			gain = 25.0 if d < 0.9 * k else (5.0 if d < 1.8 * k else 0.0)
		else:
			gain = 50.0 if d < 1.5 * k else (20.0 if d < 3.0 * k else (6.0 if d < 5.0 * k else 0.0))
			if p.moving and gain > 0.0:
				gain *= 1.2
	if friendly(): gain = 0.0
	if gain > 0.0:
		aw = minf(100.0, aw + gain * delta)
		last = p.wpos
	else:
		aw = maxf(0.0, aw - 5.0 * delta)
	if aw >= 75.0 and same and d < 10.0:
		last = p.wpos
	st = 2 if aw >= 75.0 else (1 if aw >= 35.0 else 0)
	hit_t -= delta
	hpbar -= delta
	var tgt := wpos
	var sp := 0.0
	var wob := 0.12 if type == "raider" or type == "brute" else 0.35
	var fire_camp = g.camp_near(wpos, 4.0)
	var si := w.settlement_at(wpos, 2.0)
	if (fears_fire() and st > 0 and (fire_camp != null or (p_safe and st == 2))) or si >= 0:
		# mutants keep away from campfires; nobody fights inside a settlement
		var away: Vector2 = wpos - (fire_camp.wpos if fire_camp != null else p.wpos)
		if si >= 0:
			away = wpos - w.settlements[si].pos
		tgt = wpos + away.normalized() * 3.0
		sp = 1.4
		aw = minf(aw, 70.0)
	elif st == 2:
		match type:
			"raider":
				if d > 6.5:
					tgt = p.wpos; sp = 1.3
				elif d < 3.2:
					tgt = wpos - to_p; sp = 1.1
				else:
					tgt = wpos + Vector2(-to_p.y, to_p.x) * strafe; sp = 0.9
					if randf() < delta * 0.4: strafe = -strafe
				shoot_cd -= delta
				if shoot_cd <= 0.0 and d < 9.5:
					if fl == p.fl and w.los(wpos, p.wpos, fl):
						g.enemy_shoot(self, p.wpos, weapon)
					shoot_cd = randf_range(1.0, 1.7) * (1.3 if weapon == "shotgun" else 1.0)
			"brute":
				tgt = p.wpos; sp = 1.05
				shoot_cd -= delta
				if shoot_cd <= 0.0 and d > 3.0 and d < 8.0 and fl == p.fl and w.los(wpos, p.wpos, fl):
					g.throw_rock(self, p.wpos)
					shoot_cd = randf_range(3.0, 4.5)
				if d < 0.9 and wind <= 0.0 and p.inv <= 0.0: wind = STATS[type][3]
			"shellback":
				tgt = p.wpos; sp = STATS[type][1]
				shoot_cd -= delta
				if charge_t > 0.0:
					charge_t -= delta; sp = 2.9
				elif shoot_cd <= 0.0 and d > 1.5 and d < 5.0:
					charge_t = 0.9; shoot_cd = randf_range(3.0, 4.0)
				if d < 0.85 and wind <= 0.0 and p.inv <= 0.0: wind = STATS[type][3]
			_:
				tgt = p.wpos; sp = STATS[type][1]
				if d < 0.75 and wind <= 0.0 and p.inv <= 0.0: wind = STATS[type][3]
	elif st == 1 and wpos.distance_to(last) > 0.5:
		tgt = last
		sp = 0.6 if type == "rat" else 0.9
	else:
		if patrol.size() > 0:
			var wp: Vector2 = patrol[pi]
			if wpos.distance_to(wp) < 0.8:
				pi = (pi + 1) % patrol.size()
			tgt = wp; sp = 0.8
		else:
			wander_t -= delta
			if wander_t <= 0.0:
				target = home + Vector2.from_angle(randf() * TAU) * randf() * home_r
				wander_t = randf_range(3.0, 6.0)
			tgt = target
			sp = (0.3 if type == "rat" else 0.45) if wpos.distance_to(tgt) > 0.3 else 0.0
	if wind > 0.0:
		wind -= delta
		sp = 0.0
		if wind <= 0.0 and d < (1.2 if type == "brute" else 0.95):
			g.hurt_player(wpos, dmg)
	if type != "raider" or st < 2:
		pause -= delta
		if pause <= 0.0 and randf() < delta * 0.35:
			pause = randf_range(0.4, 1.2)
		if pause > 0.0 and st < 2:
			sp = 0.0
	var dir := (tgt - wpos)
	dir = dir.normalized() if dir.length() > 0.001 else head
	dir = dir.rotated(sin(g.time * 2.3 + seed_off) * wob)
	head = head.lerp(dir, minf(1.0, delta * (6.0 if type == "raider" else 2.5))).normalized()
	if sp > 0.0:
		if not move(head * sp * delta) and patrol.size() > 0:
			pi = (pi + 1) % patrol.size()
		walk_t += delta
		if walk_t > (0.14 if sp > 1.5 else 0.25):
			walk_t = 0.0
			walk_f ^= 1
			walk_n += 1
	_visual(p)

func _visual(p: Player) -> void:
	var sd := Vector2(head.x - head.y, (head.x + head.y) * 0.5)   # heading on screen
	if st == 2:
		var t := p.wpos - wpos
		sd = Vector2(t.x - t.y, (t.x + t.y) * 0.5)
	sd = sd.normalized() if sd.length() > 0.01 else Vector2(0, 1)
	var moving := wpos.distance_squared_to(last_vis) > 0.000001
	last_vis = wpos
	if rendered:
		if type in ["raider", "ghoul", "brute"]:
			face(sd, (1 + walk_n % 4) if moving else 0)
		else:
			face(sd, walk_f if moving else 0)
	else:
		if type in ["raider", "ghoul", "brute"]:
			body.frame = (2 if sd.y < -0.3 else 0) + walk_f
		else:
			body.frame = walk_f
		body.flip_h = sd.x < 0
	if gun:
		var base := Vector2(0, -24 if rendered else -14)
		gun.points = PackedVector2Array([(base + sd * 3).round(), (base + sd * (11 if weapon == "shotgun" else 9)).round()])
	body.position.x = (1 if hit_t > 0.0 else 0) + (round(sin(Game.I.time * 40.0)) if wind > 0.0 else 0)
	var top: int = ({"raider": -50, "ghoul": -48, "brute": -64, "shellback": -26, "rat": -18} if rendered else {"raider": -42, "ghoul": -42, "brute": -48, "shellback": -24, "rat": -16})[type]
	if st == 2:
		icon.texture = Assets.tex("icon_alert"); icon.visible = true; icon.position = Vector2(-1, top)
	elif st == 1:
		icon.texture = Assets.tex("icon_suspicious"); icon.visible = true; icon.position = Vector2(-2, top)
	else:
		icon.visible = false
	sync()

func _draw() -> void:
	super._draw()
	if hpbar > 0.0 and hp < max_hp:
		var top: float = {"raider": -45, "ghoul": -45, "brute": -52, "shellback": -27, "rat": -19}[type]
		draw_rect(Rect2(-9, top, 18, 3), Color(0.1, 0.05, 0.05, 0.8))
		draw_rect(Rect2(-9, top, 18.0 * hp / max_hp, 3), Color("c84a3a"))
