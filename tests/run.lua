-- nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/tests/?.lua;" .. package.path
local H = require("harness")
local files = #_G.arg > 0 and _G.arg or { "editing_spec", "input_spec", "config_spec", "recursion_spec" }
for _, f in ipairs(files) do
  io.write(f .. "\n")
  H.run(root .. "/tests/" .. f .. ".lua")
end
io.write(("\n%d passed, %d failed\n"):format(H.passes, H.fails))
vim.cmd(H.fails == 0 and "qa!" or "cq")
