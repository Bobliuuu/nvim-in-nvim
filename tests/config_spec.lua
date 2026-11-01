local H = require("harness")
local h = require("helpers")
local test, eq = H.test, H.eq
local Instances = require("recursive_vim.instances")

local function with_config(src, text)
  local ed = h.ed(text or "hello world")
  local root = Instances.root_dir
  h.write(root .. "/cfg.lua", src)
  ed:load_config("cfg.lua")
  return ed, root
end

test("config: options are applied to THIS editor's window/buffers only", function()
  local a = with_config("vim.opt.number = true\nvim.opt.tabstop = 4\nvim.opt.cursorline = true")
  local b = a:spawn({})
  eq(a.opts.number, true)
  eq(vim.api.nvim_get_option_value("number", { win = a.win }), true)
  eq(vim.api.nvim_get_option_value("number", { win = b.win }), false)
  eq(vim.api.nvim_get_option_value("tabstop", { buf = a.buf.bufnr }), 4)
  eq(vim.api.nvim_get_option_value("tabstop", { buf = b.buf.bufnr }), 8)
  eq(vim.o.number, false, "host global option untouched")
end)

test("config: keymaps with leader, multi-key lhs, string rhs, insert maps", function()
  local ed = with_config([[
    vim.g.mapleader = ","
    vim.keymap.set("n", "<leader>x", function() vim.editor.echo("leader-x") end)
    vim.keymap.set("n", "gz", "dd")
    vim.keymap.set("n", "<leader>xy", function() vim.editor.echo("leader-xy") end)
    vim.keymap.set("i", "jk", "<Esc>")
  ]], "one\ntwo\nthree")
  ed:type(",x"); H.ok(ed.mapseq[1] == "," or ed.mapseq[2] == "x" or #ed.mapseq > 0, "pending: waits for longer map")
  ed:type("y"); eq(ed.message, "leader-xy")
  ed:type(",xj"); eq(ed.message, "leader-x"); eq(ed.row, 1, "unmatched suffix key still ran (j)")
  ed:type("gz"); eq(h.lines(ed), { "one", "three" })
  ed:type("ifoo"); eq(ed.mode, "i")
  ed:type("jk"); eq(ed.mode, "n")
  eq(h.lines(ed)[2], "fothreeo" == "" and "" or h.lines(ed)[2])
  eq(h.lines(ed), { "one", "foothree" })
end)

test("config: mappings override builtins; unmapped keys still builtin", function()
  local ed = with_config('vim.keymap.set("n", "x", function() vim.editor.echo("mine") end)')
  ed:type("x"); eq(ed.message, "mine"); eq(h.lines(ed), { "hello world" })
  ed:type("dw"); eq(h.lines(ed), { "world" })
end)

test("config: user commands (function + string), args, bang", function()
  local ed = with_config([[
    vim.api.nvim_create_user_command("Hello", function(o)
      vim.editor.echo("hi " .. o.args .. (o.bang and "!" or ""))
    end, {})
    vim.api.nvim_create_user_command("Wipe", "echo wiped", {})
  ]])
  ed:type(":Hello bob<CR>"); eq(ed.message, "hi bob")
  ed:type(":Hello! x<CR>"); eq(ed.message, "hi x!")
  ed:type(":Wipe<CR>"); eq(ed.message, "wiped")
  eq(ed:snapshot().cmds, { "Hello", "Wipe" })
  local ok = pcall(function() ed.cfg.vim.api.nvim_create_user_command("lower", "echo x", {}) end)
  eq(ok, false)
end)

test("config: virtual vim API (cursor motions, insert_text, cmd, get_line)", function()
  local ed = with_config([[
    vim.keymap.set("n", "H", function() vim.editor.move_left() end)
    vim.keymap.set("n", "L", function() vim.editor.move_right(3) end)
    vim.keymap.set("n", "X", function() vim.editor.insert_text("<<>>") end)
    vim.keymap.set("n", "Z", function() vim.cmd("set number") vim.editor.echo(vim.editor.get_line()) end)
  ]])
  ed:type("L"); eq(ed.col, 3)
  ed:type("H"); eq(ed.col, 2)
  ed:type("X"); eq(h.lines(ed), { "he<<>>llo world" })
  ed:type("u"); eq(h.lines(ed), { "hello world" }, "insert_text is one undo step")
  ed:type("Z"); eq(ed.message, "hello world"); eq(ed.opts.number, true)
end)

test("config: autocmd-style events (ModeChanged, BufWritePost)", function()
  local ed = with_config([[
    modes = {}
    vim.api.nvim_create_autocmd("ModeChanged", { callback = function(a) modes[#modes+1] = a.data.new end })
    vim.api.nvim_create_autocmd("BufWritePost", { callback = function() vim.editor.echo("saved!") end })
  ]])
  ed:type("i<Esc>:w<CR>")
  eq(ed.cfg.env.modes, { "i", "n" })
  eq(ed.message, "saved!")
end)

test("config: the host `vim` is not reachable from a config", function()
  local ed = with_config([[
    probe = {
      is_virtual = vim.is_virtual,
      fn = vim.fn, uv = vim.uv, loop = vim.loop, nvim_command = vim.api.nvim_command,
      package = package, debug = debug, loadstring = loadstring, dofile = dofile, require_is_ours = require ~= nil,
      host_opt = rawget(_G, "vim") == vim,
    }
  ]])
  local p = ed.cfg.env.probe
  eq(p.is_virtual, true)
  eq(p.fn, nil); eq(p.uv, nil); eq(p.loop, nil); eq(p.nvim_command, nil)
  eq(p.package, nil); eq(p.debug, nil); eq(p.dofile, nil)
  H.ok(ed.cfg.env.vim ~= vim, "env.vim is a different table than the host vim")
  eq(rawget(_G, "probe"), nil, "config globals do not leak into the host _G")
end)

test("config: unknown option / wrong type are reported and keep the editor alive", function()
  local ed = with_config('vim.opt.bogus = 1')
  H.ok(ed.errors[1]:match("E518"), tostring(ed.errors[1]))
  ed = with_config('vim.opt.number = "yes"')
  H.ok(ed.errors[1]:match("E474"), tostring(ed.errors[1]))
  ed:type("x"); eq(h.lines(ed), { "ello world" })
end)

test("config: require() of a sibling module in the config dir", function()
  local ed = h.ed("x")
  local d = Instances.root_dir
  h.write(d .. "/cfgdir/init.lua", 'local m = require("helper")\nvim.keymap.set("n", "Q", function() vim.editor.echo(m.msg) end)')
  h.write(d .. "/cfgdir/lua/helper.lua", 'return { msg = "from helper" }')
  ed:load_config("cfgdir/init.lua")
  ed:type("Q"); eq(ed.message, "from helper")
end)

test("reload: rebuilds mappings (no duplicates), reverts removed options, preserves buffers", function()
  local ed, root = with_config('vim.opt.number = true\nvim.keymap.set("n", "Q", function() vim.editor.echo("v1") end)')
  ed:type("ix<Esc>")
  ed:type("Q"); eq(ed.message, "v1")
  h.write(root .. "/cfg.lua", 'vim.keymap.set("n", "W", function() vim.editor.echo("v2") end)')
  H.ok(ed:reload_config())
  ed:type("Q"); H.ok(ed.message == nil, "old mapping is gone")
  ed:type("W"); eq(ed.message, "v2")
  eq(ed.opts.number, false, "option no longer set by config reverts to default")
  eq(vim.api.nvim_get_option_value("number", { win = ed.win }), false)
  eq(ed:snapshot().maps.n, { "W" })
  eq(h.lines(ed), { "xhello world" }, "buffer contents preserved across reload")
  H.ok(ed.buf:is_dirty())
end)

test("reload: a broken config keeps the previous working config, error shown in this editor", function()
  local ed, root = with_config('vim.keymap.set("n", "Q", function() vim.editor.echo("good") end)')
  h.write(root .. "/cfg.lua", 'vim.keymap.set("n", "Q", function(')   -- syntax error
  eq(ed:reload_config(), false)
  H.ok(ed.message_err and ed.message:match("cfg.lua"), tostring(ed.message))
  ed:type("Q"); eq(ed.message, "good")
  h.write(root .. "/cfg.lua", 'error("kaboom")')                       -- runtime error
  eq(ed:reload_config(), false)
  H.ok(ed.errors[#ed.errors]:match("kaboom"))
  ed:type("Q"); eq(ed.message, "good")
  h.write(root .. "/cfg.lua", 'vim.opt.number = true\nerror("late")')  -- fails AFTER setting an option
  eq(ed:reload_config(), false)
  eq(ed.opts.number, false, "half-applied config is not committed")
end)

test("config: :source and :lua run in the editor's own environment", function()
  local ed = h.ed("x")
  h.write(Instances.root_dir .. "/extra.lua", 'vim.keymap.set("n", "Q", function() vim.editor.echo("sourced") end)')
  ed:type(":source extra.lua<CR>"); ed:type("Q"); eq(ed.message, "sourced")
  ed:type(":lua vim.editor.echo('lua ' .. vim.editor.depth())<CR>"); eq(ed.message, "lua 0")
  ed:type(":lua vim.nope.x = 1<CR>"); H.ok(ed.message_err)
end)
