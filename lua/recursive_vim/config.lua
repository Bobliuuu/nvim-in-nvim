-- Configuration runtime. Every editor gets its OWN virtual `vim` and its OWN Lua environment.
-- A config file is executed with load(src, name, "t", env): the host's `vim` global is simply
-- not in env. NOTE: this isolates *state*, it is not a security sandbox (env.os / env.io exist;
-- configs are trusted code).
local Keys = require("recursive_vim.keys")
local M = {}

M.DEFAULTS = {
  number = false,
  relativenumber = false,
  cursorline = false,
  wrap = true,
  tabstop = 8,
  expandtab = false,
  scrolloff = 0,
  timeoutlen = 800,
  signcolumn = "no",
}

-- a "scope" is everything one execution of a config file defined; replacing it = reload
function M.new_scope(path)
  return { path = path, opt = {}, g = {}, maps = {}, cmds = {}, autocmds = {}, loaded = {}, active = false }
end

local function make_opt(ed, scope)
  return setmetatable({}, {
    __index = function(_, k)
      local d = M.DEFAULTS[k]
      if d == nil then error("E518: Unknown option: " .. tostring(k), 2) end
      local v = scope.opt[k]
      if v == nil then v = d end
      return v
    end,
    __newindex = function(_, k, v)
      local d = M.DEFAULTS[k]
      if d == nil then error("E518: Unknown option: " .. tostring(k), 2) end
      if type(v) ~= type(d) then
        error(("E474: Invalid argument: %s=%s (expected %s)"):format(k, tostring(v), type(d)), 2)
      end
      scope.opt[k] = v
      if scope.active then ed:refresh_options() end
    end,
  })
end

local function make_vim(ed, scope)
  local V = {}
  V.opt = make_opt(ed, scope)
  V.o, V.wo, V.bo = V.opt, V.opt, V.opt
  V.g = scope.g

  V.keymap = {
    set = function(mode, lhs, rhs, opts)
      opts = opts or {}
      for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
        if m == "x" then m = "v" end
        if not (m == "n" or m == "i" or m == "v") then error("unsupported mapping mode: " .. tostring(m), 2) end
        scope.maps[m] = scope.maps[m] or {}
        local keys = Keys.parse(lhs, scope.g.mapleader)
        scope.maps[m][table.concat(keys, "\0")] = { keys = keys, rhs = rhs, lhs = lhs, desc = opts.desc }
      end
    end,
    del = function(mode, lhs)
      for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
        local keys = Keys.parse(lhs, scope.g.mapleader)
        if scope.maps[m] then scope.maps[m][table.concat(keys, "\0")] = nil end
      end
    end,
  }

  V.api = {
    nvim_create_user_command = function(name, rhs, opts)
      if not tostring(name):match("^%u") then
        error("E183: User defined commands must start with an uppercase letter", 2)
      end
      scope.cmds[name] = { rhs = rhs, opts = opts or {} }
    end,
    nvim_del_user_command = function(name) scope.cmds[name] = nil end,
    nvim_create_autocmd = function(event, o)
      for _, e in ipairs(type(event) == "table" and event or { event }) do
        scope.autocmds[e] = scope.autocmds[e] or {}
        table.insert(scope.autocmds[e], o)
      end
    end,
    nvim_buf_get_lines = function(_, s, e) return ed.buf:lines(s, e) end,
    nvim_buf_set_lines = function(_, s, e, _, repl)
      ed:replace_lines(s, e, repl)
      ed:set_cursor(ed.row, ed.col)
    end,
    nvim_get_current_line = function() return ed.buf:line(ed.row) end,
    nvim_win_get_cursor = function() return { ed.row + 1, ed.col } end,
    nvim_win_set_cursor = function(_, pos) ed:set_cursor(pos[1] - 1, pos[2]) end,
  }

  V.editor = {
    move_left = function(n) ed:motion("h", n) end,
    move_right = function(n) ed:motion("l", n) end,
    move_up = function(n) ed:motion("k", n) end,
    move_down = function(n) ed:motion("j", n) end,
    motion = function(key, n) ed:motion(key, n) end,
    echo = function(msg) ed:echo(msg) end,
    insert_text = function(text) ed:insert_text(text) end,
    mode = function() return ed.mode end,
    get_line = function() return ed.buf:line(ed.row) end,
    get_lines = function() return ed.buf:lines() end,
    cursor = function() return { ed.row + 1, ed.col } end,
    feed = function(keys) ed:feed_keys(keys) end,
    exec = function(cmd) ed:exec(cmd) end,
    spawn = function(o) return ed:spawn(o) end,
    parent = function() return ed.parent end,
    children = function() return ed.children end,
    focus_parent = function() return ed:focus_parent() end,
    close = function() return ed:close() end,
    reload_config = function() return ed:reload_config() end,
    edit = function(path) return ed:edit(path) end,
    save = function(path) return ed:save(path) end,
    depth = function() return ed.depth end,
    id = function() return ed.id end,
    name = function() return ed.name end,
    scratch = function(lines)        -- replace the buffer without marking it modified or touching undo
      ed.buf:init_lines(lines)
      ed:set_cursor(0, 0)
    end,
    root = function() return require("recursive_vim.instances").root_dir end,
  }

  V.cmd = function(s) ed:exec(s) end
  V.notify = function(msg, level) if level and level >= 4 then ed:report_error(msg) else ed:echo(msg) end end
  V.print = function(...) ed:echo(table.concat(vim.tbl_map(tostring, { ... }), " ")) end
  V.inspect = vim.inspect
  V.split, V.trim, V.startswith, V.endswith = vim.split, vim.trim, vim.startswith, vim.endswith
  V.deepcopy, V.tbl_extend, V.tbl_contains, V.tbl_keys = vim.deepcopy, vim.tbl_extend, vim.tbl_contains, vim.tbl_keys
  V.is_virtual = true
  return V
end

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "xpcall", "select", "tonumber", "tostring",
  "type", "unpack", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "string", "table", "math",
  "os", "io", "bit" }

local function load_in_env(src, chunk, env)
  local fn, err = load(src, chunk, "t", env)
  if fn then return fn end
  if setfenv and loadstring then      -- plain 5.1 fallback
    fn = loadstring(src, chunk)
    if fn then setfenv(fn, env) return fn end
  end
  return nil, err
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function make_env(ed, scope, V)
  local env = { vim = V }
  for _, k in ipairs(SAFE) do env[k] = _G[k] end
  env.unpack = unpack or table.unpack
  env._G = env
  env.print = V.print
  local dir = scope.path and scope.path:match("^(.*)/[^/]*$")
  env.require = function(name)
    if scope.loaded[name] ~= nil then return scope.loaded[name] end
    local rel = name:gsub("%.", "/")
    for _, cand in ipairs({ dir and (dir .. "/lua/" .. rel .. ".lua"), dir and (dir .. "/" .. rel .. ".lua") }) do
      local src = cand and read(cand)
      if src then
        local fn, err = load_in_env(src, "@" .. cand, env)
        if not fn then error(err, 2) end
        local res = fn(name)
        scope.loaded[name] = res == nil and true or res
        return scope.loaded[name]
      end
    end
    error(("module '%s' not found (searched next to %s)"):format(name, scope.path or "<none>"), 2)
  end
  return env
end

local function bind(ed, scope)
  scope.vim = make_vim(ed, scope)
  scope.env = make_env(ed, scope, scope.vim)
  return scope
end

-- an empty, active scope (editors without a config file)
function M.default_scope(ed)
  local s = bind(ed, M.new_scope(nil))
  s.active = true
  return s
end

-- Execute a config file into a fresh *staging* scope. Nothing about `ed` changes until the caller commits.
function M.build(ed, path)
  local src = read(path)
  if not src then return nil, "cannot read " .. path end
  local scope = bind(ed, M.new_scope(path))
  local fn, err = load_in_env(src, "@" .. path, scope.env)
  if not fn then return nil, err end
  local ok, e = pcall(fn)
  if not ok then return nil, tostring(e) end
  return scope
end

-- run extra code (":lua", ":source") inside the editor's CURRENT scope
function M.exec(ed, src, chunk)
  local fn, err = load_in_env(src, chunk, ed.cfg.env)
  if not fn then error(err, 0) end
  return fn()
end

function M.exec_file(ed, path)
  local src = read(path)
  if not src then error("E484: Can't open file " .. path, 0) end
  return M.exec(ed, src, "@" .. path)
end

function M.lookup(maps, seq)
  if not maps then return nil, false end
  local s = table.concat(seq, "\0")
  local pre = s .. "\0"
  local longer = false
  for k in pairs(maps) do
    if #k > #pre and k:sub(1, #pre) == pre then longer = true break end
  end
  return maps[s], longer
end

return M
