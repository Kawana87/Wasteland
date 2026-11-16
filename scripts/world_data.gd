class_name WorldData
extends Resource
## Packed Sable Wastes data at one pixel per tile (made by tools/pack/pack_world.gd).
@export var size := 2048
@export var height := PackedByteArray()   # u16 little endian, normalised 0..65535 over hmin..hmax
@export var biome := PackedByteArray()    # RGBA: biome id, city density, wash, road kind * 60
@export var meta := {}                    # world.json (roads, biome names, heights)
