class_name Iso
## Isometric projection helpers. World units are tiles, screen units are pixels.
## A tile is a 32x16 diamond; height (z) is in pixels and lifts things straight up.

static func to_screen(x: float, y: float, z: float = 0.0) -> Vector2:
	return Vector2((x - y) * 16.0, (x + y) * 8.0 - z)

## Turns a direction on screen (e.g. stick or mouse offset) into a world direction.
static func screen_dir_to_world(v: Vector2) -> Vector2:
	var w := Vector2(v.x / 32.0 + v.y / 16.0, v.y / 16.0 - v.x / 32.0)
	return w.normalized() if w.length() > 0.0001 else Vector2.ZERO

## Draw order: larger depth draws on top. Used for z_index of world objects.
static func z_for(depth: float, bias: int = 0) -> int:
	return clampi(int(depth * 16.0) + bias, -4000, 4090)
