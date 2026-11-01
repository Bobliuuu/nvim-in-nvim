-- nvim -u ./init.lua [file]
-- Boots the Lua-implemented editor (Editor A) on top of the real Neovim.
local root = vim.env.RECURSIVE_VIM_ROOT or vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local file = vim.fn.argv(0)
require("recursive_vim").setup({
  root = root,
  config = vim.env.RECURSIVE_VIM_CONFIG or "configs/a/init.lua",
  file = (file ~= "" and file) or "examples/hello.txt",
})
