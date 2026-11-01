#!/usr/bin/env python3
"""Drive the REAL editor in a pty and render the virtual terminal to SVG (used for the README)."""
import html, os, shutil, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))
from pty_driver import Nvim

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG, FG = "#1a1b26", "#c0caf5"
ANSI = {"black": "#15161e", "red": "#f7768e", "green": "#9ece6a", "brown": "#e0af68", "yellow": "#e0af68",
        "blue": "#7aa2f7", "magenta": "#bb9af7", "cyan": "#7dcfff", "white": "#a9b1d6",
        "brightblack": "#414868", "brightred": "#f7768e", "brightgreen": "#9ece6a", "brightbrown": "#e0af68",
        "brightblue": "#7aa2f7", "brightmagenta": "#bb9af7", "brightcyan": "#7dcfff", "brightwhite": "#c0caf5"}


def col(c, default):
    if c == "default": return default
    if c in ANSI: return ANSI[c]
    if len(c) == 6: return "#" + c
    return default


def to_svg(screen, title, rows=None):
    cw, ch, pad = 8.4, 18.0, 16
    rows = rows or screen.lines
    W, H = screen.columns * cw + pad * 2, rows * ch + pad * 2 + 30
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:.0f} {H:.0f}" width="{W:.0f}" height="{H:.0f}" '
           f'font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="14">',
           f'<rect width="100%" height="100%" rx="10" fill="{BG}"/>',
           '<circle cx="22" cy="18" r="6" fill="#f7768e"/><circle cx="42" cy="18" r="6" fill="#e0af68"/><circle cx="62" cy="18" r="6" fill="#9ece6a"/>',
           f'<text x="{W/2:.0f}" y="22" text-anchor="middle" fill="#565f89" font-size="12">{html.escape(title)}</text>']
    top = 30 + pad
    for y in range(rows):
        row = screen.buffer[y]
        x = 0
        while x < screen.columns:                       # background runs
            ch0 = row[x]
            b = col(ch0.bg, BG) if not ch0.reverse else col(ch0.fg, FG)
            x2 = x
            while x2 < screen.columns and (col(row[x2].bg, BG) if not row[x2].reverse else col(row[x2].fg, FG)) == b: x2 += 1
            if b != BG:
                out.append(f'<rect x="{pad + x * cw:.1f}" y="{top + y * ch:.1f}" width="{(x2 - x) * cw + 0.5:.1f}" height="{ch + 0.5:.1f}" fill="{b}"/>')
            x = x2
        x = 0
        while x < screen.columns:                       # text runs
            c = row[x]
            if c.data == " ":
                x += 1; continue
            fg = col(c.fg, FG) if not c.reverse else col(c.bg, BG)
            x2, txt = x, ""
            while x2 < screen.columns and row[x2].data != " " and (col(row[x2].fg, FG) if not row[x2].reverse else col(row[x2].bg, BG)) == fg and row[x2].bold == c.bold and row[x2].italics == c.italics:
                txt += row[x2].data; x2 += 1
            wt = ' font-weight="bold"' if c.bold else ""
            it = ' font-style="italic"' if c.italics else ""
            out.append(f'<text x="{pad + x * cw:.1f}" y="{top + y * ch + 13:.1f}" fill="{fg}"{wt}{it} textLength="{(x2 - x) * cw:.1f}" lengthAdjust="spacingAndGlyphs" xml:space="preserve">{html.escape(txt)}</text>')
            x = x2
    out.append("</svg>")
    return "\n".join(out)


def boot():
    proj = tempfile.mkdtemp(prefix="rvshot")
    for d in ("configs", "examples"): shutil.copytree(os.path.join(REPO, d), os.path.join(proj, d))
    nv = Nvim(os.path.join(REPO, "init.lua"), env={"RECURSIVE_VIM_ROOT": proj}, rows=36, cols=110)
    return nv, proj


def save(nv, name, title):
    nv.screen.dirty.clear()
    # drop the stray terminal-probe message nvim prints into the pty on startup
    svg = to_svg(nv.screen, title, rows=nv.rows - 1)
    open(os.path.join(REPO, "docs", "img", name), "w").write(svg)
    print("wrote", name)


def modes_shots():
    """Insert / visual / command-line / error screenshots of a single editor."""
    nv, proj = boot()
    try:
        nv.keys(":set cursorline<CR>")
        nv.keys("jjA<CR>- inserted with our own Insert mode<Esc>")
        nv.keys("ggwvee")
        save(nv, "visual.svg", "Visual mode: v + motions, selection drawn by extmarks, d/y/c act on the range")
        nv.keys("<Esc>ggVj")
        nv.keys("<Esc>3jo")
        save(nv, "insert.svg", "Insert mode is a flag in our state machine; the host stays in Normal mode")
        nv.keys("<Esc>")
        nv.keys(":set tabstop=4 | bogus")
        save(nv, "cmdline.svg", "Command-line mode: footer shows the :cmdline being typed")
        nv.keys("<CR>")
        save(nv, "error.svg", "Errors are reported inside the editor that caused them (E492 / E518 style)")
    finally:
        nv.close()
        shutil.rmtree(proj, ignore_errors=True)


def broken_child_shot():
    nv, proj = boot()
    try:
        with open(os.path.join(proj, "configs/b/init.lua"), "w") as f:
            f.write('vim.opt.number = false\nvim.keymap.set("n", "Q", function(\n')
        nv.keys("<Space>n")
        save(nv, "broken-config.svg", "A broken child config: error shown in B's footer; B and A keep working")
        nv.keys("ihi from B, still alive<Esc>")
        nv.keys(":parent<CR>Q")
        save(nv, "broken-config-parent.svg", "Back in A: untouched, its own Q mapping still works")
    finally:
        nv.close()
        shutil.rmtree(proj, ignore_errors=True)


def main():
    modes_shots()
    broken_child_shot()
    nv, proj = boot()
    try:
        nv.keys("jjA <Esc>")
        nv.keys("ggVjy")
        nv.keys("<Esc>Q")
        save(nv, "editor-a.svg", "nvim -u ./init.lua   (Editor A: Lua editor running inside real Neovim)")

        nv.keys("<Space>n")
        nv.keys(":e! configs/c/init.lua<CR>")
        nv.keys("<Space>n")
        nv.keys(":e! configs/d/init.lua<CR>")
        nv.keys("<Space>n")
        nv.keys("ihello from level 4, a Neovim inside a Neovim inside a Neovim inside a Neovim<Esc>Q")
        save(nv, "nested.svg", "A → B → C → D   one real nvim process, four logical editors, four configs")

        nv.keys(":parent<CR>:parent<CR>")           # focus B (editing C's config)
        nv.keys(":e! configs/c/init.lua<CR>")
        nv.keys("/Editor C\")<CR>")
        nv.keys("/\")<CR>")
        nv.keys("i was reconfigured<Esc>:w<CR>")
        save(nv, "reconfigure.svg", "Editor B edits and saves Editor C's init.lua with its own :w")
    finally:
        nv.close()
        shutil.rmtree(proj, ignore_errors=True)


if __name__ == "__main__":
    main()
