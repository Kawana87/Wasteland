class_name Iso
## Isometric projection helpers. World units are tiles, screen units are pixels.
## A tile is a 48x24 diamond. Heights (z) are in "logical" pixels (the old 32x16 scale)
## and are multiplied by S on screen, so game logic never cares about the art resolution.

const S := 1.5

static func to_screen(x: float, y: float, z: float = 0.0) -> Vector2:
	return Vector2((x - y) * 24.0, (x + y) * 12.0 - z * S)

## Turns a direction on screen (e.g. stick or mouse offset) into a world direction.
static func screen_dir_to_world(v: Vector2) -> Vector2:
	var w := Vector2(v.x / 48.0 + v.y / 24.0, v.y / 24.0 - v.x / 48.0)
	return w.normalized() if w.length() > 0.0001 else Vector2.ZERO

## Draw order: larger depth draws on top. Used for z_index of world objects.
static func z_for(depth: float, bias: int = 0) -> int:
	return clampi(int(depth * 16.0) + bias, -4000, 4090)
