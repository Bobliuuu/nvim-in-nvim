-- The "Neovim isn't actually that scary" config, ported to run inside a layered editor.
local H = require("harness")
local h = require("helpers")
local test, eq = H.test, H.eq
local Instances = require("recursive_vim.instances")
local Editor = require("recursive_vim.editor")

local function boot()
  h.cleanup()
  local dir = h.project()
  vim.fn.system({ "cp", "-R", h.root .. "/examples", dir .. "/examples" })
  h.write(dir .. "/notes.txt", "one  \ntwo\t\nTODO: later\nthree\n\n\n")
  vim.fn.mkdir(dir .. "/sub", "p")
  h.write(dir .. "/sub/deep.txt", "deep file\n")
  local e = Editor.new({ config = "configs/blog/init.lua", file = "examples/hello.txt" })
  return dir, e
end

test("blog: options from the post are applied to the editor's own window", function()
  local _, e = boot()
  eq(e.opts.number, true); eq(e.opts.relativenumber, true)
  eq(e.opts.tabstop, 2); eq(e.opts.expandtab, true); eq(e.opts.wrap, false)
  eq(e.opts.scrolloff, 8); eq(e.opts.timeoutlen, 300); eq(e.opts.cursorline, true)
  local w = e.win
  eq(vim.api.nvim_get_option_value("relativenumber", { win = w }), true)
  eq(vim.api.nvim_get_option_value("scrolloff", { win = w }), 8)
  eq(vim.api.nvim_get_option_value("signcolumn", { win = w }), "yes")
  eq(vim.api.nvim_get_option_value("wrap", { win = w }), false)
end)

test("blog: start screen replaces the default buffer on the root editor only", function()
  local _, e = boot()
  H.ok(e.buf.path:match("welcome%.txt$"), e.buf.path)
  H.ok(h.lines(e)[1]:find("_", 1, true))
  local layer = e:spawn({ config = "configs/blog/init.lua" })
  eq(layer.buf.path, nil, "layers don't show the start screen")
end)

test("blog: autosave on InsertLeave writes the file", function()
  local dir, e = boot()
  e:type(":e notes.txt<CR>")
  e:type("ggAX<Esc>")
  eq(h.read(dir .. "/notes.txt"):sub(1, 6), "one  X", "saved without :w")
  H.ok(not e.buf:is_dirty())
end)

test("blog: :Format strips trailing whitespace and blank tail; ]t jumps to TODO; Tab cycles buffers", function()
  local dir, e = boot()
  e:type(":e notes.txt<CR>")
  e:type(" lf")
  eq(h.lines(e), { "one", "two", "TODO: later", "three" })
  e:type("gg]t"); eq(e.row, 2)
  local first = e.buf
  e:type("<Tab>"); H.ok(e.buf ~= first)
  e:type("<S-Tab>"); eq(e.buf, first)
end)

test("blog: <Space>e opens an explorer LAYER with its own config; <CR> opens the file in the layer above", function()
  local dir, e = boot()
  e:type(" e")
  local tree = Instances.focused
  eq(tree.name, "tree"); eq(tree.parent, e)
  eq(tree.opts.number, false, "explorer has its own options")
  eq(e.opts.number, true, "parent unchanged")
  H.ok(vim.tbl_contains(h.lines(tree), "notes.txt"), vim.inspect(h.lines(tree)))
  H.ok(vim.tbl_contains(h.lines(tree), "sub/"))
  eq(tree.buf:is_dirty(), false)
  -- enter sub/, then open deep.txt
  local function goto_line(txt) for i, l in ipairs(h.lines(tree)) do if l == txt then tree:type(":" .. i .. "<CR>") return end end error("no " .. txt) end
  goto_line("sub/"); tree:type("<CR>")
  H.ok(vim.tbl_contains(h.lines(tree), "deep.txt"))
  H.ok(vim.tbl_contains(h.lines(tree), "../"))
  goto_line("deep.txt"); tree:type("<CR>")
  eq(Instances.focused, e, "explorer closed, focus back on the editor")
  H.ok(tree.closed)
  eq(h.lines(e), { "deep file" })
  eq(e.message, "opened sub/deep.txt")
end)

test("blog: explorer q closes the layer; opening over a dirty buffer is refused (E37) and the layer stays", function()
  local _, e = boot()
  e:type(" e"); Instances.focused:type("q"); H.ok(Instances.focused == e, "q closed the explorer")
  -- parent WITHOUT autosave (plain editor) and with unsaved changes
  local p = h.ed("x")
  vim.fn.system({ "cp", "-R", h.root .. "/configs", Instances.root_dir .. "/configs" })
  h.write(Instances.root_dir .. "/other.txt", "other\n")
  p:type("iy<Esc>")
  local tree = p:spawn({ config = "configs/blog/explorer.lua", name = "tree" })
  for i, l in ipairs(h.lines(tree)) do if l == "other.txt" then tree:type(":" .. i .. "<CR>") end end
  tree:type("<CR>")
  H.ok(tree.message:match("E37"), tostring(tree.message))
  H.ok(not tree.closed, "explorer stays open after the refusal")
  eq(h.lines(p), { "yx" })
end)

test("blog: <Space>sv spawns a layer with the SAME config; <C-k>/<C-j> move between layers; <Space>sc closes", function()
  local _, e = boot()
  e:type(" sv")
  local l1 = Instances.focused
  eq(l1.parent, e); eq(l1.opts.timeoutlen, 300)
  l1:type(" sv")
  local l2 = Instances.focused
  eq(l2.depth, 2)
  l2:type("<C-k>"); eq(Instances.focused, l1)
  l1:type("<C-k>"); eq(Instances.focused, e)
  e:type("<C-j>"); eq(Instances.focused, l1)
  l1:type("<C-j>"); eq(Instances.focused, l2)
  l2:type(" sc"); eq(Instances.focused, l1); H.ok(l2.closed)
  e:type("<C-k>"); H.ok(true)
  Instances.focus(e)
  e:type(" sc"); H.ok(e.message:match("last layer"), tostring(e.message))
end)

test("blog: a layer edits the blog config itself and reloads it (config inside config inside config)", function()
  local dir, e = boot()
  e:type(" sv")
  local l = Instances.focused
  l:type(":e! configs/blog/init.lua<CR>")
  local idx
  for i, line in ipairs(h.lines(l)) do if line == "vim.opt.scrolloff = 8" then idx = i end end
  H.ok(idx)
  l:type(":" .. idx .. "<CR>$x")      -- 8 -> (deleted) ; type 20
  l:type("a20<Esc>")                  -- autosave fires (InsertLeave) from the blog config itself
  eq(h.lines(l)[idx], "vim.opt.scrolloff = 20")
  H.ok(h.read(dir .. "/configs/blog/init.lua"):find("scrolloff = 20", 1, true), "autosaved to disk")
  eq(l.opts.scrolloff, 8)
  l:type(":reload<CR>")
  eq(l.opts.scrolloff, 20)
  eq(vim.api.nvim_get_option_value("scrolloff", { win = l.win }), 20)
  eq(e.opts.scrolloff, 8, "the layer below keeps the old value until it reloads")
end)
