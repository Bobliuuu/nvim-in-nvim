#!/usr/bin/env python3
"""End-to-end: real `nvim -u ./init.lua` in a pty, driven with raw terminal bytes.

Story (spec section 8): A -> B -> C, edit C's config inside B with OUR editor, save with OUR :w,
reload C, observe the new behaviour, verify isolation, then go one level deeper (D).
"""
import os, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from pty_driver import Nvim

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
results = []


def check(name, cond, detail=""):
    results.append(cond)
    print(("  PASS " if cond else "  FAIL ") + name + (f"   [{detail}]" if (detail and not cond) else ""))


def project():
    d = tempfile.mkdtemp(prefix="rvproj")
    shutil.copytree(os.path.join(REPO, "configs"), os.path.join(d, "configs"))
    shutil.copytree(os.path.join(REPO, "examples"), os.path.join(d, "examples"))
    return d


def read(p):
    return open(p).read()


def main():
    proj = project()
    nv = Nvim(os.path.join(REPO, "init.lua"), env={"RECURSIVE_VIM_ROOT": proj})
    shots = {}
    try:
        print("Step 1+2: host Neovim loads init.lua, Editor A runs config A")
        base_procs = nv.descendants()
        a, s = nv.focused()
        check("host booted, exactly one logical editor (A)", len(s["editors"]) == 1 and a["name"] == "A")
        check("A executed its config (number=true, 2 maps, Hello cmd)",
              a["opts"]["number"] is True and a["win_number"] is True and sorted(a["maps"]["n"]) == ["<leader>n", "Q"] and a["cmds"] == ["Hello"], str(a["maps"]))
        nv.keys("Q")
        a, _ = nv.focused(); check("A: Q -> 'Editor A'", a["message"] == "Editor A", a["message"])
        nv.keys("jA!<Esc>")
        a, _ = nv.focused(); check("A: real typing edits text (jA!<Esc>)", a["lines"][1].endswith("Lua editor,!") and a["mode"] == "n", str(a["lines"]))
        nv.keys("ix<BS><Left><Right><Esc>")
        nv.keys(":w<CR>")
        check("A: :w wrote the real file", "editor,!" in read(os.path.join(proj, "examples/hello.txt")))
        nv.keys("ddu")
        a, _ = nv.focused(); check("A: dd then u (undo) restores line", a["lines"][0].startswith("Hello") and len(a["lines"]) == 5, str(a["lines"]))
        shots["A"] = nv.text()

        print("Step 3: spawn B from A (no new nvim process)")
        nv.keys("<Space>n")
        b, s = nv.focused()
        check("B created by our runtime, child of A, depth 1", b["name"] == "B" and b["parent"] == a["id"] and b["depth"] == 1)
        check("B has line numbers disabled, A still enabled", b["win_number"] is False and s["editors"][str(a["id"])]["win_number"] is True)
        nv.keys("Q")
        b, _ = nv.focused(); check("B: Q -> 'Editor B'", b["message"] == "Editor B", b["message"])
        nv.keys("ihello B<Esc>")
        b, s = nv.focused()
        check("B edits its own buffer; A's buffer untouched",
              b["lines"] == ["hello B"] and s["editors"][str(a["id"])]["lines"][0].startswith("Hello from Editor A"), str(b["lines"]))
        check("no extra OS processes launched for nesting (same processes as at boot)", nv.descendants() == base_procs, f"{base_procs} -> {nv.descendants()}")

        print("Step 4: spawn C from B")
        nv.keys("<Space>n")
        c, s = nv.focused()
        check("C created, depth 2, numbers on", c["name"] == "C" and c["depth"] == 2 and c["win_number"] is True)
        nv.keys("Q")
        c, _ = nv.focused(); check("C: Q -> 'Editor C'", c["message"] == "Editor C", c["message"])
        nv.keys("X")
        c, _ = nv.focused(); check("C: X inserts text via our implementation", c["lines"][0] == "hello from level 3", str(c["lines"]))
        s = nv.state()
        check("A and B unaffected by C (options/maps/buffers)",
              s["editors"][str(a["id"])]["win_number"] is True and s["editors"][str(b["id"])]["win_number"] is False
              and s["editors"][str(b["id"])]["lines"] == ["hello B"])
        shots["ABC"] = nv.text()

        print("Step 5: edit C's config INSIDE B with our editor, save, reload C")
        nv.keys(":parent<CR>")
        f, _ = nv.focused(); check("focus returned to B", f["name"] == "B")
        nv.keys(":e! configs/c/init.lua<CR>")  # B has an unsaved scratch buffer; ! = abandon it
        b, _ = nv.focused()
        idx = next(i for i, l in enumerate(b["lines"]) if 'echo("Editor C")' in l)
        nv.keys(f":{idx + 1}<CR>/\")<CR>")
        nv.keys("i was reconfigured<Esc>")
        b, _ = nv.focused()
        check("B's buffer now has the new string", 'echo("Editor C was reconfigured")' in b["lines"][idx], b["lines"][idx])
        check("not on disk before :w", "was reconfigured" not in read(os.path.join(proj, "configs/c/init.lua")))
        nv.keys(":w<CR>")
        check("B's :w saved configs/c/init.lua", "Editor C was reconfigured" in read(os.path.join(proj, "configs/c/init.lua")))
        shots["edit"] = nv.text()
        nv.keys(":child<CR>")
        c, _ = nv.focused(); check("focus routed to C", c["name"] == "C")
        nv.keys("Q")
        c, _ = nv.focused(); check("C still runs OLD config until reloaded", c["message"] == "Editor C", c["message"])
        nv.keys(":reload<CR>Q")
        c, _ = nv.focused(); check("C after :reload -> 'Editor C was reconfigured'", c["message"] == "Editor C was reconfigured", c["message"])
        shots["reconfigured"] = nv.text()

        print("Step 6: verify isolation, return to A")
        nv.keys(":close<CR>")
        f, _ = nv.focused(); check("C closed, focus restored to B", f["name"] == "B")
        nv.keys(":close<CR>")
        a2, s = nv.focused()
        check("focus restored to A; B and C gone", a2["name"] == "A" and len(s["editors"]) == 1)
        for k in ("maps", "cmds", "opts", "config", "bufnr", "depth"):
            check(f"A.{k} unchanged", a2[k] == a[k], f"{a2[k]} vs {a[k]}")
        check("A's text unchanged by B/C", a2["lines"] == a["lines"])
        nv.keys("Q")
        a2, _ = nv.focused(); check("A: Q still 'Editor A'", a2["message"] == "Editor A")
        nv.keys(":Hello<CR>")
        a2, _ = nv.focused(); check("A: custom :Hello works", a2["message"].startswith("Hello from nested Neovim"), a2["message"])

        print("Step 7: 4th level via the same mechanism")
        nv.keys("<Space>n<Space>n<Space>n")
        d, s = nv.focused()
        check("A->B->C->D, same constructor", d["name"] == "D" and d["depth"] == 3 and len(s["editors"]) == 4)
        nv.keys("Q")
        d, _ = nv.focused(); check("D: Q -> 'Editor D (depth 3)'", d["message"] == "Editor D (depth 3)", d["message"])
        check("D relativenumber on, others off", s["editors"][str(a2["id"])]["opts"]["relativenumber"] is False and d["opts"]["relativenumber"] is True)
        shots["ABCD"] = nv.text()
        check("still no extra OS processes at depth 4", nv.descendants() == base_procs, f"{base_procs} -> {nv.descendants()}")

        print("Terminal-level input: special keys, unicode, paste, fast input, no native leaks")
        nv.keys(":q!<CR>:q!<CR>:q!<CR>")
        a2, s = nv.focused(); check("back at A after closing D,C,B", a2["name"] == "A" and len(s["editors"]) == 1)
        host_before = nv.lua("vim.api.nvim_buf_get_lines(vim.api.nvim_list_bufs()[1],0,-1,false)")
        nv.keys("ggdG")
        nv.keys("i日本語 café 😀<Esc>")
        a2, _ = nv.focused(); check("unicode typed through a real terminal", a2["lines"] == ["日本語 café 😀"], str(a2["lines"]))
        nv.keys("o<Up><Down><Left><Right><Home><End>zz<Esc>")
        a2, _ = nv.focused(); check("arrow/home/end escape sequences", a2["lines"][-1] == "zz", str(a2["lines"]))
        nv.keys("ggdGi")
        nv.paste("pasted line 1\npasted line 2")
        nv.keys("<Esc>")
        a2, _ = nv.focused(); check("bracketed paste in insert mode", a2["lines"] == ["pasted line 1", "pasted line 2"], str(a2["lines"]))
        nv.paste("dd")
        a2, _ = nv.focused(); check("paste in normal mode = typed keys (our dd)", a2["lines"] == ["pasted line 1"], str(a2["lines"]))
        nv.keys("ggdG")
        long = "".join(chr(97 + (i * 7) % 26) for i in range(600))
        nv.keys("i" + long + "<Esc>")
        a2, _ = nv.focused(); check("600 chars in one write keep order", a2["lines"] == [long])
        nv.keys("ggdGZZ:q<BS>zq<Esc>Y&gcgcX<C-r><Esc>")
        a2, _ = nv.focused()
        nm = nv.lua("vim.api.nvim_get_mode().mode")
        check("native-only commands (ZZ Y & gc X ...) don't leak, host stays in Normal", nm == "n" and "".join(a2["lines"]) == "", f"{nm} {a2['lines']}")
        check("the host's own buffer was never edited",
              nv.lua("vim.api.nvim_buf_get_lines(vim.api.nvim_list_bufs()[1],0,-1,false)") == host_before)
        nv.raw("\x1c"); nv.raw("\x1c")
        check("emergency escape hatch toggles native passthrough", nv.lua("require('recursive_vim.input').passthrough") is True)
        nv.raw("\x1c"); nv.raw("\x1c")
        check("...and back", nv.lua("require('recursive_vim.input').passthrough") is False)
        nv.keys(":q<CR>")
        a2, _ = nv.focused()
        check(":q refuses to quit with unsaved changes (E37)", "E37" in (a2["message"] or "") and a2["message_err"] is True, str(a2["message"]))
        nv.keys(":q!<CR>")
        check(":q! on the root quits the host Neovim process", nv.wait_exit())
    finally:
        out = os.path.join(REPO, "docs", "screens")
        os.makedirs(out, exist_ok=True)
        for k, v in shots.items():
            open(os.path.join(out, f"{k}.txt"), "w").write(v + "\n")
        nv.close()
        shutil.rmtree(proj, ignore_errors=True)
    bad = results.count(False)
    print(f"\n{len(results) - bad}/{len(results)} e2e checks passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
