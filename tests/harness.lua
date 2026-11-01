-- Minimal test harness (no third-party plugins).
local H = { tests = {}, fails = 0, passes = 0 }

function H.test(name, fn) H.tests[#H.tests + 1] = { name = name, fn = fn } end

function H.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(("%sexpected %s\n     got %s"):format(msg and (msg .. ": ") or "", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function H.ok(v, msg) if not v then error(msg or "assertion failed", 2) end end

function H.run(file)
  local before = #H.tests
  dofile(file)
  for i = before + 1, #H.tests do
    local t = H.tests[i]
    local ok, err = xpcall(t.fn, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
    if ok then
      H.passes = H.passes + 1
      io.write("  ok   " .. t.name .. "\n")
    else
      H.fails = H.fails + 1
      io.write("  FAIL " .. t.name .. "\n    " .. tostring(err):gsub("\n", "\n    ") .. "\n")
    end
  end
end

return H
