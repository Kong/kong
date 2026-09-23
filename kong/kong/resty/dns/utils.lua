--------------------------------------------------------------------------
-- DNS utility module.
--
-- Parses the `/etc/hosts` and `/etc/resolv.conf` configuration files, caches them,
-- and provides some utility functions.
--
-- _NOTE_: parsing the files is done using blocking i/o file operations.
--
-- @copyright 2016-2020 Kong Inc.
-- @author Thijs Schreijer
-- @license Apache 2.0


local _M = {}
local utils = require("pl.utils")
local gsub = string.gsub
local tinsert = table.insert
local time = ngx.now

-- pattern that will only match data before a # or ; comment
-- returns nil if there is none before the # or ;
-- 2nd capture is the comment after the # or ;
local PATT_COMMENT = "^([^#;]+)[#;]*(.*)$"
-- Splits a string in IP and hostnames part, drops leading/trailing whitespace
local PATT_IP_HOST = "^%s*([%[%]%x%.%:]+)%s+(%S.-%S)%s*$"

local _DEFAULT_HOSTS = "/etc/hosts"              -- hosts filename to use when omitted
local _DEFAULT_RESOLV_CONF = "/etc/resolv.conf"  -- resolv.conf default filename

--- Default filename to parse for the `hosts` file.
-- @field DEFAULT_HOSTS Defaults to `/etc/hosts`
_M.DEFAULT_HOSTS = _DEFAULT_HOSTS

--- Default filename to parse for the `resolv.conf` file.
-- @field DEFAULT_RESOLV_CONF Defaults to `/etc/resolv.conf`
_M.DEFAULT_RESOLV_CONF = _DEFAULT_RESOLV_CONF

--- Maximum number of nameservers to parse from the `resolv.conf` file
-- @field MAXNS Defaults to 3
_M.MAXNS = 3

--- Maximum number of entries to parse from `search` parameter in the `resolv.conf` file
-- @field MAXSEARCH Defaults to 6
_M.MAXSEARCH = 6

--- Parsing configuration files and variables
-- @section parsing

--- Parses a `hosts` file or table.
-- Does not check for correctness of ip addresses nor hostnames. Might return
-- `nil + error` if the file cannot be read.
--
-- __NOTE__: All output will be normalized to lowercase, IPv6 addresses will
-- always be returned in brackets.
-- @param filename (optional) Filename to parse, or a table with the file
-- contents in lines (defaults to `'/etc/hosts'` if omitted)
-- @return 1; reverse lookup table, ip addresses (table with `ipv4` and `ipv6`
-- fields) indexed by their canonical names and aliases
-- @return 2; list with all entries. Containing fields `ip`, `canonical` and `family`,
-- and a list of aliasses
-- @usage local lookup, list = utils.parseHosts({
--   "127.0.0.1   localhost",
--   "1.2.3.4     someserver",
--   "192.168.1.2 test.computer.com",
--   "192.168.1.3 ftp.COMPUTER.com alias1 alias2",
-- })
--
-- print(lookup["localhost"])         --> "127.0.0.1"
-- print(lookup["ftp.computer.com"])  --> "192.168.1.3" note: name in lowercase!
-- print(lookup["alias1"])            --> "192.168.1.3"
_M.parseHosts = function(filename)
  local lines
  if type(filename) == "table" then
    lines = filename
  else
    local err
    lines, err = utils.readlines(filename or _M.DEFAULT_HOSTS)
    if not lines then return lines, err end
  end
  local result = {}
  local reverse = {}
  for _, line in ipairs(lines) do
    line = line:lower()
    local data, _ = line:match(PATT_COMMENT)
    if data then
      local ip, hosts, family, name, _
      -- parse the line
      ip, hosts = data:match(PATT_IP_HOST)
      -- parse and validate the ip address
      if ip then
        name, _, family = _M.parseHostname(ip)
        if family ~= "ipv4" and family ~= "ipv6" then
          ip = nil  -- not a valid IP address
        else
          ip = name
        end
      end
      -- add the names
      if ip and hosts then
        local entry = { ip = ip, family = family }
        local key = "canonical"
        for host in hosts:gmatch("%S+") do
          entry[key] = host
          key = (tonumber(key) or 0) + 1
          local rev = reverse[host]
          if not rev then
            rev = {}
            reverse[host] = rev
          end
          rev[family] = rev[family] or ip -- do not overwrite, first one wins
        end
        tinsert(result, entry)
      end
    end
  end
  return reverse, result
end


local boolOptions = { "debug", "rotate", "no-check-names", "inet6",
                       "ip6-bytestring", "ip6-dotint", "no-ip6-dotint",
                       "edns0", "single-request", "single-request-reopen",
                       "no-tld-query", "use-vc"}
for i, name in ipairs(boolOptions) do boolOptions[name] = name boolOptions[i] = nil end

local numOptions = { "ndots", "timeout", "attempts" }
for i, name in ipairs(numOptions) do numOptions[name] = name numOptions[i] = nil end

-- Parses a single option.
-- @param target table in which to insert the option
-- @param details string containing the option details
-- @return modified target table
local parseOption = function(target, details)
  local option, n = details:match("^([^:]+)%:*(%d*)$")
  if boolOptions[option] and n == "" then
    target[option] = true
    if option == "ip6-dotint" then target["no-ip6-dotint"] = nil end
    if option == "no-ip6-dotint" then target["ip6-dotint"] = nil end
  elseif numOptions[option] and tonumber(n) then
    target[option] = tonumber(n)
  end
end

--- Parses a `resolv.conf` file or table.
-- Does not check for correctness of ip addresses nor hostnames, bad options
-- will be ignored. Might return `nil + error` if the file cannot be read.
-- @param filename (optional) File to parse (defaults to `'/etc/resolv.conf'` if
-- omitted) or a table with the file contents in lines.
-- @return a table with fields `nameserver` (table), `domain` (string), `search` (table),
-- `sortlist` (table) and `options` (table)
-- @see applyEnv
_M.parseResolvConf = function(filename)
  local lines
  if type(filename) == "table" then
    lines = filename
  else
    local err
    lines, err = utils.readlines(filename or _M.DEFAULT_RESOLV_CONF)
    if not lines then return lines, err end
  end
  local result = {}
  for _,line in ipairs(lines) do
    local data, _ = line:match(PATT_COMMENT)
    if data then
      local option, details = data:match("^%s*(%a+)%s+(.-)%s*$")
      if option == "nameserver" then
        result.nameserver = result.nameserver or {}
        if #result.nameserver < _M.MAXNS then
          tinsert(result.nameserver, details:lower())
        end
      elseif option == "domain" then
        result.search = nil  -- mutually exclusive, last one wins
        result.domain = details:lower()
      elseif option == "search" then
        result.domain = nil  -- mutually exclusive, last one wins
        local search = {}
        result.search = search
        for host in details:gmatch("%S+") do
          if #search < _M.MAXSEARCH then
            tinsert(search, host:lower())
          end
        end
      elseif option == "sortlist" then
        local list = {}
        result.sortlist = list
        for ips in details:gmatch("%S+") do
          tinsert(list, ips)
        end
      elseif option == "options" then
        result.options = result.options or {}
        parseOption(result.options, details)
      end
    end
  end
  return result
end

--- Will parse `LOCALDOMAIN` and `RES_OPTIONS` environment variables.
-- It will insert them into the given `resolv.conf` based configuration table.
--
-- __NOTE__: if the input is `nil+error` it will return the input, to allow for
-- pass-through error handling
-- @param config Options table, as parsed by `parseResolvConf`, or an empty table to get only the environment options
-- @return modified table
-- @see parseResolvConf
-- @usage -- errors are passed through, so this;
-- local config, err = utils.parseResolvConf()
-- if config then
--   config, err = utils.applyEnv(config)
-- end
--
-- -- Is identical to;
-- local config, err = utils.applyEnv(utils.parseResolvConf())
_M.applyEnv = function(config, err)
  if not config then return config, err end -- allow for 'nil+error' pass-through
  local localdomain = os.getenv("LOCALDOMAIN") or ""
  if localdomain ~= "" then
    config.domain = nil  -- mutually exclusive, last one wins
    local search = {}
    config.search = search
    for host in localdomain:gmatch("%S+") do
      tinsert(search, host:lower())
    end
  end

  local options = os.getenv("RES_OPTIONS") or ""
  if options ~= "" then
    config.options = config.options or {}
    for option in options:gmatch("%S+") do
      parseOption(config.options, option)
    end
  end
  return config
end

--- Caching configuration files and variables
-- @section caching

-- local caches
local cacheHosts  -- cached value
local cacheHostsr  -- cached value
local lastHosts = 0 -- timestamp
local ttlHosts   -- time to live for cache

--- returns the `parseHosts` results, but cached.
-- Once `ttl` has been provided, only after it expires the file will be parsed again.
--
-- __NOTE__: if cached, the _SAME_ tables will be returned, so do not modify them
-- unless you know what you are doing!
-- @param ttl cache time-to-live in seconds (can be updated in following calls)
-- @return reverse and list tables, same as `parseHosts`.
-- @see parseHosts
_M.getHosts = function(ttl)
  ttlHosts = ttl or ttlHosts
  local now = time()
  if (not ttlHosts) or (lastHosts + ttlHosts <= now) then
    cacheHosts = nil    -- expired
    cacheHostsr = nil    -- expired
  end

  if not cacheHosts then
    cacheHostsr, cacheHosts = _M.parseHosts()
    lastHosts = now
  end

  return cacheHostsr, cacheHosts
end


local cacheResolv  -- cached value
local lastResolv = 0 -- timestamp
local ttlResolv   -- time to live for cache

--- returns the `applyEnv` results, but cached.
-- Once `ttl` has been provided, only after it expires it will be parsed again.
--
-- __NOTE__: if cached, the _SAME_ table will be returned, so do not modify them
-- unless you know what you are doing!
-- @param ttl cache time-to-live in seconds (can be updated in following calls)
-- @return configuration table, same as `parseResolveConf`.
-- @see parseResolvConf
_M.getResolv = function(ttl)
  ttlResolv = ttl or ttlResolv
  local now = time()
  if (not ttlResolv) or (lastResolv + ttlResolv <= now) then
    cacheResolv = nil    -- expired
  end

  if not cacheResolv then
    lastResolv = now
    cacheResolv = _M.applyEnv(_M.parseResolvConf())
  end

  return cacheResolv
end

--- Miscellaneous
-- @section miscellaneous

--- checks the hostname type; ipv4, ipv6, or name.
-- Type is determined by exclusion, not by validation. So if it returns `'ipv6'` then
-- it can only be an ipv6, but it is not necessarily a valid ipv6 address.
-- @param name the string to check (this may contain a port number)
-- @return string either; `'ipv4'`, `'ipv6'`, or `'name'`
-- @usage hostnameType("123.123.123.123")  -->  "ipv4"
-- hostnameType("127.0.0.1:8080")   -->  "ipv4"
-- hostnameType("::1")              -->  "ipv6"
-- hostnameType("[::1]:8000")       -->  "ipv6"
-- hostnameType("some::thing")      -->  "ipv6", but invalid...
_M.hostnameType = function(name)
  local remainder, colons = gsub(name, ":", "")
  if colons > 1 then return "ipv6" end
  if remainder:match("^[%d%.]+$") then return "ipv4" end
  return "name"
end

--- parses a hostname with an optional port.
-- Does not validate the name/ip. IPv6 addresses are always returned in
-- square brackets, even if the input wasn't.
-- @param name the string to check (this may contain a port number)
-- @return `name/ip` + `port (or nil)` + `type` (one of: `"ipv4"`, `"ipv6"`, or `"name"`)
_M.parseHostname = function(name)
  local t = _M.hostnameType(name)
  if t == "ipv4" or t == "name" then
    local ip, port = name:match("^([^:]+)%:*(%d*)$")
    return ip, tonumber(port), t
  elseif t == "ipv6" then
    if name:match("%[") then  -- brackets, so possibly a port
      local ip, port = name:match("^%[([^%]]+)%]*%:*(%d*)$")
      return "["..ip.."]", tonumber(port), t
    end
    return "["..name.."]", nil, t  -- no brackets also means no port
  end
  return nil, nil, nil -- should never happen
end

return _M
