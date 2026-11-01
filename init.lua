-- nvim -u ./init.lua [file]
-- Boots the Lua-implemented editor (Editor A) on top of the real Neovim.
--   RECURSIVE_VIM_ROOT   project dir that holds configs/ (default: this directory)
--   RECURSIVE_VIM_CONFIG config file for Editor A      (default: configs/a/init.lua)
local code = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.env.RECURSIVE_VIM_ROOT or code
package.path = code .. "/lua/?.lua;" .. code .. "/lua/?/init.lua;" .. package.path

local file = vim.fn.argv(0)
require("recursive_vim").setup({
  root = root,
  config = vim.env.RECURSIVE_VIM_CONFIG or "configs/a/init.lua",
  file = (file ~= "" and file) or "examples/hello.txt",
})
