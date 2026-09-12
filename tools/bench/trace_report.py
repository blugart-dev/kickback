#!/usr/bin/env python3
"""Summarise a KickbackTraceRecorder trace (JSON lines).

    python tools/bench/trace_report.py <trace.jsonl> [--char Target1] [--from 2.0 --to 8.0]

Per character: time in each state, pelvis height stats and the dominant bounce
frequency (FFT of pelvis y after detrending), worst-error stats and the top spikes
with timestamps, ground clipping (lowest body point under 0), root motor saturation
(command magnitude vs limit), and frame-pacing anomalies (frames with >1 physics
step, fps dips). Prints a compact report; no dependencies beyond the stdlib.
"""
import argparse
import json
import math
import sys
from collections import Counter, defaultdict


def load(path):
    header = None
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("header"):
                header = obj
            else:
                rows.append(obj)
    return header, rows


def dominant_frequency(samples, dt):
    """Naive DFT peak of a detrended series (short traces; O(n^2) is fine)."""
    n = len(samples)
    if n < 16 or dt <= 0:
        return None, 0.0
    mean = sum(samples) / n
    # linear detrend
    xs = list(range(n))
    xm = (n - 1) / 2.0
    sxx = sum((x - xm) ** 2 for x in xs)
    sxy = sum((x - xm) * (s - mean) for x, s in zip(xs, samples))
    slope = sxy / sxx if sxx else 0.0
    d = [s - mean - slope * (x - xm) for x, s in zip(xs, samples)]
    best_k, best_p = 0, 0.0
    for k in range(1, n // 2):
        re = sum(d[i] * math.cos(2 * math.pi * k * i / n) for i in range(n))
        im = sum(d[i] * math.sin(2 * math.pi * k * i / n) for i in range(n))
        p = re * re + im * im
        if p > best_p:
            best_p, best_k = p, k
    if best_k == 0:
        return None, 0.0
    freq = best_k / (n * dt)
    amp = 2.0 * math.sqrt(best_p) / n
    return freq, amp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--char", default=None, help="only this character (parent node name)")
    ap.add_argument("--from", dest="t0", type=float, default=None)
    ap.add_argument("--to", dest="t1", type=float, default=None)
    ap.add_argument("--spikes", type=int, default=5)
    args = ap.parse_args()

    header, rows = load(args.trace)
    if args.t0 is not None:
        rows = [r for r in rows if r["t"] >= args.t0]
    if args.t1 is not None:
        rows = [r for r in rows if r["t"] <= args.t1]
    if not rows:
        print("no rows")
        return 1
    dt = rows[0].get("dt", 1.0 / 60.0)
    print(f"trace: {args.trace}")
    if header:
        print(f"  godot {header.get('godot')} | {header.get('physics_engine')} @ {header.get('physics_hz')} Hz | scene {header.get('scene')}")
    span = rows[-1]["t"] - rows[0]["t"]
    print(f"  {len(rows)} ticks over {span:.2f} s (dt {dt * 1000:.2f} ms)")

    # frame pacing
    multi = [r for r in rows if r.get("steps_this_frame", 1) > 1]
    fps = [r.get("fps", 0) for r in rows if r.get("fps", 0) > 0]
    if fps:
        print(f"  process fps: min {min(fps):.0f} / mean {sum(fps) / len(fps):.0f} / max {max(fps):.0f}; "
              f"frames with >1 physics step: {len(multi)} ({100.0 * len(multi) / len(rows):.1f}% of ticks)")

    per = defaultdict(list)
    for r in rows:
        for c in r.get("chars", []):
            if args.char and c.get("name") != args.char:
                continue
            per[c["name"]].append((r["t"], c))

    for name, samples in per.items():
        print(f"\n== {name} ({len(samples)} ticks, motor_mode={samples[0][1].get('motor_mode')})")
        states = Counter(c["state"] for _, c in samples)
        print("  states: " + ", ".join(f"{s} {100.0 * n / len(samples):.0f}%" for s, n in states.most_common()))
        ys = [c["hips"][1] for _, c in samples]
        tgt = [c["hips_target_y"] for _, c in samples if c.get("hips_target_y") is not None]
        print(f"  pelvis y: min {min(ys):.3f} / mean {sum(ys) / len(ys):.3f} / max {max(ys):.3f} "
              f"(peak-to-peak {1000.0 * (max(ys) - min(ys)):.1f} mm)")
        if tgt:
            sag = [t - y for t, y in zip(tgt, ys)]
            print(f"  pelvis sag vs target: mean {1000.0 * sum(sag) / len(sag):.1f} mm, max {1000.0 * max(sag):.1f} mm")
        f, a = dominant_frequency(ys, dt)
        if f:
            print(f"  pelvis bounce: dominant {f:.2f} Hz, amplitude {1000.0 * a:.1f} mm "
                  f"({'suspicious' if a > 0.004 and f > 1.5 else 'ok'})")
        vy = [abs(c["hips_v"][1]) for _, c in samples]
        print(f"  |pelvis vY|: mean {sum(vy) / len(vy):.3f} m/s, max {max(vy):.3f} m/s")
        errs = [c["worst_err"] for _, c in samples]
        print(f"  worst body error: mean {sum(errs) / len(errs):.1f} deg, max {max(errs):.1f} deg")
        spikes = sorted(samples, key=lambda s: -s[1]["worst_err"])[: args.spikes]
        print("  top error samples: " + "; ".join(f"t={t:.2f} {c['worst_body']} {c['worst_err']:.0f} deg ({c['state']})" for t, c in spikes))
        low = min(samples, key=lambda s: s[1]["lowest_y"])
        print(f"  lowest body point: {low[1]['lowest_y']:.3f} ({low[1]['lowest_body']} at t={low[0]:.2f})"
              + ("  <-- BELOW GROUND (y<0)" if low[1]["lowest_y"] < 0 else ""))
        bal = [c["balance"] for _, c in samples]
        print(f"  balance ratio: mean {sum(bal) / len(bal):.2f}, max {max(bal):.2f}")
        cmds = [(c.get("root_cmd"), c.get("root_limit")) for _, c in samples if c.get("root_cmd") is not None]
        if cmds:
            print(f"  root motor: mean cmd {sum(c for c, _ in cmds) / len(cmds):.2f} rad/s, max {max(c for c, _ in cmds):.2f}; limit {cmds[0][1]}")
        po = [c["pelvis_offset"] for _, c in samples if c.get("pelvis_offset") is not None]
        if po:
            print(f"  foot-IK pelvis offset: mean {1000.0 * sum(po) / len(po):.1f} mm, min {1000.0 * min(po):.1f} mm")
    return 0


if __name__ == "__main__":
    sys.exit(main())
