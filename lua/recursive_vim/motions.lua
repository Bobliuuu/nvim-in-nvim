-- Motions are pure functions of (ctx, row, col, count, has_count, opts) -> row, col [, keep_want].
-- ctx = { n = line count, line = function(r) -> string, want = char index|nil, search = {pat,dir}|nil }
-- kind: "exclusive" | "inclusive" | "linewise"
local T = require("recursive_vim.text")
local M = {}

function M.ctx_from_lines(lines, want)
  return { n = #lines, line = function(r) return lines[r + 1] or "" end, want = want }
end

local function fwd(ctx, r, c)
  local s = ctx.line(r)
  local n = T.next(s, c)
  if n < #s then return r, n end
  if r + 1 < ctx.n then return r + 1, 0 end
  return nil
end

local function back(ctx, r, c)
  if c > 0 then return r, T.prev(ctx.line(r), c) end
  if r > 0 then return r - 1, T.last(ctx.line(r - 1)) end
  return nil
end

local function eof_pos(ctx, r, op) local s = ctx.line(r); return r, op and #s or T.last(s) end

local function w1(ctx, r, c, op)
  local start = T.class(ctx.line(r), c)
  if start == "word" or start == "punct" then
    while true do
      local nr, nc = fwd(ctx, r, c)
      if not nr then return eof_pos(ctx, r, op) end
      local crossed = nr ~= r
      r, c = nr, nc
      if crossed or T.class(ctx.line(r), c) ~= start then break end
    end
  else
    local nr, nc = fwd(ctx, r, c)
    if not nr then return eof_pos(ctx, r, op) end
    r, c = nr, nc
  end
  while T.class(ctx.line(r), c) == "space" do
    local nr, nc = fwd(ctx, r, c)
    if not nr then return eof_pos(ctx, r, op) end
    r, c = nr, nc
  end
  return r, c
end

local function b1(ctx, r, c)
  local nr, nc = back(ctx, r, c)
  if not nr then return r, c end
  r, c = nr, nc
  while T.class(ctx.line(r), c) == "space" do
    local pr, pc = back(ctx, r, c)
    if not pr then return r, c end
    r, c = pr, pc
  end
  local s = ctx.line(r)
  local k = T.class(s, c)
  if k == "eol" then return r, 0 end
  while c > 0 do
    local pc = T.prev(s, c)
    if T.class(s, pc) ~= k then break end
    c = pc
  end
  return r, c
end

local function e1(ctx, r, c, stay)
  local s = ctx.line(r)
  if stay and #s > 0 then
    local k = T.class(s, c)
    if k ~= "space" then
      local n = T.next(s, c)
      if n >= #s or T.class(s, n) ~= k then return r, c end
    end
  end
  local nr, nc = fwd(ctx, r, c)
  if not nr then return r, c end
  r, c = nr, nc
  while true do
    local k = T.class(ctx.line(r), c)
    if k ~= "space" and k ~= "eol" then break end
    local pr, pc = fwd(ctx, r, c)
    if not pr then return r, c end
    r, c = pr, pc
  end
  local s2 = ctx.line(r)
  local k = T.class(s2, c)
  while true do
    local n = T.next(s2, c)
    if n >= #s2 or T.class(s2, n) ~= k then break end
    c = n
  end
  return r, c
end

local function vertical(ctx, r, c, nr)
  nr = math.max(0, math.min(nr, ctx.n - 1))
  local want = ctx.want or T.char_index(ctx.line(r), c)
  return nr, T.byte_of(ctx.line(nr), want), true
end

M.defs = {
  h = { kind = "exclusive", fn = function(ctx, r, c, n)
    local s = ctx.line(r)
    for _ = 1, n do c = T.prev(s, c) end
    return r, c
  end },
  l = { kind = "exclusive", fn = function(ctx, r, c, n, _, o)
    local s = ctx.line(r)
    local limit = o.op and #s or T.last(s)
    for _ = 1, n do c = math.min(T.next(s, c), limit) end
    return r, c
  end },
  j = { kind = "linewise", vertical = true, fn = function(ctx, r, c, n) return vertical(ctx, r, c, r + n) end },
  k = { kind = "linewise", vertical = true, fn = function(ctx, r, c, n) return vertical(ctx, r, c, r - n) end },
  w = { kind = "exclusive", fn = function(ctx, r, c, n, _, o)
    for i = 1, n do
      local r0 = r
      r, c = w1(ctx, r, c, o.op)
      if o.op and i == n and r > r0 then r, c = r0, #ctx.line(r0) end
    end
    return r, c
  end },
  b = { kind = "exclusive", fn = function(ctx, r, c, n)
    for _ = 1, n do r, c = b1(ctx, r, c) end
    return r, c
  end },
  e = { kind = "inclusive", fn = function(ctx, r, c, n, _, o)
    for i = 1, n do r, c = e1(ctx, r, c, o.cw and i == 1) end
    return r, c
  end },
  ["0"] = { kind = "exclusive", fn = function(_, r) return r, 0 end },
  ["^"] = { kind = "exclusive", fn = function(ctx, r) return r, T.first_nonblank(ctx.line(r)) end },
  ["$"] = { kind = "inclusive", fn = function(ctx, r, _, n)
    r = math.min(r + n - 1, ctx.n - 1)
    return r, T.last(ctx.line(r)), false
  end },
  gg = { kind = "linewise", fn = function(ctx, _, _, n, has)
    local r = has and math.min(n - 1, ctx.n - 1) or 0
    return r, T.first_nonblank(ctx.line(r))
  end },
  G = { kind = "linewise", fn = function(ctx, _, _, n, has)
    local r = has and math.min(n - 1, ctx.n - 1) or ctx.n - 1
    return r, T.first_nonblank(ctx.line(r))
  end },
}

-- plain-text search with wrap-around. dir = 1 | -1. Returns row, col or nil.
function M.find(ctx, r, c, pat, dir)
  if not pat or pat == "" then return nil end
  for i = 0, ctx.n do
    local row = ((r + dir * i) % ctx.n)
    local s = ctx.line(row)
    if dir == 1 then
      local from = (i == 0) and (c + math.max(T.clen(s, c), 1) + 1) or 1
      local a = s:find(pat, from, true)
      if a then return row, a - 1 end
    else
      local last, init = nil, 1
      while true do
        local a = s:find(pat, init, true)
        if not a then break end
        if i ~= 0 or a - 1 < c then last = a - 1 end
        init = a + 1
      end
      if last then return row, last end
    end
  end
  return nil
end

M.defs.n = { kind = "exclusive", fn = function(ctx, r, c, n)
  local s = ctx.search; if not s then return r, c end
  for _ = 1, n do local nr, nc = M.find(ctx, r, c, s.pat, s.dir); if nr then r, c = nr, nc end end
  return r, c
end }
M.defs.N = { kind = "exclusive", fn = function(ctx, r, c, n)
  local s = ctx.search; if not s then return r, c end
  for _ = 1, n do local nr, nc = M.find(ctx, r, c, s.pat, -s.dir); if nr then r, c = nr, nc end end
  return r, c
end }

return M
