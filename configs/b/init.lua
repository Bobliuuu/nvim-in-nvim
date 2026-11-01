-- Editor B: spawned by A. Different options, different mappings.
vim.g.mapleader = " "

vim.opt.number = false
vim.opt.cursorline = true

vim.keymap.set("n", "Q", function()
  vim.editor.echo("Editor B")
end)

vim.keymap.set("n", "<leader>n", function()
  vim.editor.spawn({ config = "configs/c/init.lua" })
end)
