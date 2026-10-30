import json

import numpy as np

EPS = 1e-5


# Widen bf16 to float64
def bf(a):
    a = np.asarray(a)
    if a.dtype != np.uint16:
        return a.astype(np.float64)
    return (a.astype(np.uint32) << 16).view(np.float32).astype(np.float64)


class W:
    def __init__(self, path):
        self.z = np.load(path)
        self.name = str(self.z["__name__"])
        c = json.loads(str(self.z["__config__"]))
        s = c["ssm_cfg"]
        assert (
            s["layer"] == "Mamba3"
            and not s.get("is_mimo")
            and not s.get("is_outproj_norm")
        )
        assert (
            s.get("ngroups", 1) == 1
            and c["rms_norm"]
            and not c.get("attn_layer_idx")
        )
        self.cfg = c
        self.DM = c["d_model"]
        self.DI = s.get("expand", 2) * self.DM
        self.NS = s.get("d_state", 128)
        self.P = s.get("headdim", 64)
        self.NH = self.DI // self.P
        sp = int(self.NS * s.get("rope_fraction", 0.5))
        self.NA = (sp - sp % 2) // 2
        self.DF = (c["d_intermediate"] + 127) // 128 * 128
        assert self.DF > 0
        self.NL = c["n_layer"]
        self.A_FLOOR = s.get("A_floor", 1e-4)
        # Projection slice ends
        self.SPLIT = np.cumsum(
            [self.DI, self.DI, self.NS, self.NS, self.NH, self.NH, self.NH]
        )
        self.c = {}

    def __getitem__(self, k):
        if k not in self.c:
            self.c[k] = bf(self.z[k])
        return self.c[k]

    def emb(self, t):
        return bf(self.z["embedding.weight"][t])


def rms(v, g):
    return v / np.sqrt((v * v).mean(-1, keepdims=True) + EPS) * g


def sigmoid(v):
    return 1 / (1 + np.exp(-v))


def silu(v):
    return v * sigmoid(v)


def softplus(v):
    return np.log1p(np.exp(-np.abs(v))) + np.maximum(v, 0)


# Mamba3 A parametrization
def heavy(v):
    return np.maximum(v, 0) + 1 / (1 - np.minimum(v, 0))


def rot(t, c, s):
    na = c.shape[-1]
    a, b = t[..., 0 : 2 * na : 2].copy(), t[..., 1 : 2 * na : 2].copy()
    o = t.copy()
    o[..., 0 : 2 * na : 2] = a * c - b * s
    o[..., 1 : 2 * na : 2] = a * s + b * c
    return o


def state0(w):
    return {
        "ang": np.zeros((w.NH, w.NA)),
        "H": np.zeros((w.NH, w.P, w.NS)),
        "k": np.zeros((w.NH, w.NS)),
        "v": np.zeros((w.NH, w.P)),
    }


# Trapezoid SISO update
def ssm(q, k, v, adt, dt, trap, qb, kb, ang, D, z, st):
    q, k = q + qb, k + kb
    a = st["ang"] + ang * dt[:, None]
    a = a - 2 * np.pi * np.floor(a / (2 * np.pi))
    c, s = np.cos(a), np.sin(a)
    qr, kr = rot(q, c, s), rot(k, c, s)
    lam = sigmoid(trap)
    alpha = np.exp(adt)
    beta = (1 - lam) * dt * alpha
    gamma = lam * dt
    H = alpha[:, None, None] * st["H"] + beta[:, None, None] * (
        st["v"][:, :, None] * st["k"][:, None, :]
    )
    H = H + gamma[:, None, None] * (v[:, :, None] * kr[:, None, :])
    y = np.einsum("hpn,hn->hp", H, qr)
    if D is not None:
        y = y + D[:, None] * v
    yp = y
    if z is not None:
        y = y * silu(z)
    tr = {
        "a": a,
        "cos": c,
        "sin": s,
        "qb": q,
        "kb": k,
        "qr": qr,
        "kr": kr,
        "lam": lam,
        "alpha": alpha,
        "beta": beta,
        "gamma": gamma,
        "H": H,
        "yp": yp.reshape(-1),
    }
    return y, {"ang": a, "H": H, "k": kr, "v": v.copy()}, tr


def layer(w, L, r, st):
    p = f"layers.{L}."
    NH, NS, NA, P, DF = w.NH, w.NS, w.NA, w.P, w.DF
    u = rms(r, w[p + "norm.weight"])
    zx = w[p + "mixer.in_proj.weight"] @ u
    z, x, B, C, ddt, dA, trap, ang = np.split(zx, w.SPLIT)
    A = np.minimum(-heavy(dA), -w.A_FLOOR)
    dt = softplus(ddt + w[p + "mixer.dt_bias"])
    Bn = rms(B, w[p + "mixer.B_norm.weight"])
    Cn = rms(C, w[p + "mixer.C_norm.weight"])
    Bh, Ch = np.broadcast_to(Bn, (NH, NS)), np.broadcast_to(Cn, (NH, NS))
    th = np.tanh(ang)
    angp = np.broadcast_to(th * np.pi, (NH, NA))
    y, st2, tr = ssm(
        Ch,
        Bh,
        x.reshape(NH, P),
        A * dt,
        dt,
        trap,
        w[p + "mixer.C_bias"][:, 0],
        w[p + "mixer.B_bias"][:, 0],
        angp,
        w[p + "mixer.D"],
        z.reshape(NH, P),
        st,
    )
    out = w[p + "mixer.out_proj.weight"] @ y.reshape(-1)
    r1 = r + out
    u2 = rms(r1, w[p + "norm2.weight"])
    f = w[p + "mlp.fc1.weight"] @ u2
    g = f[:DF] * silu(f[DF:])
    m = w[p + "mlp.fc2.weight"] @ g
    tr.update(
        u=u,
        zx=zx,
        A=A,
        adt=A * dt,
        dt=dt,
        th=th,
        Bn=Bn,
        Cn=Cn,
        out=out,
        r1=r1,
        u2=u2,
        f=f,
        g=g,
        m=m,
        y=y.reshape(-1),
        ro=r1 + m,
    )
    return r1 + m, st2, tr


def logits(w, r):
    e = w.z["embedding.weight"]
    x = rms(r, w["norm_f.weight"])
    out = np.empty(e.shape[0])
    for i in range(0, e.shape[0], 16384):
        out[i : i + 16384] = bf(e[i : i + 16384]) @ x
    return out


def run(w, toks, layers=None):
    nl = w.NL if layers is None else layers
    sts = [state0(w) for _ in range(nl)]
    hist = []
    for t in toks:
        r = w.emb(t)
        rec = {"r_in": r, "st_in": list(sts), "tr": []}
        for L in range(nl):
            r, sts[L], tr = layer(w, L, r, sts[L])
            rec["tr"].append(tr)
        rec["r"] = r
        rec["sts"] = list(sts)
        hist.append(rec)
    return hist


def finish(w, r, sts, L0=1):
    for L in range(L0, w.NL):
        r, _, _ = layer(w, L, r, sts[L])
    return logits(w, r)
