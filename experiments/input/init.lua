-- Phase 0 experiment: can vim.on_key() fully replace native editing?
vim.opt.shortmess:append("I")
vim.opt.virtualedit = "onemore"
local S = { mode = "n", pending = "", passthrough = false, log = {}, panic = 0, errors = 0 }
_G.EXP = S
local buf = vim.api.nvim_get_current_buf()

local function cur() local p = vim.api.nvim_win_get_cursor(0) return p[1] - 1, p[2] end
local function line(r) return vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or "" end
local function setcur(r, c)
  local n = vim.api.nvim_buf_line_count(buf)
  r = math.max(0, math.min(r, n - 1))
  c = math.max(0, math.min(c, math.max(#line(r) - (S.mode == "n" and 1 or 0), 0)))
  vim.api.nvim_win_set_cursor(0, { r + 1, c })
end

local function handle(k)
  table.insert(S.log, k)
  if S.mode == "i" then
    local r, c = cur()
    if k == "<Esc>" then S.mode = "n"; setcur(r, c - 1)
    elseif k == "<BS>" then
      if c > 0 then vim.api.nvim_buf_set_text(buf, r, c - 1, r, c, {}); setcur(r, c - 1) end
    elseif k == "<CR>" then
      vim.api.nvim_buf_set_text(buf, r, c, r, c, { "", "" }); vim.api.nvim_win_set_cursor(0, { r + 2, 0 })
    elseif #k > 0 and not k:match("^<.+>$") or k == "<lt>" then
      local ch = k == "<lt>" and "<" or k
      vim.api.nvim_buf_set_text(buf, r, c, r, c, { ch }); vim.api.nvim_win_set_cursor(0, { r + 1, c + #ch })
    end
    return
  end
  -- normal
  local r, c = cur()
  if S.pending == "d" then
    S.pending = ""
    if k == "d" then vim.api.nvim_buf_set_lines(buf, r, r + 1, false, {}); setcur(r, 0) end
    return
  end
  if k == "E" then error("boom") end
  if k == "h" then setcur(r, c - 1)
  elseif k == "l" then setcur(r, c + 1)
  elseif k == "j" then setcur(r + 1, c)
  elseif k == "k" then setcur(r - 1, c)
  elseif k == "i" then S.mode = "i"
  elseif k == "x" then vim.api.nvim_buf_set_text(buf, r, c, r, c + 1, {}); setcur(r, c)
  elseif k == "d" then S.pending = "d"
  end
end

vim.on_key(function(key, typed)
  local raw = typed ~= "" and typed or key
  local k = vim.fn.keytrans(raw)
  if k == "<C-\\>" then S.panic = S.panic + 1
    if S.panic >= 2 then S.passthrough = not S.passthrough; S.panic = 0 end
    return ""
  end
  S.panic = 0
  if S.passthrough then return nil end
  local ok, err = pcall(handle, k)
  if not ok then S.errors = S.errors + 1; S.last_err = tostring(err); S.mode = "n"; S.pending = "" end
  return ""
end, vim.api.nvim_create_namespace("exp"))

-- paste never goes through on_key: it arrives via nvim_paste() -> vim.paste(). Route it into the same dispatcher.
local orig_paste = vim.paste
vim.paste = function(lines, phase)
  if S.passthrough then return orig_paste(lines, phase) end
  for i, l in ipairs(lines) do
    for _, ch in ipairs(vim.fn.split(l, "\\zs")) do pcall(handle, ch) end
    if i < #lines then pcall(handle, "<CR>") end
  end
  return true
end
