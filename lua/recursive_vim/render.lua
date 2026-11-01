-- Display adapter. The ONLY file that turns logical editor state into host windows/options.
-- Per-instance options become *window-local* / *buffer-local* options of that editor's own float,
-- never global host options (the one exception is the single physical cursor shape).
local api = vim.api
local M = {}

local SEL_NS = api.nvim_create_namespace("recursive_vim_selection")
local PALETTE = { "#7aa2f7", "#bb9af7", "#9ece6a", "#e0af68", "#f7768e", "#7dcfff" }
local MODE_LABEL = { n = " NORMAL ", i = " INSERT ", v = " VISUAL ", V = " V-LINE ", c = " COMMAND " }
local MODE_HL = { n = "RvNormal", i = "RvInsert", v = "RvVisual", V = "RvVisual", c = "RvCommand" }
local last_cursor

function M.setup()
  local function hl(name, v) api.nvim_set_hl(0, name, v) end
  hl("RvNormal", { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
  hl("RvInsert", { fg = "#1a1b26", bg = "#9ece6a", bold = true })
  hl("RvVisual", { fg = "#1a1b26", bg = "#bb9af7", bold = true })
  hl("RvCommand", { fg = "#1a1b26", bg = "#e0af68", bold = true })
  hl("RvBar", { fg = "#c0caf5", bg = "#24283b" })
  hl("RvBarDim", { fg = "#7982a9", bg = "#24283b" })
  hl("RvMsg", { fg = "#c0caf5", bold = true })
  hl("RvErr", { fg = "#f7768e", bold = true })
  hl("RvHint", { fg = "#565f89", italic = true })
  for i, c in ipairs(PALETTE) do
    hl("RvBorder" .. (i - 1), { fg = c })
    hl("RvTitle" .. (i - 1), { fg = "#1a1b26", bg = c, bold = true })
  end
end

local function esc(s) return (tostring(s):gsub("%%", "%%%%")) end

function M.geometry(ed)
  local p = ed.parent
  if not p then
    return { r = 0, c = 0, w = vim.o.columns, h = vim.o.lines - vim.o.cmdheight }
  end
  local g = p.geom
  -- child box sits inside the parent's box, just below the parent's winbar, so every level stays visible
  return { r = g.r + 2, c = g.c + 3, w = math.max(g.w - 6, 24), h = math.max(g.h - 4, 8) }
end

local function win_cfg(ed)
  local g = ed.geom
  return { relative = "editor", row = g.r, col = g.c, width = g.w - 2, height = g.h - 2 }
end

function M.display_name(ed, buf)
  buf = buf or ed.buf
  local root = require("recursive_vim.instances").root_dir
  local p = buf.path
  if not p then return "[No Name]" end
  if root and p:sub(1, #root + 1) == root .. "/" then p = p:sub(#root + 2) end
  return p
end

function M.open(ed)
  ed.geom = M.geometry(ed)
  local cfg = win_cfg(ed)
  cfg.border = "rounded"
  cfg.style = "minimal"
  cfg.zindex = 50 + ed.depth * 2
  cfg.title = " " .. ed.name .. " "
  cfg.title_pos = "center"
  cfg.footer = " "
  cfg.footer_pos = "left"
  ed.win = api.nvim_open_win(ed.buf.bufnr, false, cfg)
  local pal = ed.depth % #PALETTE
  api.nvim_set_option_value("winhighlight",
    ("FloatBorder:RvBorder%d,FloatTitle:RvTitle%d,FloatFooter:RvMsg,Normal:Normal,WinBar:RvBar,WinBarNC:RvBarDim")
      :format(pal, pal), { win = ed.win })
  api.nvim_set_option_value("signcolumn", "no", { win = ed.win })
  api.nvim_set_option_value("scrolloff", 2, { win = ed.win })
  api.nvim_set_option_value("winbar", " ", { win = ed.win })
end

function M.apply_options(ed)
  if not (ed.win and api.nvim_win_is_valid(ed.win)) then return end
  for _, k in ipairs({ "number", "relativenumber", "cursorline", "wrap", "scrolloff", "signcolumn" }) do
    api.nvim_set_option_value(k, ed.opts[k], { win = ed.win })
  end
  for _, b in ipairs(ed.buffers) do
    if api.nvim_buf_is_valid(b.bufnr) then
      api.nvim_set_option_value("tabstop", ed.opts.tabstop, { buf = b.bufnr })
      api.nvim_set_option_value("expandtab", ed.opts.expandtab, { buf = b.bufnr })
    end
  end
end

function M.set_visible(ed, visible)
  if ed.win and api.nvim_win_is_valid(ed.win) then api.nvim_win_set_config(ed.win, { hide = not visible }) end
end

function M.relayout(roots)
  local function go(ed)
    ed.geom = M.geometry(ed)
    if ed.win and api.nvim_win_is_valid(ed.win) then api.nvim_win_set_config(ed.win, win_cfg(ed)) end
    for _, c in ipairs(ed.children) do go(c) end
  end
  for _, r in ipairs(roots) do go(r) end
end

function M.destroy(ed)
  if ed.win and api.nvim_win_is_valid(ed.win) then pcall(api.nvim_win_close, ed.win, true) end
  ed.win = nil
end

local function pending_text(ed)
  local s, parts = ed.nstate, {}
  if s.reg then parts[#parts + 1] = '"' .. s.reg end
  if s.count then parts[#parts + 1] = tostring(s.count) end
  if s.op then parts[#parts + 1] = s.op end
  if s.opcount then parts[#parts + 1] = tostring(s.opcount) end
  if s.prefix and s.prefix ~= '"' then parts[#parts + 1] = s.prefix end
  local out = table.concat(parts)
  if #ed.mapseq > 0 then out = out .. table.concat(ed.mapseq) end
  return out
end

function M.refresh(ed)
  if ed.closed or not (ed.win and api.nvim_win_is_valid(ed.win)) then return end
  local focused = require("recursive_vim.instances").focused == ed
  -- cursor
  local row = math.max(0, math.min(ed.row, ed.buf:count() - 1))
  pcall(api.nvim_win_set_cursor, ed.win, { row + 1, ed.col })
  -- winbar
  local label = ed.cmdline and MODE_LABEL.c or MODE_LABEL[ed.mode] or ed.mode
  local hlg = ed.cmdline and MODE_HL.c or MODE_HL[ed.mode] or "RvNormal"
  local dirty = ed.buf:is_dirty() and " [+]" or ""
  local bar = ("%%#%s#%s%%#RvBar# %s %s%s%%=%s  %d:%d "):format(
    hlg, label, esc("#" .. ed.id), esc(M.display_name(ed)), dirty, esc(pending_text(ed)), row + 1, ed.col + 1)
  api.nvim_set_option_value("winbar", bar, { win = ed.win })
  -- title + footer
  local pal = ed.depth % #PALETTE
  local footer
  if ed.cmdline then
    footer = { { " " .. ed.cmdline.prefix .. ed.cmdline.text .. "█ ", "RvMsg" } }
  elseif ed.message then
    footer = { { " " .. ed.message .. " ", ed.message_err and "RvErr" or "RvMsg" } }
  else
    local n = #ed.children
    footer = { { (" depth %d · %d %s "):format(ed.depth, n, n == 1 and "child" or "children"), "RvHint" } }
  end
  pcall(api.nvim_win_set_config, ed.win, {
    title = { { " " .. ed.name .. " · " .. M.display_name(ed) .. " ", "RvTitle" .. pal } }, title_pos = "center",
    footer = footer, footer_pos = "left",
  })
  -- visual selection
  api.nvim_buf_clear_namespace(ed.buf.bufnr, SEL_NS, 0, -1)
  if (ed.mode == "v" or ed.mode == "V") and ed.vanchor then
    local a, b = ed.vanchor, { ed.row, ed.col }
    if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then a, b = b, a end
    if ed.mode == "V" then
      for r = a[1], b[1] do api.nvim_buf_set_extmark(ed.buf.bufnr, SEL_NS, r, 0, { line_hl_group = "Visual" }) end
    else
      local lastline = ed.buf:line(b[1])
      local ec = math.min(#lastline, b[2] + math.max(require("recursive_vim.text").clen(lastline, b[2]), 1))
      api.nvim_buf_set_extmark(ed.buf.bufnr, SEL_NS, a[1], a[2], { end_row = b[1], end_col = ec, hl_group = "Visual" })
    end
  end
  -- the single physical cursor
  if focused then
    local shape = ed.mode == "i" and "a:ver25-blinkon0" or "a:block-blinkon0"
    if shape ~= last_cursor then vim.o.guicursor = shape; last_cursor = shape end
  end
end

return M
