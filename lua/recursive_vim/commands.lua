-- Ex commands (":w", ":e foo", ...) plus per-editor user commands.
local Config = require("recursive_vim.config")
local M = {}

local ALIAS = {
  w = "write", write = "write", q = "quit", quit = "quit", wq = "wq", x = "wq", xit = "wq",
  e = "edit", edit = "edit", se = "set", set = "set", so = "source", source = "source", lua = "lua",
  reload = "reload", spawn = "spawn", close = "close", parent = "parent", child = "child", echo = "echo",
  noh = "noh", ls = "ls", messages = "messages", bn = "bnext", bnext = "bnext", bp = "bprev", bprev = "bprev",
}

local H = {}
function H.write(ed, args) ed:save(args ~= "" and args or nil) end
function H.quit(ed, _, bang) ed:quit(bang) end
function H.wq(ed, args, bang) if ed:save(args ~= "" and args or nil) then ed:quit(bang) end end
function H.edit(ed, args, bang) ed:edit(args ~= "" and args or ed.buf.path, bang) end
function H.reload(ed) ed:reload_config() end
function H.spawn(ed, args) ed:spawn({ config = args ~= "" and args or nil }) end
function H.close(ed) if not ed:close() then ed:echo("E444: Cannot close last editor") end end
function H.parent(ed) if not ed:focus_parent() then ed:echo("no parent editor") end end
function H.child(ed, args)
  local c = args ~= "" and ed.children[tonumber(args)] or ed.active_child or ed.children[#ed.children]
  if c then require("recursive_vim.instances").focus(c) else ed:echo("no child editor") end
end
function H.echo(ed, args) ed:echo(args) end
function H.noh() end
function H.ls(ed)
  local t = {}
  for i, b in ipairs(ed.buffers) do
    t[#t + 1] = ("%d%s %s%s"):format(i, b == ed.buf and "%" or "", require("recursive_vim.render").display_name(ed, b), b:is_dirty() and " +" or "")
  end
  ed:echo(table.concat(t, " | "))
end
function H.messages(ed) ed:echo(table.concat(ed.messages, " | ")) end
function H.bnext(ed) ed:cycle_buf(1) end
function H.bprev(ed) ed:cycle_buf(-1) end
function H.source(ed, args)
  if args == "" then error("E471: Argument required", 0) end
  Config.exec_file(ed, ed:resolve(args))
end
function H.lua(ed, args) Config.exec(ed, args, "=:lua") end
function H.set(ed, args)
  local opt = ed.cfg.vim.opt
  for tok in args:gmatch("%S+") do
    local name, val = tok:match("^(%w+)=(.+)$")
    if name then
      opt[name] = tonumber(val) or val
    elseif tok:sub(-1) == "?" then
      ed:echo(tok:sub(1, -2) .. "=" .. tostring(opt[tok:sub(1, -2)]))
    elseif tok:sub(-1) == "!" then
      local n = tok:sub(1, -2); opt[n] = not opt[n]
    elseif Config.DEFAULTS[tok] ~= nil then
      opt[tok] = true
    elseif tok:sub(1, 2) == "no" and Config.DEFAULTS[tok:sub(3)] ~= nil then
      opt[tok:sub(3)] = false
    else
      error("E518: Unknown option: " .. tok, 0)
    end
  end
end

function M.exec(ed, line)
  local range, name, bang, args = line:match("^%s*([%$%d]*)(%a[%w_]*)(!?)%s*(.-)%s*$")
  if not name then
    local r = line:match("^%s*([%$%d]+)%s*$")
    if r then ed:set_cursor(r == "$" and ed.buf:count() - 1 or tonumber(r) - 1, 0) return end
    if line:match("^%s*$") then return end
    error("E492: Not an editor command: " .. line, 0)
  end
  local uc = ed.cfg.cmds[name]
  if uc then
    if type(uc.rhs) == "string" then return M.exec(ed, uc.rhs) end
    return uc.rhs({ name = name, args = args, fargs = vim.split(args, "%s+", { trimempty = true }), bang = bang == "!" })
  end
  local h = H[ALIAS[name] or ""]
  if not h then error("E492: Not an editor command: " .. name, 0) end
  if range ~= "" and ALIAS[name] ~= "write" then ed:set_cursor(range == "$" and ed.buf:count() - 1 or tonumber(range) - 1, 0) end
  return h(ed, args, bang == "!")
end

return M
