# Discoveries

A running log of what turned out to be true (all observed on Neovim 0.12.6, macOS).

## What Neovim actually gives you
* A **buffer** is just an array of lines with an id. A **window** is a viewport onto one buffer with its own *window-local* options. A **float**
  is a window placed at `row/col` (outer corner, border included) with a z-index. We never use native splits: one float per editor.
* **Rendering is free**: line numbers, wrapping, cursorline, syntax (`vim.treesitter.start`), winbar, border titles/footers all come from the host.
  Everything *behavioural* is ours.
* `nvim_buf_set_text` / `nvim_buf_set_lines` change text without going through Vim's edit commands, so "implement editing ourselves" is cleanly possible.

## How `init.lua` runs
`nvim -u ./init.lua` executes the file in the host's LuaJIT state and **does not add its directory to `runtimepath`**, so `require("recursive_vim")`
fails until `package.path` is extended by hand. Everything we call (`vim.api.*`, `vim.on_key`) is the same API a plugin would use.

## Key input
* `vim.on_key(fn)` runs **after mappings, before native processing**; returning `""` really drops the key. See `docs/input-research.md`.
* Easy-to-miss traps: callbacks are *removed on error*; paste bypasses `on_key`; the host cursor clamps in Normal mode; `key` ≠ `typed`;
  stock Neovim has 47 default mappings (some Lua) which collide with upstream issue #36480.
* `<Esc>` is ambiguous at the byte level (`\x1b` + `x` = Alt-x). A real terminal resolves this by timing; our pty tests send `<Esc>` alone.
* Our logical Insert mode is **not** native Insert. The host is in Normal mode forever; "Insert" is a flag in our state machine.

## Why input interception is hard
You are fighting a state machine that is already running. Any key you fail to swallow executes against *your* buffers with Vim semantics, and
several channels bypass the obvious hook: paste, mouse, `<Cmd>` mappings, terminal escape timing, and (in tests) `nvim_input` vs `feedkeys`.

## Modal editing, concretely
Vim's grammar is `["register][count]operator[count](motion|text-object)`. The trick that makes it small:
* **motions are pure functions** `(ctx, row, col, count) -> row, col` plus a *kind* (`exclusive` / `inclusive` / `linewise`);
* **operators are functions of a range**;
* the parser only glues them. `dw`, `d$`, `d2w`, `cw`, `yj`, `d/foo`-style combos fall out of that without enumerating them.
  Even `x`, `D`, `C`, `s`, `S`, `Y` are *key expansions* (`x` = `dl`, `D` = `d$`).
* Quirks Vim hardcodes and we had to as well: `cw` behaves like `ce`; `dw` on the last word of a line must not join lines; `dj` on the last
  line fails; counts multiply (`2d3w` = 6 words); an operator must be allowed to move *past* the last char (`dl` at EOL).
* **Dot-repeat** is almost free if you record the keys of the last change command (including inserted text up to `<Esc>`) and replay them.
* **Undo** here is whole-buffer snapshots, one per command (an insert session = one step). Simple, obviously correct, O(size) per edit.

## Per-instance configuration
Three independent mechanisms make "config inside config" work:
1. **A private environment per config run** (`load(src, name, "t", env)`) so `vim` means *this editor's* `vim`.
2. **A scope object** holding everything a config run defined; reload replaces the whole scope, so nothing can be duplicated or leak.
3. **Display adapters** that translate logical options to *window-local* host options of that editor's float.

## Why recursion is possible
The editor never refers to "the host": it talks to a few primitives (buffer, float, key). A child editor needs the same primitives, which the host
happily provides again, plus a *parent pointer* and focus routing. The config API exposes `spawn`, and `spawn` is the same constructor. Depth 8 works
exactly like depth 2; the tests spawn eight.

## Leaky abstractions
* **Global cursor shape** (`guicursor`) and **global key delivery** are properties of the single real terminal; they can't be per-instance.
* **Window-local options follow the window**, not the buffer. Switching buffers in a float needs us to re-apply our options.
* A **float's `row/col` includes its border**, and hidden floats still own their z-order.
* The TUI is **two OS processes** (client + embedded server). "No extra processes for nesting" has to be asserted as "same descendants as at boot".
* `nvim_buf_set_lines(0, -1, {})` on a buffer leaves one empty line; Vim's "buffer is never empty" invariant leaks through the API.
* Highlight groups are global; we namespace ours with an `Rv` prefix.

## What cannot reasonably be recreated with public APIs alone
* **Pending-key timeouts** need our own timer (`timeoutlen`); there is no hook into Neovim's.
* **Regex search**, folds, marks, macros (`q`), `:g`/`:s`, the jump list, completion, `:help`, and Vimscript are not implemented; we'd be rewriting Vim.
* **Real IME / composing input and mouse** don't arrive as plain keys; we turn the mouse off.
* **Per-instance cursor style / true separate terminals**: there is one terminal.
* **A hard sandbox** for configs: Lua environments isolate *names*, not capabilities.
* **Native undo tree, `:earlier`, persistent undo**: we only keep linear snapshot stacks.
* Anything that must keep working if the hook breaks: the hook *is* the editor, hence the `<C-\><C-\>` escape hatch.
