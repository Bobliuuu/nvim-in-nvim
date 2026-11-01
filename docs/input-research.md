# Input interception research (Phase 0)

**Question:** can Lua replace native Neovim editing, so that `i`, `x`, `dd` do nothing natively and we implement them ourselves?

**Answer:** yes. `vim.on_key()` returning `""` + a `vim.paste` override is enough. Tested on **Neovim 0.12.6** through a real pty-attached TUI
(`experiments/input_experiments.py`, 22 assertions, all passing). Reproduce: `python3 experiments/input_experiments.py`.

## Setup
`experiments/input/init.lua` is an isolated config: one `on_key` callback, a tiny Lua state machine (h j k l i x dd, logical Insert),
buffer edits only through `nvim_buf_set_text` / `nvim_buf_set_lines`. `experiments/pty_driver.py` forks `nvim` in a pty, writes raw bytes
(as a terminal would), and queries state over `--listen` + `--remote-expr` (dev-only; not a runtime dependency).

## Results
| # | Requirement | Result |
|---|-------------|--------|
| 1-3 | `h j k l` in Lua | PASS |
| 4 | native `x` suppressed, our `x` runs | PASS |
| 5 | native `dd` suppressed, our `dd` runs | PASS |
| 6-8 | logical Insert; host stays in *native Normal* the whole time | PASS |
| 9 | Unicode (é, →, CJK, emoji = 4-byte) | PASS |
| 11 | 500 chars written in one `write()` keep order | PASS |
| 12 | bracketed paste | PASS only after overriding `vim.paste` (see below) |
| 13 | arrows, F-keys (escape sequences) arrive as `<Up>`, `<F1>`... | PASS |
| 14-16 | `:`, `ZZ`, `<C-v> <C-w> <C-r>` have no native effect | PASS |
| 17 | emergency escape `<C-\><C-\>` toggles passthrough to native Neovim | PASS |
| 18 | error in callback is contained, hook survives | PASS |

## Findings (the surprising parts)
1. **`on_key` returning `""` reliably discards the key** before native handling. Covers `<Cmd>` too. No leaks observed for any key in the matrix.
2. **`{fn} will be removed on error`** (docs). One uncaught `error()` would silently hand the editor back to native Vim. We wrap the handler
   in `pcall`, reset logical state on error, and still return `""`.
3. **Paste bypasses `on_key`.** Bracketed paste arrives via `nvim_paste()` -> `vim.paste()`. Without override, pasting `dd` in logical Normal
   mode natively edits the buffer. We replace `vim.paste` and feed the text into the *same* dispatcher as typed keys.
4. **Host cursor clamping.** In native Normal mode the real cursor cannot sit past the last character, so "insert at end of line" breaks
   (characters land in reversed order!). Fix: `virtualedit=onemore` on the host. Our logical Insert mode lives on the host's Normal mode.
5. **Key representation.** `on_key(key, typed)`: use `typed` when non-empty (pre-mapping), `vim.fn.keytrans()` to normalise to `<Esc>`, `<BS>`, `<C-r>`.
   The host has no mappings, so `key` is enough; `typed` is a fallback.
6. **Emergency escape must be inside the hook** (a mapping is dead if the hook is wedged). `<C-\><C-\>` is handled before dispatch, can't be remapped.
7. Issue [#36480](https://github.com/neovim/neovim/issues/36480) was not reachable from the dev sandbox; we did not rely on any behaviour it might
   describe. Everything above is empirically observed on 0.12.6, not assumed.

## Alternatives considered
- **Buffer-local mappings:** need to map every key incl. all printable Unicode, no catch-all, typed-ahead ordering subtle. Rejected.
- **`nvim_open_term` + `on_input`:** only sees input for a terminal buffer; replaces the host's buffer model with a pty. Rejected, overkill.
- **Hybrid:** unnecessary.

## Decision
One global `vim.on_key` hook (+ `vim.paste` override) = the single physical input layer. It forwards every key to the focused logical editor.
