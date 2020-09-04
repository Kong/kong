local pl_stringx = require "pl.stringx"
local utils = require "kong.tools.utils"


local concat = table.concat


local listeners = {}


local subsystem_flags = {
  http = { "ssl", "http2", "proxy_protocol", "deferred", "bind", "reuseport",
           "backlog=%d+" },
  stream = { "udp", "ssl", "proxy_protocol", "bind", "reuseport", "backlog=%d+" },
}


-- This meta table will prevent the parsed table to be passed on in the
-- intermediate Kong config file in the prefix directory.
-- We thus avoid 'table: 0x41c3fa58' from appearing into the prefix
-- hidden configuration file.
-- This is only to be applied to values that are injected into the
-- configuration object, and not configuration properties themselves,
-- otherwise we would prevent such properties from being specifiable
-- via environment variables.
local _nop_tostring_mt = {
  __tostring = function() return "" end,
}


-- @param value The options string to check for flags (whitespace separated)
-- @param flags List of boolean flags to check for.
-- @returns 1) remainder string after all flags removed, 2) table with flag
-- booleans, 3) sanitized flags string
local function parse_option_flags(value, flags)
  assert(type(value) == "string")

  value = " " .. value .. " "

  local sanitized = ""
  local result = {}

  for _, flag in ipairs(flags) do
    local count
    local patt = "%s(" .. flag .. ")%s"

    local found = value:match(patt)
    if found then
      -- replace pattern like `backlog=%d+` with actual values
      flag = found
    end

    value, count = value:gsub(patt, " ")

    if count > 0 then
      result[flag] = true
      sanitized = sanitized .. " " .. flag

    else
      result[flag] = false
    end
  end

  return pl_stringx.strip(value), result, pl_stringx.strip(sanitized)
end


-- Parses a listener address line.
-- Supports multiple (comma separated) addresses, with flags such as
-- 'ssl' and 'http2' added to the end.
-- Pre- and postfixed whitespace as well as comma's are allowed.
-- "off" as a first entry will return empty tables.
-- @param values list of entries (strings)
-- @param flags array of strings listing accepted flags.
-- @return list of parsed entries, each entry having fields
-- `listener` (string, full listener), `ip` (normalized string)
-- `port` (number), and a boolean entry for each flag added to the entry
-- (e.g. `ssl`).
local function parse_listeners(values, flags)
  assert(type(flags) == "table")
  local list = {}
  local usage = "must be of form: [off] | <ip>:<port> [" ..
                concat(flags, "] [") .. "], [... next entry ...]"

  if #values == 0 then
    return nil, usage
  end

  if pl_stringx.strip(values[1]) == "off" then
    return list
  end

  for _, entry in ipairs(values) do
    -- parse the flags
    local remainder, listener, cleaned_flags = parse_option_flags(entry, flags)

    -- verify IP for remainder
    local ip

    if utils.hostname_type(remainder) == "name" then
      -- it's not an IP address, so a name/wildcard/regex
      ip = {}
      ip.host, ip.port = remainder:match("(.+):([%d]+)$")

    else
      -- It's an IPv4 or IPv6, normalize it
      ip = utils.normalize_ip(remainder)
      -- nginx requires brackets in IPv6 addresses, but normalize_ip does
      -- not include them (due to backwards compatibility with its other uses)
      if ip and ip.type == "ipv6" then
        ip.host = "[" .. ip.host .. "]"
      end
    end

    if not ip or not ip.port then
      return nil, usage
    end

    listener.ip = ip.host
    listener.port = ip.port
    listener.listener = ip.host .. ":" .. ip.port ..
                        (#cleaned_flags == 0 and "" or " " .. cleaned_flags)

    table.insert(list, listener)
  end

  return list
end


-- Parse a set of "*_listen" flags from the configuration.
-- @tparam table conf The main configuration table
-- @tparam table listener_config The listener configuration to parse.
-- Each item is a table with the following keys:
-- * 'name' (e.g. 'proxy_listen')
-- * 'subsystem' ("http" or "stream") or 'flags' (for a custom array of flags)
-- * 'ssl_flag' (name of the ssl flag to set if the 'ssl' flag is set (optional)
function listeners.parse(conf, listener_configs)
  for _, l in ipairs(listener_configs) do
    local plural = l.name .. "ers" -- proxy_listen -> proxy_listeners

    -- extract ports/listen ips
    local flags = l.flags or subsystem_flags[l.subsystem]
    local err
    conf[plural], err = parse_listeners(conf[l.name], flags)
    if err then
      return nil, l.name .. " " .. err
    end
    setmetatable(conf[plural], _nop_tostring_mt)

    if l.ssl_flag then
      conf[l.ssl_flag] = false
      for _, listener in ipairs(conf[plural]) do
        if listener.ssl == true then
          conf[l.ssl_flag] = true
          break
        end
      end
    end
  end

  return true
end


return listeners
