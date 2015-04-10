local stringy = require "stringy"
local utils = require "kong.tools.utils"
local rex = require "rex_pcre"

local _M = {}

local function is_header(value)
  return string.match(value, "(%S+):%s*(%S+)")
end

-- Create a table representation of multipart/data body
--
-- @param {string} body The multipart/data string body
-- @param {string} boundary The multipart/data boundary
-- @return {table} Lua representation of the body
function _M.decode(body, boundary)
  local result = {
    data = {},
    indexes = {}
  }

  local part_headers = {}
  local part_index = 1
  local part_name, part_value

  for line in body:gmatch("[^\r\n]+") do
    if utils.starts_with(line, "--"..boundary) then
      if part_name ~= nil then
        result.data[part_index] = {
          name = part_name,
          headers = part_headers,
          value = part_value
        }

        result.indexes[part_name] = part_index

        -- Reset fields for the next part
        part_headers = {}
        part_value = nil
        part_name = nil
        part_index = part_index + 1
      end
    elseif utils.starts_with(string.lower(line), "content-disposition") then --Beginning of part
      -- Extract part_name
      local parts = stringy.split(line, ";")
      for _,v in ipairs(parts) do
        if not is_header(v) then -- If it's not content disposition part
          local current_parts = stringy.split(stringy.strip(v), "=")
          if string.lower(table.remove(current_parts, 1)) == "name" then
             local current_value = stringy.strip(table.remove(current_parts, 1))
             part_name = string.sub(current_value, 2, string.len(current_value) - 1)
          end
        end
      end
      table.insert(part_headers, line)
    else
      if is_header(line) then
        table.insert(part_headers, line)
      else
        -- The value part begins
        part_value = (part_value and part_value.."\r\n" or "")..line
      end
    end
  end
  return result
end

-- Creates a multipart/data body from a table
--
-- @param {table} t The table that contains the multipart/data body properties
-- @param {boundary} boundary The multipart/data boundary to use
-- @return {string} The multipart/data string body
function _M.encode(t, boundary)
  local result = ""

  for _, v in ipairs(t.data) do
    local part = "--"..boundary.."\r\n"
    for _, header in ipairs(v.headers) do
      part = part..header.."\r\n"
    end
    result = result..part.."\r\n"..v.value.."\r\n"
  end
  result = result.."--"..boundary.."--"

  return result
end

return _M