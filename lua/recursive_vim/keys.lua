-- Key notation. Canonical keys: printable chars as themselves (" ", "<"), specials as "<Esc>", "<C-r>", ...
local M = {}

local NAMES = {
  esc = "<Esc>", cr = "<CR>", enter = "<CR>", ["return"] = "<CR>", bs = "<BS>", tab = "<Tab>", del = "<Del>",
  up = "<Up>", down = "<Down>", left = "<Left>", right = "<Right>", home = "<Home>", ["end"] = "<End>",
  pageup = "<PageUp>", pagedown = "<PageDown>", space = " ", lt = "<", bar = "|", bslash = "\\", nl = "<NL>",
}

-- normalise a keytrans()-style or hand-written special name
local function special(name)
  local inner = name:sub(2, -2)
  local low = inner:lower()
  if NAMES[low] then return NAMES[low] end
  local mod, ch = inner:match("^[Cc]%-(.+)$")
  if mod then return "<C-" .. mod:lower() .. ">" end
  local m2 = inner:match("^[Mm]%-(.+)$")
  if m2 then return "<M-" .. m2 .. ">" end
  if low:match("^f%d+$") then return "<F" .. low:sub(2) .. ">" end
  return name
end

-- raw keycode string from Neovim -> canonical key
function M.normalize(raw)
  local k = vim.fn.keytrans(raw)
  if k:sub(1, 1) == "<" and #k > 1 then return special(k) end
  return k
end

-- "<leader>n" / "gg" / "<C-r>x" -> list of canonical keys
function M.parse(lhs, leader)
  local out, i = {}, 1
  while i <= #lhs do
    local s, e = lhs:find("^<[%w%-_]+>", i)
    if s then
      local name = lhs:sub(s, e)
      if name:lower() == "<leader>" then
        for _, k in ipairs(M.parse(leader or "\\")) do out[#out + 1] = k end
      else
        out[#out + 1] = special(name)
      end
      i = e + 1
    else
      local b = lhs:byte(i)
      local len = b < 0x80 and 1 or b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
      out[#out + 1] = lhs:sub(i, i + len - 1)
      i = i + len
    end
  end
  return out
end

function M.is_printable(k)
  return k == "<" or (#k > 0 and k:sub(1, 1) ~= "<")
end

-- text -> keys (for paste / insert_text): newline -> <CR>, tab -> <Tab>
function M.from_text(text)
  local out = {}
  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    out[#out + 1] = ch == "\n" and "<CR>" or ch == "\t" and "<Tab>" or ch
  end
  return out
end

return M
