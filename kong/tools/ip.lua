local ipmatcher  = require "resty.ipmatcher"



local type     = type
local ipairs   = ipairs
local tonumber = tonumber
local tostring = tostring
local gsub     = string.gsub
local sub      = string.sub
local fmt      = string.format
local lower    = string.lower
local find     = string.find
local split    = require("kong.tools.string").split


local _M = {}


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


local function validate(input, f1, f2, prefixes)
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


function _M.is_valid_ipv4(ipv4)
  return validate(ipv4, ipmatcher.parse_ipv4)
end


function _M.is_valid_ipv6(ipv6)
  return validate(ipv6, ipmatcher.parse_ipv6)
end


function _M.is_valid_ip(ip)
  return validate(ip, ipmatcher.parse_ipv4, ipmatcher.parse_ipv6)
end


function _M.is_valid_cidr_v4(cidr_v4)
  return validate(cidr_v4, ipmatcher.parse_ipv4, nil, ipv4_prefixes)
end


function _M.is_valid_cidr_v6(cidr_v6)
  return validate(cidr_v6, ipmatcher.parse_ipv6, nil, ipv6_prefixes)
end


function _M.is_valid_cidr(cidr)
  return validate(cidr, _M.is_valid_cidr_v4, _M.is_valid_cidr_v6)
end


function _M.is_valid_ip_or_cidr_v4(ip_or_cidr_v4)
  return validate(ip_or_cidr_v4, ipmatcher.parse_ipv4, _M.is_valid_cidr_v4)
end


function _M.is_valid_ip_or_cidr_v6(ip_or_cidr_v6)
  return validate(ip_or_cidr_v6, ipmatcher.parse_ipv6, _M.is_valid_cidr_v6)
end


function _M.is_valid_ip_or_cidr(ip_or_cidr)
  return validate(ip_or_cidr, _M.is_valid_ip,  _M.is_valid_cidr)
end


--- checks the hostname type; ipv4, ipv6, or name.
-- Type is determined by exclusion, not by validation. So if it returns 'ipv6' then
-- it can only be an ipv6, but it is not necessarily a valid ipv6 address.
-- @param name the string to check (this may contain a portnumber)
-- @return string either; 'ipv4', 'ipv6', or 'name'
-- @usage hostname_type("123.123.123.123")  -->  "ipv4"
-- hostname_type("::1")              -->  "ipv6"
-- hostname_type("some::thing")      -->  "ipv6", but invalid...
function _M.hostname_type(name)
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
function _M.normalize_ipv4(address)
  local a,b,c,d,port
  if address:find(":", 1, true) then
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
function _M.normalize_ipv6(address)
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
  if check:find("::", 1, true) then
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
function _M.check_hostname(address)
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
function _M.normalize_ip(address)
  local atype = _M.hostname_type(address)
  local addr, port = verify_types[atype](address)
  if not addr then
    return nil, port
  end
  return {
    type = atype,
    host = addr,
    port = port,
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
function _M.format_host(p1, p2)
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


return _M
