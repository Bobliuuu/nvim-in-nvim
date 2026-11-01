-- Editor A: the first logical editor, running directly on the real Neovim.
vim.g.mapleader = " "

vim.opt.number = true
vim.opt.tabstop = 4

vim.keymap.set("n", "Q", function()
  vim.editor.echo("Editor A")
end, { desc = "who am I?" })

vim.keymap.set("n", "<leader>n", function()
  vim.editor.spawn({ config = "configs/b/init.lua" })
end, { desc = "spawn editor B" })

vim.api.nvim_create_user_command("Hello", function()
  vim.editor.echo("Hello from nested Neovim! (depth " .. vim.editor.depth() .. ")")
end, {})
