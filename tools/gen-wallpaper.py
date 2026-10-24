#!/usr/bin/env python3
"""Genera ink.png: enso de tinta blanca sobre papel negro, con gotas y destellos. Solo blanco y negro.
Uso: python3 tools/gen-wallpaper.py [salida.png]   (siempre 2560x1440)
Deps (Arch): python-pillow python-numpy python-scipy python-opencv"""
import sys
import numpy as np, cv2, random
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter, gaussian_filter1d

random.seed(7); np.random.seed(7)
OUT = sys.argv[1] if len(sys.argv) > 1 else 'ink.png'
W, H = 2560, 1440  # composición pensada para 2560x1440; swaybg lo escala con -m fill
rng = np.random.default_rng(7)

def smooth_noise(shape, sigma, amp=1.0):
    n = gaussian_filter(rng.standard_normal(shape), sigma)
    return amp * n / (np.abs(n).max() + 1e-9)

def brush(mask, pts, widths, nb, dry=0.7, wob=1.2, seed=0):
    """Pincel de cerdas: cada cerda se seca antes hacia el final (kasure)."""
    r = np.random.default_rng(seed)
    d = ImageDraw.Draw(mask)
    T = len(pts)
    tang = np.gradient(pts, axis=0)
    tang /= (np.linalg.norm(tang, axis=1, keepdims=True) + 1e-9)
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    t = np.linspace(0, 1, T)
    for i in range(nb):
        u = r.uniform(-1, 1) * (0.5 + 0.5 * r.random() ** 0.5)
        bw = r.uniform(2.0, 4.4)
        n = gaussian_filter1d(r.random(T), r.uniform(6, 22))
        n = (n - n.min()) / (n.max() - n.min() + 1e-9)
        thr = 0.08 + dry * t ** 1.8 + 0.25 * abs(u) ** 2 * t
        alive = n > thr
        off = gaussian_filter1d(r.standard_normal(T), 8) * wob
        v = int(r.uniform(190, 255))
        P = pts + nrm * (u * widths[:, None] / 2 + off[:, None])
        for k in range(T - 1):
            if alive[k] and alive[k + 1]:
                d.line((P[k, 0], P[k, 1], P[k + 1, 0], P[k + 1, 1]), fill=v, width=int(round(bw)))

def goo(mask_arr, sigma=3.2, lo=0.38, hi=0.52):
    b = gaussian_filter(mask_arr, sigma)
    return np.clip((b - lo) / (hi - lo), 0, 1)

# ---------------- fondo: papel negro con fibras ----------------
base = np.zeros((H, W, 3), np.float32)
base[:] = (10, 10, 10)
base += smooth_noise((H, W), 80, 2.5)[..., None]
fib = Image.new("L", (W, H), 0)
fd = ImageDraw.Draw(fib)
for _ in range(2600):
    x, y = random.randint(0, W), random.randint(0, H)
    a = random.uniform(0, 3.14159)
    l = random.randint(8, 45)
    fd.line((x, y, x + l * np.cos(a), y + l * np.sin(a)), fill=random.randint(8, 26), width=1)
fib = np.asarray(fib.filter(__import__("PIL.ImageFilter", fromlist=["x"]).GaussianBlur(0.7)), np.float32)
base += fib[..., None] * 0.55
yy, xx = np.mgrid[0:H, 0:W]
vig = 1 - 0.38 * (((xx - W * 0.62) / (W * 0.8)) ** 2 + ((yy - H * 0.5) / (H * 0.85)) ** 2)
base *= np.clip(vig, 0.5, 1)[..., None]

# ---------------- enso ----------------
cx, cy, R = 1840, 590, 335
T = 900
th = np.deg2rad(np.linspace(-132, 205, T))
t = np.linspace(0, 1, T)
rad = R * (1 + 0.035 * t) + gaussian_filter1d(rng.standard_normal(T), 60) * 6
pts = np.stack([cx + rad * np.cos(th), cy + rad * np.sin(th)], 1)
w = 82 * (1 - 0.62 * t ** 1.4)
w *= np.clip(0.55 + 9 * t, 0, 1)                     # carga de tinta al inicio
w += gaussian_filter1d(rng.standard_normal(T), 25) * 4
w[-60:] *= np.linspace(1, 0.25, 60)

stroke = Image.new("L", (W, H), 0)
brush(stroke, pts, w, 60, dry=0.78, wob=1.6, seed=3)
stroke = np.asarray(stroke, np.float32) / 255
stroke = np.clip(gaussian_filter(stroke, 0.8) * 1.12, 0, 1)

# ---------------- gotas ----------------
dm = Image.new("L", (W, H), 0)
dd = ImageDraw.Draw(dm)
drips = []
angles = [47, 63, 68, 83, 90, 109, 131, 36]
lens = [150, 70, 310, 120, 430, 60, 210, 90]
for a, L in zip(angles, lens):
    ar = np.deg2rad(a)
    i = int(np.argmin(np.abs(th - ar)))
    x0 = pts[i, 0] + rng.uniform(-4, 4)
    y0 = pts[i, 1] + w[i] * 0.05
    wd = rng.uniform(5.0, 12.5)
    if y0 + L > H - 190:
        L = H - 190 - y0
    drips.append((x0, y0, L, wd))
    ys = np.arange(y0, y0 + L, 2.0)
    for j, y in enumerate(ys):
        s = (y - y0) / L
        rr = wd * (0.75 - 0.35 * np.sin(min(s * 1.6, 1) * 1.57)) + wd * 0.1 * np.sin(s * 9)
        dd.ellipse((x0 - rr, y - rr, x0 + rr, y + rr), fill=255)
    b = wd * rng.uniform(1.25, 1.6)                        # gota colgante
    yb = y0 + L
    dd.ellipse((x0 - b, yb - b * 1.15, x0 + b, yb + b * 1.15), fill=255)
dm = goo(np.asarray(dm, np.float32) / 255, 2.6, 0.36, 0.5)

# salpicaduras
sp = Image.new("L", (W, H), 0)
sd = ImageDraw.Draw(sp)
sx, sy = pts[0]
for _ in range(70):
    ang = rng.uniform(np.deg2rad(150), np.deg2rad(290))
    dist = min(rng.pareto(1.8) * 30 + 50, 230)
    x, y = sx + dist * np.cos(ang) - 20, sy + dist * np.sin(ang)
    r = max(1.2, min(7, rng.pareto(2.6) * 1.8 + 1.2))
    sd.ellipse((x - r, y - r, x + r, y + r), fill=255)
for _ in range(34):
    ang = rng.uniform(-2.6, 0.6)
    dist = rng.uniform(R + 90, R + 260)
    x, y = cx + dist * np.cos(ang), cy + dist * np.sin(ang)
    r = rng.uniform(1.0, 3.2)
    sd.ellipse((x - r, y - r, x + r, y + r), fill=255)
sp = goo(np.asarray(sp, np.float32) / 255, 0.9, 0.3, 0.5)

# ---------------- destellos de cuatro puntas ----------------
def sparkle(cx_, cy_, r, rot=0.0):
    m = Image.new("L", (W, H), 0)
    pts_ = []
    for k in range(96):
        a_ = 2 * np.pi * k / 96
        px = np.sign(np.cos(a_)) * abs(np.cos(a_)) ** 4.5 * r   # astroide afilada: 4 puntas finas
        py = np.sign(np.sin(a_)) * abs(np.sin(a_)) ** 4.5 * r
        pts_.append((cx_ + px * np.cos(rot) - py * np.sin(rot),
                     cy_ + px * np.sin(rot) + py * np.cos(rot)))
    ImageDraw.Draw(m).polygon(pts_, fill=255)
    return goo(np.asarray(m, np.float32) / 255, 1.6, 0.35, 0.5)

stars = np.maximum.reduce([
    sparkle(640, 330, 95, 0.10),
    sparkle(470, 560, 46, -0.15),
    sparkle(820, 200, 34, 0.0),
    sparkle(2330, 1130, 58, 0.05),
])

mask = np.clip(np.maximum.reduce([stroke, dm, sp, stars]), 0, 1)

# bordes irregulares (tinta en papel)
dx = smooth_noise((H, W), 14, 3.2) + smooth_noise((H, W), 2.2, 0.9)
dy = smooth_noise((H, W), 14, 3.2) + smooth_noise((H, W), 2.2, 0.9)
mapx = (xx + dx).astype(np.float32); mapy = (yy + dy).astype(np.float32)
mask = cv2.remap(mask.astype(np.float32), mapx, mapy, cv2.INTER_LINEAR)

# ---------------- composición ----------------
img = base.copy()
halo = gaussian_filter(mask, 9) * 0.07 + gaussian_filter(mask, 28) * 0.05   # tinta que se filtra
ink = np.array([236, 236, 236], np.float32)
img += halo[..., None] * ink
shade = 0.80 + 0.30 * gaussian_filter(mask, 5)                              # volumen en las gotas
tex = 1 + smooth_noise((H, W), 3, 0.05)
col = ink[None, None, :] * (shade * tex)[..., None]
img = img * (1 - mask[..., None]) + col * mask[..., None]

img += rng.standard_normal((H, W, 1)).astype(np.float32) * 1.2              # grano
out = np.clip(img, 0, 255).astype(np.uint8)
Image.fromarray(out).save(OUT, optimize=True)
print("ok")
