---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is preferred.
--
-- @copyright Copyright 2016-2020 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local ffi = require "ffi"
local uuid = require "resty.jit-uuid"
local pl_stringx = require "pl.stringx"

local C          = ffi.C
local ffi_fill   = ffi.fill
local ffi_new    = ffi.new
local ffi_str    = ffi.string
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local select     = select
local tostring   = tostring
local sort       = table.sort
local concat     = table.concat
local insert     = table.insert
local lower      = string.lower
local fmt        = string.format
local find       = string.find
local gsub       = string.gsub
local split      = pl_stringx.split
local re_find    = ngx.re.find
local re_match   = ngx.re.match

ffi.cdef[[
typedef unsigned char u_char;

int gethostname(char *name, size_t len);

int RAND_bytes(u_char *buf, int num);

unsigned long ERR_get_error(void);
void ERR_load_crypto_strings(void);
void ERR_free_strings(void);

const char *ERR_reason_error_string(unsigned long e);

int open(const char * filename, int flags, int mode);
size_t read(int fd, void *buf, size_t count);
int write(int fd, const void *ptr, int numbytes);
int close(int fd);
char *strerror(int errnum);
]]

local _M = {}

--- splits a string.
-- just a placeholder to the penlight `pl.stringx.split` function
-- @function split
_M.split = split

--- strips whitespace from a string.
-- @function strip
_M.strip = function(str)
  if str == nil then
    return ""
  end
  str = tostring(str)
  if #str > 200 then
    return str:gsub("^%s+", ""):reverse():gsub("^%s+", ""):reverse()
  else
    return str:match("^%s*(.-)%s*$")
  end
end

--- packs a set of arguments in a table.
-- Explicitly sets field `n` to the number of arguments, so it is `nil` safe
_M.pack = function(...) return {n = select("#", ...), ...} end

--- unpacks a table to a list of arguments.
-- Explicitly honors the `n` field if given in the table, so it is `nil` safe
_M.unpack = function(t, i, j) return unpack(t, i or 1, j or t.n or #t) end

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

    ok, _, stdout = pl_utils.executeex("uname -ms")
    if ok then
      _system_infos.uname = stdout:gsub(";", ","):sub(1, -2)
    end

    return _system_infos
  end
end

local get_rand_bytes

do
  local ngx_log = ngx.log
  local WARN    = ngx.WARN

  local system_constants = require "lua_system_constants"
  local O_RDONLY = system_constants.O_RDONLY()
  local bytes_buf_t = ffi.typeof "char[?]"

  local function urandom_bytes(buf, size)
    local fd = ffi.C.open("/dev/urandom", O_RDONLY, 0) -- mode is ignored
    if fd < 0 then
      ngx_log(WARN, "Error opening random fd: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))

      return false
    end

    local res = ffi.C.read(fd, buf, size)
    if res <= 0 then
      ngx_log(WARN, "Error reading from urandom: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))

      return false
    end

    if ffi.C.close(fd) ~= 0 then
      ngx_log(WARN, "Error closing urandom: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))
    end

    return true
  end

  -- try to get n_bytes of CSPRNG data, first via /dev/urandom,
  -- and then falling back to OpenSSL if necessary
  get_rand_bytes = function(n_bytes, urandom)
    local buf = ffi_new(bytes_buf_t, n_bytes)
    ffi_fill(buf, n_bytes, 0x0)

    -- only read from urandom if we were explicitly asked
    if urandom then
      local rc = urandom_bytes(buf, n_bytes)

      -- if the read of urandom was successful, we returned true
      -- and buf is filled with our bytes, so return it as a string
      if rc then
        return ffi_str(buf, n_bytes)
      end
    end

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

  _M.get_rand_bytes = get_rand_bytes
end

--- Generates a v4 uuid.
-- @function uuid
-- @return string with uuid
_M.uuid = uuid.generate_v4

--- Generates a random unique string
-- @return string  The random string (a chunk of base64ish-encoded random bytes)
do
  local char = string.char
  local rand = math.random
  local encode_base64 = ngx.encode_base64

  -- generate a random-looking string by retrieving a chunk of bytes and
  -- replacing non-alphanumeric characters with random alphanumeric replacements
  -- (we dont care about deriving these bytes securely)
  -- this serves to attempt to maintain some backward compatibility with the
  -- previous implementation (stripping a UUID of its hyphens), while significantly
  -- expanding the size of the keyspace.
  local function random_string()
    -- get 24 bytes, which will return a 32 char string after encoding
    -- this is done in attempt to maintain backwards compatibility as
    -- much as possible while improving the strength of this function
    return encode_base64(get_rand_bytes(24, true))
           :gsub("/", char(rand(48, 57)))  -- 0 - 10
           :gsub("+", char(rand(65, 90)))  -- A - Z
           :gsub("=", char(rand(97, 122))) -- a - z
  end

  _M.random_string = random_string
end

local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
function _M.is_valid_uuid(str)
  if type(str) ~= 'string' or #str ~= 36 then
    return false
  end
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

  local function compare_keys(a, b)
    local ta = type(a)
    if ta == type(b) then
      return a < b
    end
    return ta == "number" -- numbers go first, then the rest of keys (usually strings)
  end


  -- Recursively URL escape and format key and value
  -- Handles nested arrays and tables
  local function recursive_encode_args(parent_key, value, raw, no_array_indexes, query)
    local sub_keys = {}
    for sk in pairs(value) do
      sub_keys[#sub_keys + 1] = sk
    end
    sort(sub_keys, compare_keys)

    local sub_value, next_sub_key
    for _, sub_key in ipairs(sub_keys) do
      sub_value = value[sub_key]

      if type(sub_key) == "number" then
        if no_array_indexes then
          next_sub_key = parent_key .. "[]"
        else
          next_sub_key = ("%s[%s]"):format(parent_key, tostring(sub_key))
        end
      else
        next_sub_key = ("%s.%s"):format(parent_key, tostring(sub_key))
      end

      if type(sub_value) == "table" then
        recursive_encode_args(next_sub_key, sub_value, raw, no_array_indexes, query)
      else
        query[#query+1] = encode_args_value(next_sub_key, sub_value, raw)
      end
    end
  end


  --- Encode a Lua table to a querystring
  -- Tries to mimic ngx_lua's `ngx.encode_args`, but has differences:
  -- * It percent-encodes querystring values.
  -- * It also supports encoding for bodies (only because it is used in http_client for specs.
  -- * It encodes arrays like Lapis instead of like ngx.encode_args to allow interacting with Lapis
  -- * It encodes ngx.null as empty strings
  -- * It encodes true and false as "true" and "false"
  -- * It is capable of encoding nested data structures:
  --   * An array access is encoded as `arr[1]`
  --   * A struct access is encoded as `struct.field`
  --   * Nested structures can use both: `arr[1].field[3]`
  -- @see https://github.com/Mashape/kong/issues/749
  -- @param[type=table] args A key/value table containing the query args to encode.
  -- @param[type=boolean] raw If true, will not percent-encode any key/value and will ignore special boolean rules.
  -- @param[type=boolean] no_array_indexes If true, arrays/map elements will be
  --                      encoded without an index: 'my_array[]='. By default,
  --                      array elements will have an index: 'my_array[0]='.
  -- @treturn string A valid querystring (without the prefixing '?')
  function _M.encode_args(args, raw, no_array_indexes)
    local query = {}
    local keys = {}

    for k in pairs(args) do
      keys[#keys+1] = k
    end

    sort(keys, compare_keys)

    for _, key in ipairs(keys) do
      local value = args[key]
      if type(value) == "table" then
        recursive_encode_args(key, value, raw, no_array_indexes, query)
      elseif value == ngx.null then
        query[#query+1] = encode_args_value(key, "")
      elseif  value ~= nil or raw then
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

  local function decode_array(t)
    local keys = {}
    local len  = 0
    for k in pairs(t) do
      len = len + 1
      local number = tonumber(k)
      if not number then
        return nil
      end
      keys[len] = number
    end

    table.sort(keys)
    local new_t = {}

    for i=1,len do
      if keys[i] ~= i then
        return nil
      end
      new_t[i] = t[tostring(i)]
    end

    return new_t
  end

  -- Parses params in post requests
  -- Transforms "string-like numbers" inside "array-like" tables into numbers
  -- (needs a complete array with no holes starting on "1")
  --   { x = {["1"] = "a", ["2"] = "b" } } becomes { x = {"a", "b"} }
  -- Transforms empty strings into ngx.null:
  --   { x = "" } becomes { x = ngx.null }
  -- Transforms the strings "true" and "false" into booleans
  --   { x = "true" } becomes { x = true }
  function _M.decode_args(args)
    local new_args = {}

    for k, v in pairs(args) do
      if type(v) == "table" then
        v = decode_array(v) or v
      elseif v == "" then
        v = ngx.null
      elseif v == "true" then
        v = true
      elseif v == "false" then
        v = false
      end
      new_args[k] = v
    end

    return new_args
  end

end


--- Checks whether a request is https or was originally https (but already
-- terminated). It will check in the current request (global `ngx` table). If
-- the header `X-Forwarded-Proto` exists -- with value `https` then it will also
-- be considered as an https connection.
-- @param trusted_ip boolean indicating if the client is a trusted IP
-- @param allow_terminated if truthy, the `X-Forwarded-Proto` header will be checked as well.
-- @return boolean or nil+error in case the header exists multiple times
_M.check_https = function(trusted_ip, allow_terminated)
  if ngx.var.scheme:lower() == "https" then
    return true
  end

  if not allow_terminated then
    return false
  end

  -- if we trust this IP, examine it's X-Forwarded-Proto header
  -- otherwise, we fall back to relying on the client scheme
  -- (which was either validated earlier, or we fall through this block)
  if trusted_ip then
    local scheme = ngx.req.get_headers()["x-forwarded-proto"]

    -- we could use the first entry (lower security), or check the contents of
    -- each of them (slow). So for now defensive, and error
    -- out on multiple entries for the x-forwarded-proto header.
    if type(scheme) == "table" then
      return nil, "Only one X-Forwarded-Proto header allowed"
    end

    return tostring(scheme):lower() == "https"
  end

  return false
end

--- Merges two table together.
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.table_merge(t1, t2)
  if not t1 then
    t1 = {}
  end
  if not t2 then
    t2 = {}
  end

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
  if type(t) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil and t[tostring(i)] == nil then
      return false
    end
  end
  return true
end

--- Deep copies a table into a new table.
-- Tables used as keys are also deep copied, as are metatables
-- @param orig The table to copy
-- @param copy_mt Copy metatable (default is true)
-- @return Returns a copy of the input table
function _M.deep_copy(orig, copy_mt)
  if copy_mt == nil then
    copy_mt = true
  end
  local copy
  if type(orig) == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[_M.deep_copy(orig_key)] = _M.deep_copy(orig_value, copy_mt)
    end
    if copy_mt then
      setmetatable(copy, _M.deep_copy(getmetatable(orig)))
    end
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

--- Merges two tables recursively
-- For each subtable in t1 and t2, an equivalent (but different) table will
-- be created in the resulting merge. If t1 and t2 have a subtable with in the
-- same key k, res[k] will be a deep merge of both subtables.
-- Metatables are not taken into account.
-- Keys are copied by reference (if tables are used as keys they will not be
-- duplicated)
-- @param t1 one of the tables to merge
-- @param t2 one of the tables to merge
-- @return Returns a table representing a deep merge of the new table
function _M.deep_merge(t1, t2)
  local res = _M.deep_copy(t1)

  for k, v in pairs(t2) do
    if type(v) == "table" and type(res[k]) == "table" then
      res[k] = _M.deep_merge(res[k], v)
    else
      res[k] = _M.deep_copy(v) -- returns v when it is not a table
    end
  end

  return res
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
  if not errors then
    errors = {}
  end

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
  local status, res = xpcall(require, function(err)
                                        return debug.traceback(err)
                                      end, module_name)
  if status then
    return true, res
  -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
  elseif type(res) == "string" and find(res, "module '" .. module_name .. "' not found", nil, true) then
    return false, res
  else
    error("error loading module '" .. module_name .. "':\n" .. res)
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
  if colons > 1 then
    return "ipv6"
  end
  if remainder:match("^[%d%.]+$") then
    return "ipv4"
  end
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
    return nil, "invalid ipv4 address: " .. address
  end
  a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if a < 0 or a > 255 or b < 0 or b > 255 or c < 0 or
     c > 255 or d < 0 or d > 255 then
    return nil, "invalid ipv4 address: " .. address
  end
  if port then
    port = tonumber(port)
    if port > 65535 then
      return nil, "invalid port number"
    end
  end

  return fmt("%d.%d.%d.%d",a,b,c,d), port
end

--- parses, validates and normalizes an ipv6 address.
-- @param address the string containing the address (formats; ipv6, [ipv6], [ipv6]:port)
-- @return normalized expanded address (string) + port (number or nil), or alternatively nil+error
_M.normalize_ipv6 = function(address)
  local check, port = address:match("^(%b[])(.-)$")
  if port == "" then
    port = nil
  end
  if check then
    check = check:sub(2, -2)  -- drop the brackets
    -- we have ipv6 in brackets, now get port if we got something left
    if port then
      port = port:match("^:(%d-)$")
      if not port then
        return nil, "invalid ipv6 address"
      end
      port = tonumber(port)
      if port > 65535 then
        return nil, "invalid port number"
      end
    end
  else
    -- no brackets, so full address only; no brackets, no port
    check = address
    port = nil
  end
  -- check ipv6 format and normalize
  if check:sub(1,1) == ":" then
    check = "0" .. check
  end
  if check:sub(-1,-1) == ":" then
    check = check .. "0"
  end
  if check:find("::") then
    -- expand double colon
    local _, count = gsub(check, ":", "")
    local ins = ":" .. string.rep("0:", 8 - count)
    check = gsub(check, "::", ins, 1)  -- replace only 1 occurence!
  end
  local a,b,c,d,e,f,g,h = check:match("^(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?)$")
  if not a then
    -- not a valid IPv6 address
    return nil, "invalid ipv6 address: " .. address
  end
  local zeros = "0000"
  return lower(fmt("%s:%s:%s:%s:%s:%s:%s:%s",
      zeros:sub(1, 4 - #a) .. a,
      zeros:sub(1, 4 - #b) .. b,
      zeros:sub(1, 4 - #c) .. c,
      zeros:sub(1, 4 - #d) .. d,
      zeros:sub(1, 4 - #e) .. e,
      zeros:sub(1, 4 - #f) .. f,
      zeros:sub(1, 4 - #g) .. g,
      zeros:sub(1, 4 - #h) .. h)), port
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
    if port > 65535 then
      return nil, "invalid port number"
    end
  end
  local match = name:match("^[%d%a%-%.%_]+$")
  if match == nil then
    return nil, "invalid hostname: " .. address
  end

  -- Reject prefix/trailing dashes and dots in each segment
  -- note: punycode allowes prefixed dash, if the characters before the dash are escaped
  for _, segment in ipairs(split(name, ".")) do
    if segment == "" or segment:match("-$") or segment:match("^%.") or segment:match("%.$") then
      return nil, "invalid hostname: " .. address
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
  if not addr then
    return nil, port
  end
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
-- local addr, err = format_ip(check_hostname("//bad .. name\\"))    --> nil, "invalid hostname: ... "
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
    return nil, "cannot format type '" .. t .. "'"
  end
  if typ == "ipv6" and not find(host, "[", nil, true) then
    return "[" .. _M.normalize_ipv6(host) .. "]" .. (port and ":" .. port or "")
  else
    return host ..  (port and ":" .. port or "")
  end
end

--- Validates a header name.
-- Checks characters used in a header name to be valid, as per nginx only
-- a-z, A-Z, 0-9 and '-' are allowed.
-- @param name (string) the header name to verify
-- @return the valid header name, or `nil+error`
_M.validate_header_name = function(name)
  if name == nil or name == "" then
    return nil, "no header name provided"
  end

  if re_match(name, "^[a-zA-Z0-9-_]+$", "jo") then
    return name
  end

  return nil, "bad header name '" .. name ..
              "', allowed characters are A-Z, a-z, 0-9, '_', and '-'"
end

--- Validates a cookie name.
-- Checks characters used in a cookie name to be valid
-- a-z, A-Z, 0-9, '_' and '-' are allowed.
-- @param name (string) the cookie name to verify
-- @return the valid cookie name, or `nil+error`
_M.validate_cookie_name = function(name)
  if name == nil or name == "" then
    return nil, "no cookie name provided"
  end

  if re_match(name, "^[a-zA-Z0-9-_]+$", "jo") then
    return name
  end

  return nil, "bad cookie name '" .. name ..
              "', allowed characters are A-Z, a-z, 0-9, '_', and '-'"
end


---
-- Given an http status and an optional message, this function will
-- return a body that could be used in `kong.response.exit`.
--
-- * Status 204 will always return nil for the body
-- * 405, 500 and 502 always return a predefined message
-- * If there is a message, it will be used as a body
-- * Otherwise, there's a default body for 401, 404 & 503 responses
--
-- If after applying those rules there's a body, and that body isn't a
-- table, it will be transformed into one of the form `{ message = ... }`,
-- where `...` is the untransformed body.
--
-- This function throws an error on invalid inputs.
--
-- @tparam number status The status to be used
-- @tparam[opt] table|string message The message to be used
-- @tparam[opt] table headers The headers to be used
-- @return table|nil a possible body which can be used in kong.response.exit
-- @usage
--
-- --- 204 always returns nil
-- get_default_exit_body(204) --> nil
-- get_default_exit_body(204, "foo") --> nil
--
-- --- 405, 500 & 502 always return predefined values
--
-- get_default_exit_body(502, "ignored") --> { message = "Bad gateway" }
--
-- --- If message is a table, it is returned
--
-- get_default_exit_body(200, { ok = true }) --> { ok = true }
--
-- --- If message is not a table, it is transformed into one
--
-- get_default_exit_body(200, "ok") --> { message = "ok" }
--
-- --- 401, 404 and 503 provide default values if none is defined
--
-- get_default_exit_body(404) --> { message = "Not found" }
--
do
  local _overrides = {
    [405] = "Method not allowed",
    [500] = "An unexpected error occurred",
    [502] = "Bad gateway",
  }

  local _defaults = {
    [401] = "Unauthorized",
    [404] = "Not found",
    [503] = "Service unavailable",
  }

  local MIN_STATUS_CODE      = 100
  local MAX_STATUS_CODE      = 599

  function _M.get_default_exit_body(status, message)
    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if status == 204 then
      return nil
    end

    local body = _overrides[status] or message or _defaults[status]
    if body ~= nil and type(body) ~= "table" then
      body = { message = body }
    end

    return body
  end
end


---
-- Converts bytes to another unit in a human-readable string.
-- @tparam number bytes A value in bytes.
--
-- @tparam[opt] string unit The unit to convert the bytes into. Can be either
-- of `b/B`, `k/K`, `m/M`, or `g/G` for bytes (unchanged), kibibytes,
-- mebibytes, or gibibytes, respectively. Defaults to `b` (bytes).
-- @tparam[opt] number scale The number of digits to the right of the decimal
-- point. Defaults to 2.
-- @treturn string A human-readable string.
-- @usage
--
-- bytes_to_str(5497558) -- "5497558"
-- bytes_to_str(5497558, "m") -- "5.24 MiB"
-- bytes_to_str(5497558, "G", 3) -- "5.120 GiB"
--
function _M.bytes_to_str(bytes, unit, scale)
  if not unit or unit == "" or lower(unit) == "b" then
    return fmt("%d", bytes)
  end

  scale = scale or 2

  if type(scale) ~= "number" or scale < 0 then
    error("scale must be equal or greater than 0", 2)
  end

  local fspec = fmt("%%.%df", scale)

  if lower(unit) == "k" then
    return fmt(fspec .. " KiB", bytes / 2^10)
  end

  if lower(unit) == "m" then
    return fmt(fspec .. " MiB", bytes / 2^20)
  end

  if lower(unit) == "g" then
    return fmt(fspec .. " GiB", bytes / 2^30)
  end

  error("invalid unit '" .. unit .. "' (expected 'k/K', 'm/M', or 'g/G')", 2)
end


return _M
