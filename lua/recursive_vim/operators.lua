-- Operators act on a RANGE. Motions/text objects produce ranges; nothing here knows about keys.
-- range = { sr, sc, er, ec, linewise }   (charwise: end is exclusive)
local T = require("recursive_vim.text")
local M = {}

-- motion result -> range
function M.range_from_motion(ctx, r1, c1, r2, c2, kind)
  if kind == "linewise" then
    return { sr = math.min(r1, r2), er = math.max(r1, r2), linewise = true }
  end
  if r2 < r1 or (r2 == r1 and c2 < c1) then r1, c1, r2, c2 = r2, c2, r1, c1 end
  if kind == "inclusive" then c2 = T.next(ctx.line(r2), c2) end
  return { sr = r1, sc = c1, er = r2, ec = c2 }
end

function M.linewise_range(ctx, row, count)
  return { sr = row, er = math.min(row + count - 1, ctx.n - 1), linewise = true }
end

-- text objects: iw / aw
function M.textobject(ctx, r, c, which, key, count)
  if key ~= "w" then return nil end
  local s = ctx.line(r)
  if #s == 0 then return nil end
  local k = T.class(s, c)
  local function run_end(pos, kind)
    while true do
      local n = T.next(s, pos)
      if n >= #s or T.class(s, n) ~= kind then return n end
      pos = n
    end
  end
  local a = c
  while a > 0 do
    local p = T.prev(s, a)
    if T.class(s, p) ~= k then break end
    a = p
  end
  local e = run_end(c, k)           -- exclusive end of the run
  if which == "a" then
    if k ~= "space" and e < #s and T.class(s, e) == "space" then e = run_end(e, "space")
    elseif k ~= "space" then
      while a > 0 and T.class(s, T.prev(s, a)) == "space" do a = T.prev(s, a) end
    end
  end
  for _ = 2, count do
    if e >= #s then break end
    e = run_end(e, T.class(s, e))
  end
  return { sr = r, sc = a, er = r, ec = e }
end

-- operator implementations: fn(editor, range, regname)
M.defs = {
  y = function(ed, rg, reg)
    ed:yank_range(rg, reg)
    ed:set_cursor(rg.sr, rg.linewise and ed.col or rg.sc)
  end,
  d = function(ed, rg, reg)
    ed:yank_range(rg, reg, "delete")
    ed:delete_range(rg)
  end,
  c = function(ed, rg, reg)
    ed:yank_range(rg, reg, "delete")
    ed:enter_insert()            -- first, so the cursor may sit past the last char
    ed:delete_range(rg, true)
  end,
}

return M
