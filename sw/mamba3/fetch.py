import json
import pickle
import sys
import urllib.request
import zipfile
from pathlib import Path

import mref
import numpy as np

HF = "https://huggingface.co/state-spaces/{}/resolve/main/{}"
EVAL_IDS = [
    128000,
    791,
    6864,
    315,
    9822,
    374,
    12366,
    13,
    578,
    6864,
    315,
    10057,
    374,
]
OUT = Path(__file__).resolve().parents[2] / "build" / "mamba3"
RAM = 64 << 20
STORAGE = {"BFloat16Storage": np.uint16, "FloatStorage": np.float32}


class Stor:
    def __init__(self, key, dt):
        self.key, self.dt = key, dt


def rebuild(st, off, size, stride, *a):
    return (st, off, tuple(size), tuple(stride))


# Pickle loader without torch
class Unp(pickle.Unpickler):
    def find_class(self, mod, name):
        if (mod, name) == ("torch._utils", "_rebuild_tensor_v2"):
            return rebuild
        if mod == "torch" and name in STORAGE:
            return STORAGE[name]
        if (mod, name) == ("collections", "OrderedDict"):
            return dict
        raise pickle.UnpicklingError(f"{mod}.{name}")

    def persistent_load(self, pid):
        assert pid[0] == "storage" and pid[1] in STORAGE.values(), pid
        return Stor(pid[2], pid[1])


def load(path):
    z = zipfile.ZipFile(path)
    pre = z.namelist()[0].split("/")[0]
    meta = Unp(z.open(f"{pre}/data.pkl")).load()
    out = {}
    for k, (st, off, size, stride) in meta.items():
        raw = np.frombuffer(z.read(f"{pre}/data/{st.key}"), st.dt)
        n = int(np.prod(size))
        exp = tuple(int(np.prod(size[i + 1 :])) for i in range(len(size)))
        assert stride == exp or n <= 1, (k, stride)
        out[k.replace("backbone.", "")] = (
            raw[off : off + n].reshape(size).copy()
        )
    return out


# Round to nearest even
def tobf16(a):
    u = np.asarray(a, np.float32).view(np.uint32)
    return ((u + 0x7FFF + ((u >> 16) & 1)) >> 16).astype(np.uint16)


def npz(name):
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    dst = d / "weights.npz"
    if dst.exists():
        return dst
    binp = d / "pytorch_model.bin"
    if not binp.exists():
        urllib.request.urlretrieve(HF.format(name, "pytorch_model.bin"), binp)
    cfg = (
        urllib.request.urlopen(HF.format(name, "config.json"), timeout=60)
        .read()
        .decode()
    )
    w = load(binp)
    w["__config__"] = np.array(cfg)
    w["__name__"] = np.array(name)
    if "lm_head.weight" in w:
        assert np.array_equal(w["lm_head.weight"], w["embedding.weight"])
        del w["lm_head.weight"]
    np.savez(dst, **w)
    return dst


def main():
    name, layer, fmt = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    assert fmt in ("fp32", "bf16"), "format is fp32 or bf16"
    path = npz(name)
    w = mref.W(str(path))
    assert 0 <= layer < w.NL, f"layer {layer} out of range 0..{w.NL - 1}"
    T = len(EVAL_IDS) - 1
    hist = mref.run(w, EVAL_IDS, layer + 1)
    r = hist[T]["r_in"] if layer == 0 else hist[T]["tr"][layer - 1]["ro"]
    st = hist[T]["st_in"][layer]
    p = f"layers.{layer}."
    blobs = {}

    def f32(n, a):
        blobs[n] = np.ascontiguousarray(
            np.asarray(a, np.float64).astype(np.float32)
        )

    for n, k in (
        ("w_in", "mixer.in_proj.weight"),
        ("w_out", "mixer.out_proj.weight"),
        ("w_f1", "mlp.fc1.weight"),
        ("w_f2", "mlp.fc2.weight"),
    ):
        raw = w.z[p + k]
        assert raw.shape[1] % 2 == 0, (k, raw.shape)
        if fmt == "bf16":
            blobs[n] = np.ascontiguousarray(
                raw if raw.dtype == np.uint16 else tobf16(raw)
            )
        else:
            f32(n, w[p + k])
    for n, k in (
        ("t_norm", "norm.weight"),
        ("t_norm2", "norm2.weight"),
        ("t_bnorm", "mixer.B_norm.weight"),
        ("t_cnorm", "mixer.C_norm.weight"),
        ("t_d", "mixer.D"),
        ("t_dtb", "mixer.dt_bias"),
    ):
        f32(n, w[p + k])
    f32("t_bb", w[p + "mixer.B_bias"][:, 0])
    f32("t_cb", w[p + "mixer.C_bias"][:, 0])
    f32("i_r", r)
    f32("i_h", st["H"])
    f32("i_kp", st["k"])
    f32("i_vp", st["v"])
    f32("i_ang", st["ang"])
    assert (
        w[p + "mlp.fc1.weight"].shape[0] == 2 * w.DF
        and w[p + "mixer.in_proj.weight"].shape[1] == w.DM
    )
    for n, a in blobs.items():
        a.tofile(OUT / f"{n}.bin")
    # Projection slice offsets
    O = dict(
        zip(
            ["Z", "X", "B", "C", "DT", "A", "TR", "ANG"],
            [0] + [int(v) for v in w.SPLIT],
        )
    )
    nzx = O["ANG"] + w.NA
    assert w[p + "mixer.in_proj.weight"].shape[0] == nzx
    hd = [
        f'#define MODEL "{name} layer {layer} {fmt}"',
        f"#define WBF16 {int(fmt == 'bf16')}",
    ]
    hd += [
        f"#define {k} {v}"
        for k, v in {
            "DM": w.DM,
            "DI": w.DI,
            "NS": w.NS,
            "NH": w.NH,
            "P": w.P,
            "NA": w.NA,
            "DF": w.DF,
            "NZX": nzx,
        }.items()
    ]
    hd += [f"#define O_{k} {v}" for k, v in O.items()]
    hd += [f"#define A_FLOOR {w.A_FLOOR!r}f", f"#define EPS {mref.EPS!r}f"]
    (OUT / "model.h").write_text("#pragma once\n" + "\n".join(hd) + "\n")
    meta = {
        "npz": str(path),
        "name": name,
        "layer": layer,
        "fmt": fmt,
        "ids": EVAL_IDS,
        "T": T,
    }
    (OUT / "meta.json").write_text(json.dumps(meta) + "\n")
    rod = sum(a.nbytes for a in blobs.values())
    # Static array bytes estimate
    bss = 4 * (
        w.NH * w.P * w.NS
        + 8 * w.NH * w.NS
        + 3 * w.NH * w.NA
        + 12 * w.DI
        + 8 * w.DM
        + 3 * w.DF
        + nzx
        + 16 * w.NH
        + 2 * w.NS
    )
    print(
        f"{name} layer {layer} {fmt}: d_model {w.DM} d_inner {w.DI} heads {w.NH}x{w.P} d_state {w.NS} "
        f"rope pairs {w.NA} mlp {w.DF}"
    )
    print(
        f"wrote {OUT}: weights and inputs {rod} bytes, arrays about {bss} bytes, "
        f"{'fits' if rod + bss < RAM - (1 << 20) else 'DOES NOT FIT'} in {RAM} bytes"
    )


if __name__ == "__main__":
    main()
