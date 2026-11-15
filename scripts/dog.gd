class_name Dog
extends Actor
## Your dog. Follows you around; teleports to you if it gets stuck.

var walk_t := 0.0
var walk_f := 0
var face_dir := Vector2(1, 0)
var moving_now := false

func _ready() -> void:
	if not use_rendered("dog", 2): make_body("dog", 2, 14, 10)
	radius = 0.2
	shadow_w = 8

func step(delta: float, p: Player) -> void:
	fl = p.fl
	var goal := p.wpos + Vector2(-0.8, 0.4)
	var d := wpos.distance_to(goal)
	if d > 8.0 or (fl > 0 and building() != p.building()):
		wpos = p.wpos
	elif d > 0.6:
		var dir := (goal - wpos) / d
		if not move(dir * 3.8 * delta) and d > 3.0:
			wpos += dir * 3.8 * delta
		body.flip_h = (dir.x - dir.y) < 0
		face_dir = world_to_screen_dir(dir)
		moving_now = true
		walk_t += delta
		if walk_t > 0.12:
			walk_t = 0.0
			walk_f ^= 1
	if rendered:
		face(face_dir, walk_f if moving_now else 0)
	else:
		body.frame = walk_f
	moving_now = false
	sync()
