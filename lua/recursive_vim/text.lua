-- UTF-8 aware helpers. All columns are 0-based byte offsets of a character start.
local M = {}

function M.clen(s, c)
  local b = s:byte(c + 1)
  if not b then return 0 end
  if b < 0x80 then return 1 elseif b >= 0xF0 then return 4 elseif b >= 0xE0 then return 3 elseif b >= 0xC0 then return 2 end
  return 1
end

-- start of the next char; may equal #s (one past the end)
function M.next(s, c) return math.min(c + M.clen(s, c), #s) end

function M.prev(s, c)
  if c <= 0 then return 0 end
  c = c - 1
  while c > 0 do
    local b = s:byte(c + 1)
    if b >= 0x80 and b < 0xC0 then c = c - 1 else break end
  end
  return c
end

-- start of the last char (0 for an empty line)
function M.last(s) if #s == 0 then return 0 end return M.prev(s, #s) end

-- snap a byte offset onto a character boundary
function M.snap(s, c)
  c = math.max(0, math.min(c, #s))
  while c > 0 and c < #s do
    local b = s:byte(c + 1)
    if b >= 0x80 and b < 0xC0 then c = c - 1 else break end
  end
  return c
end

function M.class(s, c)
  local b = s:byte(c + 1)
  if not b then return "eol" end
  if b == 32 or b == 9 then return "space" end
  if b >= 0x80 or string.char(b):match("[%w_]") then return "word" end
  return "punct"
end

function M.first_nonblank(s)
  local i = s:find("%S")
  return i and (i - 1) or M.last(s)
end

-- char index (0-based) of byte offset
function M.char_index(s, c)
  local n, i = 0, 0
  while i < c and i < #s do i = M.next(s, i); n = n + 1 end
  return n
end

-- byte offset of char index, clamped to `limit` (default: last char)
function M.byte_of(s, idx, limit)
  limit = limit or M.last(s)
  local i = 0
  while idx > 0 and i < #s do i = M.next(s, i); idx = idx - 1 end
  return math.min(i, limit)
end

return M
