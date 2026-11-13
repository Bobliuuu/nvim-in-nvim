#!/usr/bin/env python3
"""Run every test layer and record the pass counts in results/tests.json (source of the README/video numbers)."""
import json, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def run(cmd):
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=1500)
    return p.stdout + p.stderr
res = {}
o = run(["nvim", "--headless", "-u", "NONE", "-l", "tests/run.lua"])
m = re.search(r"(\d+) passed, (\d+) failed", o); res["lua_specs"] = {"passed": int(m[1]), "failed": int(m[2])}
o = run([sys.executable, "tests/e2e_pty.py"])
m = re.search(r"(\d+)/(\d+) e2e checks passed", o); res["e2e_pty"] = {"passed": int(m[1]), "of": int(m[2])}
o = run([sys.executable, "tests/e2e_blog.py"])
m = re.search(r"(\d+)/(\d+) blog e2e checks passed", o); res["e2e_blog"] = {"passed": int(m[1]), "of": int(m[2])}
o = run([sys.executable, "experiments/input_experiments.py"])
m = re.search(r"(\d+)/(\d+) passed", o); res["research"] = {"passed": int(m[1]), "of": int(m[2])}
res["e2e_total"] = {"passed": res["e2e_pty"]["passed"] + res["e2e_blog"]["passed"], "of": res["e2e_pty"]["of"] + res["e2e_blog"]["of"]}
lua = [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(ROOT, "lua")) for f in fs if f.endswith(".lua")]
res["editor_lua_lines"] = sum(len(open(f).read().splitlines()) for f in lua)
res["editor_lua_files"] = len(lua)
res["nvim"] = re.search(r"NVIM (v[\d.]+)", run(["nvim", "--version"]))[1]
json.dump(res, open(os.path.join(ROOT, "results/tests.json"), "w"), indent=1)
print(json.dumps(res))
