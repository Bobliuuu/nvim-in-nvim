local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local rv = require("recursive_vim")
local a = rv.setup({ root = root, config = "configs/a/init.lua", file = "examples/hello.txt", on_root_quit = function() end })
a:type("jlix<Esc>")
print(vim.inspect(a:snapshot().lines), a.mode, a.row, a.col)
a:type("Q") print(a.message)
a:type("<Space>n")
local b = require("recursive_vim.instances").focused
print(b.name, b.depth)
b:type("Q") print(b.message)
