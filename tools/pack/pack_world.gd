extends SceneTree
## godot --headless --script tools/pack/pack_world.gd  (after python3 tools/pack/export_raw.py)
func _init() -> void:
	var d := WorldData.new()
	d.height = FileAccess.get_file_as_bytes("/tmp/wd_height.raw")
	d.biome = FileAccess.get_file_as_bytes("/tmp/wd_biome.raw")
	d.meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worldmap/data/world.json"))
	d.size = int(d.meta.size)
	var err := ResourceSaver.save(d, "res://assets/worldmap/data/world_data.res", ResourceSaver.FLAG_COMPRESS)
	print("packed ", d.height.size(), " ", d.biome.size(), " err ", err)
	quit()
