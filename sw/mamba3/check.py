import json
import sys
from pathlib import Path

import mref
import numpy as np

OUT = Path(__file__).resolve().parents[2] / "build" / "mamba3"


# Parse ro hex dumps
def parse(path, n):
    res, cur = {}, None
    with open(path, errors="replace") as fh:
        lines = fh.readlines()
    for line in lines:
        f = line.split()
        if len(f) == 2 and f[1] == "ro":
            cur = res.setdefault(f[0], [])
        elif cur is not None and f and len(cur) < n:
            cur += [int(f[0][k : k + 8], 16) for k in range(0, len(f[0]), 8)]
    return {
        k: np.array(v, np.uint32).view(np.float32).astype(np.float64)
        for k, v in res.items()
        if len(v) == n
    }


def main():
    meta = json.loads((OUT / "meta.json").read_text())
    w = mref.W(meta["npz"])
    L, T = meta["layer"], meta["T"]
    runs = parse(sys.argv[1], w.DM)
    assert runs, f"no ro dump in {sys.argv[1]}"
    hist = mref.run(w, meta["ids"])
    ref = hist[T]["tr"][L]["ro"]
    lf = mref.logits(w, hist[T]["r"])
    tf = np.argsort(-lf)[:5]
    print(f"{meta['name']} layer {L} {meta['fmt']}, prompt token T={T}")
    print(
        f"float64 reference: next token {int(tf[0])}, top-5 {[int(v) for v in tf]}, "
        f"top1-top2 margin {lf[tf[0]] - lf[tf[1]]:.3g}"
    )
    for tag, ro in runs.items():
        e = np.abs(ro - ref)
        lq = mref.finish(w, ro, hist[T]["st_in"], L + 1)
        tq = np.argsort(-lq)[:5]
        print(
            f"{tag}: layer output max abs err {e.max():.3g} (ref max {np.abs(ref).max():.3g}), "
            f"next token {int(tq[0])}, same: {tq[0] == tf[0]}, top-5 {[int(v) for v in tq]}, "
            f"logit max abs diff {np.abs(lq - lf).max():.3g}"
        )


if __name__ == "__main__":
    main()
