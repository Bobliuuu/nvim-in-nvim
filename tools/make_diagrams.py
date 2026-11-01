#!/usr/bin/env python3
"""Generates the README diagrams (docs/img/*.svg). Plain SVG, no dependencies."""
import html, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "img")
BG, PANEL, LINE, FG, DIM = "#1a1b26", "#24283b", "#414868", "#c0caf5", "#7982a9"
C = {"blue": "#7aa2f7", "purple": "#bb9af7", "green": "#9ece6a", "orange": "#e0af68", "red": "#f7768e", "cyan": "#7dcfff"}


class Svg:
    def __init__(self, w, h, title):
        self.w, self.h, self.o = w, h, []
        self.o.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
                      f'font-family="ui-sans-serif,-apple-system,Segoe UI,Helvetica,Arial,sans-serif" font-size="14">'
                      f'<title>{html.escape(title)}</title>'
                      '<defs>' + "".join(
                          f'<marker id="a-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
                          f'<path d="M0,0 L10,5 L0,10 z" fill="{v}"/></marker>' for k, v in {**C, "dim": DIM}.items()) +
                      '</defs>'
                      f'<rect width="100%" height="100%" rx="12" fill="{BG}"/>')

    def box(self, x, y, w, h, color, title, lines=(), mono=False, fill=PANEL, dash=False):
        d = ' stroke-dasharray="6 4"' if dash else ""
        self.o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{fill}" stroke="{color}" stroke-width="1.6"{d}/>')
        self.o.append(f'<text x="{x + 14}" y="{y + 24}" fill="{color}" font-weight="700" font-size="14.5">{html.escape(title)}</text>')
        for i, l in enumerate(lines):
            fam = ' font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="12.5"' if mono else ' font-size="13"'
            self.o.append(f'<text x="{x + 14}" y="{y + 46 + i * 19}" fill="{FG}"{fam}>{html.escape(l)}</text>')

    def text(self, x, y, s, color=FG, size=13, anchor="start", weight="400", mono=False):
        fam = ' font-family="ui-monospace,SFMono-Regular,Menlo,monospace"' if mono else ""
        self.o.append(f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" text-anchor="{anchor}" font-weight="{weight}"{fam}>{html.escape(s)}</text>')

    def arrow(self, x1, y1, x2, y2, color="dim", label=None, dash=False, lx=None, ly=None):
        col = DIM if color == "dim" else C[color]
        d = ' stroke-dasharray="5 4"' if dash else ""
        self.o.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="1.8"{d} marker-end="url(#a-{color})"/>')
        if label:
            self.text(lx if lx is not None else (x1 + x2) / 2 + 8, ly if ly is not None else (y1 + y2) / 2 - 4, label, col, 12)

    def save(self, name):
        with open(os.path.join(OUT, name), "w") as f:
            f.write("\n".join(self.o) + "\n</svg>\n")
        print("wrote", name)


def architecture():
    s = Svg(980, 700, "Architecture of nvim-in-nvim")
    s.text(490, 34, "One real Neovim process. Everything inside the dashed box is Lua we wrote.", FG, 15, "middle", "700")
    s.box(20, 56, 940, 624, DIM, "REAL NEOVIM (public API only)", fill="none", dash=True)
    s.box(40, 92, 280, 74, C["cyan"], "Terminal", ["bytes → keys (xterm, UTF-8, paste)"])
    s.box(360, 92, 580, 74, C["red"], "input.lua  ·  the ONLY physical input layer",
          ["vim.on_key → returns \"\" (native editing never sees the key)", "vim.paste override · emergency <C-\\><C-\\> and <C-c>x3"], mono=True)
    s.arrow(320, 129, 360, 129, "cyan")
    s.box(40, 196, 900, 66, C["orange"], "instances.lua  ·  registry + focus",
          ["Instances.focused → one pointer. Shows ancestors, hides the rest. close(subtree) restores the parent."])
    s.arrow(650, 166, 650, 196, "red", "dispatch(key)", lx=662, ly=186)

    # three editor columns
    cols = [("Editor A", "depth 0", C["blue"], 40), ("Editor B", "depth 1", C["purple"], 350), ("Editor C …", "depth 2…", C["green"], 660)]
    for name, dep, col, x in cols:
        s.box(x, 292, 280, 178, col, f"{name}  ({dep})", [
            "mode · cursor · pending keys",
            "registers · undo stacks",
            "buffers   (owned, guarded)",
            "scope: opts · maps · cmds · events",
            "private Lua env + virtual `vim`",
            "float window · parent · children"], mono=True)
    s.arrow(180, 262, 180, 292, "orange")
    s.arrow(490, 262, 490, 292, "orange", dash=True)
    s.arrow(800, 262, 800, 292, "orange", dash=True)
    s.arrow(320, 400, 350, 400, "purple", "spawn", dash=True, lx=322, ly=392)
    s.arrow(630, 400, 660, 400, "green", "spawn", dash=True, lx=632, ly=392)
    s.text(490, 494, "Every editor is built by the same Editor.new(); spawn = new(parent = self). No depth branches.", DIM, 12.5, "middle")

    # shared engine
    s.box(40, 530, 440, 124, C["blue"], "Editing engine (shared code, per-editor state)", [
        "modes.lua      normal/insert/cmdline/visual parser",
        "motions.lua    pure: (ctx,pos,count) → pos, kind",
        "operators.lua  range → edit   (d c y)",
        "commands.lua   :w :q :e :set :source :lua :spawn"], mono=True)
    s.box(500, 530, 440, 124, C["green"], "Host adapters", [
        "buffer.lua   owned scratch buffers, undo snapshots",
        "config.lua   load(src,…,env), scopes, virtual vim",
        "render.lua   float, winbar, footer, per-window opts",
        "nvim_buf_set_text / nvim_open_win / set_option_value"], mono=True)
    s.arrow(180, 470, 180, 530, "blue", dash=True)
    s.arrow(800, 470, 800, 530, "green", dash=True)
    s.save("architecture.svg")


def keypress():
    s = Svg(980, 420, "Life of one keypress")
    s.text(490, 32, "Life of a keypress: `d` `w` composed, not hardcoded", FG, 15, "middle", "700")
    steps = [
        ("1  terminal", "sends \"d\"", C["cyan"]),
        ("2  vim.on_key", "returns \"\" →\nnative d never runs", C["red"]),
        ("3  input.lua", "normalise key,\nroute to focused\neditor", C["orange"]),
        ("4  mapping layer", "per-editor maps,\nprefix wait / timeout", C["purple"]),
        ("5  modes.lua", "state = {op = d}\nwaiting for motion", C["blue"]),
    ]
    x = 20
    for t, b, col in steps:
        s.box(x, 60, 176, 112, col, t, b.split("\n"))
        if x > 20: s.arrow(x - 20, 116, x, 116, "dim")
        x += 192
    s.text(490, 205, "…then the user presses `w`:", DIM, 13, "middle")
    steps2 = [
        ("6  motions.w", "ctx, row, col, count\n→ target (r, c)\nkind = exclusive", C["green"]),
        ("7  range", "start..target\nbecomes a RANGE\n{sr,sc,er,ec}", C["blue"]),
        ("8  operators.d", "yank range into\nregisters, then delete", C["orange"]),
        ("9  Editor:replace", "undo checkpoint,\nBuf:set_text(editor,…)\nowner check", C["purple"]),
        ("10 render", "cursor · winbar ·\nfooter · selection", C["cyan"]),
    ]
    x = 20
    for t, b, col in steps2:
        s.box(x, 228, 176, 112, col, t, b.split("\n"))
        if x > 20: s.arrow(x - 20, 284, x, 284, "dim")
        x += 192
    s.text(490, 376, "`d` knows nothing about `w`. `dw`, `d$`, `d2w`, `cw`, `yj`, `dG` all come from one operator × one motion.", FG, 13, "middle")
    s.text(490, 400, "x = dl · D = d$ · C = c$ · s = cl · S = cc · Y = yy  (key expansions, not special cases)", DIM, 12.5, "middle", mono=True)
    s.save("keypress-flow.svg")


def scopes():
    s = Svg(980, 560, "Per-editor configuration scopes and transactional reload")
    s.text(490, 32, "Why configs can't contaminate each other", FG, 15, "middle", "700")
    for i, (n, col, x, src) in enumerate([
            ("Editor A", C["blue"], 20, ["number = true", "Q → \"Editor A\"", "<leader>n → spawn B"]),
            ("Editor B", C["purple"], 340, ["number = false", "Q → \"Editor B\"", "<leader>n → spawn C"]),
            ("Editor C", C["green"], 660, ["number = true", "Q → \"Editor C\"", "X → insert_text(…)"])]):
        s.box(x, 56, 300, 100, col, f"configs/{n[-1].lower()}/init.lua", src, mono=True)
        s.arrow(x + 150, 156, x + 150, 186, col.replace("#", "") and ("blue" if i == 0 else "purple" if i == 1 else "green"), "load(src, name, \"t\", env)", lx=x + 160, ly=176)
        s.box(x, 190, 300, 138, col, f"env {n[-1]}  (private Lua environment)", [
            "vim  = virtual vim → scope " + n[-1],
            "string, table, math, pcall …",
            "NOT in env: host `vim`, package,",
            "debug, dofile, vim.fn, vim.uv"], mono=True)
        s.arrow(x + 150, 328, x + 150, 358, ("blue" if i == 0 else "purple" if i == 1 else "green"))
        s.box(x, 362, 300, 100, col, f"scope {n[-1]}", ["opt · g · maps · cmds · autocmds"], mono=True)
        s.text(x + 150, 482, "→ float window " + n[-1] + ": window-local", DIM, 12.5, "middle", mono=True)
        s.text(x + 150, 500, "options (number, tabstop, …)", DIM, 12.5, "middle", mono=True)
    s.box(20, 516, 940, 36, C["orange"], "Reload  =  run file against a STAGING scope → commit only on success → old scope kept on error", [])
    s.save("config-scopes.svg")


def reload_flow():
    s = Svg(980, 330, "Config reload transaction")
    s.text(490, 30, "Config reload is a transaction", FG, 15, "middle", "700")
    s.box(20, 56, 200, 90, C["blue"], "editor:reload_config()", ["read configs/c/init.lua"], mono=True)
    s.box(260, 56, 220, 90, C["purple"], "Config.build", ["new staging scope", "run file in new env"], mono=True)
    s.arrow(220, 100, 260, 100, "dim")
    s.box(520, 30, 200, 70, C["red"], "error / syntax error", ["keep OLD scope", "report in THIS editor"], mono=True)
    s.box(520, 118, 200, 70, C["green"], "ok", ["swap scope atomically", "refresh_options()"], mono=True)
    s.arrow(480, 80, 520, 66, "red"); s.arrow(480, 120, 520, 150, "green")
    s.box(760, 56, 200, 132, C["orange"], "untouched", ["buffers + undo", "cursor, registers", "children, parent", "OTHER editors"], mono=True)
    s.arrow(720, 153, 760, 130, "dim", dash=True)
    s.box(20, 216, 940, 96, PANEL, "Guarantees (each one is a test)", [
        "No duplicated mappings (scope replaced wholesale) · removed options revert to defaults",
        "Half-applied configs are discarded: `vim.opt.number = true; error('late')` leaves number unchanged",
        "A broken child config never takes down its parent"])
    s.save("reload-transaction.svg")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    architecture(); keypress(); scopes(); reload_flow()
