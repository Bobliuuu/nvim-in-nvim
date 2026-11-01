-- Modal state machine. Normal mode is a small parser:
--   [register] [count] operator [count] (motion | text-object)   or   [count] command
-- Operators (operators.lua) and motions (motions.lua) never know about each other; this file composes them.
local T = require("recursive_vim.text")
local Keys = require("recursive_vim.keys")
local Motions = require("recursive_vim.motions")
local Ops = require("recursive_vim.operators")
local M = {}

local ALIAS = {
  ["<Left>"] = "h", ["<Right>"] = "l", ["<Up>"] = "k", ["<Down>"] = "j", ["<Home>"] = "0", ["<End>"] = "$",
  ["<BS>"] = "h", [" "] = "l", ["<C-h>"] = "h", ["<NL>"] = "j",
}

-- commands that are just other keys in disguise (composition in action)
local EXPAND = {
  x = { "d", "l" }, X = { "d", "h" }, D = { "d", "$" }, C = { "c", "$" }, s = { "c", "l" }, S = { "c", "c" },
  Y = { "y", "y" },
}

function M.idle(ed)
  local s = ed.nstate
  return not (s.count or s.opcount or s.op or s.prefix or s.reg)
end

local function total(st) return (st.count or 1) * (st.opcount or 1), (st.count or st.opcount) ~= nil end

local function visual_range(ed)
  local a = ed.vanchor
  local r1, c1, r2, c2 = a[1], a[2], ed.row, ed.col
  if ed.mode == "V" then return { sr = math.min(r1, r2), er = math.max(r1, r2), linewise = true } end
  return Ops.range_from_motion(ed:ctx(), r1, c1, r2, c2, "inclusive")
end

local function apply(ed, op, rg, reg)
  ed.nstate = {}
  Ops.defs[op](ed, rg, reg)
end

local CMDS = {}
CMDS.i = function(ed) ed:enter_insert() end
CMDS.a = function(ed)
  local s = ed.buf:line(ed.row)
  ed:enter_insert()
  if #s > 0 then ed:set_cursor(ed.row, T.next(s, ed.col)) end
end
CMDS.I = function(ed) ed:enter_insert(); ed:set_cursor(ed.row, #ed.buf:line(ed.row) > 0 and T.first_nonblank(ed.buf:line(ed.row)) or 0) end
CMDS.A = function(ed) ed:enter_insert(); ed:set_cursor(ed.row, #ed.buf:line(ed.row)) end
CMDS.o = function(ed)
  ed:enter_insert()
  ed:replace_lines(ed.row + 1, ed.row + 1, { "" })
  ed:set_cursor(ed.row + 1, 0)
end
CMDS.O = function(ed)
  ed:enter_insert()
  ed:replace_lines(ed.row, ed.row, { "" })
  ed:set_cursor(ed.row, 0)
end
CMDS.p = function(ed, n, _, st) ed:put(true, n, st.reg) end
CMDS.P = function(ed, n, _, st) ed:put(false, n, st.reg) end
CMDS.u = function(ed, n) for _ = 1, n do ed:undo() end end
CMDS["<C-r>"] = function(ed, n) for _ = 1, n do ed:redo() end end
CMDS["."] = function(ed) ed:dot_repeat() end
CMDS[":"] = function(ed) ed:start_cmdline(":") end
CMDS["/"] = function(ed) ed:start_cmdline("/") end
CMDS.J = function(ed, n)
  for _ = 1, math.max(n - 1, 1) do
    if ed.row + 1 >= ed.buf:count() then break end
    local a, b = ed.buf:line(ed.row), ed.buf:line(ed.row + 1)
    b = b:gsub("^%s+", "")
    local joined = (#a > 0 and #b > 0) and (a .. " " .. b) or (a .. b)
    ed:replace_lines(ed.row, ed.row + 2, { joined })
    ed:set_cursor(ed.row, #a)
  end
end
CMDS.v = function(ed)
  if ed.mode == "v" then return ed:set_mode("n") end
  if ed.mode == "n" then ed.vanchor = { ed.row, ed.col } end
  ed:set_mode("v")
end
CMDS.V = function(ed)
  if ed.mode == "V" then return ed:set_mode("n") end
  if ed.mode == "n" then ed.vanchor = { ed.row, ed.col } end
  ed:set_mode("V")
end
CMDS.o_visual = function(ed)
  local a = ed.vanchor
  ed.vanchor = { ed.row, ed.col }
  ed:set_cursor(a[1], a[2])
end

function M.normal(ed, key)
  local st = ed.nstate
  local visual = ed.mode ~= "n"
  key = ALIAS[key] or key

  if key == "<Esc>" or key == "<C-c>" then
    ed.nstate = {}
    if visual then ed:set_mode("n"); ed:set_cursor(ed.row, ed.col) end
    return
  end

  local prefix = st.prefix
  st.prefix = nil
  if prefix == '"' then
    if key:match("^[%w\"_]$") then st.reg = key else ed.nstate = {} end
    return
  elseif prefix == "r" then
    local n = total(st)
    ed.nstate = {}
    if Keys.is_printable(key) then ed:replace_chars(key, n) end
    return
  elseif prefix == "i" or prefix == "a" then
    local n = total(st)
    local rg = Ops.textobject(ed:ctx(), ed.row, ed.col, prefix, key, n)
    if not rg then ed.nstate = {} return end
    if visual then
      ed.nstate = {}
      ed.vanchor = { rg.sr, rg.sc }
      ed:set_cursor(rg.er, T.prev(ed.buf:line(rg.er), rg.ec))
    else
      apply(ed, st.op, rg, st.reg)
    end
    return
  elseif prefix == "g" then
    key = "g" .. key
  end

  -- counts ----------------------------------------------------------------
  if key:match("^%d$") and (key ~= "0" or (st.op and st.opcount or st.count)) then
    local d = tonumber(key)
    if st.op then st.opcount = (st.opcount or 0) * 10 + d else st.count = (st.count or 0) * 10 + d end
    return
  end

  if key == '"' then st.prefix = '"' return end
  if key == "g" then st.prefix = "g" return end
  if key == "r" and not visual then st.prefix = "r" return end
  if (key == "i" or key == "a") and (st.op or visual) then st.prefix = key return end

  local count, has = total(st)

  -- operators -------------------------------------------------------------
  if Ops.defs[key] then
    if visual then
      local rg, reg = visual_range(ed), st.reg
      ed:set_mode("n")
      return apply(ed, key, rg, reg)
    end
    if not st.op then st.op = key return end
    if st.op == key then
      local rg = Ops.linewise_range(ed:ctx(), ed.row, count)
      return apply(ed, key, rg, st.reg)
    end
    ed.nstate = {}
    return
  end
  if visual and key == "x" then return M.normal(ed, "d") end

  -- motions ---------------------------------------------------------------
  local mo = Motions.defs[key]
  if mo then
    local o = { op = st.op ~= nil }
    local def = mo
    if st.op == "c" and key == "w" then
      local s = ed.buf:line(ed.row)
      if #s > 0 and T.class(s, ed.col) ~= "space" then def, o.cw = Motions.defs.e, true end
    end
    local ctx = ed:ctx()
    local r, c, keep = def.fn(ctx, ed.row, ed.col, count, has, o)
    if st.op then
      if mo.vertical and r == ed.row then ed.nstate = {} return end
      return apply(ed, st.op, Ops.range_from_motion(ctx, ed.row, ed.col, r, c, def.kind), st.reg)
    end
    ed.nstate = {}
    ed:set_cursor(r, c, keep)
    return
  end

  -- everything below needs "no operator pending"
  if st.op then ed.nstate = {} return end

  if visual and key == "o" then ed.nstate = {} return CMDS.o_visual(ed) end

  local exp = EXPAND[key]
  if exp then
    if visual then ed.nstate = {} return end
    for _, k in ipairs(exp) do M.normal(ed, k) end
    return
  end

  local cmd = CMDS[key]
  if cmd and not (visual and not (key == "v" or key == "V" or key == "u" or key == ":")) then
    local s = st
    ed.nstate = {}
    cmd(ed, count, has, s)
    return
  end
  ed.nstate = {}
end

function M.insert(ed, key)
  local r, c = ed.row, ed.col
  local s = ed.buf:line(r)
  key = ({ ["<C-c>"] = "<Esc>", ["<C-h>"] = "<BS>", ["<C-m>"] = "<CR>", ["<NL>"] = "<CR>", ["<C-i>"] = "<Tab>" })[key] or key
  if key == "<Esc>" then
    ed:leave_insert()
  elseif key == "<CR>" then
    ed:insert_at_cursor("\n")
  elseif key == "<BS>" then
    if c > 0 then
      local p = T.prev(s, c)
      ed:replace(r, p, r, c, { "" })
      ed:set_cursor(r, p)
    elseif r > 0 then
      local plen = #ed.buf:line(r - 1)
      ed:replace(r - 1, plen, r, 0, { "" })
      ed:set_cursor(r - 1, plen)
    end
  elseif key == "<Del>" then
    if c < #s then ed:replace(r, c, r, T.next(s, c), { "" })
    elseif r + 1 < ed.buf:count() then ed:replace(r, c, r + 1, 0, { "" }) end
  elseif key == "<Tab>" then
    ed:insert_at_cursor(ed.opts.expandtab and (" "):rep(ed.opts.tabstop) or "\t")
  elseif key == "<Left>" then ed:set_cursor(r, T.prev(s, c))
  elseif key == "<Right>" then ed:set_cursor(r, T.next(s, c))
  elseif key == "<Up>" then ed:set_cursor(r - 1, c)
  elseif key == "<Down>" then ed:set_cursor(r + 1, c)
  elseif key == "<Home>" then ed:set_cursor(r, 0)
  elseif key == "<End>" then ed:set_cursor(r, #s)
  elseif Keys.is_printable(key) then
    ed:insert_at_cursor(key)
  end
end

function M.command(ed, key)
  local cl = ed.cmdline
  if key == "<Esc>" or key == "<C-c>" then
    ed:end_cmdline()
  elseif key == "<CR>" or key == "<NL>" then
    local prefix, text = cl.prefix, cl.text
    ed:end_cmdline()
    if text ~= "" then table.insert(ed.hist[prefix], text) end
    if prefix == ":" then ed:exec(text) else ed:search_for(text) end
  elseif key == "<BS>" or key == "<C-h>" then
    if cl.text == "" then ed:end_cmdline()
    else cl.text = cl.text:sub(1, T.prev(cl.text, #cl.text)) end
  elseif key == "<C-u>" then cl.text = ""
  elseif key == "<C-w>" then cl.text = cl.text:gsub("%S*%s*$", "")
  elseif key == "<Up>" or key == "<Down>" then
    local h = ed.hist[cl.prefix]
    cl.hi = math.max(0, math.min((cl.hi or #h + 1) + (key == "<Up>" and -1 or 1), #h + 1))
    cl.text = h[cl.hi] or ""
  elseif Keys.is_printable(key) then
    cl.text = cl.text .. key
  elseif key == "<Tab>" then cl.text = cl.text .. "\t"
  end
end

return M
