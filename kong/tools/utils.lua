---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is prefered.
--

local url = require "socket.url"
local uuid = require "lua_uuid"

local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table_sort = table.sort
local table_concat = table.concat
local table_insert = table.insert
local string_find = string.find
local string_format = string.format

local _M = {}

--- Generates a random unique string
-- @return string  The random string (a uuid without hyphens)
function _M.random_string()
  return uuid():gsub("-", "")
end

--- URL escape and format key and value
-- An obligatory url.unescape pass must be done to prevent double-encoding
-- already encoded values (which contain a '%' character that `url.escape` escapes)
local function encode_args_value(key, value, raw)
  if not raw then
    key = url.unescape(key)
    key = url.escape(key)
  end
  if value ~= nil then
    if not raw then
      value = url.unescape(value)
      value = url.escape(value)
    end
    return string_format("%s=%s", key, value)
  else
    return key
  end
end

--- Encode a Lua table to a querystring
-- Tries to mimic ngx_lua's `ngx.encode_args`, but also percent-encode querystring values.
-- Supports multi-value query args, boolean values.
-- It also supports encoding for bodies (only because it is used in http_client for specs.
-- @TODO drop and use `ngx.encode_args` once it implements percent-encoding.
-- @see https://github.com/Mashape/kong/issues/749
-- @param[type=table] args A key/value table containing the query args to encode.
-- @param[type=boolean] raw If true, will not percent-encode any key/value and will ignore special boolean rules.
-- @treturn string A valid querystring (without the prefixing '?')
function _M.encode_args(args, raw)
  local query = {}
  local keys = {}

  for k in pairs(args) do
    keys[#keys+1] = k
  end

  table_sort(keys)

  for _, key in ipairs(keys) do
    local value = args[key]
    if type(value) == "table" then
      for _, sub_value in ipairs(value) do
        query[#query+1] = encode_args_value(key, sub_value, raw)
      end
    elseif value == true then
      query[#query+1] = encode_args_value(key, raw and true or nil, raw)
    elseif value ~= false and value ~= nil or raw then
      value = tostring(value)
      if value ~= "" then
        query[#query+1] = encode_args_value(key, value, raw)
      elseif raw then
        query[#query+1] = key
      end
    end
  end

  return table_concat(query, "&")
end

--- Calculates a table size.
-- All entries both in array and hash part.
-- @param t The table to use
-- @return number The size
function _M.table_size(t)
  local res = 0
  if t then
    for _ in pairs(t) do
      res = res + 1
    end
  end
  return res
end

--- Merges two table together.
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.table_merge(t1, t2)
  local res = {}
  for k,v in pairs(t1) do res[k] = v end
  for k,v in pairs(t2) do res[k] = v end
  return res
end

--- Checks if a value exists in a table.
-- @param arr The table to use
-- @param val The value to check
-- @return Returns `true` if the table contains the value, `false` otherwise
function _M.table_contains(arr, val)
  if arr then
    for _, v in pairs(arr) do
      if v == val then
        return true
      end
    end
  end
  return false
end

--- Checks if a table is an array and not an associative array.
-- *** NOTE *** string-keys containing integers are considered valid array entries!
-- @param t The table to check
-- @return Returns `true` if the table is an array, `false` otherwise
function _M.is_array(t)
  if type(t) ~= "table" then return false end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil and t[tostring(i)] == nil then return false end
  end
  return true
end

--- Deep copies a table into a new table.
-- Tables used as keys are also deep copied, as are metatables
-- @param orig The table to copy
-- @return Returns a copy of the input table
function _M.deep_copy(orig)
  local copy
  if type(orig) == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[_M.deep_copy(orig_key)] = _M.deep_copy(orig_value)
    end
    setmetatable(copy, _M.deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

local err_list_mt = {}

--- Add an error message to a key/value table.
-- If the key already exists, a sub table is created with the original and the new value.
-- @param errors (Optional) Table to attach the error to. If `nil`, the table will be created.
-- @param k Key on which to insert the error in the `errors` table.
-- @param v Value of the error
-- @return The `errors` table with the new error inserted.
function _M.add_error(errors, k, v)
  if not errors then errors = {} end

  if errors and errors[k] then
    if getmetatable(errors[k]) ~= err_list_mt then
      errors[k] = setmetatable({errors[k]}, err_list_mt)
    end

    table_insert(errors[k], v)
  else
    errors[k] = v
  end

  return errors
end

--- Try to load a module.
-- Will not throw an error if the module was not found, but will throw an error if the
-- loading failed for another reason (eg: syntax error).
-- @param module_name Path of the module to load (ex: kong.plugins.keyauth.api).
-- @return success A boolean indicating wether the module was found.
-- @return module The retrieved module.
function _M.load_module_if_exists(module_name)
  local status, res = pcall(require, module_name)
  if status then
    return true, res
  -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
  elseif type(res) == "string" and string_find(res, "module '"..module_name.."' not found", nil, true) then
    return false
  else
    error(res)
  end
end

return _M
