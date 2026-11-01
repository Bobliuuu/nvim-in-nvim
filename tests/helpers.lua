local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local Instances = require("recursive_vim.instances")
local Editor = require("recursive_vim.editor")
local render = require("recursive_vim.render")

local M = { root = root }
Instances.on_root_quit = function() end
render.setup()

function M.tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

function M.write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "wb")); f:write(text); f:close()
end

function M.read(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

-- copy configs/ to a temp project dir so tests may edit them
function M.project()
  local d = M.tmpdir()
  vim.fn.system({ "cp", "-R", root .. "/configs", d .. "/configs" })
  Instances.root_dir = d
  return d
end

function M.cleanup()
  for _, r in ipairs(Instances.roots()) do Instances.close(r) end
  Instances.focused = nil
  Instances.root_dir = root
end

-- editor over a given text; `at` = {row, col} 0-based
function M.ed(text, at)
  M.cleanup()
  local d = M.tmpdir()
  local lines = type(text) == "table" and text or vim.split(text, "\n", { plain = true })
  M.write(d .. "/t.txt", table.concat(lines, "\n") .. "\n")
  Instances.root_dir = d
  local ed = Editor.new({ file = "t.txt" })
  if at then ed:set_cursor(at[1], at[2]) end
  return ed
end

function M.lines(ed) return ed.buf:lines() end

return M
