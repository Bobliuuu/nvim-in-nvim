local M = {}

local function host_setup()
  local o = vim.o
  o.termguicolors = true
  o.showmode, o.showcmd, o.ruler, o.laststatus = false, false, false, 0
  o.mouse = ""
  o.virtualedit = "onemore"      -- logical Insert mode lives on the host's Normal mode; the cursor must reach EOL
  o.swapfile = false
  o.ttimeoutlen = 10
  o.shortmess = o.shortmess .. "I"
end

-- opts: root (project dir), config (path), file (path to open), on_root_quit (fn)
function M.setup(opts)
  opts = opts or {}
  local Instances = require("recursive_vim.instances")
  if opts.root then Instances.root_dir = opts.root end
  if opts.on_root_quit then Instances.on_root_quit = opts.on_root_quit end
  host_setup()
  require("recursive_vim.render").setup()
  require("recursive_vim.input").install()
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function() require("recursive_vim.render").relayout(Instances.roots()) end,
  })
  local Editor = require("recursive_vim.editor")
  M.root = Editor.new({ config = opts.config, file = opts.file })
  return M.root
end

-- JSON-friendly snapshot for tests / debugging
function M.state()
  local Instances = require("recursive_vim.instances")
  local out = { focused = Instances.focused and Instances.focused.id, editors = {} }
  for id, ed in pairs(Instances.all) do out.editors[tostring(id)] = ed:snapshot() end
  return out
end

return M
