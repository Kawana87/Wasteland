class_name ErrorOverlay
extends Logger
## Shows script/engine errors on screen in every build (phones have no console), so a screenshot
## is enough to report one. The first error stays; a count shows how many followed.

var label: Label
var n := 0
var first := ""
var mx := Mutex.new()

func _init(l: Label) -> void:
	label = l

func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING: return
	var where := file.get_file()
	# known harmless engine noise (no audio device, vsync on some drivers, JSON parse of a corrupt save)
	if where in ["audio_driver_alsa.cpp", "audio_server.cpp", "gl_manager_x11.cpp", "json.cpp"]: return
	var msg := "%s  (%s:%d %s)" % [rationale if rationale != "" else code, where, line, function]
	for bt in script_backtraces:
		if bt.get_frame_count() > 0:
			msg = "%s  (%s:%d %s)" % [rationale if rationale != "" else code, bt.get_frame_file(0).get_file(), bt.get_frame_line(0), bt.get_frame_function(0)]
			break
	mx.lock()
	n += 1
	if first == "": first = msg
	var t := "ERROR: %s%s" % [first, ("   (+%d more)" % (n - 1)) if n > 1 else ""]
	mx.unlock()
	_show.call_deferred(t)

func _show(t: String) -> void:
	if is_instance_valid(label):
		label.text = t
		label.visible = true

func _log_message(message: String, error: bool) -> void:
	pass
