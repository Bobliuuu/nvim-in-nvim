local H = require("harness")
local h = require("helpers")
local test, eq = H.test, H.eq
local Instances = require("recursive_vim.instances")
local Editor = require("recursive_vim.editor")

-- The Section 8 scenario, in-process (tests/e2e_pty.py runs the same story with real terminal input).
local function story()
  local dir = h.project()
  h.write(dir .. "/scratch.txt", "alpha\nbeta\n")
  local A = Editor.new({ config = "configs/a/init.lua", file = "scratch.txt" })
  return dir, A
end

test("recursion: A -> B -> C, each with its own config, options, mappings", function()
  local _, A = story()
  eq(A.opts.number, true)
  eq(vim.api.nvim_get_option_value("number", { win = A.win }), true)
  A:type("Q"); eq(A.message, "Editor A")
  A:type("<Space>n")
  local B = Instances.focused
  eq(B.name, "B"); eq(B.parent, A); eq(B.depth, 1)
  eq(vim.api.nvim_get_option_value("number", { win = B.win }), false)
  eq(vim.api.nvim_get_option_value("number", { win = A.win }), true, "A still has numbers")
  B:type("Q"); eq(B.message, "Editor B")
  B:type("<Space>n")
  local C = Instances.focused
  eq(C.name, "C"); eq(C.depth, 2)
  C:type("Q"); eq(C.message, "Editor C")
  C:type("X"); eq(h.lines(C)[1], "hello from level 3" .. "")
  eq(vim.api.nvim_get_option_value("number", { win = C.win }), true)
  eq(vim.api.nvim_get_option_value("number", { win = B.win }), false)
  eq(h.lines(A), { "alpha", "beta" }, "A's buffer untouched by B and C")
  eq(h.lines(B), { "" }, "B's buffer untouched by C")
end)

test("recursion: B edits C's config file, saves with :w, C reloads and behaves differently", function()
  local dir, A = story()
  A:type("<Space>n"); local B = Instances.focused
  B:type("<Space>n"); local C = Instances.focused
  C:type("Q"); eq(C.message, "Editor C")
  -- go back to B (C stays alive) and edit configs/c/init.lua with OUR editor
  C:type(":parent<CR>")
  eq(Instances.focused, B)
  B:type(":e configs/c/init.lua<CR>")
  local lines = h.lines(B)
  local idx
  for i, l in ipairs(lines) do if l:find('vim.editor.echo("Editor C")', 1, true) then idx = i end end
  H.ok(idx, "found the echo line")
  B:type(":" .. idx .. "<CR>")
  B:type('/C")<CR>')                       -- land on the C right before the closing quote
  B:type("a was reconfigured<Esc>")
  eq(h.lines(B)[idx], '  vim.editor.echo("Editor C was reconfigured")')
  eq(h.read(dir .. "/configs/c/init.lua"):find("was reconfigured", 1, true), nil, "not saved yet")
  B:type(":w<CR>")
  H.ok(h.read(dir .. "/configs/c/init.lua"):find("Editor C was reconfigured", 1, true), "saved to disk by our :w")
  -- C still runs the OLD config until reloaded
  C:type("Q"); eq(C.message, "Editor C")  -- (focus routing: feed C directly)
  B:type(":child<CR>")
  eq(Instances.focused, C)
  C:type(":reload<CR>")
  C:type("Q"); eq(C.message, "Editor C was reconfigured")
end)

test("recursion: isolation — A's state is unchanged after B and C were created, edited, closed", function()
  local dir, A = story()
  local snapA = A:snapshot()
  A:type("<Space>n"); local B = Instances.focused
  B:type("ihello from B<Esc>")
  B:type("<Space>n"); local C = Instances.focused
  C:type("X")
  C:type(":q!<CR>"); eq(Instances.focused, B, "closing C restores focus to B")
  B:type(":q!<CR>"); eq(Instances.focused, A, "closing B restores focus to A")
  local after = A:snapshot()
  for _, k in ipairs({ "lines", "maps", "cmds", "opts", "mode", "row", "col", "config", "dirty", "bufnr", "depth", "children" }) do
    eq(after[k], snapA[k], k)
  end
  A:type("Q"); eq(A.message, "Editor A")
  A:type(":Hello<CR>"); eq(A.message, "Hello from nested Neovim! (depth 0)")
  eq(vim.api.nvim_get_option_value("number", { win = A.win }), true)
  eq(h.read(dir .. "/scratch.txt"), "alpha\nbeta\n", "file on disk untouched")
end)

test("recursion: a 4th (and 8th) level uses the same constructor — no depth special cases", function()
  local _, A = story()
  local cur = A
  local expect = { "A", "B", "C", "D" }
  for lvl = 1, 3 do
    cur:type("<Space>n")
    cur = Instances.focused
    eq(cur.name, expect[lvl + 1])
  end
  cur:type("Q"); eq(cur.message, "Editor D (depth 3)")
  eq(vim.api.nvim_get_option_value("relativenumber", { win = cur.win }), true)
  eq(vim.api.nvim_get_option_value("relativenumber", { win = A.win }), false)
  -- programmatic: spawn without any config, 4 more levels
  for _ = 1, 4 do cur = cur:spawn({}) end
  eq(cur.depth, 7); eq(cur.name, "H")
  cur:type("ideep<Esc>"); eq(h.lines(cur), { "deep" })
end)

test("recursion: focus routing, visibility and parent/child navigation", function()
  local _, A = story()
  A:type("<Space>n"); local B = Instances.focused
  B:type("<Space>n"); local C = Instances.focused
  eq(vim.api.nvim_get_current_win(), C.win)
  local snap = function(e) return e:snapshot().win_visible end
  H.ok(snap(A) and snap(B) and snap(C), "ancestors stay visible (nested look)")
  C:type(":parent<CR>")
  eq(Instances.focused, B); eq(vim.api.nvim_get_current_win(), B.win)
  H.ok(not snap(C), "descendants of the focused editor are hidden")
  B:type(":parent<CR>"); eq(Instances.focused, A)
  H.ok(not snap(B) and not snap(C))
  A:type(":child<CR>"); eq(Instances.focused, B)
  B:type(":child<CR>"); eq(Instances.focused, C)
  H.ok(snap(A) and snap(B) and snap(C))
end)

test("recursion: buffer ownership — an editor cannot modify another's buffer", function()
  local _, A = story()
  local B = A:spawn({})
  local ok, err = pcall(function() B.buf:set_text(A, 0, 0, 0, 0, { "x" }) end)  -- wrong owner passes A to B's buffer
  eq(ok, false)
  H.ok(tostring(err):match("owned by editor"), tostring(err))
  ok = pcall(function() A.buf:set_lines(B, 0, 1, { "evil" }) end)
  eq(ok, false)
  eq(h.lines(A), { "alpha", "beta" })
  H.ok(A.buf.bufnr ~= B.buf.bufnr)
end)

test("recursion: two editors may open the same file independently (separate buffers, undo, cursor)", function()
  local dir, A = story()
  local B = A:spawn({ file = "scratch.txt" })
  A:type("x") -- A is not focused but we can feed it directly: still isolated
  eq(h.lines(A)[1], "lpha")
  eq(h.lines(B)[1], "alpha")
  B:type("dd")
  eq(h.lines(B), { "beta" })
  eq(h.lines(A), { "lpha", "beta" })
  A:type("u"); eq(h.lines(A)[1], "alpha")
  eq(h.lines(B), { "beta" })
end)

test("recursion: cleanup closes windows and wipes buffers of the whole subtree", function()
  local _, A = story()
  local wins0, bufs0 = #vim.api.nvim_list_wins(), #vim.api.nvim_list_bufs()
  A:type("<Space>n"); local B = Instances.focused
  B:type("<Space>n"); local C = Instances.focused
  C:type(":e configs/c/init.lua<CR>")
  local wins1, bufs1 = #vim.api.nvim_list_wins(), #vim.api.nvim_list_bufs()
  eq(wins1, wins0 + 2); H.ok(bufs1 > bufs0)
  local bufnrs = {}
  for _, e in ipairs({ B, C }) do for _, b in ipairs(e.buffers) do bufnrs[#bufnrs + 1] = b.bufnr end end
  B:type(":q!<CR>")    -- closing B must also close C (child) and restore A
  eq(Instances.focused, A)
  eq(#vim.api.nvim_list_wins(), wins0)
  eq(#vim.api.nvim_list_bufs(), bufs0)
  for _, n in ipairs(bufnrs) do H.ok(not vim.api.nvim_buf_is_valid(n), "buffer wiped") end
  H.ok(B.closed and C.closed)
  eq(#A.children, 0)
end)

test("recursion: a child with a broken config does not take down its parent", function()
  local dir, A = story()
  h.write(dir .. "/configs/b/init.lua", "this is not lua (((")
  A:type("<Space>n")
  local B = Instances.focused
  eq(B.name, "B")
  H.ok(B.message_err, "error shown in the affected instance")
  eq(A.message_err, nil, "parent unaffected")
  B:type("ihi<Esc>"); eq(h.lines(B), { "hi" })
  A:type("Q") ; eq(A.message, "Editor A")
end)

test("recursion: :q on the root asks the host to quit", function()
  local _, A = story()
  local quit
  Instances.on_root_quit = function() quit = true end
  A:type(":q<CR>")
  eq(quit, true)
  Instances.on_root_quit = function() end
end)
