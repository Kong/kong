---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is prefered.
--
-- @copyright Copyright 2016 Mashape Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local url = require "socket.url"
local ffi = require "ffi"
local uuid = require "resty.jit-uuid"
local pl_stringx = require "pl.stringx"

local ffi_new    = ffi.new
local ffi_str    = ffi.string
local ffi_typeof = ffi.typeof
local C          = ffi.C
local fmt        = string.format
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local re_find    = ngx.re.find
local tostring   = tostring
local sort       = table.sort
local concat     = table.concat
local insert     = table.insert
local find       = string.find
local gsub       = string.gsub

ffi.cdef[[
typedef unsigned char u_char;
u_char * ngx_hex_dump(u_char *dst, const u_char *src, size_t len);
int RAND_bytes(u_char *buf, int num);

int gethostname(char *name, size_t len);
]]

local t = ffi_typeof "uint8_t[?]"

local function bytes(len, format)
  local s = ffi_new(t, len)
  C.RAND_bytes(s, len)
  if not s then return nil end
  if format == "hex" then
    local b = ffi_new(t, len * 2)
    C.ngx_hex_dump(b, s, len)
    return ffi_str(b, len * 2), true
  else
    return ffi_str(s, len), true
  end
end

local _M = {}

--- Retrieves the hostname of the local machine
-- @return string  The hostname
function _M.get_hostname()
  local result
  local SIZE = 128

  local buf = ffi.new("unsigned char[?]", SIZE)
  local res = C.gethostname(buf, SIZE)

  if res == 0 then
    local hostname = ffi.string(buf, SIZE)
    result = gsub(hostname, "%z+$", "")
  else
    local f = io.popen("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    result = gsub(hostname, "\n$", "")
  end

  return result
end

local v4_uuid = uuid.generate_v4

--- Generates a v4 uuid.
-- @function uuid
-- @return string with uuid
_M.uuid = uuid.generate_v4

--- Seeds the random generator, use with care.
-- Kong already seeds this once per worker process. It's
-- dangerous to ever call it again. So ask yourself
-- "Do I feel lucky?" Well, do ya, punk?
-- See https://github.com/bungle/lua-resty-random/blob/master/lib/resty/random.lua#L49-L52
function _M.randomseed()
  local a,b,c,d = bytes(4):byte(1, 4)
  local seed = a * 0x1000000 + b * 0x10000 + c * 0x100 + d
  ngx.log(ngx.DEBUG, "seeding random number generator with: ", seed)
  return math.randomseed(seed)
end

--- Generates a random unique string
-- @return string  The random string (a uuid without hyphens)
function _M.random_string()
  return v4_uuid():gsub("-", "")
end

local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
function _M.is_valid_uuid(str)
  if type(str) ~= 'string' or #str ~= 36 then return false end
  return re_find(str, uuid_regex, 'ioj') ~= nil
end

-- function below is more acurate, but invalidates previously accepted uuids and hence causes
-- trouble with existing data during migrations.
-- see: https://github.com/thibaultcha/lua-resty-jit-uuid/issues/8
-- function _M.is_valid_uuid(str)
--  return str == "00000000-0000-0000-0000-000000000000" or uuid.is_valid(str)
--end

_M.split = pl_stringx.split
_M.strip = pl_stringx.strip

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
    return fmt("%s=%s", key, value)
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

  sort(keys)

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
      elseif raw or value == "" then
        query[#query+1] = key
      end
    end
  end

  return concat(query, "&")
end

--- Checks whether a request is https or was originally https (but already terminated).
-- It will check in the current request (global `ngx` table). If the header `X-Forwarded-Proto` exists
-- with value `https` then it will also be considered as an https connection.
-- @param allow_terminated if truthy, the `X-Forwarded-Proto` header will be checked as well.
-- @return boolean or nil+error in case the header exists multiple times
_M.check_https = function(allow_terminated)
  if ngx.var.scheme:lower() == "https" then
    return true
  end

  if not allow_terminated then
    return false
  end

  local forwarded_proto_header = ngx.req.get_headers()["x-forwarded-proto"]
  if tostring(forwarded_proto_header):lower() == "https" then
    return true
  end

  if type(forwarded_proto_header) == "table" then
    -- we could use the first entry (lower security), or check the contents of each of them (slow). So for now defensive, and error
    -- out on multiple entries for the x-forwarded-proto header.
    return nil, "Only one X-Forwarded-Proto header allowed"
  end

  return false
end

--- Merges two table together.
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.table_merge(t1, t2)
  if not t1 then t1 = {} end
  if not t2 then t2 = {} end

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

function _M.shallow_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

local err_list_mt = {}

--- Concatenates lists into a new table.
function _M.concat(...)
  local result = {}
  local insert = table.insert
  for _, t in ipairs({...}) do
    for _, v in ipairs(t) do insert(result, v) end
  end
  return result
end

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

    insert(errors[k], v)
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
  elseif type(res) == "string" and find(res, "module '"..module_name.."' not found", nil, true) then
    return false
  else
    error(res)
  end
end

local find = string.find
local tostring = tostring

-- Numbers taken from table 3-7 in www.unicode.org/versions/Unicode6.2.0/UnicodeStandard-6.2.pdf
-- find-based solution inspired by http://notebook.kulchenko.com/programming/fixing-malformed-utf8-in-lua
function _M.validate_utf8(val)
  local str = tostring(val)
  local i, len = 1, #str
  while i <= len do
    if     i == find(str, "[%z\1-\127]", i) then i = i + 1
    elseif i == find(str, "[\194-\223][\123-\191]", i) then i = i + 2
    elseif i == find(str,        "\224[\160-\191][\128-\191]", i)
        or i == find(str, "[\225-\236][\128-\191][\128-\191]", i)
        or i == find(str,        "\237[\128-\159][\128-\191]", i)
        or i == find(str, "[\238-\239][\128-\191][\128-\191]", i) then i = i + 3
    elseif i == find(str,        "\240[\144-\191][\128-\191][\128-\191]", i)
        or i == find(str, "[\241-\243][\128-\191][\128-\191][\128-\191]", i)
        or i == find(str,        "\244[\128-\143][\128-\191][\128-\191]", i) then i = i + 4
    else
      return false, i
    end
  end

  return true
end

return _M
