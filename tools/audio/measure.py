"""Measures audio files with ffmpeg's ebur128 filter (EBU R128 / ITU-R BS.1770) and prints a
Markdown table: duration, integrated loudness, max short-term, max momentary, true peak.

Usage: measure.py FILE [FILE ...]
"""
from __future__ import annotations

import re
import subprocess
import sys

FRAME = re.compile(r"t:\s*([\d.]+).*?M:\s*(-?[\d.]+|-inf)\s+S:\s*(-?[\d.]+|-inf)")


def ebur128(path: str) -> dict:
    proc = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-v", "verbose", "-i", path, "-af",
         "ebur128=peak=true:framelog=verbose", "-f", "null", "-"],
        capture_output=True, text=True, check=True)
    log = proc.stderr
    t_max, m_max, s_max = 0.0, -120.0, -120.0
    for m in FRAME.finditer(log):
        t_max = max(t_max, float(m.group(1)))
        if m.group(2) != "-inf":
            m_max = max(m_max, float(m.group(2)))
        if m.group(3) != "-inf":
            s_max = max(s_max, float(m.group(3)))
    summary = log[log.rfind("Summary:"):]
    i = float(re.search(r"I:\s*(-?[\d.]+) LUFS", summary).group(1))
    tp = float(re.search(r"Peak:\s*(-?[\d.]+|-inf) dBFS", summary).group(1))
    dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", log)
    seconds = (int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3))
               if dur else t_max)
    return {"dur": seconds, "I": i, "S": s_max, "M": m_max, "TP": tp}


def main(paths: list[str]) -> int:
    print("| file | dur (s) | I (LUFS) | S max (LUFS) | M max (LUFS) | true peak (dBTP) |")
    print("|---|---:|---:|---:|---:|---:|")
    worst = -120.0
    for p in paths:
        r = ebur128(p)
        worst = max(worst, r["TP"])
        name = p.rsplit("/", 1)[-1]
        s_max = "n/a (< 3 s)" if r["S"] <= -119.0 else f"{r['S']:.1f}"
        print(f"| `{name}` | {r['dur']:.2f} | {r['I']:.1f} | {s_max} | {r['M']:.1f} | "
              f"{r['TP']:.1f} |")
    print(f"\nmax true peak: {worst:.1f} dBTP ({'OK' if worst <= -1.0 else 'OVER -1 dBTP'})")
    return 0 if worst <= -1.0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
