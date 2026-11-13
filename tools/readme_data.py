#!/usr/bin/env python3
"""results/tests.json (tools/record_tests.py) + source line counts -> results/derived/readme_data.json."""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
t = json.load(open(os.path.join(ROOT, "results/tests.json")))
d = os.path.join(ROOT, "lua/recursive_vim")
mods = sorted(({"module": f[:-4], "lines": len(open(os.path.join(d, f)).read().splitlines())} for f in os.listdir(d) if f.endswith(".lua")),
              key=lambda m: -m["lines"])
t["nvim_mm"] = float(".".join(t["nvim"].lstrip("v").split(".")[:2]))
t["modules"] = mods
t["tests_rows"] = [
    {"layer": "Lua specs (headless nvim)", "passed": t["lua_specs"]["passed"], "of": t["lua_specs"]["passed"] + t["lua_specs"]["failed"]},
    {"layer": "End-to-end (real TUI in a pty)", "passed": t["e2e_pty"]["passed"], "of": t["e2e_pty"]["of"]},
    {"layer": "End-to-end (blog config layers)", "passed": t["e2e_blog"]["passed"], "of": t["e2e_blog"]["of"]},
    {"layer": "Phase-0 input research", "passed": t["research"]["passed"], "of": t["research"]["of"]},
]
t["tests_all"] = {"passed": sum(r["passed"] for r in t["tests_rows"]), "of": sum(r["of"] for r in t["tests_rows"])}
os.makedirs(os.path.join(ROOT, "results/derived"), exist_ok=True)
json.dump(t, open(os.path.join(ROOT, "results/derived/readme_data.json"), "w"), indent=1)
print(json.dumps(t)[:300])
