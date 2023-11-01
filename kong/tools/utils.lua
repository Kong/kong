---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is preferred.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local ffi = require "ffi"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"

local C             = ffi.C
local ffi_new       = ffi.new
local type          = type
local pairs         = pairs
local ipairs        = ipairs
local tostring      = tostring
local tonumber      = tonumber
local sort          = table.sort
local concat        = table.concat
local insert        = table.insert
local lower         = string.lower
local fmt           = string.format
local find          = string.find
local gsub          = string.gsub
local join          = pl_stringx.join
local split         = pl_stringx.split
local re_match      = ngx.re.match
local setmetatable  = setmetatable

ffi.cdef[[
typedef long time_t;
typedef int clockid_t;
typedef struct timespec {
        time_t   tv_sec;        /* seconds */
        long     tv_nsec;       /* nanoseconds */
} nanotime;

int clock_gettime(clockid_t clk_id, struct timespec *tp);

int gethostname(char *name, size_t len);
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

do
  local _system_infos

  function _M.get_system_infos()
    if _system_infos then
      return _system_infos
    end

    _system_infos = {}

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

do
  local trusted_certs_paths = {
    "/etc/ssl/certs/ca-certificates.crt",                -- Debian/Ubuntu/Gentoo
    "/etc/pki/tls/certs/ca-bundle.crt",                  -- Fedora/RHEL 6
    "/etc/ssl/ca-bundle.pem",                            -- OpenSUSE
    "/etc/pki/tls/cacert.pem",                           -- OpenELEC
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", -- CentOS/RHEL 7
    "/etc/ssl/cert.pem",                                 -- OpenBSD, Alpine
  }

  function _M.get_system_trusted_certs_filepath()
    for _, path in ipairs(trusted_certs_paths) do
      if pl_path.exists(path) then
        return path
      end
    end

    return nil,
           "Could not find trusted certs file in " ..
           "any of the `system`-predefined locations. " ..
           "Please install a certs file there or set " ..
           "lua_ssl_trusted_certificate to an " ..
           "specific filepath instead of `system`"
  end
end


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


  local ngx_null = ngx.null

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
      elseif value == ngx_null then
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

    sort(keys)
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
        v = ngx_null
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


--- Try to load a module.
-- Will not throw an error if the module was not found, but will throw an error if the
-- loading failed for another reason (eg: syntax error).
-- @param module_name Path of the module to load (ex: kong.plugins.keyauth.api).
-- @return success A boolean indicating whether the module was found.
-- @return module The retrieved module, or the error in case of a failure
function _M.load_module_if_exists(module_name)
  local status, res = xpcall(function()
    return require(module_name)
  end, debug.traceback)
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


do
  local ipmatcher =  require "resty.ipmatcher"
  local sub = string.sub

  local ipv4_prefixes = {}
  for i = 0, 32 do
    ipv4_prefixes[tostring(i)] = i
  end

  local ipv6_prefixes = {}
  for i = 0, 128 do
    ipv6_prefixes[tostring(i)] = i
  end

  local function split_cidr(cidr, prefixes)
    local p = find(cidr, "/", 3, true)
    if not p then
      return
    end

    return sub(cidr, 1, p - 1), prefixes[sub(cidr, p + 1)]
  end

  local validate = function(input, f1, f2, prefixes)
    if type(input) ~= "string" then
      return false
    end

    if prefixes then
      local ip, prefix = split_cidr(input, prefixes)
      if not ip or not prefix then
        return false
      end

      input = ip
    end

    if f1(input) then
      return true
    end

    if f2 and f2(input) then
      return true
    end

    return false
  end

  _M.is_valid_ipv4 = function(ipv4)
    return validate(ipv4, ipmatcher.parse_ipv4)
  end

  _M.is_valid_ipv6 = function(ipv6)
    return validate(ipv6, ipmatcher.parse_ipv6)
  end

  _M.is_valid_ip = function(ip)
    return validate(ip, ipmatcher.parse_ipv4, ipmatcher.parse_ipv6)
  end

  _M.is_valid_cidr_v4 = function(cidr_v4)
    return validate(cidr_v4, ipmatcher.parse_ipv4, nil, ipv4_prefixes)
  end

  _M.is_valid_cidr_v6 = function(cidr_v6)
    return validate(cidr_v6, ipmatcher.parse_ipv6, nil, ipv6_prefixes)
  end

  _M.is_valid_cidr = function(cidr)
    return validate(cidr, _M.is_valid_cidr_v4, _M.is_valid_cidr_v6)
  end

  _M.is_valid_ip_or_cidr_v4 = function(ip_or_cidr_v4)
    return validate(ip_or_cidr_v4, ipmatcher.parse_ipv4, _M.is_valid_cidr_v4)
  end

  _M.is_valid_ip_or_cidr_v6 = function(ip_or_cidr_v6)
    return validate(ip_or_cidr_v6, ipmatcher.parse_ipv6, _M.is_valid_cidr_v6)
  end

  _M.is_valid_ip_or_cidr = function(ip_or_cidr)
    return validate(ip_or_cidr, _M.is_valid_ip,  _M.is_valid_cidr)
  end
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
  -- notes:
  --   - punycode allows prefixed dash, if the characters before the dash are escaped
  --   - FQDN can end in dots
  for index, segment in ipairs(split(name, ".")) do
    if segment:match("-$") or segment:match("^%.") or segment:match("%.$") or
       (segment == "" and index ~= #split(name, ".")) then
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
-- Explicitly accepts 'nil+error' as input, to pass through any errors from the normalizing and name checking functions.
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


local validate_labels
do
  local nkeys = require "table.nkeys"

  local MAX_KEY_SIZE   = 63
  local MAX_VALUE_SIZE = 63
  local MAX_KEYS_COUNT = 10

  -- validation rules based on Kong Labels AIP
  -- https://kong-aip.netlify.app/aip/129/
  local BASE_PTRN = "[a-z0-9]([\\w\\.:-]*[a-z0-9]|)$"
  local KEY_PTRN  = "(?!kong)(?!konnect)(?!insomnia)(?!mesh)(?!kic)" .. BASE_PTRN
  local VAL_PTRN  = BASE_PTRN

  local function validate_entry(str, max_size, pattern)
    if str == "" or #str > max_size then
      return nil, fmt(
        "%s must have between 1 and %d characters", str, max_size)
    end
    if not re_match(str, pattern, "ajoi") then
      return nil, fmt("%s is invalid. Must match pattern: %s", str, pattern)
    end
    return true
  end

  -- Validates a label array.
  -- Validates labels based on the kong Labels AIP
  function validate_labels(raw_labels)
    if nkeys(raw_labels) > MAX_KEYS_COUNT then
      return nil, fmt(
        "labels validation failed: count exceeded %d max elements",
        MAX_KEYS_COUNT
      )
    end

    for _, kv in ipairs(raw_labels) do
      local del = kv:find(":", 1, true)
      local k = del and kv:sub(1, del - 1) or ""
      local v = del and kv:sub(del + 1) or ""

      local ok, err = validate_entry(k, MAX_KEY_SIZE, KEY_PTRN)
      if not ok then
        return nil, "label key validation failed: " .. err
      end
      ok, err = validate_entry(v, MAX_VALUE_SIZE, VAL_PTRN)
      if not ok then
        return nil, "label value validation failed: " .. err
      end
    end

    return true
  end
end
_M.validate_labels = validate_labels


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


do
  local NGX_ERROR = ngx.ERROR

  if not pcall(ffi.typeof, "ngx_uint_t") then
    ffi.cdef [[
      typedef uintptr_t ngx_uint_t;
    ]]
  end

  if not pcall(ffi.typeof, "ngx_int_t") then
    ffi.cdef [[
      typedef intptr_t ngx_int_t;
    ]]
  end

  -- ngx_str_t defined by lua-resty-core
  local s = ffi_new("ngx_str_t[1]")
  s[0].data = "10"
  s[0].len = 2

  if not pcall(function() C.ngx_parse_time(s, 0) end) then
    ffi.cdef [[
      ngx_int_t ngx_parse_time(ngx_str_t *line, ngx_uint_t is_sec);
    ]]
  end

  function _M.nginx_conf_time_to_seconds(str)
    s[0].data = str
    s[0].len = #str

    local ret = C.ngx_parse_time(s, 1)
    if ret == NGX_ERROR then
      error("bad argument #1 'str'", 2)
    end

    return tonumber(ret, 10)
  end
end


local get_mime_type
local get_response_type
local get_error_template
do
  local CONTENT_TYPE_JSON    = "application/json"
  local CONTENT_TYPE_GRPC    = "application/grpc"
  local CONTENT_TYPE_HTML    = "text/html"
  local CONTENT_TYPE_XML     = "application/xml"
  local CONTENT_TYPE_PLAIN   = "text/plain"
  local CONTENT_TYPE_APP     = "application"
  local CONTENT_TYPE_TEXT    = "text"
  local CONTENT_TYPE_DEFAULT = "default"
  local CONTENT_TYPE_ANY     = "*"

  local MIME_TYPES = {
    [CONTENT_TYPE_GRPC]     = "",
    [CONTENT_TYPE_HTML]     = "text/html; charset=utf-8",
    [CONTENT_TYPE_JSON]     = "application/json; charset=utf-8",
    [CONTENT_TYPE_PLAIN]    = "text/plain; charset=utf-8",
    [CONTENT_TYPE_XML]      = "application/xml; charset=utf-8",
    [CONTENT_TYPE_APP]      = "application/json; charset=utf-8",
    [CONTENT_TYPE_TEXT]     = "text/plain; charset=utf-8",
    [CONTENT_TYPE_DEFAULT]  = "application/json; charset=utf-8",
  }

  local ERROR_TEMPLATES = {
    [CONTENT_TYPE_GRPC]   = "",
    [CONTENT_TYPE_HTML]   = [[
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Error</title>
  </head>
  <body>
    <h1>Error</h1>
    <p>%s.</p>
    <p>request_id: %s</p>
  </body>
</html>
]],
    [CONTENT_TYPE_JSON]   = [[
{
  "message":"%s",
  "request_id":"%s"
}]],
    [CONTENT_TYPE_PLAIN]  = "%s\nrequest_id: %s\n",
    [CONTENT_TYPE_XML]    = [[
<?xml version="1.0" encoding="UTF-8"?>
<error>
  <message>%s</message>
  <requestid>%s</requestid>
</error>
]],
  }

  local ngx_log = ngx.log
  local ERR     = ngx.ERR
  local custom_error_templates = setmetatable({}, {
    __index = function(self, format)
      local template_path = kong.configuration["error_template_" .. format]
      if not template_path then
        rawset(self, format, false)
        return false
      end

      local template, err
      if pl_path.exists(template_path) then
        template, err = pl_file.read(template_path)
      else
        err = "file not found"
      end

      if template then
        rawset(self, format, template)
        return template
      end

      ngx_log(ERR, fmt("failed reading the custom %s error template: %s", format, err))
      rawset(self, format, false)
      return false
    end
  })


  get_response_type = function(accept_header)
    local content_type = MIME_TYPES[CONTENT_TYPE_DEFAULT]
    if type(accept_header) == "table" then
      accept_header = join(",", accept_header)
    end

    if accept_header ~= nil then
      local pattern = [[
        ((?:[a-z0-9][a-z0-9-!#$&^_+.]+|\*) \/ (?:[a-z0-9][a-z0-9-!#$&^_+.]+|\*))
        (?:
          \s*;\s*
          q = ( 1(?:\.0{0,3}|) | 0(?:\.\d{0,3}|) )
          | \s*;\s* [a-z0-9][a-z0-9-!#$&^_+.]+ (?:=[^;]*|)
        )*
      ]]
      local accept_values = split(accept_header, ",")
      local max_quality = 0

      for _, accept_value in ipairs(accept_values) do
        accept_value = _M.strip(accept_value)
        local matches = ngx.re.match(accept_value, pattern, "ajoxi")

        if matches then
          local media_type = matches[1]
          local q = tonumber(matches[2]) or 1

          if q > max_quality then
            max_quality = q
            content_type = get_mime_type(media_type) or content_type
          end
        end
      end
    end

    return content_type
  end


  get_mime_type = function(content_header, use_default)
    use_default = use_default == nil or use_default
    content_header = _M.strip(content_header)
    content_header = _M.split(content_header, ";")[1]
    local mime_type

    local entries = split(content_header, "/")
    if #entries > 1 then
      if entries[2] == CONTENT_TYPE_ANY then
        if entries[1] == CONTENT_TYPE_ANY then
          mime_type = MIME_TYPES[CONTENT_TYPE_DEFAULT]
        else
          mime_type = MIME_TYPES[entries[1]]
        end
      else
        mime_type = MIME_TYPES[content_header]
      end
    end

    if mime_type or use_default then
      return mime_type or MIME_TYPES[CONTENT_TYPE_DEFAULT]
    end

    return nil, "could not find MIME type"
  end


  get_error_template = function(mime_type)
    if mime_type == CONTENT_TYPE_JSON or mime_type == MIME_TYPES[CONTENT_TYPE_JSON] then
      return custom_error_templates.json or ERROR_TEMPLATES[CONTENT_TYPE_JSON]

    elseif mime_type == CONTENT_TYPE_HTML or mime_type == MIME_TYPES[CONTENT_TYPE_HTML] then
      return custom_error_templates.html or ERROR_TEMPLATES[CONTENT_TYPE_HTML]

    elseif mime_type == CONTENT_TYPE_XML or mime_type == MIME_TYPES[CONTENT_TYPE_XML] then
      return custom_error_templates.xml or ERROR_TEMPLATES[CONTENT_TYPE_XML]

    elseif mime_type == CONTENT_TYPE_PLAIN or mime_type == MIME_TYPES[CONTENT_TYPE_PLAIN] then
      return custom_error_templates.plain or ERROR_TEMPLATES[CONTENT_TYPE_PLAIN]

    elseif mime_type == CONTENT_TYPE_GRPC or mime_type == MIME_TYPES[CONTENT_TYPE_GRPC] then
      return ERROR_TEMPLATES[CONTENT_TYPE_GRPC]

    end

    return nil, "no template found for MIME type " .. (mime_type or "empty")
  end

end
_M.get_mime_type = get_mime_type
_M.get_response_type = get_response_type
_M.get_error_template = get_error_template


local topological_sort do

  local function visit(current, neighbors_map, visited, marked, sorted)
    if visited[current] then
      return true
    end

    if marked[current] then
      return nil, "Cycle detected, cannot sort topologically"
    end

    marked[current] = true

    local schemas_pointing_to_current = neighbors_map[current]
    if schemas_pointing_to_current then
      local neighbor, ok, err
      for i = 1, #schemas_pointing_to_current do
        neighbor = schemas_pointing_to_current[i]
        ok, err = visit(neighbor, neighbors_map, visited, marked, sorted)
        if not ok then
          return nil, err
        end
      end
    end

    marked[current] = false

    visited[current] = true

    insert(sorted, 1, current)

    return true
  end

  topological_sort = function(items, get_neighbors)
    local neighbors_map = {}
    local source, destination
    local neighbors
    for i = 1, #items do
      source = items[i] -- services
      neighbors = get_neighbors(source)
      for j = 1, #neighbors do
        destination = neighbors[j] --routes
        neighbors_map[destination] = neighbors_map[destination] or {}
        insert(neighbors_map[destination], source)
      end
    end

    local sorted = {}
    local visited = {}
    local marked = {}

    local current, ok, err
    for i = 1, #items do
      current = items[i]
      if not visited[current] and not marked[current] then
        ok, err = visit(current, neighbors_map, visited, marked, sorted)
        if not ok then
          return nil, err
        end
      end
    end

    return sorted
  end
end
_M.topological_sort = topological_sort

---
-- Sort by handler priority and check for collisions. In case of a collision
-- sorting will be applied based on the plugin's name.
-- @tparam table plugin table containing `handler` table and a `name` string
-- @tparam table plugin table containing `handler` table and a `name` string
-- @treturn boolean outcome of sorting
function _M.sort_by_handler_priority(a, b)
  local prio_a = a.handler.PRIORITY or 0
  local prio_b = b.handler.PRIORITY or 0
  if prio_a == prio_b and not
      (prio_a == 0 or prio_b == 0) then
    return a.name > b.name
  end
  return prio_a > prio_b
end


local time_ns
do
  local nanop = ffi_new("nanotime[1]")
  function time_ns()
    -- CLOCK_REALTIME -> 0
    C.clock_gettime(0, nanop)
    local t = nanop[0]

    return tonumber(t.tv_sec) * 1e9 + tonumber(t.tv_nsec)
  end
end
_M.time_ns = time_ns


local try_decode_base64
do
  local decode_base64    = ngx.decode_base64
  local decode_base64url = require "ngx.base64".decode_base64url

  local function decode_base64_str(str)
    if type(str) == "string" then
      return decode_base64(str)
             or decode_base64url(str)
             or nil, "base64 decoding failed: invalid input"

    else
      return nil, "base64 decoding failed: not a string"
    end
  end

  function try_decode_base64(value)
    if type(value) == "table" then
      for i, v in ipairs(value) do
        value[i] = decode_base64_str(v) or v
      end

      return value
    end

    if type(value) == "string" then
      return decode_base64_str(value) or value
    end

    return value
  end
end
_M.try_decode_base64 = try_decode_base64


local get_now_ms
local get_updated_now_ms
local get_start_time_ms
local get_updated_monotonic_ms
do
  local now             = ngx.now
  local update_time     = ngx.update_time
  local start_time      = ngx.req.start_time
  local monotonic_msec  = require("resty.core.time").monotonic_msec

  function get_now_ms()
    return now() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function get_updated_now_ms()
    update_time()
    return now() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function get_start_time_ms()
    return start_time() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function get_updated_monotonic_ms()
    update_time()
    return monotonic_msec()
  end
end
_M.get_now_ms         = get_now_ms
_M.get_updated_now_ms = get_updated_now_ms
_M.get_start_time_ms  = get_start_time_ms
_M.get_updated_monotonic_ms = get_updated_monotonic_ms


do
  local modules = {
    "kong.tools.gzip",
    "kong.tools.table",
    "kong.tools.sha256",
    "kong.tools.yield",
    "kong.tools.uuid",
    "kong.tools.rand",
  }

  for _, str in ipairs(modules) do
    local mod = require(str)
    for name, func in pairs(mod) do
      _M[name] = func
    end
  end
end


return _M
