-- One logical editor. Created by the same constructor at every depth; `spawn` is just `new` with a parent.
local api = vim.api
local T = require("recursive_vim.text")
local Keys = require("recursive_vim.keys")
local Buf = require("recursive_vim.buffer")
local Registers = require("recursive_vim.registers")
local Motions = require("recursive_vim.motions")
local Config = require("recursive_vim.config")
local Modes = require("recursive_vim.modes")
local Commands = require("recursive_vim.commands")
local Instances = require("recursive_vim.instances")
local render = require("recursive_vim.render")

local Editor = {}
Editor.__index = Editor

local function label(depth)
  if depth < 26 then return string.char(65 + depth) end
  return "L" .. depth
end

function Editor.new(o)
  o = o or {}
  local self = setmetatable({}, Editor)
  self.id = Instances.next_id()
  self.parent = o.parent
  self.depth = o.parent and o.parent.depth + 1 or 0
  self.name = o.name or label(self.depth)
  self.children = {}
  self.mode, self.row, self.col = "n", 0, 0
  self.nstate, self.mapseq, self.cmd_keys = {}, {}, {}
  self.regs = Registers.new()
  self.opts = vim.deepcopy(Config.DEFAULTS)
  self.buffers = {}
  self.errors, self.messages = {}, {}
  self.hist = { [":"] = {}, ["/"] = {} }
  self.cfg = Config.default_scope(self)
  self.config_path = o.config
  self:_add_buf(Buf.new(self, o.file and self:resolve(o.file) or nil))
  Instances.register(self)
  if self.parent then table.insert(self.parent.children, self) end
  render.open(self)
  self:refresh_options()
  if o.config then self:load_config(o.config) end
  Instances.focus(self)
  self:fire("EditorSpawn")
  return self
end

function Editor:spawn(o)
  if type(o) == "string" then o = { config = o } end
  o = vim.tbl_extend("force", {}, o or {}, { parent = self })
  return Editor.new(o)
end

function Editor:resolve(path)
  if path:sub(1, 1) == "/" then return path end
  if path:sub(1, 2) == "~/" then return vim.env.HOME .. path:sub(2) end
  return Instances.root_dir .. "/" .. path
end

-- configuration ----------------------------------------------------------
function Editor:refresh_options()
  for k, d in pairs(Config.DEFAULTS) do
    local v = self.cfg.opt[k]
    if v == nil then v = d end
    self.opts[k] = v
  end
  render.apply_options(self)
end

-- Run the config in a staging scope; commit only on success (a broken reload keeps the old config).
function Editor:load_config(path)
  local scope, err = Config.build(self, self:resolve(path))
  if not scope then
    err = tostring(err):gsub(vim.pesc(Instances.root_dir) .. "/", "")   -- show project-relative paths
    self:report_error(("config %s: %s"):format(path, err))
    return false
  end
  scope.active = true
  self.cfg, self.config_path = scope, path
  self.mapseq = {}
  self:refresh_options()
  self:fire("ConfigLoaded")
  return true
end

function Editor:reload_config()
  if not self.config_path then self:echo("no config file to reload") return false end
  if self:load_config(self.config_path) then
    self:echo("Reloaded " .. self.config_path)
    return true
  end
  return false
end

function Editor:fire(event, data)
  for _, au in ipairs(self.cfg.autocmds[event] or {}) do
    self:_safe(au.callback, { event = event, data = data })
  end
end

-- messages ---------------------------------------------------------------
function Editor:echo(msg)
  msg = tostring(msg)
  self.message, self.message_err = msg:match("[^\n]*"), false
  self.messages[#self.messages + 1] = msg
end

function Editor:report_error(msg)
  msg = tostring(msg)
  self.errors[#self.errors + 1] = msg
  self.messages[#self.messages + 1] = msg
  self.message, self.message_err = msg:match("[^\n]*"), true
end

function Editor:_safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    self:report_error(err)
    self:recover()
  end
  return ok
end

-- put the editor back into a sane state (used on errors and by the <C-c><C-c><C-c> panic key)
function Editor:recover()
  self.nstate, self.mapseq, self.cmdline = {}, {}, nil
  if self.mode ~= "n" then self:set_mode("n") end
  self.cp_taken, self.changed = false, false
  self:set_cursor(self.row, self.col)
end

-- input ------------------------------------------------------------------
Editor.timeoutlen = 800   -- ms a pending mapping prefix waits for its next key

function Editor:_cancel_timer()
  if self.timer then
    self.timer:stop()
    if not self.timer:is_closing() then self.timer:close() end
    self.timer = nil
  end
end

function Editor:feed(key)
  if self.closed then return end
  self:_cancel_timer()
  self.message = nil
  local ok, err = pcall(self._map_feed, self, key)
  if not ok then self:report_error(err); self:recover() end
  render.refresh(self)
end

function Editor:type(keys)       -- convenience for tests/scripts: "ihello<Esc>" through the mapping layer
  for _, k in ipairs(Keys.parse(keys, self.cfg.g.mapleader)) do self:feed(k) end
end

function Editor:feed_keys(keys)  -- no mappings (like :normal!)
  for _, k in ipairs(type(keys) == "table" and keys or Keys.parse(keys, self.cfg.g.mapleader)) do self:_builtin(k) end
end

function Editor:_map_idle()
  if self.mode == "n" or self.mode == "v" or self.mode == "V" then return Modes.idle(self) end
  return self.mode == "i"
end

function Editor:_map_feed(key)
  local mode = self.mode == "V" and "v" or self.mode
  if not (self.cfg.maps[mode] and next(self.cfg.maps[mode])) or not self:_map_idle() then
    if #self.mapseq > 0 then self:_flush_seq() end
    return self:_builtin(key)
  end
  self.mapseq[#self.mapseq + 1] = key
  self:_resolve_seq()
end

function Editor:_flush_seq()
  local seq = self.mapseq
  self.mapseq = {}
  for _, k in ipairs(seq) do self:_builtin(k) end
end

-- force = the timeout fired: stop waiting for a longer mapping
function Editor:_resolve_seq(force)
  while #self.mapseq > 0 do
    local mode = self.mode == "V" and "v" or self.mode
    local maps = self.cfg.maps[mode]
    local seq = self.mapseq
    local exact, longer = Config.lookup(maps, seq)
    if exact and (force or not longer) then
      self.mapseq = {}
      return self:_run_map(exact)
    elseif longer and not force then
      self.timer = vim.defer_fn(function()
        self.timer = nil
        if self.closed or #self.mapseq == 0 then return end
        local ok, err = pcall(self._resolve_seq, self, true)
        if not ok then self:report_error(err); self:recover() end
        render.refresh(self)
      end, Editor.timeoutlen)
      return
    end
    -- no match for the whole sequence: run the longest mapped prefix, else the first key literally
    local done
    for n = #seq - 1, 1, -1 do
      local e = Config.lookup(maps, { unpack(seq, 1, n) })
      if e then
        self.mapseq = { unpack(seq, n + 1) }
        self:_run_map(e)
        done = true
        break
      end
    end
    if not done then
      local first = table.remove(seq, 1)
      self:_builtin(first)
    end
    if not self:_map_idle() then self:_flush_seq() return end
  end
end

function Editor:_run_map(entry)
  self.cmd_keys = {}
  if type(entry.rhs) == "function" then
    self:_safe(entry.rhs)
  else
    self:feed_keys(entry.rhs)
  end
  self.changed, self.cp_taken = false, false
end

function Editor:_builtin(key)
  if not self.replaying and self.mode == "n" and Modes.idle(self) then self.cmd_keys = {} end
  if not self.replaying then self.cmd_keys[#self.cmd_keys + 1] = key end
  local m = self.mode
  if m == "i" then Modes.insert(self, key)
  elseif m == "c" then Modes.command(self, key)
  else Modes.normal(self, key) end
  if self.mode == "n" and Modes.idle(self) then
    if self.changed and not self.replaying then self.last_change = self.cmd_keys end
    self.changed, self.cp_taken = false, false
  end
end

function Editor:dot_repeat()
  local keys = self.last_change
  if not keys then return end
  self.replaying = true
  local ok, err = pcall(function() for _, k in ipairs(keys) do self:_builtin(k) end end)
  self.replaying = false
  if not ok then error(err, 0) end
end

-- modes ------------------------------------------------------------------
function Editor:set_mode(m)
  if self.mode == m then return end
  local old = self.mode
  self.mode = m
  self:fire("ModeChanged", { old = old, new = m })
end

function Editor:enter_insert() self:set_mode("i") end

function Editor:leave_insert()
  local s = self.buf:line(self.row)
  self:set_mode("n")
  self:set_cursor(self.row, self.col > 0 and T.prev(s, self.col) or 0)
end

function Editor:start_cmdline(prefix)
  self.cmdline = { prefix = prefix, text = "", prev = self.mode }
  self.mode = "c"
end

function Editor:end_cmdline()
  local prev = self.cmdline and self.cmdline.prev or "n"
  self.cmdline = nil
  self.mode = (prev == "v" or prev == "V") and "n" or prev
  self:set_cursor(self.row, self.col)
end

function Editor:search_for(pat)
  self.search = { pat = pat, dir = 1 }
  local r, c = Motions.find(self:ctx(), self.row, self.col, pat, 1)
  if r then self:set_cursor(r, c) else self:echo("E486: Pattern not found: " .. pat) end
end

function Editor:exec(line)
  local ok, err = pcall(Commands.exec, self, line)
  if not ok then self:report_error(err) end
  return ok
end

-- cursor & buffer --------------------------------------------------------
function Editor:ctx()
  local buf = self.buf
  return { n = buf:count(), line = function(r) return buf:line(r) end, want = self.want, search = self.search }
end

function Editor:set_cursor(r, c, keep_want)
  r = math.max(0, math.min(r, self.buf:count() - 1))
  local s = self.buf:line(r)
  local maxc = self.mode == "i" and #s or T.last(s)
  c = T.snap(s, math.max(0, math.min(c, maxc)))
  self.row, self.col = r, c
  if not keep_want then self.want = nil end
end

function Editor:motion(key, count)
  local mo = Motions.defs[key]
  local r, c, keep = mo.fn(self:ctx(), self.row, self.col, count or 1, count ~= nil, {})
  self:set_cursor(r, c, keep)
end

function Editor:_begin_edit()
  if not self.cp_taken then
    self.buf:checkpoint(self, self.row, self.col)
    self.cp_taken = true
  end
  self.changed = true
end

function Editor:replace(sr, sc, er, ec, repl)
  self:_begin_edit()
  self.buf:set_text(self, sr, sc, er, ec, repl)
end

function Editor:replace_lines(s, e, repl)
  self:_begin_edit()
  self.buf:set_lines(self, s, e, repl)
end

function Editor:insert_at_cursor(text)
  local lines = vim.split(text, "\n", { plain = true })
  local r, c = self.row, self.col
  self:replace(r, c, r, c, lines)
  if #lines == 1 then self:set_cursor(r, c + #text) else self:set_cursor(r + #lines - 1, #lines[#lines]) end
end

function Editor:insert_text(text)       -- public: insert at the cursor without changing mode
  local was = self.mode
  if was ~= "i" then self.mode = "i" end   -- allow the cursor to land past the last char while inserting
  self:insert_at_cursor(text)
  if was ~= "i" then
    self.mode = was
    self:set_cursor(self.row, T.prev(self.buf:line(self.row), self.col))
  end
end

function Editor:yank_range(rg, reg, kind)
  local lines
  if rg.linewise then lines = self.buf:lines(rg.sr, rg.er + 1)
  else lines = self.buf:get_text(rg.sr, rg.sc, rg.er, rg.ec) end
  self.regs:set(reg, lines, rg.linewise or false, kind or "yank")
end

function Editor:delete_range(rg, keep_line)
  if rg.linewise then
    if keep_line then
      self:replace_lines(rg.sr, rg.er + 1, { "" })
      self:set_cursor(rg.sr, 0)
    else
      self:replace_lines(rg.sr, rg.er + 1, {})
      local r = math.min(rg.sr, self.buf:count() - 1)
      self:set_cursor(r, T.first_nonblank(self.buf:line(r)))
    end
  else
    if rg.sr == rg.er and rg.sc == rg.ec then return end
    self:replace(rg.sr, rg.sc, rg.er, rg.ec, { "" })
    self:set_cursor(rg.sr, rg.sc)
  end
end

function Editor:replace_chars(ch, n)
  local s = self.buf:line(self.row)
  local e = self.col
  for _ = 1, n do e = T.next(s, e) end
  if e - self.col < 1 or T.char_index(s, e) - T.char_index(s, self.col) < n then return end
  self:replace(self.row, self.col, self.row, e, { ch:rep(n) })
  self:set_cursor(self.row, self.col + #ch * (n - 1))
end

function Editor:put(after, count, reg)
  local e = self.regs:get(reg)
  if not e then return self:echo("E353: Nothing in register " .. (reg or '"')) end
  if e.linewise then
    local lines = {}
    for _ = 1, count do for _, l in ipairs(e.lines) do lines[#lines + 1] = l end end
    local at = after and self.row + 1 or self.row
    self:replace_lines(at, at, lines)
    self:set_cursor(at, T.first_nonblank(lines[1]))
  else
    local s = self.buf:line(self.row)
    local col = (after and #s > 0) and T.next(s, self.col) or self.col
    local text = table.concat(e.lines, "\n"):rep(count)
    local rl = vim.split(text, "\n", { plain = true })
    self:replace(self.row, col, self.row, col, rl)
    if #rl == 1 then self:set_cursor(self.row, T.prev(self.buf:line(self.row), col + #rl[1]))
    else self:set_cursor(self.row, col) end
  end
end

function Editor:undo()
  local s = self.buf:undo_step(self, self.row, self.col)
  if not s then return self:echo("Already at oldest change") end
  self:set_cursor(s.row, s.col)
end

function Editor:redo()
  local s = self.buf:redo_step(self, self.row, self.col)
  if not s then return self:echo("Already at newest change") end
  self:set_cursor(s.row, s.col)
end

-- buffers & files --------------------------------------------------------
function Editor:_add_buf(b)
  table.insert(self.buffers, b)
  self.buf = b
  return b
end

function Editor:switch_buf(b)
  self.buf.row, self.buf.col = self.row, self.col
  self.buf = b
  self.mode, self.nstate, self.mapseq = "n", {}, {}
  api.nvim_win_set_buf(self.win, b.bufnr)
  self.row, self.col = b.row, b.col
  self:refresh_options()
  self:set_cursor(self.row, self.col)
end

function Editor:cycle_buf(d)
  if #self.buffers < 2 then return end
  local idx
  for i, b in ipairs(self.buffers) do if b == self.buf then idx = i end end
  self:switch_buf(self.buffers[(idx - 1 + d) % #self.buffers + 1])
end

function Editor:edit(path, force)
  local abs = self:resolve(path)
  if self.buf.path == abs then
    if force then
      local fresh = Buf.new(self, abs)
      local old = self.buf
      for i, b in ipairs(self.buffers) do if b == old then self.buffers[i] = fresh end end
      self.buf = fresh
      api.nvim_win_set_buf(self.win, fresh.bufnr)
      old:wipe()
      self:refresh_options()
      self:set_cursor(0, 0)
    end
    return
  end
  for _, b in ipairs(self.buffers) do
    if b.path == abs then return self:switch_buf(b) end
  end
  if self.buf:is_dirty() and not force then
    error("E37: No write since last change (add ! to override)", 0)
  end
  local b = Buf.new(self, abs)
  self.buf.row, self.buf.col = self.row, self.col
  table.insert(self.buffers, b)
  self:switch_buf(b)
  self:echo(('"%s"%s'):format(render.display_name(self, b), b.existed and "" or " [New]"))
end

function Editor:save(path)
  local n, bytes = self.buf:write(self, path and self:resolve(path) or nil)
  if not n then self:report_error(bytes) return false end
  self:echo(('"%s" %dL, %dB written'):format(render.display_name(self), n, bytes))
  self:fire("BufWritePost", { file = self.buf.path })
  return true
end

-- focus / lifetime -------------------------------------------------------
function Editor:quit(force)
  if not force then
    for _, b in ipairs(self.buffers) do
      if b:is_dirty() then
        error(("E37: No write since last change (add ! to override)%s"):format(b == self.buf and "" or " [other buffer]"), 0)
      end
    end
  end
  Instances.close(self)
end

function Editor:close()
  self:_cancel_timer()
  if not self.parent and #Instances.roots() <= 1 then return false end
  Instances.close(self)
  return true
end

function Editor:focus_parent()
  if not self.parent then return false end
  Instances.focus(self.parent)
  return true
end

function Editor:snapshot()
  local maps = {}
  for m, t in pairs(self.cfg.maps) do
    maps[m] = {}
    for _, e in pairs(t) do maps[m][#maps[m] + 1] = e.lhs end
    table.sort(maps[m])
  end
  local cmds = vim.tbl_keys(self.cfg.cmds)
  table.sort(cmds)
  return {
    id = self.id, name = self.name, depth = self.depth, parent = self.parent and self.parent.id,
    children = vim.tbl_map(function(c) return c.id end, self.children),
    mode = self.mode, row = self.row, col = self.col, lines = self.buf:lines(), path = self.buf.path,
    dirty = self.buf:is_dirty(), message = self.message, message_err = self.message_err,
    errors = self.errors, opts = self.opts, maps = maps, cmds = cmds, config = self.config_path,
    win_number = api.nvim_get_option_value("number", { win = self.win }),
    win_visible = not api.nvim_win_get_config(self.win).hide,
    bufnr = self.buf.bufnr, buf_id = self.buf.id, nbuffers = #self.buffers,
    reg = self.regs:get() and self.regs:get().lines or vim.NIL,
    focused = Instances.focused == self,
  }
end

return Editor
