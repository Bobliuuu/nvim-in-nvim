-- Editor C: spawned by B. B can open THIS FILE, edit it with our Lua editor, save it, and reload C.
vim.g.mapleader = " "

vim.opt.number = true

vim.keymap.set("n", "Q", function()
  vim.editor.echo("Editor C")
end)

vim.keymap.set("n", "X", function()
  vim.editor.insert_text("hello from level 3")
end)

vim.keymap.set("n", "<leader>n", function()
  vim.editor.spawn({ config = "configs/d/init.lua" })
end)
