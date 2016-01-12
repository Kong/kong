-- A metatable for pretty printing a table with key=value properties
--
-- Example:
--   {hello = "world", foo = "bar", baz = {"hello", "world"}}
-- Output:
--   "hello=world foo=bar, baz=hello,world"

local utils = require "kong.tools.utils"

local printable_mt = {}

function printable_mt:__tostring()
  local t = {}
  for k, v in pairs(self) do
    if type(v) == "table" then
      if utils.is_array(v) then
        v = table.concat(v, ",")
      else
        setmetatable(v, printable_mt)
      end
    end

    table.insert(t, k.."="..tostring(v))
  end
  return table.concat(t, " ")
end

function printable_mt.__concat(a, b)
  if getmetatable(a) == printable_mt then
    return tostring(a)..b
  else
    return a..tostring(b)
  end
end

return printable_mt
