-- Registry + focus. Knows nothing about editing. The same code path serves depth 0 and depth 40.
local api = vim.api
local M = { all = {}, focused = nil, seq = 0 }

local function script_root()
  local src = debug.getinfo(1, "S").source:sub(2)
  return (src:gsub("/lua/recursive_vim/instances%.lua$", ""))
end
M.root_dir = vim.env.RECURSIVE_VIM_ROOT or script_root()

M.on_root_quit = function() vim.cmd("qa!") end

function M.next_id() M.seq = M.seq + 1 return M.seq end
function M.register(ed) M.all[ed.id] = ed end

function M.roots()
  local out = {}
  for _, e in pairs(M.all) do if not e.parent then out[#out + 1] = e end end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function M.focus(ed)
  local render = require("recursive_vim.render")
  local prev = M.focused
  M.focused = ed
  local visible, e = {}, ed
  while e do visible[e] = true; e = e.parent end
  for _, x in pairs(M.all) do render.set_visible(x, visible[x] == true) end
  if ed.parent then ed.parent.active_child = ed end
  api.nvim_set_current_win(ed.win)
  if prev and not prev.closed then render.refresh(prev) end
  e = ed
  while e do render.refresh(e); e = e.parent end
end

function M.close(ed)
  if ed.closed then return end
  for i = #ed.children, 1, -1 do M.close(ed.children[i]) end
  ed.closed = true
  ed:_cancel_timer()
  M.all[ed.id] = nil
  local parent = ed.parent
  if parent then
    for i, c in ipairs(parent.children) do if c == ed then table.remove(parent.children, i) break end end
    if parent.active_child == ed then parent.active_child = parent.children[#parent.children] end
  end
  require("recursive_vim.render").destroy(ed)
  for _, b in ipairs(ed.buffers) do b:wipe() end
  if M.focused == ed or (M.focused and M.focused.closed) then
    M.focused = nil
    if parent then M.focus(parent) else M.on_root_quit(ed) end
  end
end

return M
