-- A Buf wraps a real Neovim scratch buffer and is OWNED by exactly one editor.
-- Every mutation takes the calling editor and refuses if it is not the owner.
-- Native undo is disabled; undo/redo are our own snapshot stacks.
local api = vim.api
local Buf = {}
Buf.__index = Buf

local next_id = 0
local UNDO_LIMIT = 500

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function Buf.new(owner, path)
  next_id = next_id + 1
  local b = setmetatable({ id = next_id, owner = owner, path = path, undo = {}, redo = {}, row = 0, col = 0 }, Buf)
  b.bufnr = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("undolevels", -1, { buf = b.bufnr })
  local lines = { "" }
  b.final_nl = true
  if path then
    local data = read_file(path)
    if data then
      lines = vim.split(data, "\n", { plain = true })
      b.final_nl = lines[#lines] == ""
      if b.final_nl and #lines > 1 then table.remove(lines) end
      b.existed = true
    end
  end
  api.nvim_buf_set_lines(b.bufnr, 0, -1, false, lines)
  b.saved = table.concat(lines, "\n")
  if path and path:match("%.lua$") then pcall(vim.treesitter.start, b.bufnr, "lua") end
  return b
end

function Buf:guard(ed)
  if ed ~= self.owner then
    error(("buffer #%d is owned by editor #%d, editor #%s may not modify it"):format(
      self.id, self.owner.id, ed and ed.id or "?"), 3)
  end
end

function Buf:count() return api.nvim_buf_line_count(self.bufnr) end
function Buf:line(r) return api.nvim_buf_get_lines(self.bufnr, r, r + 1, false)[1] or "" end
function Buf:lines(s, e) return api.nvim_buf_get_lines(self.bufnr, s or 0, e or -1, false) end
function Buf:get_text(sr, sc, er, ec) return api.nvim_buf_get_text(self.bufnr, sr, sc, er, ec, {}) end

function Buf:set_lines(ed, s, e, repl)
  self:guard(ed)
  api.nvim_buf_set_lines(self.bufnr, s, e, false, repl)
  if self:count() == 0 then api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "" }) end
end

function Buf:set_text(ed, sr, sc, er, ec, repl)
  self:guard(ed)
  api.nvim_buf_set_text(self.bufnr, sr, sc, er, ec, repl)
end

-- undo -------------------------------------------------------------------
function Buf:snapshot(row, col) return { lines = self:lines(), row = row, col = col } end

function Buf:checkpoint(ed, row, col)
  self:guard(ed)
  self.undo[#self.undo + 1] = self:snapshot(row, col)
  if #self.undo > UNDO_LIMIT then table.remove(self.undo, 1) end
  self.redo = {}
end

local function swap(self, ed, from, to, row, col)
  self:guard(ed)
  local s = table.remove(from)
  if not s then return nil end
  to[#to + 1] = self:snapshot(row, col)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, s.lines)
  return s
end
function Buf:undo_step(ed, row, col) return swap(self, ed, self.undo, self.redo, row, col) end
function Buf:redo_step(ed, row, col) return swap(self, ed, self.redo, self.undo, row, col) end

-- files ------------------------------------------------------------------
function Buf:is_dirty() return table.concat(self:lines(), "\n") ~= self.saved end

function Buf:write(ed, path)
  self:guard(ed)
  path = path or self.path
  if not path then return nil, "E32: No file name" end
  local lines = self:lines()
  local f, err = io.open(path, "wb")
  if not f then return nil, "E212: Can't open file for writing: " .. tostring(err) end
  local data = table.concat(lines, "\n") .. (self.final_nl and "\n" or "")
  f:write(data)
  f:close()
  self.path = path
  self.saved = table.concat(lines, "\n")
  return #lines, #data
end

function Buf:wipe()
  if api.nvim_buf_is_valid(self.bufnr) then pcall(api.nvim_buf_delete, self.bufnr, { force = true }) end
end

return Buf
