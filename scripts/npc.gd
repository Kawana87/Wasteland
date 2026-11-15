class_name Npc
extends Actor
## Friendly / harmless life: settlers, traders, travelling merchants, two-headed cattle and crows.

const BARKS := [
	"Water's clean today. Mostly.", "Watch for ghouls in the old city.", "Got any spare scrap?",
	"Brute was seen near the highway.", "Crops are coming in alright.", "Stay as long as you like, friend.",
	"Raiders hit a caravan last week.", "Don't drink from the green puddles.",
]

var type := "settler"
var home := Vector2.ZERO
var home_r := 4.0
var target := Vector2.ZERO
var wait := 0.0
var walk_t := 0.0
var walk_f := 0
var face_dir := Vector2(0, 1)
var settlement := -1
var patrol: Array = []
var pi := 0
var bark_t := 0.0
# crows
var flying := false
var fly_dir := Vector2.ZERO
var gone_t := 0.0

func setup(d: Dictionary) -> void:
	type = d["type"]
	wpos = d["pos"]
	home = d.get("home", wpos)
	settlement = d.get("settlement", -1)
	patrol = d.get("patrol", [])
	target = wpos
	match type:
		"settler":
			if not use_rendered("settler%d" % d.get("look", 1), 8): make_body("settler%d" % d.get("look", 1), 6, 16, 24)
			home_r = 4.5
		"trader", "wanderer":
			if not use_rendered("trader", 8): make_body("trader", 6, 16, 24)
			home_r = 0.6 if type == "trader" else 0.0
		"cattle":
			if not use_rendered("cattle", 2): make_body("cattle", 2, 20, 11)
			shadow_w = 14
			home_r = 3.5
		"crow":
			if not use_rendered("crow", 3): make_body("crow", 3, 8, 6)
			shadow_w = 4
	bark_t = randf_range(4.0, 12.0)

func step(delta: float, p: Player) -> void:
	var g := Game.I
	if type == "crow":
		_crow(delta, p)
		return
	var sp := 0.0
	if type == "wanderer" and patrol.size() > 0:
		var wp: Vector2 = patrol[pi]
		if wpos.distance_to(wp) < 0.8:
			pi = (pi + 1) % patrol.size()
		target = wp
		sp = 0.9
	else:
		wait -= delta
		if wait <= 0.0 and wpos.distance_to(target) < 0.3:
			target = home + Vector2.from_angle(randf() * TAU) * randf() * home_r
			wait = randf_range(2.0, 6.0)
		if wpos.distance_to(target) > 0.3 and wait <= 0.0:
			sp = 0.35 if type == "cattle" else 0.7
	if p.wpos.distance_to(wpos) < 1.2 and type != "cattle":
		sp = 0.0            # stop and look at you
	if sp > 0.0:
		var dir := (target - wpos).normalized()
		var before := wpos
		if not move(dir * sp * delta):
			target = wpos
		if type == "cattle" and building() != 0:
			wpos = before          # livestock stays outdoors
			target = wpos
		body.flip_h = (dir.x - dir.y) < 0
		face_dir = world_to_screen_dir(dir)
		walk_t += delta
		if walk_t > 0.22:
			walk_t = 0.0
			walk_f ^= 1
			walk_n += 1
	else:
		walk_f = 0
		if type != "cattle":
			body.flip_h = (p.wpos.x - p.wpos.y) < (wpos.x - wpos.y)
			face_dir = world_to_screen_dir(p.wpos - wpos)
	if rendered:
		if type == "cattle":
			face(face_dir, walk_f)
		else:
			face(face_dir, (1 + walk_n % 4) if sp > 0.0 else 0)
	elif type == "cattle":
		body.frame = walk_f
	else:
		body.frame = walk_f
	if type == "settler":
		bark_t -= delta
		if bark_t <= 0.0:
			bark_t = randf_range(10.0, 20.0)
			if p.wpos.distance_to(wpos) < 3.0:
				g.add_text(wpos + Vector2(0, -0.2), BARKS[randi() % BARKS.size()], Color("e8e0c8"), 2.6)
	sync()

func _crow(delta: float, p: Player) -> void:
	if gone_t > 0.0:
		gone_t -= delta
		if gone_t <= 0.0:
			flying = false
			jz = 0.0
			wpos = home + Vector2(randf_range(-1, 1), randf_range(-1, 1))
			visible = true
		return
	if not flying and (p.wpos.distance_to(wpos) < 3.0 or Game.I.noise_level > 0.0 and p.wpos.distance_to(wpos) < 8.0):
		flying = true
		fly_dir = (wpos - p.wpos).normalized().rotated(randf_range(-0.6, 0.6))
	if flying:
		wpos += fly_dir * 4.0 * delta
		jz = minf(60.0, jz + 30.0 * delta)
		walk_t += delta
		if walk_t > 0.1:
			walk_t = 0.0
			walk_f ^= 1
		if rendered:
			face(world_to_screen_dir(fly_dir), 1 + walk_f)
		else:
			body.frame = 1 + walk_f
			body.flip_h = fly_dir.x - fly_dir.y < 0
		if jz >= 60.0:
			gone_t = randf_range(20.0, 40.0)
	else:
		wait -= delta
		if wait <= 0.0:
			wait = randf_range(0.5, 2.0)
			if randf() < 0.5:
				wpos += Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
				body.flip_h = randf() < 0.5
				face_dir = Vector2.from_angle(randi_range(0, 7) * PI / 4.0)
		if rendered:
			face(face_dir, 0)
		else:
			body.frame = 0
	position = Iso.to_screen(wpos.x, wpos.y, world().hz(clampf(wpos.x, 0, 63.9), clampf(wpos.y, 0, 63.9))).round()
	z_index = Iso.z_for(wpos.x + wpos.y, 4)
	body.position.y = -round(jz)
	queue_redraw()
