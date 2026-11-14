"""Fallout-style post-process: desaturate, warm the shadows, then reduce to a 256-colour palette."""
import sys
from PIL import Image, ImageEnhance, ImageFilter

def fallout_grade(im, colors=256, dither=True):
    im = im.convert("RGB")
    im = ImageEnhance.Color(im).enhance(0.78)
    im = ImageEnhance.Contrast(im).enhance(1.12)
    im = ImageEnhance.Brightness(im).enhance(0.92)
    im = im.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    q = im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                    dither=Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE)
    return q.convert("RGB")

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    out = fallout_grade(Image.open(src))
    out.save(dst)
    out.resize((out.width * 2, out.height * 2), Image.NEAREST).save(dst.replace(".png", "_2x.png"))
