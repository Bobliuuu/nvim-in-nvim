-- Integration tests that push keys through Neovim's REAL input pipeline (nvim_feedkeys "tx" -> on_key).
-- True terminal-level tests (pty, escape sequences, paste) live in tests/e2e_pty.py.
local H = require("harness")
local h = require("helpers")
local test, eq = H.test, H.eq
local input = require("recursive_vim.input")
local Instances = require("recursive_vim.instances")

input.install()

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
end

local function host_tick() return vim.api.nvim_buf_get_changedtick(vim.api.nvim_get_current_buf()) end

test("input: keys reach the focused editor; host buffers are untouched", function()
  local ed = h.ed("hello\nworld")
  local nbufs = #vim.api.nvim_list_bufs()
  feed("lx")
  eq(h.lines(ed), { "hllo", "world" })
  feed("jdd")
  eq(h.lines(ed), { "hllo" })
  feed("ixyz<Esc>")
  eq(h.lines(ed), { "xyzhllo" })
  eq(vim.api.nvim_get_mode().mode, "n", "host stays in native normal mode")
  eq(#vim.api.nvim_list_bufs(), nbufs, "no stray host buffers")
end)

test("input: native i / x / dd / : / ZZ do nothing natively", function()
  local ed = h.ed("abc")
  feed("i")
  eq(ed.mode, "i")
  eq(vim.api.nvim_get_mode().mode, "n")
  feed("<Esc>")
  feed(":")
  eq(vim.api.nvim_get_mode().mode, "n", "no native cmdline")
  eq(ed.mode, "c")
  feed("<Esc>ZZ")
  eq(vim.api.nvim_get_mode().mode, "n")
  eq(h.lines(ed), { "abc" })
end)

test("input: special keys (arrows, BS, CR, Tab) and unicode", function()
  local ed = h.ed("")
  feed("iab<Left>X<Right>Y<BS><CR>日本<Esc>")
  eq(h.lines(ed), { "aXb", "日本" })
  feed("gg<Down><Up>")
  eq(ed.row, 0)
end)

test("input: ordering under fast input (1000 chars in one feed)", function()
  local ed = h.ed("")
  local s = {}
  for i = 1, 1000 do s[i] = string.char(97 + (i * 7) % 26) end
  s = table.concat(s)
  feed("i" .. s .. "<Esc>")
  eq(h.lines(ed), { s })
end)

test("input: feeding to the focused editor only (child focus routes keys)", function()
  local a = h.ed("a-text")
  local b = a:spawn({})
  feed("ib<Esc>")
  eq(h.lines(b), { "b" }, "child got the keys")
  eq(h.lines(a), { "a-text" }, "parent did not")
  b:focus_parent()
  feed("A!<Esc>")
  eq(h.lines(a), { "a-text!" })
  eq(h.lines(b), { "b" })
end)

test("input: callback errors are contained, state recovers, hook keeps working", function()
  local ed = h.ed("abc")
  ed.cfg.vim.keymap.set("n", "E", function() error("boom") end)
  feed("E")
  H.ok(ed.message_err and ed.message:match("boom"), tostring(ed.message))
  eq(ed.mode, "n")
  feed("x")
  eq(h.lines(ed), { "bc" })
  -- an error raised from inside a builtin path (buffer owned by someone else)
  local other = ed:spawn({})
  other.buf:guard(other) -- fine
  local ok = pcall(function() ed.buf:set_lines(other, 0, 1, { "evil" }) end)
  eq(ok, false)
  eq(h.lines(ed), { "bc" })
end)

test("input: emergency escape <C-c>x3 resets logical state", function()
  local ed = h.ed("abc")
  feed(":set <C-c>")
  -- the first <C-c> cancelled the cmdline already; force a weird state and panic out of it
  ed.mode, ed.cmdline = "c", { prefix = ":", text = "zzz", prev = "n" }
  ed.nstate = { op = "d", count = 3 }
  feed("<C-c><C-c><C-c>")
  eq(ed.mode, "n"); eq(ed.cmdline, nil); eq(ed.nstate, {})
end)

test("input: <C-\\><C-\\> toggles passthrough to native Neovim and back", function()
  local ed = h.ed("abc")
  feed("<C-\\><C-\\>")
  eq(input.passthrough, true)
  local ok, err = pcall(function()
    feed("x") -- native x now edits the focused window's buffer; our editor logic must not run
    eq(h.lines(ed), { "bc" })
    eq(ed.cmd_keys, {}, "our dispatcher saw nothing")
  end)
  feed("<C-\\><C-\\>")
  eq(input.passthrough, false)
  assert(ok, err)
  feed("x")
  eq(h.lines(ed), { "c" })
  eq(ed.cmd_keys, { "x" })
end)

test("input: paste goes through the same dispatcher (insert and normal mode)", function()
  local ed = h.ed("")
  feed("i")
  vim.paste({ "line one", "line two" }, -1)
  eq(h.lines(ed), { "line one", "line two" })
  feed("<Esc>")
  vim.paste({ "dd" }, -1) -- in normal mode a paste is just typed keys: runs OUR dd
  eq(h.lines(ed), { "line one" })
end)

test("input: host has no mappings (upstream on_key issue #36480 cannot trigger)", function()
  eq(#vim.api.nvim_get_keymap("n"), 0)
  eq(#vim.api.nvim_get_keymap("i"), 0)
end)
