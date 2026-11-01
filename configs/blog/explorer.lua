-- The "file tree" layer. Spawned by configs/blog/init.lua; has its OWN options and mappings.
-- <CR>/l open the entry in the layer above and close this one; h goes up a directory; q closes.
vim.g.mapleader = " "
vim.opt.number = false
vim.opt.cursorline = true
vim.opt.wrap = false
vim.opt.signcolumn = "no"

local dir = "."     -- relative to the project root

local function list(d)
  local abs = vim.editor.root() .. "/" .. d
  local out = { "▾ " .. d }
  if d ~= "." then out[#out + 1] = "../" end
  local p = io.popen('ls -1Ap "' .. abs .. '" 2>/dev/null')
  if p then
    for name in p:lines() do
      if name ~= ".git/" and name ~= ".DS_Store" then out[#out + 1] = name end
    end
    p:close()
  end
  return out
end

local function render()
  vim.editor.scratch(list(dir))
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
end

local function open()
  local name = vim.api.nvim_get_current_line()
  if name:sub(1, 2) == "▾ " then return end
  if name == "../" then
    dir = dir:match("^(.*)/[^/]+$") or "."
    return render()
  end
  if name:sub(-1) == "/" then
    dir = (dir == ".") and name:sub(1, -2) or (dir .. "/" .. name:sub(1, -2))
    return render()
  end
  local path = (dir == ".") and name or (dir .. "/" .. name)
  local ok, err = pcall(function() vim.editor.parent():edit(path) end)
  if not ok then return vim.editor.echo(err) end
  vim.editor.parent():echo("opened " .. path)
  vim.editor.close()
end

vim.keymap.set("n", "<CR>", open)
vim.keymap.set("n", "l", open)
vim.keymap.set("n", "h", function() dir = dir:match("^(.*)/[^/]+$") or "."; render() end)
vim.keymap.set("n", "q", function() vim.editor.close() end)
vim.keymap.set("n", "<Esc>", function() vim.editor.close() end)

vim.api.nvim_create_autocmd("EditorSpawn", { callback = render })
