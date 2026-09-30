"""SDF -> triangle mesh: narrow-band grid sampling, marching cubes, cleanup, QEM decimation,
surface projection, gradient normals, SDF ambient occlusion and a deterministic OBJ writer.

Everything is deterministic: no randomness, fixed iteration orders, fixed number formatting.
"""
from __future__ import annotations

import math
import time

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from skimage import measure

from sdf import evaluate, gradient


def log(msg: str) -> None:
    print(f"[sculpt {time.strftime('%H:%M:%S')}] {msg}", flush=True)


# --------------------------------------------------------------------------- sampling + MC

def sample_narrow_band(f, lo, hi, h: float, strides=(16, 8, 4, 2, 1), band: float = 2.0):
    """Hierarchical narrow-band sampling of ``f`` on a grid of spacing ``h`` covering [lo, hi].

    The coarsest lattice (stride 16) is evaluated everywhere; at each finer stride only the
    cells whose corners lie within ``band`` cell diagonals of the surface are subdivided and
    their nodes evaluated. The returned ``mask`` marks the finest active cells (by their origin
    node): marching cubes only visits those, so values elsewhere are irrelevant (set to +1).
    A cell whose corners disagree in sign always has a corner within half a diagonal of the
    surface, so no crossing is lost as long as the field is a distance bound.
    Returns (volume float32 (nx, ny, nz), origin, mask).
    """
    lo = np.asarray(lo, dtype=np.float64)
    s0 = strides[0]
    nc = np.ceil((hi - np.asarray(lo)) / (h * s0)).astype(np.int64)
    n = nc * s0 + 1
    vol = np.ones(tuple(n), dtype=np.float32)
    done = np.zeros(tuple(n), dtype=bool)

    def eval_nodes(nodes):
        lin = np.unique(np.ravel_multi_index(nodes.T, tuple(n)))
        lin = lin[~done.ravel()[lin]]
        if len(lin):
            ijk = np.stack(np.unravel_index(lin, tuple(n)), axis=1)
            vol.ravel()[lin] = evaluate(f, lo[None, :] + ijk * h).astype(np.float32)
            done.ravel()[lin] = True
        return len(lin)

    # coarsest lattice: all nodes
    g = np.stack(np.meshgrid(*[np.arange(0, n[i], s0) for i in range(3)], indexing="ij"),
                 axis=-1).reshape(-1, 3)
    total = eval_nodes(g)
    corners = np.array([[x, y, z] for x in (0, 1) for y in (0, 1) for z in (0, 1)])
    cells = np.stack(np.meshgrid(*[np.arange(nc[i]) for i in range(3)], indexing="ij"),
                     axis=-1).reshape(-1, 3) * s0  # cell origins (node indices)
    prev = s0
    for s in list(strides[1:]) + [None]:
        # keep cells (size prev) whose corner values are near the surface
        thr = band * prev * h * math.sqrt(3.0)
        keep = np.zeros(len(cells), dtype=bool)
        for c in corners:
            nd = cells + c[None, :] * prev
            keep |= np.abs(vol[nd[:, 0], nd[:, 1], nd[:, 2]]) < thr
        cells = cells[keep]
        if s is None:
            break
        k = prev // s
        sub = np.stack(np.meshgrid(*[np.arange(k)] * 3, indexing="ij"), axis=-1).reshape(-1, 3) * s
        cells = (cells[:, None, :] + sub[None, :, :]).reshape(-1, 3)
        nodes = (cells[:, None, :] + corners[None, :, :] * s).reshape(-1, 3)
        total += eval_nodes(nodes)
        prev = s
    mask = np.zeros(tuple(n), dtype=bool)
    mask[cells[:, 0], cells[:, 1], cells[:, 2]] = True
    log(f"grid {tuple(int(x) for x in n)} h={h:.4f}: {total} evaluations, "
        f"{len(cells)} active cells")
    return vol, lo, mask


def marching_cubes(vol, origin, h: float, mask=None):
    verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(h, h, h), mask=mask,
                                                allow_degenerate=False, method="lewiner")
    verts = verts.astype(np.float64) + origin[None, :]
    faces = faces.astype(np.int64)
    if signed_volume(verts, faces) < 0.0:
        faces = faces[:, [0, 2, 1]]
    return verts, faces


def signed_volume(V, F) -> float:
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


# --------------------------------------------------------------------------- topology helpers

def compact(V, F, *extra):
    used = np.unique(F)
    remap = np.full(len(V), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    out = [V[used], remap[F]]
    for e in extra:
        out.append(e[used])
    return tuple(out)


def keep_largest_component(V, F):
    n = len(V)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]]])
    g = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    ncomp, labels = connected_components(g, directed=False)
    if ncomp == 1:
        return V, F, 0
    face_lab = labels[F[:, 0]]
    counts = np.bincount(face_lab, minlength=ncomp)
    best = int(np.argmax(counts))
    dropped = int(len(F) - counts[best])
    F = F[face_lab == best]
    V, F = compact(V, F)
    return V, F, dropped


def edge_stats(F):
    """Returns (#boundary edges, #non-manifold edges) of a triangle list."""
    e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
    _, counts = np.unique(e[:, 0] * (F.max() + 1) + e[:, 1], return_counts=True)
    return int((counts == 1).sum()), int((counts > 2).sum())


def euler_components(V, F):
    n = len(V)
    e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
    ne = len(np.unique(e[:, 0] * n + e[:, 1]))
    g = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    ncomp, _ = connected_components(g, directed=False)
    return n - ne + len(F), ncomp


# --------------------------------------------------------------------------- QEM decimation

_SYM = [(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (1, 2), (1, 3), (2, 2), (2, 3), (3, 3)]


def _face_normals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    return n


def _quadrics(V, F):
    n = _face_normals(V, F)
    area2 = np.linalg.norm(n, axis=1)
    nn = n / np.maximum(area2, 1e-30)[:, None]
    d = -np.einsum("ij,ij->i", nn, V[F[:, 0]])
    plane = np.concatenate([nn, d[:, None]], axis=1)
    w = area2 * 0.5
    K = np.stack([w * plane[:, i] * plane[:, j] for i, j in _SYM], axis=1)
    Q = np.zeros((len(V), 10))
    for c in range(3):
        np.add.at(Q, F[:, c], K)
    return Q


def _eval_q(Q, x):
    """x^T Q x for homogeneous x = (x, 1); Q in 10-component symmetric form."""
    X, Y, Z = x[:, 0], x[:, 1], x[:, 2]
    return (Q[:, 0] * X * X + 2 * Q[:, 1] * X * Y + 2 * Q[:, 2] * X * Z + 2 * Q[:, 3] * X
            + Q[:, 4] * Y * Y + 2 * Q[:, 5] * Y * Z + 2 * Q[:, 6] * Y
            + Q[:, 7] * Z * Z + 2 * Q[:, 8] * Z + Q[:, 9])


def _optimal(Q, pu, pv):
    a, b, c, d, e, f = Q[:, 0], Q[:, 1], Q[:, 2], Q[:, 4], Q[:, 5], Q[:, 7]
    r = -np.stack([Q[:, 3], Q[:, 6], Q[:, 8]], axis=1)
    # adjugate of symmetric [[a b c][b d e][c e f]]
    A00 = d * f - e * e
    A01 = c * e - b * f
    A02 = b * e - c * d
    A11 = a * f - c * c
    A12 = b * c - a * e
    A22 = a * d - b * b
    det = a * A00 + b * A01 + c * A02
    mid = 0.5 * (pu + pv)
    scale = (np.abs(a) + np.abs(d) + np.abs(f)) ** 3 + 1e-300
    ok = np.abs(det) > 1e-9 * scale
    inv = 1.0 / np.where(ok, det, 1.0)
    x = np.stack([
        (A00 * r[:, 0] + A01 * r[:, 1] + A02 * r[:, 2]) * inv,
        (A01 * r[:, 0] + A11 * r[:, 1] + A12 * r[:, 2]) * inv,
        (A02 * r[:, 0] + A12 * r[:, 1] + A22 * r[:, 2]) * inv,
    ], axis=1)
    elen = np.linalg.norm(pv - pu, axis=1)
    far = np.linalg.norm(x - mid, axis=1) > elen
    use_mid = ~ok | far
    x[use_mid] = mid[use_mid]
    # compare with the endpoints / midpoint and keep the cheapest
    cands = [x, pu, pv, mid]
    costs = np.stack([_eval_q(Q, cnd) for cnd in cands], axis=1)
    best = np.argmin(costs, axis=1)
    out = np.choose(best[:, None], cands)
    return out, costs[np.arange(len(best)), best]


def _tri_quality(a, b, c):
    n = np.cross(b - a, c - a)
    area = 0.5 * np.linalg.norm(n, axis=1)
    s = (np.einsum("ij,ij->i", b - a, b - a) + np.einsum("ij,ij->i", c - b, c - b)
         + np.einsum("ij,ij->i", a - c, a - c))
    return 4.0 * math.sqrt(3.0) * area / np.maximum(s, 1e-300), n


def decimate(V, F, target_faces: int, *, quantile: float = 0.35, min_dot: float = 0.2,
             min_quality: float = 0.03, max_valence: int = 12, length_weight: float = 0.02,
             project=None, importance=None):
    """Batched quadric-error edge collapse (Garland-Heckbert), fully vectorised.

    Each pass selects an independent set of cheapest edges (an edge is taken only when it is the
    cheapest edge in the 2-ring of both endpoints, which makes the touched stars disjoint), then
    rejects collapses that break the link condition, flip a face, create a sliver or raise valence
    too much. ``project(points) -> points`` optionally snaps new vertices back to the SDF surface.
    ``importance(points) -> weights`` (>= 1) scales the error of each vertex: regions with a
    higher weight keep proportionally more triangles (e.g. the face of a figure).
    """
    V = V.copy()
    F = F.copy()
    n = len(V)
    Q = _quadrics(V, F)
    wv = np.ones(n) if importance is None else np.asarray(importance(V), dtype=np.float64)
    Q *= wv[:, None]
    passes = 0
    stall = 0
    rejected = np.zeros(0, dtype=np.int64)  # edge keys rejected recently (skipped for a while)
    while len(F) > target_faces and passes < 400:
        passes += 1
        e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
        key = np.unique(e[:, 0] * n + e[:, 1])
        eu, ev = key // n, key % n
        pu, pv = V[eu], V[ev]
        Qe = Q[eu] + Q[ev]
        x, cost = _optimal(Qe, pu, pv)
        el2 = np.einsum("ij,ij->i", pv - pu, pv - pu)
        cost = cost + length_weight * el2 * el2 * 0.5 * (wv[eu] + wv[ev])
        order = np.argsort(cost, kind="stable")
        rank = np.empty(len(order), dtype=np.int64)
        rank[order] = np.arange(len(order))
        need = (len(F) - target_faces) // 2 + 1
        limit = max(int(len(order) * quantile), 1)
        allowed = rank < limit
        if passes % 8 == 0:
            rejected = np.zeros(0, dtype=np.int64)
        if len(rejected):
            allowed &= ~np.isin(key, rejected)
        big = np.iinfo(np.int64).max
        m1 = np.full(n, big, dtype=np.int64)
        np.minimum.at(m1, eu[allowed], rank[allowed])
        np.minimum.at(m1, ev[allowed], rank[allowed])
        m2 = m1.copy()
        np.minimum.at(m2, eu, m1[ev])
        np.minimum.at(m2, ev, m1[eu])
        sel = np.flatnonzero(allowed & (rank == m2[eu]) & (rank == m2[ev]))
        if len(sel) == 0:
            break
        su, sv, sx = eu[sel], ev[sel], x[sel]
        if project is not None:
            sx = project(sx)
        # valence + link condition via CSR neighbour lists
        both = np.concatenate([eu, ev])
        other = np.concatenate([ev, eu])
        srt = np.argsort(both, kind="stable")
        nb_idx = other[srt]
        deg = np.bincount(both, minlength=n)
        ptr = np.concatenate([[0], np.cumsum(deg)])
        ok = ~((deg[su] <= 3) & (deg[sv] <= 3)) & (deg[su] + deg[sv] - 4 <= max_valence)

        def gather(vs):
            cnt = deg[vs]
            owner = np.repeat(np.arange(len(vs)), cnt)
            start = np.repeat(ptr[vs], cnt)
            off = np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt)
            return owner, nb_idx[start + off]
        ou, nu = gather(su)
        ov, nv = gather(sv)
        k_all = np.concatenate([ou * n + nu, ov * n + nv])
        uk, cnt = np.unique(k_all, return_counts=True)
        cm = uk[cnt == 2]
        common = np.bincount(cm // n, minlength=len(sel))
        ok &= common == 2
        # the two common neighbours lose one edge each: they must keep degree >= 3
        thin = np.bincount(cm // n, weights=(deg[cm % n] <= 3), minlength=len(sel))
        ok &= thin == 0
        # flip / sliver check on faces touching exactly one endpoint of a selected edge
        emap = np.full(n, -1, dtype=np.int64)
        emap[su] = np.arange(len(sel))
        emap[sv] = np.arange(len(sel))
        fm = emap[F]
        hits = (fm >= 0).sum(axis=1)
        moved = np.flatnonzero(hits == 1)
        corner = np.argmax(fm[moved] >= 0, axis=1)
        eid = fm[moved, corner]
        a, b, c = V[F[moved, 0]], V[F[moved, 1]], V[F[moved, 2]]
        q_old, n_old = _tri_quality(a, b, c)
        newp = sx[eid]
        a2, b2, c2 = a.copy(), b.copy(), c.copy()
        a2[corner == 0] = newp[corner == 0]
        b2[corner == 1] = newp[corner == 1]
        c2[corner == 2] = newp[corner == 2]
        q_new, n_new = _tri_quality(a2, b2, c2)
        dn = np.einsum("ij,ij->i", n_old, n_new) / np.maximum(
            np.linalg.norm(n_old, axis=1) * np.linalg.norm(n_new, axis=1), 1e-300)
        bad = (dn < min_dot) | ((q_new < min_quality) & (q_new < 0.5 * q_old))
        bad_e = np.zeros(len(sel), dtype=bool)
        bad_e[eid[bad]] = True
        ok &= ~bad_e
        good = np.flatnonzero(ok)
        rejected = np.union1d(rejected, key[sel[~ok]])
        if len(good) > need:
            good = good[np.argsort(rank[sel][good], kind="stable")[:need]]
        if len(good) == 0:
            stall += 1
            quantile = min(1.0, quantile * 1.5)
            if stall > 6:
                break
            continue
        stall = 0
        gu, gv = su[good], sv[good]
        V[gu] = sx[good]
        Q[gu] += Q[gv]
        wv[gu] = np.maximum(wv[gu], wv[gv])
        remap = np.arange(n)
        remap[gv] = gu
        F = remap[F]
        keep = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 2] != F[:, 0])
        F = F[keep]
    V, F = compact(V, F)
    log(f"decimate: {passes} passes -> {len(F)} faces")
    return V, F


# --------------------------------------------------------------------------- local refinement

class RadialWarp:
    """Magnifies a ball of the model for marching cubes (finer effective grid there).

    The grid lives in a warped space u; world = forward(u) = c + (u - c) * phi(r) / r with
    phi'(r) = 1/m inside r0, blending smoothly (smoothstep) to 1 at r1, so ``forward`` never
    expands distances: f(forward(u)) is still a distance *bound* in u-space and the narrow-band
    culling stays conservative. Outside r1 the map is a pure radial shift by ``delta``.
    Effective grid spacing: h / m inside r0, h beyond r1.
    """

    def __init__(self, centre, m: float, r0: float, r1: float):
        self.c = np.asarray(centre, dtype=np.float64)
        self.m, self.r0, self.r1 = float(m), float(r0), float(r1)
        self.delta = self.r1 - self.phi(np.array([self.r1]))[0]

    def phi(self, r):
        r0, r1, a = self.r0, self.r1, 1.0 - 1.0 / self.m
        w = r1 - r0
        t = np.clip((r - r0) / w, 0.0, 1.0)
        integ = np.where(r <= r0, 0.0, np.where(r >= r1, 0.5 * w + (r - r1), w * (t ** 3 - 0.5 * t ** 4)))
        return r / self.m + a * integ

    def forward(self, u):
        q = u - self.c[None, :]
        r = np.sqrt(np.einsum("ij,ij->i", q, q))
        s = self.phi(r) / np.maximum(r, 1e-12)
        s = np.where(r < 1e-9, 1.0 / self.m, s)
        return self.c[None, :] + q * s[:, None]

    def sdf(self, f):
        def g(u):
            return f(self.forward(u))
        return g

    def bounds(self, lo, hi):
        """Box in u-space that maps onto (a superset of) the world box [lo, hi]."""
        return np.asarray(lo, float) - self.delta, np.asarray(hi, float) + self.delta



# --------------------------------------------------------------------------- surface attributes

def project_to_surface(f, P, h: float, iters: int = 3):
    P = P.copy()
    for _ in range(iters):
        d = evaluate(f, P)
        g = gradient(f, P, 0.25 * h)
        step = np.clip(d, -0.5 * h, 0.5 * h)
        P -= g * step[:, None]
    return P


def sdf_ambient_occlusion(f, P, N, steps, strength: float = 1.0, cone: float = 0.55):
    """Ambient occlusion from the SDF: at each scale h, how much of the free distance h along the
    normal (and 4 tilted directions forming a cone) is actually free. 1 = fully open."""
    # tangent frame per vertex
    ref = np.where(np.abs(N[:, 1:2]) < 0.9, np.array([[0.0, 1.0, 0.0]]),
                   np.array([[1.0, 0.0, 0.0]]))
    T = np.cross(N, ref)
    T /= np.linalg.norm(T, axis=1)[:, None]
    B = np.cross(N, T)
    dirs = [N]
    for ang in (0.0, 0.5 * math.pi, math.pi, 1.5 * math.pi):
        dvec = N * math.cos(cone) + (T * math.cos(ang) + B * math.sin(ang)) * math.sin(cone)
        dirs.append(dvec)
    occ = np.zeros(len(P))
    wsum = 0.0
    for i, h in enumerate(steps):
        w = 1.0 / (1.0 + i * 0.35)
        for j, dvec in enumerate(dirs):
            wd = 1.0 if j == 0 else 0.6
            d = evaluate(f, P + dvec * h)
            occ += w * wd * np.clip((h - d) / h, 0.0, 1.0)
            wsum += w * wd
    ao = 1.0 - strength * occ / wsum
    return np.clip(ao, 0.0, 1.0)


# --------------------------------------------------------------------------- output

def write_obj(path: str, V, N, C, F, header: str) -> int:
    """Deterministic OBJ: ``v x y z r g b`` (vertex colour extension), ``vn`` and ``f v//n``.
    Faces are counter-clockwise seen from outside (OBJ convention; Godot's importer converts
    to its clockwise front faces). Returns the file size in bytes."""
    lines = [f"# {line}" for line in header.splitlines()]
    vs = np.round(V, 5) + 0.0  # + 0.0 turns -0.0 into 0.0
    cs = np.round(C, 3) + 0.0
    ns = np.round(N, 4) + 0.0
    lines += [f"v {a:.5f} {b:.5f} {c:.5f} {r:.3f} {g:.3f} {bb:.3f}"
              for (a, b, c), (r, g, bb) in zip(vs.tolist(), cs.tolist())]
    lines += [f"vn {a:.4f} {b:.4f} {c:.4f}" for a, b, c in ns.tolist()]
    F1 = F + 1
    lines += [f"f {a}//{a} {b}//{b} {c}//{c}" for a, b, c in F1.tolist()]
    data = ("\n".join(lines) + "\n").encode("ascii")
    with open(path, "wb") as fh:
        fh.write(data)
    return len(data)


def bake(f, lo, hi, h: float, target_faces: int, ao_steps, ao_strength: float = 1.0,
         decimate_kw=None, warp=None):
    """Full pipeline for one sculpture. Returns dict with V, N, C, F and stats. ``warp`` (a
    ``RadialWarp``) refines the marching-cubes grid locally."""
    t0 = time.time()
    if warp is not None:
        lo, hi = warp.bounds(lo, hi)
        vol, origin, mask = sample_narrow_band(warp.sdf(f), lo, hi, h)
    else:
        vol, origin, mask = sample_narrow_band(f, lo, hi, h)
    # every face of the grid box must be outside the shape (closed mesh)
    for axis in range(3):
        for side in (0, -1):
            face = np.take(mask, side, axis=axis)
            assert not face.any(), f"shape touches the grid bounds (axis {axis}, side {side})"
    V, F = marching_cubes(vol, origin, h, mask)
    del vol, mask
    if warp is not None:
        V = warp.forward(V)
    log(f"marching cubes: {len(V)} verts {len(F)} faces ({time.time() - t0:.1f}s)")
    V, F, dropped = keep_largest_component(V, F)
    if dropped:
        log(f"removed {dropped} faces in loose islands")
    b0, nm0 = edge_stats(F)
    log(f"after marching cubes: boundary={b0} nonmanifold={nm0} euler/components={euler_components(V, F)}")
    if b0:
        e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
        k, c = np.unique(e[:, 0] * len(V) + e[:, 1], return_counts=True)
        log(f"boundary near {np.round(V[k[c == 1][:4] // len(V)], 3).tolist()}")
    kw = dict(decimate_kw or {})

    def proj(P):
        return project_to_surface(f, P, h, iters=2)
    if len(F) > target_faces:
        V, F = decimate(V, F, target_faces, project=proj, **kw)
    V = project_to_surface(f, V, h, iters=3)
    N = gradient(f, V, 0.35 * h)
    # orientation check: gradient normals must agree with the winding (outward)
    fn = _face_normals(V, F)
    agree = np.einsum("ij,ij->i", fn, N[F[:, 0]] + N[F[:, 1]] + N[F[:, 2]])
    ao = sdf_ambient_occlusion(f, V, N, ao_steps, ao_strength)
    C = np.repeat(ao[:, None], 3, axis=1)
    boundary, nonmanifold = edge_stats(F)
    chi, ncomp = euler_components(V, F)
    stats = {
        "vertices": int(len(V)), "triangles": int(len(F)), "boundary_edges": boundary,
        "nonmanifold_edges": nonmanifold, "components": ncomp, "euler": chi,
        "winding_disagreements": int((agree <= 0).sum()),
        "ao_min": float(ao.min()), "ao_mean": float(ao.mean()),
        "seconds": round(time.time() - t0, 1),
    }
    log(f"stats {stats}")
    return {"V": V, "N": N, "C": C, "F": F, "stats": stats}
