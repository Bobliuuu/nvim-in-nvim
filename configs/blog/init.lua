-- A port of the config from "Neovim isn't actually that scary" (alvinayang.com),
-- limited to what a plugin-free, Lua-only editor can express. Run it with:
--
--   RECURSIVE_VIM_CONFIG=configs/blog/init.lua nvim -u ./init.lua
--
-- What maps over 1:1: leader + options + autosave + keymaps + diagnostics-free basics.
-- What becomes a LAYER: splits, file tree, tabs. Each is a child editor.
-- What cannot exist without plugins/LSP: telescope, treesitter-textobjects, LSP, git, lualine themes.

vim.g.mapleader = " "

-- options (init.lua of the post) ---------------------------------------------
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.timeoutlen = 300
vim.opt.tabstop = 2
vim.opt.expandtab = true
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true

-- autosave on InsertLeave (the post also saves on FocusLost/BufLeave) --------
vim.api.nvim_create_autocmd("ModeChanged", {
  callback = function(a)
    if a.data.old == "i" and a.data.new == "n" then vim.cmd("update") end
  end,
})

-- start screen (alpha.nvim analogue) ----------------------------------------
vim.api.nvim_create_autocmd("EditorSpawn", {
  callback = function()
    if vim.editor.depth() == 0 then vim.editor.edit("examples/welcome.txt") end
  end,
})

-- file explorer (nvim-tree / oil analogue): a child editor layer --------------
local function explorer()
  vim.editor.spawn({ config = "configs/blog/explorer.lua", name = "tree" })
end
vim.keymap.set("n", "<leader>e", explorer, { desc = "file explorer" })
vim.keymap.set("n", "<leader>ff", explorer, { desc = "find files" })
vim.keymap.set("n", "<leader>o", explorer, { desc = "oil" })

-- splits are layers: the same config, one level deeper -----------------------
local function layer() vim.editor.spawn({ config = "configs/blog/init.lua" }) end
vim.keymap.set("n", "<leader>sv", layer, { desc = "vertical split" })
vim.keymap.set("n", "<leader>sh", layer, { desc = "horizontal split" })
vim.keymap.set("n", "<leader>sc", function()
  if not vim.editor.close() then vim.editor.echo("last layer, use :q") end
end, { desc = "close split" })

-- <C-h/j/k/l> split navigation -> move between layers ---------------------------
vim.keymap.set("n", "<C-k>", function() vim.cmd("parent") end)
vim.keymap.set("n", "<C-h>", function() vim.cmd("parent") end)
vim.keymap.set("n", "<C-j>", function() vim.cmd("child") end)
vim.keymap.set("n", "<C-l>", function() vim.cmd("child") end)

-- buffer tabs ------------------------------------------------------------------
vim.keymap.set("n", "<Tab>", ":bnext<CR>")
vim.keymap.set("n", "<S-Tab>", ":bprev<CR>")

-- misc maps of the post ----------------------------------------------------------
vim.keymap.set("n", "<leader>w", ":w<CR>")
vim.keymap.set("n", "<leader>nm", ":messages<CR>")
vim.keymap.set("n", "<leader>nd", function() vim.editor.echo("") end)
vim.keymap.set("n", "<leader>lf", ":Format<CR>")
vim.keymap.set("n", "]t", "/TODO<CR>", { desc = "next todo-comment" })

vim.api.nvim_create_user_command("Format", function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do lines[i] = (l:gsub("%s+$", "")) end
  while #lines > 1 and lines[#lines] == "" do table.remove(lines) end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.editor.echo("formatted " .. #lines .. " lines")
end, {})
