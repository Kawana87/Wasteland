class_name Enemy
extends Actor
## Raiders, mutant hounds and rats. All share the awareness system:
## 0-35 unaware (wander/patrol), 35-75 suspicious "?" (go check the last noise), 75+ alert "!".

var type := "hound"
var hp := 1
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
var strafe := 1.0
var hit_t := 0.0
var patrol: Array = []
var pi := 0
var camp := -1
var dead := false
var seed_off := 0.0
var walk_t := 0.0
var walk_f := 0
var icon: Sprite2D
var gun: Line2D

func setup(spawn: Dictionary) -> void:
	type = spawn["type"]
	wpos = spawn["pos"]
	fl = spawn.get("fl", 0)
	home = spawn.get("home", wpos)
	home_r = spawn.get("home_r", 4.0)
	patrol = spawn.get("patrol", [])
	pi = 1 if patrol.size() > 1 else 0
	camp = spawn.get("camp", -1)
	hp = 2 if type == "raider" else 1
	seed_off = randf() * 10.0
	shoot_cd = randf_range(1.0, 2.0)
	strafe = 1.0 if randf() < 0.5 else -1.0
	head = Vector2.from_angle(randf() * TAU)
	last = wpos
	match type:
		"raider":
			make_body("raider", 6, 16, 24)
			gun = Line2D.new()
			gun.width = 1.0
			gun.default_color = Color("2a2a2a")
			gun.antialiased = false
			add_child(gun)
		"hound":
			make_body("hound", 2, 16, 10)
			shadow_w = 12
		"rat":
			make_body("rat", 2, 8, 6)
			shadow_w = 6
			radius = 0.18
	icon = Sprite2D.new()
	icon.centered = false
	icon.visible = false
	add_child(icon)

func hear(at: Vector2, rad: float, amt: float) -> void:
	var r := rad * (1.3 if type == "hound" else 1.0)
	var d := wpos.distance_to(at)
	if d < r:
		aw = minf(100.0, aw + amt * (1.0 - 0.6 * d / r))
		last = at + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))

func damage(n: int, from: Vector2) -> void:
	hp -= n
	aw = 100.0
	last = from
	hit_t = 0.15
	if hp <= 0:
		Game.I.kill_enemy(self, false)
	else:
		Game.I.burst(wpos, 4, [Color("a83a2a")], 9.0)
		Game.I.sfx("hit")

func think(delta: float, p: Player, p_at_camp: bool) -> void:
	var g := Game.I
	var w := world()
	var to_p := p.wpos - wpos
	var d := to_p.length()
	var same := (building() == p.building() and fl == p.fl) or (d < 2.2 and fl == p.fl)
	same = same and g.state == "play" and p.climb.is_empty()
	var k := 1.35 if type == "hound" else (0.7 if type == "rat" else 1.0)
	var gain := 0.0
	if same:
		if p.crouch:
			gain = 25.0 if d < 0.9 * k else (5.0 if d < 1.8 * k else 0.0)
		else:
			gain = 50.0 if d < 1.5 * k else (20.0 if d < 3.0 * k else (6.0 if d < 5.0 * k else 0.0))
			if p.moving and gain > 0.0:
				gain *= 1.2
	if gain > 0.0:
		aw = minf(100.0, aw + gain * delta)
		last = p.wpos
	else:
		aw = maxf(0.0, aw - 5.0 * delta)
	if aw >= 75.0 and same and d < 10.0:
		last = p.wpos
	st = 2 if aw >= 75.0 else (1 if aw >= 35.0 else 0)
	hit_t -= delta
	var tgt := wpos
	var sp := 0.0
	var wob := 0.12 if type == "raider" else 0.4
	var fire_camp = g.camp_near(wpos, 4.0)
	if type != "raider" and st > 0 and (fire_camp != null or (p_at_camp and st == 2)):
		# mutants won't go near a campfire
		var c = fire_camp if fire_camp != null else g.camp_near(p.wpos, 3.2)
		tgt = wpos + (wpos - c.wpos) * 2.0
		sp = 1.4
		aw = minf(aw, 70.0)
	elif st == 2:
		if type == "raider":
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
					g.enemy_shoot(self, p.wpos)
				shoot_cd = randf_range(1.0, 1.7)
		else:
			tgt = p.wpos
			sp = 1.9 if type == "hound" else 1.3
			if d < 0.7 and wind <= 0.0 and p.inv <= 0.0:
				wind = 0.45 if type == "hound" else 0.55
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
		if wind <= 0.0 and d < 0.95:
			g.hurt_player(wpos)
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
		if walk_t > (0.12 if type == "hound" else 0.25):
			walk_t = 0.0
			walk_f ^= 1
	_visual(p)

func _visual(p: Player) -> void:
	var sd := Vector2(head.x - head.y, (head.x + head.y) * 0.5)   # heading on screen
	if type == "raider":
		var a := sd
		if st == 2:
			var t := p.wpos - wpos
			a = Vector2(t.x - t.y, (t.x + t.y) * 0.5)
		a = a.normalized() if a.length() > 0.01 else Vector2(0, 1)
		body.frame = (2 if a.y < -0.3 else 0) + walk_f
		body.flip_h = a.x < 0
		var base := Vector2(0, -9)
		gun.points = PackedVector2Array([(base + a * 2).round(), (base + a * 7).round()])
	else:
		body.frame = walk_f
		body.flip_h = sd.x < 0
	body.position.x = (1 if hit_t > 0.0 else 0) + (round(sin(Game.I.time * 40.0)) if wind > 0.0 else 0)
	var top := -26 if type == "raider" else (-16 if type == "hound" else -11)
	if st == 2:
		icon.texture = Assets.tex("icon_alert"); icon.visible = true; icon.position = Vector2(-1, top)
	elif st == 1:
		icon.texture = Assets.tex("icon_suspicious"); icon.visible = true; icon.position = Vector2(-2, top)
	else:
		icon.visible = false
	sync()
