-- Per-editor registers. An entry is { lines = {...}, linewise = bool }.
local R = {}
R.__index = R

function R.new() return setmetatable({ r = {} }, R) end

-- name: optional register name; kind: "yank" | "delete"
function R:set(name, lines, linewise, kind)
  if name == "_" then return end
  local e = { lines = lines, linewise = linewise }
  self.r['"'] = e
  if name and name ~= '"' then self.r[name:lower()] = e end
  if kind == "yank" and not name then self.r["0"] = e end
end

function R:get(name) return self.r[name or '"'] end

return R
