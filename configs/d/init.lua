-- Editor D: level four. No new editor code was written for it.
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true

vim.keymap.set("n", "Q", function()
  vim.editor.echo("Editor D (depth " .. vim.editor.depth() .. ")")
end)
