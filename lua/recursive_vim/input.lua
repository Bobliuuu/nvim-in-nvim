-- The ONE physical input layer. Nothing else in the project calls vim.on_key / replaces vim.paste.
-- Every key is swallowed (return "") and handed to whichever logical editor currently has focus.
local Keys = require("recursive_vim.keys")
local Instances = require("recursive_vim.instances")
local M = { passthrough = false, panic_bs = 0, panic_c = 0, installed = false }

function M.dispatch(key)
  local ed = Instances.focused
  if not ed then return end
  local ok, err = pcall(ed.feed, ed, key)
  if not ok then pcall(ed.report_error, ed, err) pcall(ed.recover, ed) end
end

local function emergency(k)
  -- <C-\><C-\>  : toggle full passthrough to native Neovim (escape hatch if the runtime is wedged)
  -- <C-c> x3    : reset the focused editor's logical state (mode, pending keys, cmdline)
  if k == "<C-\\>" then
    M.panic_bs = M.panic_bs + 1
    M.panic_c = 0
    if M.panic_bs >= 2 then M.passthrough = not M.passthrough; M.panic_bs = 0 end
    return true
  end
  M.panic_bs = 0
  if k == "<C-c>" then
    M.panic_c = M.panic_c + 1
    if M.panic_c >= 3 then
      M.panic_c = 0
      local ed = Instances.focused
      if ed then pcall(ed.recover, ed); pcall(ed.echo, ed, "reset (<C-c> x3)") end
    end
  else
    M.panic_c = 0
  end
  return false
end

-- The host must own ZERO mappings: Neovim ships defaults (some are Lua functions) and swallowing a key that
-- has a Lua mapping triggers upstream issue #36480. All user mappings live in per-editor tables instead.
function M.clear_host_keymaps()
  for _, mode in ipairs({ "n", "i", "v", "x", "s", "o", "c", "t", "l" }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do pcall(vim.api.nvim_del_keymap, mode, m.lhs) end
  end
end

function M.install()
  if M.installed then return end
  M.installed = true
  M.clear_host_keymaps()
  M.ns = vim.api.nvim_create_namespace("recursive_vim_input")

  vim.on_key(function(key, typed)
    -- `typed` is what the user pressed; `key` is after mappings (default Neovim maps X -> dh, Y -> y$ ...)
    local raw = (typed ~= nil and typed ~= "") and typed or key
    if raw == nil or raw == "" then return nil end
    local k = Keys.normalize(raw)
    if emergency(k) then return "" end
    if M.passthrough then return nil end
    M.dispatch(k)
    return ""
  end, M.ns)

  -- Bracketed paste never goes through on_key (it arrives via nvim_paste -> vim.paste).
  local orig = vim.paste
  vim.paste = function(lines, phase)
    if M.passthrough then return orig(lines, phase) end
    for i, l in ipairs(lines) do
      for _, k in ipairs(Keys.from_text(l)) do M.dispatch(k) end
      if i < #lines then M.dispatch("<CR>") end
    end
    return true
  end
end

return M
