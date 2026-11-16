class_name Audio
extends Node
## All game sound: one-shot effects (pooled, quieter with distance from the player), ambient beds
## that cross-fade with where you are and the time of day (wind, night insects, town chatter,
## campfire crackle, rooms, rain), and Sable Radio — original tunes between a DJ's news breaks.
## Every sound is synthesised by tools/audio/make_audio.py.

const POOL := 14
var players: Array[AudioStreamPlayer] = []
var beds := {}            # name -> AudioStreamPlayer (looping)
var bed_target := {}      # name -> target linear volume
var cache := {}
var radio: AudioStreamPlayer
var radio_on := false
var radio_track := -1
var dj_t := 0.0
var master_vol := 1.0

const BEDS := ["amb_wind", "amb_night", "amb_town", "amb_fire", "amb_inside", "amb_rain"]
const TRACKS := ["radio_1", "radio_2", "radio_3", "radio_4"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for b in BEDS:
		var p := AudioStreamPlayer.new()
		var s = _stream(b)
		if s == null: continue
		s.loop = true
		p.stream = s
		p.volume_db = -60.0
		add_child(p)
		p.play()
		beds[b] = p
		bed_target[b] = 0.0
	radio = AudioStreamPlayer.new()
	radio.volume_db = -7.0
	add_child(radio)
	radio.finished.connect(_next_track)

func _stream(nm: String):
	if cache.has(nm): return cache[nm]
	var path := "res://assets/audio/%s.ogg" % nm
	var s = load(path) if ResourceLoader.exists(path) else null
	cache[nm] = s
	return s

## Play a sound. at = world position (quieter and duller further from the player), or Vector2.INF
## for UI sounds. pitch_var randomises pitch a little so repeats don't sound mechanical.
func play(nm: String, at: Vector2 = Vector2.INF, vol_db: float = 0.0, pitch_var: float = 0.06) -> void:
	var s = _stream(nm)
	if s == null: return
	var g := Game.I
	var db := vol_db
	if at != Vector2.INF and g != null and g.player != null:
		var d: float = at.distance_to(g.player.wpos)
		if d > 34.0: return
		db += -d * 0.75
	var best: AudioStreamPlayer = null
	for p in players:
		if not p.playing: best = p; break
	if best == null:
		best = players[0]
		players.push_back(players.pop_front())
	best.stream = s
	best.volume_db = db + linear_to_db(master_vol)
	best.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	best.play()

## Ambient levels (0..1) for each bed; Audio eases toward them.
func set_bed(nm: String, v: float) -> void:
	bed_target[nm] = v

func _process(delta: float) -> void:
	for b in beds:
		var p: AudioStreamPlayer = beds[b]
		var cur := db_to_linear(p.volume_db) / maxf(master_vol, 0.001)
		var tgt: float = bed_target.get(b, 0.0)
		cur = move_toward(cur, tgt, delta * 0.35)
		p.volume_db = linear_to_db(maxf(cur * master_vol, 0.0001))
	if radio_on:
		dj_t -= delta

# ------------------------------------------------------------------ radio
func toggle_radio() -> void:
	radio_on = not radio_on
	play("radio_tune", Vector2.INF, -6.0, 0.0)
	if radio_on:
		dj_t = 2.0
		_dj_break()
		_next_track()
	else:
		radio.stop()

func _next_track() -> void:
	if not radio_on: return
	var k := randi() % TRACKS.size()
	if k == radio_track: k = (k + 1) % TRACKS.size()
	radio_track = k
	radio.stream = _stream(TRACKS[k])
	radio.play()
	if randf() < 0.75: _dj_break()

func _dj_break() -> void:
	var g := Game.I
	if g == null or g.hud == null: return
	g.hud.radio_line(Lore.dj_line(g))
