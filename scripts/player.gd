class_name Player
extends Actor
## The player character: movement, aiming, shooting, melee, sneaking, jumping, climbing.

var hp := 20.0
var max_hp := 20.0
var gun_len := 6
var aim := Vector2(0, 1)       # screen-space aim direction
var cd := 0.0
var mcd := 0.0
var swing := 0.0
var inv := 0.0
var flash := 0.0
var crouch := false
var moving := false
var walk_t := 0.0
var walk_f := 0
var carry := {"scrap": 0, "cloth": 0, "wood": 0}
var kills := 0
var regen := 0.0
var climb := {}                # {from, to, t} while on a rope
var gun: Line2D
var arc: Line2D

func _ready() -> void:
	make_body("player", 6, 16, 24)
	radius = 0.28
	gun = Line2D.new()
	gun.width = 1.0
	gun.default_color = Color("2a2a2a")
	gun.antialiased = false
	add_child(gun)
	arc = Line2D.new()
	arc.width = 1.0
	arc.default_color = Color("f2e6c8")
	arc.antialiased = false
	add_child(arc)

func world_aim() -> Vector2:
	return Iso.screen_dir_to_world(aim)

func step(delta: float, move_in: Vector2, aim_in: Vector2) -> void:
	cd -= delta; mcd -= delta; swing -= delta; inv -= delta; flash -= delta
	update_jump(delta)
	if not climb.is_empty():
		climb["t"] += delta / 1.2
		var t: float = minf(1.0, climb["t"])
		var a: Vector2 = climb["from"]
		wpos = a.lerp(climb["to"], t)
		moving = true
		if climb["t"] >= 1.0:
			climb = {}
	else:
		moving = move_in.length() > 0.15
		if moving:
			var d := Iso.screen_dir_to_world(move_in)
			var sp := (1.6 if crouch else 3.4) * minf(1.0, move_in.length())
			move(d * sp * delta)
		if aim_in.length() > 0.2:
			aim = aim_in.normalized()
		elif moving:
			aim = move_in.normalized()
	if moving:
		walk_t += delta
		if walk_t > 0.14:
			walk_t = 0.0
			walk_f ^= 1
	_visual()

func _visual() -> void:
	var back := aim.y < -0.3
	var f := 0
	if crouch:
		f = 5 if back else 4
	else:
		f = (2 if back else 0) + (walk_f if moving else 0)
	body.frame = f
	body.flip_h = aim.x < 0
	body.visible = not (inv > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0)
	var base := Vector2(0, -14 + (5 if crouch else 0) - round(jz))
	gun.visible = climb.is_empty()
	gun.points = PackedVector2Array([(base + aim * 3).round(), (base + aim * (2 + gun_len * 1.5)).round()])
	if swing > 0.0:
		var pts := PackedVector2Array()
		var a0 := aim.angle()
		for i in range(-3, 4):
			var a := a0 + i * 0.3
			pts.append((base + Vector2(cos(a) * 14, sin(a) * 10)).round())
		arc.points = pts
		arc.visible = true
	else:
		arc.visible = false
	sync()

func start_jump() -> void:
	if jz <= 0.0 and climb.is_empty():
		vz = 90.0
		jz = 0.01
