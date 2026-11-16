"""Raw little-endian dumps of the world-map game data for tools/pack/pack_world.gd."""
import numpy as np
from PIL import Image
D = 'assets/worldmap/data/'
h = np.array(Image.open(D + 'height.png')).astype('<u2')
b = np.array(Image.open(D + 'biome.png')).astype(np.uint8)
h.tofile('/tmp/wd_height.raw')
b.tofile('/tmp/wd_biome.raw')
print(h.shape, b.shape)
