"""Droplet hydraulic erosion (after Hans Theobald Beyer's / Sebastian Lague's method), compiled with numba.
Heights are in grid-cell units so slopes are real slopes."""
import numpy as np
from numba import njit


@njit(cache=True)
def _grad(h, x, y):
    n = h.shape[0]
    ix, iy = int(x), int(y)
    u, v = x - ix, y - iy
    a, b, c, d = h[iy, ix], h[iy, ix + 1], h[iy + 1, ix], h[iy + 1, ix + 1]
    gx = (b - a) * (1 - v) + (d - c) * v
    gy = (c - a) * (1 - u) + (d - b) * u
    return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v, gx, gy


@njit(cache=True)
def erode(h, mask, drops, seed, life=48, inertia=0.06, cap_k=5.0, min_slope=0.01, k_erode=0.35, k_dep=0.3,
          evap=0.015, gravity=4.0, radius=2):
    np.random.seed(seed)
    n = h.shape[0]
    # brush weights
    rr = radius
    for _ in range(drops):
        x = np.random.random() * (n - 2 * rr - 2) + rr; y = np.random.random() * (n - 2 * rr - 2) + rr
        dx = 0.0; dy = 0.0; speed = 1.0; water = 1.0; sed = 0.0
        for _s in range(life):
            ix, iy = int(x), int(y)
            u, v = x - ix, y - iy
            hh, gx, gy = _grad(h, x, y)
            dx = dx * inertia - gx * (1 - inertia); dy = dy * inertia - gy * (1 - inertia)
            ln = np.sqrt(dx * dx + dy * dy)
            if ln < 1e-9:
                break
            dx /= ln; dy /= ln
            nx, ny = x + dx, y + dy
            if nx < rr + 1 or ny < rr + 1 or nx > n - rr - 2 or ny > n - rr - 2:
                break
            nh, _, _ = _grad(h, nx, ny)
            dh = nh - hh
            cap = max(-dh, min_slope) * speed * water * cap_k
            m = mask[iy, ix]
            if sed > cap or dh > 0:
                dep = min(dh, sed) if dh > 0 else (sed - cap) * k_dep
                sed -= dep
                h[iy, ix] += dep * (1 - u) * (1 - v); h[iy, ix + 1] += dep * u * (1 - v)
                h[iy + 1, ix] += dep * (1 - u) * v; h[iy + 1, ix + 1] += dep * u * v
            else:
                er = min((cap - sed) * k_erode * m, -dh)
                # spread the erosion over a small brush
                tot = 0.0
                for oy in range(-rr, rr + 1):
                    for ox in range(-rr, rr + 1):
                        w = max(0.0, rr + 0.5 - np.sqrt(ox * ox + oy * oy)); tot += w
                for oy in range(-rr, rr + 1):
                    for ox in range(-rr, rr + 1):
                        w = max(0.0, rr + 0.5 - np.sqrt(ox * ox + oy * oy)) / tot
                        h[iy + oy, ix + ox] -= er * w
                sed += er
            speed = np.sqrt(max(0.0, speed * speed + dh * gravity * -1.0))
            water *= (1 - evap)
            x, y = nx, ny
    return h
