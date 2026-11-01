#!/usr/bin/env python3
"""End-to-end for configs/blog (a port of the 'Neovim isn't actually that scary' config) in a REAL terminal."""
import os, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from pty_driver import Nvim

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
results = []


def check(name, cond, detail=""):
    results.append(cond)
    print(("  PASS " if cond else "  FAIL ") + name + (f"   [{detail}]" if (detail and not cond) else ""))


def main():
    proj = tempfile.mkdtemp(prefix="rvblog")
    for d in ("configs", "examples"): shutil.copytree(os.path.join(REPO, d), os.path.join(proj, d))
    open(os.path.join(proj, "notes.txt"), "w").write("alpha  \nTODO: ship it\nomega\n")
    nv = Nvim(os.path.join(REPO, "init.lua"), env={"RECURSIVE_VIM_ROOT": proj, "RECURSIVE_VIM_CONFIG": "configs/blog/init.lua"})
    try:
        base = nv.descendants()
        e, s = nv.focused()
        check("blog config loaded: start screen shown", (e["path"] or "").endswith("examples/welcome.txt"), str(e["path"]))
        o = e["opts"]
        check("options from the post (rnu, tabstop=2, scrolloff=8, timeoutlen=300, nowrap)",
              o["relativenumber"] and o["tabstop"] == 2 and o["scrolloff"] == 8 and o["timeoutlen"] == 300 and not o["wrap"], str(o))

        nv.keys(" e")
        t, s = nv.focused()
        check("<Space>e spawns the file-explorer LAYER (own config, number off)", t["name"] == "tree" and t["opts"]["number"] is False and t["depth"] == 1, str(t["name"]))
        check("explorer lists the project", "notes.txt" in t["lines"] and "configs/" in t["lines"], str(t["lines"]))
        nv.keys(f":{t['lines'].index('notes.txt') + 1}<CR><CR>")
        e, s = nv.focused()
        check("<CR> opened notes.txt in the layer above and closed the tree", e["name"] == "A" and e["lines"][0] == "alpha  " and len(s["editors"]) == 1, str(e["lines"]))

        nv.keys("A!<Esc>")
        check("autosave on InsertLeave: file on disk updated by a real <Esc>", open(os.path.join(proj, "notes.txt")).read().startswith("alpha  !"))
        nv.keys("A   <Esc>")
        check("(setup) line now has trailing spaces", nv.focused()[0]["lines"][0] == "alpha  !   ", str(nv.focused()[0]["lines"]))
        nv.keys(" lf")
        check("<Space>lf :Format strips trailing whitespace", nv.focused()[0]["lines"][0] == "alpha  !", str(nv.focused()[0]["lines"]))
        nv.keys("gg]t")
        e, _ = nv.focused(); check("]t jumps to the TODO line", e["row"] == 1, str(e["row"]))

        nv.keys(" sv")
        l1, s = nv.focused()
        check("<Space>sv: a new layer running the same config", l1["depth"] == 1 and l1["config"] == "configs/blog/init.lua" and l1["opts"]["scrolloff"] == 8)
        nv.keys(" sv")
        l2, s = nv.focused()
        check("layers nest (depth 2)", l2["depth"] == 2 and len(s["editors"]) == 3)
        nv.keys("<C-k>")
        f, _ = nv.focused(); check("<C-k> (raw 0x0b) focuses the layer above", f["id"] == l1["id"])
        nv.keys("<C-j>")
        f, _ = nv.focused(); check("<C-j> (raw 0x0a) focuses the layer below", f["id"] == l2["id"])

        # config inside config inside config: edit the blog config from a layer, autosave, reload
        nv.keys(":e! configs/blog/init.lua<CR>")
        f, _ = nv.focused()
        idx = f["lines"].index("vim.opt.scrolloff = 8")
        nv.keys(f":{idx + 1}<CR>$x" + "a20<Esc>")
        check("autosave wrote the edited blog config to disk from inside a layer",
              "scrolloff = 20" in open(os.path.join(proj, "configs/blog/init.lua")).read())
        nv.keys(":reload<CR>")
        f, s = nv.focused()
        check("the layer reloaded it (scrolloff=20) while the layer below still has 8",
              f["opts"]["scrolloff"] == 20 and s["editors"][str(l1["id"])]["opts"]["scrolloff"] == 8, str(f["opts"]["scrolloff"]))
        nv.keys(" sc")
        f, s = nv.focused(); check("<Space>sc closes the layer", f["id"] == l1["id"] and len(s["editors"]) == 2)
        check("still one real Neovim (same OS processes as at boot)", nv.descendants() == base)
    finally:
        nv.close()
        shutil.rmtree(proj, ignore_errors=True)
    bad = results.count(False)
    print(f"\n{len(results) - bad}/{len(results)} blog e2e checks passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
