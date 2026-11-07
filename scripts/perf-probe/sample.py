#!/usr/bin/env python3
"""Samples the Stackbar process tree: CPU (from cputime deltas), RSS, spawns.
usage: sample.py <app pid> <warmup s> <window s> <outdir>"""
import json, os, re, subprocess, sys, time, collections

pid0, warm, window, out = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
os.makedirs(out, exist_ok=True)

def cpu_s(t):  # [dd-]hh:mm:ss.ss or mm:ss.ss
    days = 0
    if "-" in t: d, t = t.split("-"); days = int(d)
    p = [float(x) for x in t.split(":")]
    while len(p) < 3: p.insert(0, 0.0)
    return days * 86400 + p[0] * 3600 + p[1] * 60 + p[2]

def snap():
    r = subprocess.run(["ps", "-axo", "pid=,ppid=,rss=,cputime=,lstart=,command="], capture_output=True, text=True).stdout
    rows = {}
    for line in r.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\w+ \w+\s+\d+ [\d:]+ \d+)\s+(.*)", line)
        if m:
            pid, ppid, rss, cpu, ls, cmd = m.groups()
            rows[int(pid)] = dict(pid=int(pid), ppid=int(ppid), rss_kb=int(rss), cpu=cpu_s(cpu), start=ls, cmd=cmd)
    return rows

def tree(rows):
    keep = {pid0} if pid0 in rows else set()
    changed = True
    while changed:
        changed = False
        for p in rows.values():
            if p["ppid"] in keep and p["pid"] not in keep: keep.add(p["pid"]); changed = True
    return keep

def name(cmd):
    a = cmd.split(" ")[0]
    b = os.path.basename(a)
    if "Stackbar.app/Contents/MacOS/Stackbar" in cmd and " " not in cmd.strip(): return "Stackbar(app)"
    return b if len(b) < 60 else b[:60]

seen = {}          # (pid,start) -> record, all processes in tree ever seen (fast 1 s scan)
t_end = time.time() + warm + window
t_win = time.time() + warm
samples = []       # every 10 s
next10 = 0
first = last = None
while time.time() < t_end:
    now = time.time()
    rows = snap()
    keep = tree(rows)
    for pid in keep:
        p = rows[pid]
        seen.setdefault((pid, p["start"]), dict(p, first_seen=now))
    if now >= t_win and now >= next10:
        next10 = now + 10
        s = dict(t=now - t_win, procs={})
        for pid in keep:
            p = rows[pid]
            s["procs"][pid] = dict(name=name(p["cmd"]), cmd=p["cmd"][:200], rss_kb=p["rss_kb"], cpu=p["cpu"])
        s["all_procs"] = len(rows)
        samples.append(s)
    time.sleep(1)

json.dump(dict(samples=samples, seen=[dict(v, key=str(k)) for k, v in seen.items()]), open(f"{out}/samples.json", "w"))

# --- analysis
lines = []
def P(x=""): lines.append(x); print(x)
if len(samples) < 2:
    P("not enough samples"); sys.exit(0)
a, b = samples[0], samples[-1]
dt = b["t"] - a["t"]
P(f"### Idle window {dt:.0f} s, {len(samples)} samples (after {warm} s warm-up)")
P()
P("| process | pid | CPU % avg | RSS start MB | RSS end MB | RSS max MB | growth MB |")
P("|---|---|---|---|---|---|---|")
tot_cpu = tot_s = tot_e = 0
rows_out = []
for pid, pe in b["procs"].items():
    ps = a["procs"].get(pid)
    if not ps: continue
    cpu = (pe["cpu"] - ps["cpu"]) / dt * 100
    mx = max(s["procs"][pid]["rss_kb"] for s in samples if pid in s["procs"]) / 1024
    rows_out.append((cpu, pe["name"], pid, ps["rss_kb"] / 1024, pe["rss_kb"] / 1024, mx))
    tot_cpu += cpu; tot_s += ps["rss_kb"] / 1024; tot_e += pe["rss_kb"] / 1024
for cpu, n, pid, rs, re_, mx in sorted(rows_out, reverse=True):
    P(f"| {n} | {pid} | {cpu:.2f} | {rs:.1f} | {re_:.1f} | {mx:.1f} | {re_ - rs:+.1f} |")
P(f"| **total ({len(rows_out)} procs)** | | **{tot_cpu:.2f}** | **{tot_s:.1f}** | **{tot_e:.1f}** | | **{tot_e - tot_s:+.1f}** |")
P()
# spawned children seen (by 1 s scan) after window start
spawned = collections.Counter()
for v in seen.values():
    if v["first_seen"] >= t_win - 1 and v["pid"] != pid0:
        spawned[(name(v["cmd"]), " ".join(v["cmd"].split()[:3])[:90])] += 1
P(f"### Processes spawned in the tree during the window, seen by a 1 s scan (short-lived ones can be missed): {sum(spawned.values())}")
P()
P("| count | process | command start |")
P("|---|---|---|")
for (n, c), k in spawned.most_common(25):
    P(f"| {k} | {n} | `{c}` |")
open(f"{out}/summary.md", "w").write("\n".join(lines) + "\n")
