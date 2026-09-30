"""Signed distance field library (numpy, vectorised).

Every shape is a callable ``f(p) -> d`` where ``p`` is an ``(N, 3)`` float64 array of points and
``d`` an ``(N,)`` array: negative inside, positive outside. Primitives are exact distances; smooth
booleans and deformations are bounds (good enough for marching cubes, gradient normals and SDF
ambient occlusion). Nothing here is random: variation is passed in explicitly by the figures.

Conventions: +Y up, +Z front. Rotations are 3x3 matrices whose *columns* are the local axes
expressed in world space, so ``local = (p - origin) @ R``.
"""
from __future__ import annotations

import math

import numpy as np

Array = np.ndarray


# --------------------------------------------------------------------------- vector helpers

def v3(x, y=None, z=None) -> Array:
    if y is None:
        return np.asarray(x, dtype=np.float64).reshape(3)
    return np.array([x, y, z], dtype=np.float64)


def normalize(v) -> Array:
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def rot_axis(axis, angle: float) -> Array:
    """Rotation matrix (Rodrigues) of ``angle`` radians around ``axis``."""
    a = normalize(axis)
    c, s = np.cos(angle), np.sin(angle)
    x, y, z = a
    return np.array([
        [c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
        [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
        [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)],
    ])


def rot_x(a: float) -> Array:
    return rot_axis((1, 0, 0), a)


def rot_y(a: float) -> Array:
    return rot_axis((0, 1, 0), a)


def rot_z(a: float) -> Array:
    return rot_axis((0, 0, 1), a)


def frame_from(y_axis, z_hint) -> Array:
    """Orthonormal frame (columns x, y, z) with the given y and z as close as possible to hint."""
    y = normalize(y_axis)
    z = np.asarray(z_hint, dtype=np.float64)
    z = normalize(z - y * np.dot(z, y))
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


def _len(p: Array) -> Array:
    return np.sqrt(np.einsum("ij,ij->i", p, p))


def _clamp01(x: Array) -> Array:
    return np.clip(x, 0.0, 1.0)


def smoothstep(e0: float, e1: float, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------- bounds (culling)
# Every shape may carry ``f.bound = (centre, radius)``: a sphere that encloses the solid. The
# booleans use it to skip evaluating a part at points where it cannot change the result.

def with_bound(f, c, r):
    f.bound = (v3(c), float(r))
    return f


def bound_of(f):
    return getattr(f, "bound", None)


def merge_bounds(bounds, pad: float = 0.0):
    if any(b is None for b in bounds):
        return None
    cs = np.array([b[0] for b in bounds])
    rs = np.array([b[1] for b in bounds])
    lo = (cs - rs[:, None]).min(axis=0)
    hi = (cs + rs[:, None]).max(axis=0)
    c = 0.5 * (lo + hi)
    r = float(np.max(np.linalg.norm(cs - c, axis=1) + rs)) + pad
    return (c, r)


# --------------------------------------------------------------------------- primitives

def sphere(c, r: float):
    c = v3(c)

    def f(p):
        return _len(p - c) - r
    return with_bound(f, c, r)


def ellipsoid(c, radii, R=None):
    """Approximate ellipsoid distance (Quilez, k0*(k0-1)/k1): exact on the surface, bound nearby."""
    c = v3(c)
    r = v3(radii)
    Rm = None if R is None else np.asarray(R, dtype=np.float64)

    def f(p):
        q = p - c
        if Rm is not None:
            q = q @ Rm
        k0 = _len(q / r)
        k1 = _len(q / (r * r))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
    return with_bound(f, c, float(np.max(r)))


def capsule(a, b, r: float):
    a, b = v3(a), v3(b)
    ba = b - a
    inv = 1.0 / float(np.dot(ba, ba))

    def f(p):
        pa = p - a
        h = _clamp01((pa @ ba) * inv)
        return _len(pa - h[:, None] * ba) - r
    return with_bound(f, 0.5 * (a + b), 0.5 * math.sqrt(1.0 / inv) + r)


def round_cone(a, b, ra: float, rb: float):
    """Exact round cone (Quilez): spheres of radius ra at a and rb at b joined by a cone."""
    a, b = v3(a), v3(b)
    ba = b - a
    l2 = float(np.dot(ba, ba))
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    def f(p):
        pa = p - a
        y = pa @ ba
        z = y - l2
        w = pa * l2 - y[:, None] * ba
        x2 = np.einsum("ij,ij->i", w, w)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d_mid = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - ra
        d_b = np.sqrt(x2 + z2) * il2 - rb
        d_a = np.sqrt(x2 + y2) * il2 - ra
        out = np.where(np.sign(y) * a2 * y2 < k, d_a, d_mid)
        out = np.where(np.sign(z) * a2 * z2 > k, d_b, out)
        return out
    return with_bound(f, 0.5 * (a + b), 0.5 * math.sqrt(l2) + max(ra, rb))


def round_box(c, half, r: float, R=None):
    c = v3(c)
    h = v3(half) - r
    Rm = None if R is None else np.asarray(R, dtype=np.float64)

    def f(p):
        q = p - c
        if Rm is not None:
            q = q @ Rm
        q = np.abs(q) - h
        outside = _len(np.maximum(q, 0.0))
        inside = np.minimum(np.max(q, axis=1), 0.0)
        return outside + inside - r
    return with_bound(f, c, float(np.linalg.norm(v3(half))))


def halfspace(point, normal):
    """Solid on the side opposite to ``normal`` (d = signed height above the plane)."""
    point, n = v3(point), normalize(normal)

    def f(p):
        return (p - point) @ n
    return f


def tube(points, radii):
    """Chain of round cones through ``points`` with per-point ``radii`` (hard union, smooth joints)."""
    pts = [v3(p) for p in points]
    parts = [round_cone(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(len(pts) - 1)]
    return union(*parts)


# --------------------------------------------------------------------------- booleans

def smin(a: Array, b: Array, k: float) -> Array:
    """Polynomial smooth minimum; k is the blend width in world units (0 = hard)."""
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a: Array, b: Array, k: float) -> Array:
    return -smin(-a, -b, k)


def sculpt(base, ops):
    """``base`` modified by ``ops`` = [(kind, sdf, k)], kind "add" (smooth union) or "sub"
    (smooth subtraction), applied in order. Parts with a bound are only evaluated where they can
    change the running distance (lower bound |p-c|-r, halved for approximate fields)."""
    ops = [(kind, g, float(k)) for kind, g, k in ops]

    def f(p):
        d = base(p)
        for kind, g, k in ops:
            b = bound_of(g)
            if b is None:
                gv = g(p)
                d = smin(d, gv, k) if kind == "add" else smax(d, -gv, k)
                continue
            lb = _len(p - b[0]) - b[1]
            lb = np.where(lb > 0.0, 0.5 * lb, lb)
            m = lb < (d + k if kind == "add" else -d + k)
            idx = np.flatnonzero(m)
            if len(idx) == 0:
                continue
            if len(idx) == len(d):
                gv = g(p)
                d = smin(d, gv, k) if kind == "add" else smax(d, -gv, k)
                continue
            gv = g(p[idx])
            d[idx] = smin(d[idx], gv, k) if kind == "add" else smax(d[idx], -gv, k)
        return d
    adds = [bound_of(base)] + [bound_of(g) for kind, g, k in ops if kind == "add"]
    pad = max([k for _, _, k in ops] + [0.0])
    bb = merge_bounds(adds, pad)
    if bb is not None:
        f.bound = bb
    return f


def union(*fs, k: float = 0.0):
    return sculpt(fs[0], [("add", g, k) for g in fs[1:]])


def blend(base, parts):
    """Sequential smooth union: ``parts`` is a list of ``(sdf, k)``; order matters for k."""
    return sculpt(base, [("add", g, k) for g, k in parts])


def subtract(a, b, k: float = 0.0):
    """``a`` minus ``b`` with a smooth fillet of width k."""
    return sculpt(a, [("sub", b, k)])


def intersect(a, b, k: float = 0.0):
    def f(p):
        return smax(a(p), b(p), k)
    if bound_of(a) is not None:
        f.bound = bound_of(a)
    return f


def offset(a, amount: float):
    """Inflate (amount > 0) or erode a shape."""
    def f(p):
        return a(p) - amount
    b = bound_of(a)
    if b is not None:
        f.bound = (b[0], b[1] + max(amount, 0.0))
    return f


def shell(a, thickness: float):
    def f(p):
        return np.abs(a(p)) - thickness * 0.5
    return f


# --------------------------------------------------------------------------- transforms

def place(a, origin=(0, 0, 0), R=None):
    """Put shape ``a`` (authored in a local frame) at ``origin`` with rotation ``R`` (columns =
    local axes in world)."""
    o = v3(origin)
    Rm = np.eye(3) if R is None else np.asarray(R, dtype=np.float64)

    def f(p):
        return a((p - o) @ Rm)
    b = bound_of(a)
    if b is not None:
        f.bound = (o + Rm @ b[0], b[1])
    return f


def mirror_x(a):
    def f(p):
        q = p.copy()
        q[:, 0] = -q[:, 0]
        return a(q)
    b = bound_of(a)
    if b is not None:
        f.bound = (b[0] * np.array([-1.0, 1.0, 1.0]), b[1])
    return f


def scale(a, s):
    """Uniform (float) or per-axis scale. Per-axis scale returns a bound (divided by max scale)."""
    s_arr = np.asarray(s, dtype=np.float64)
    if s_arr.ndim == 0:
        sf = float(s_arr)

        def f(p):
            return a(p / sf) * sf
        b = bound_of(a)
        if b is not None:
            f.bound = (b[0] * sf, b[1] * sf)
        return f
    m = float(np.min(s_arr))

    def g(p):
        return a(p / s_arr) * m
    b = bound_of(a)
    if b is not None:
        g.bound = (b[0] * s_arr, b[1] * float(np.max(s_arr)))
    return g


def bend(a, k: float, axis: int = 0):
    """Bend around the local Z axis: points along +X curve toward +Y with curvature k."""
    def f(p):
        c, s = np.cos(k * p[:, 0]), np.sin(k * p[:, 0])
        q = np.empty_like(p)
        q[:, 0] = c * p[:, 0] - s * p[:, 1]
        q[:, 1] = s * p[:, 0] + c * p[:, 1]
        q[:, 2] = p[:, 2]
        return a(q)
    return f


def twist(a, k: float):
    """Twist around local Y by k radians per unit of height (bound: keep k * radius small)."""
    def f(p):
        c, s = np.cos(k * p[:, 1]), np.sin(k * p[:, 1])
        q = np.empty_like(p)
        q[:, 0] = c * p[:, 0] - s * p[:, 2]
        q[:, 1] = p[:, 1]
        q[:, 2] = s * p[:, 0] + c * p[:, 2]
        return a(q)
    return f


def displace(a, disp, lipschitz: float = 1.0):
    """Add a small displacement field ``disp(p)``; the sum is divided by ``lipschitz``."""
    def f(p):
        return (a(p) + disp(p)) / lipschitz
    return f


def cup(a, c: float):
    """Curl a slab around its Y axis: z is lifted by c*x^2 (transverse arch of a palm)."""
    def f(p):
        q = p.copy()
        q[:, 2] = q[:, 2] - c * q[:, 0] * q[:, 0]
        return a(q) / np.sqrt(1.0 + (2.0 * c * np.minimum(np.abs(p[:, 0]), 3.0)) ** 2)
    b = bound_of(a)
    if b is not None:
        f.bound = (b[0], b[1] + abs(c) * (abs(b[0][0]) + b[1]) ** 2)
    return f


# --------------------------------------------------------------------------- evaluation helpers

def evaluate(f, p: Array, chunk: int = 400_000) -> Array:
    """Evaluate in chunks to bound temporary memory."""
    p = np.asarray(p, dtype=np.float64)
    out = np.empty(len(p), dtype=np.float64)
    for i in range(0, len(p), chunk):
        out[i:i + chunk] = f(p[i:i + chunk])
    return out


def gradient(f, p: Array, eps: float) -> Array:
    """Central-difference gradient (tetrahedral 4-tap), normalised."""
    k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=np.float64)
    g = np.zeros_like(p)
    for kk in k:
        g += kk[None, :] * evaluate(f, p + kk[None, :] * eps)[:, None]
    n = _len(g)
    return g / np.maximum(n, 1e-12)[:, None]
