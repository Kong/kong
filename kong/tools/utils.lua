---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is prefered.
--
-- @copyright Copyright 2016 Mashape Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local ffi = require "ffi"
local uuid = require "resty.jit-uuid"
local pl_stringx = require "pl.stringx"

local C          = ffi.C
local ffi_new    = ffi.new
local ffi_str    = ffi.string
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local sort       = table.sort
local concat     = table.concat
local insert     = table.insert
local lower      = string.lower
local fmt        = string.format
local find       = string.find
local gsub       = string.gsub
local split      = pl_stringx.split
local strip      = pl_stringx.strip
local re_find    = ngx.re.find

ffi.cdef[[
typedef unsigned char u_char;

int gethostname(char *name, size_t len);

int RAND_bytes(u_char *buf, int num);

unsigned long ERR_get_error(void);
void ERR_load_crypto_strings(void);
void ERR_free_strings(void);

const char *ERR_reason_error_string(unsigned long e);
]]

local _M = {}

--- splits a string.
-- just a placeholder to the penlight `pl.stringx.split` function
-- @function split
_M.split = split

--- strips whitespace from a string.
-- just a placeholder to the penlight `pl.stringx.strip` function
-- @function strip
_M.strip = strip


--- Retrieves the hostname of the local machine
-- @return string  The hostname
function _M.get_hostname()
  local result
  local SIZE = 128

  local buf = ffi_new("unsigned char[?]", SIZE)
  local res = C.gethostname(buf, SIZE)

  if res == 0 then
    local hostname = ffi_str(buf, SIZE)
    result = gsub(hostname, "%z+$", "")
  else
    local f = io.popen("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    result = gsub(hostname, "\n$", "")
  end

  return result
end

do
  local pl_utils = require "pl.utils"

  local _system_infos

  function _M.get_system_infos()
    if _system_infos then
      return _system_infos
    end

    _system_infos = {
      hostname = _M.get_hostname()
    }

    local ok, _, stdout = pl_utils.executeex("getconf _NPROCESSORS_ONLN")
    if ok then
      _system_infos.cores = tonumber(stdout:sub(1, -2))
    end

    ok, _, stdout = pl_utils.executeex("uname -a")
    if ok then
      _system_infos.uname = stdout:gsub(";", ","):sub(1, -2)
    end

    return _system_infos
  end
end

do
  local bytes_buf_t = ffi.typeof "char[?]"

  function _M.get_rand_bytes(n_bytes)
    local buf = ffi_new(bytes_buf_t, n_bytes)

    if C.RAND_bytes(buf, n_bytes) == 0 then
      -- get error code
      local err_code = C.ERR_get_error()
      if err_code == 0 then
        return nil, "could not get SSL error code from the queue"
      end

      -- get human-readable error string
      C.ERR_load_crypto_strings()
      local err = C.ERR_reason_error_string(err_code)
      C.ERR_free_strings()

      return nil, "could not get random bytes (" ..
                  "reason:" .. ffi_str(err) .. ") "
    end

    return ffi_str(buf, n_bytes)
  end
end

local v4_uuid = uuid.generate_v4

--- Generates a v4 uuid.
-- @function uuid
-- @return string with uuid
_M.uuid = uuid.generate_v4

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

do
  local url = require "socket.url"

  --- URL escape and format key and value
  -- values should be already decoded or the `raw` option should be passed to prevent double-encoding
  local function encode_args_value(key, value, raw)
    if not raw then
      key = url.escape(key)
    end
    if value ~= nil then
      if not raw then
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

--- Copies a table into a new table.
-- neither sub tables nor metatables will be copied.
-- @param orig The table to copy
-- @return Returns a copy of the input table
function _M.shallow_copy(orig)
  local copy
  if type(orig) == "table" then
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
-- @return module The retrieved module, or the error in case of a failure
function _M.load_module_if_exists(module_name)
  local status, res = pcall(require, module_name)
  if status then
    return true, res
  -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
  elseif type(res) == "string" and find(res, "module '"..module_name.."' not found", nil, true) then
    return false, res
  else
    error(res)
  end
end

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

--- checks the hostname type; ipv4, ipv6, or name.
-- Type is determined by exclusion, not by validation. So if it returns 'ipv6' then
-- it can only be an ipv6, but it is not necessarily a valid ipv6 address.
-- @param name the string to check (this may contain a portnumber)
-- @return string either; 'ipv4', 'ipv6', or 'name'
-- @usage hostname_type("123.123.123.123")  -->  "ipv4"
-- hostname_type("::1")              -->  "ipv6"
-- hostname_type("some::thing")      -->  "ipv6", but invalid...
_M.hostname_type = function(name)
  local remainder, colons = gsub(name, ":", "")
  if colons > 1 then return "ipv6" end
  if remainder:match("^[%d%.]+$") then return "ipv4" end
  return "name"
end

--- parses, validates and normalizes an ipv4 address.
-- @param address the string containing the address (formats; ipv4, ipv4:port)
-- @return normalized address (string) + port (number or nil), or alternatively nil+error
_M.normalize_ipv4 = function(address)
  local a,b,c,d,port
  if address:find(":") then
    -- has port number
    a,b,c,d,port = address:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?):(%d+)$")
  else
    -- without port number
    a,b,c,d,port = address:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
  end
  if not a then
    return nil, "invalid ipv4 address: "..address
  end
  a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if (a<0) or (a>255) or (b<0) or (b>255) or (c<0) or (c>255) or (d<0) or (d>255) then
    return nil, "invalid ipv4 address: "..address
  end
  if port then port = tonumber(port) end
  
  return fmt("%d.%d.%d.%d",a,b,c,d), port
end

--- parses, validates and normalizes an ipv6 address.
-- @param address the string containing the address (formats; ipv6, [ipv6], [ipv6]:port)
-- @return normalized expanded address (string) + port (number or nil), or alternatively nil+error
_M.normalize_ipv6 = function(address)
  local check, port = address:match("^(%b[])(.-)$")
  if port == "" then port = nil end
  if check then
    check = check:sub(2, -2)  -- drop the brackets
    -- we have ipv6 in brackets, now get port if we got something left
    if port then 
      port = port:match("^:(%d-)$")
      if not port then
        return nil, "invalid ipv6 address"
      end
    end
  else
    -- no brackets, so full address only; no brackets, no port
    check = address
    port = nil
  end
  -- check ipv6 format and normalize
  if check:sub(1,1) == ":" then check = "0"..check end
  if check:sub(-1,-1) == ":" then check = check.."0" end
  if check:find("::") then
    -- expand double colon
    local _, count = gsub(check, ":", "")
    local ins = ":"..string.rep("0:", 8 - count)
    check = gsub(check, "::", ins, 1)  -- replace only 1 occurence!
  end
  local a,b,c,d,e,f,g,h = check:match("^(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?)$")
  if not a then
    -- not a valid IPv6 address
    return nil, "invalid ipv6 address: "..address
  end
  local zeros = "0000"
  if port then
    port = tonumber(port)
  end
  return lower(fmt("%s:%s:%s:%s:%s:%s:%s:%s",
      zeros:sub(1, 4 - #a)..a,
      zeros:sub(1, 4 - #b)..b,
      zeros:sub(1, 4 - #c)..c,
      zeros:sub(1, 4 - #d)..d,
      zeros:sub(1, 4 - #e)..e,
      zeros:sub(1, 4 - #f)..f,
      zeros:sub(1, 4 - #g)..g,
      zeros:sub(1, 4 - #h)..h)), port
end

--- parses and validates a hostname.
-- @param address the string containing the hostname (formats; name, name:port)
-- @return hostname (string) + port (number or nil), or alternatively nil+error
_M.check_hostname = function(address)
  local name = address
  local port = address:match(":(%d+)$")
  if port then
    name = name:sub(1, -(#port+2))
    port = tonumber(port)
  end
  local match = name:match("^[%d%a%-%.%_]+$")
  if match == nil then
    return nil, "invalid hostname: "..address
  end

  -- Reject prefix/trailing dashes and dots in each segment
  -- note: punycode allowes prefixed dash, if the characters before the dash are escaped
  for _, segment in ipairs(split(name, ".")) do
    if segment == "" or segment:match("-$") or segment:match("^%.") or segment:match("%.$") then
      return nil, "invalid hostname: "..address
    end
  end
  return name, port
end

local verify_types = {
  ipv4 = _M.normalize_ipv4,
  ipv6 = _M.normalize_ipv6,
  name = _M.check_hostname,
}
--- verifies and normalizes ip adresses and hostnames. Supports ipv4, ipv4:port, ipv6, [ipv6]:port, name, name:port.
-- Returned ipv4 addresses will have no leading zero's, ipv6 will be fully expanded without brackets.
-- Note: a name will not be normalized!
-- @param address string containing the address
-- @return table with the following fields: `host` (string; normalized address, or name), `type` (string; 'ipv4', 'ipv6', 'name'), and `port` (number or nil), or alternatively nil+error on invalid input
_M.normalize_ip = function(address)
  local atype = _M.hostname_type(address)
  local addr, port = verify_types[atype](address)
  if not addr then return nil, port end 
  return {
    type = atype,
    host = addr,
    port = port
  }
end

--- Formats an ip address or hostname with an (optional) port for use in urls.
-- Supports ipv4, ipv6 and names.
--
-- Explictly accepts 'nil+error' as input, to pass through any errors from the normalizing and name checking functions.
-- @param p1 address to format, either string with name/ip, table returned from `normalize_ip`, or from the `socket.url` library.
-- @param p2 port (optional) if p1 is a table, then this port will be inserted if no port-field is in the table
-- @return formatted address or nil+error
-- @usage
-- local addr, err = format_ip(normalize_ip("001.002.003.004:123"))  --> "1.2.3.4:123"
-- local addr, err = format_ip(normalize_ip("::1"))                  --> "[0000:0000:0000:0000:0000:0000:0000:0001]"
-- local addr, err = format_ip("::1", 80))                           --> "[::1]:80"
-- local addr, err = format_ip(check_hostname("//bad..name\\"))      --> nil, "invalid hostname: ..."
_M.format_host = function(p1, p2)
  local t = type(p1)
  if t == "nil" then 
    return p1, p2   -- just pass through any errors passed in
  end
  local host, port, typ
  if t == "table" then
    port = p1.port or p2
    host = p1.host
    typ = p1.type or _M.hostname_type(host)
  elseif t == "string" then
    port = p2
    host = p1
    typ = _M.hostname_type(host)
  else
    return nil, "cannot format type '"..t.."'"
  end
  if (typ == "ipv6") and (not find(host, "%[")) then
    return "["..host.."]" ..  (port and ":"..port or "")
  else
    return host ..  (port and ":"..port or "")
  end
end

return _M
