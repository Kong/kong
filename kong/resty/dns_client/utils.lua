local utils = require("kong.resty.dns.utils")

local log = ngx.log
local NOTICE = ngx.NOTICE

local math_random   = math.random
local table_insert  = table.insert
local table_remove  = table.remove

local readlines = require("pl.utils").readlines

local DEFAULT_HOSTS_FILE  = "/etc/hosts"
local DEFAULT_RESOLV_CONF = "/etc/resolv.conf"

local LOCALHOST = {
  ipv4 = "127.0.0.1",
  ipv6 = "[::1]",
}

local DEFAULT_HOSTS = { localhost = LOCALHOST }


local _M = {}


-- checks the hostname type
-- @return "ipv4", "ipv6", or "name"
function _M.hostname_type(name)
  local remainder, colons = name:gsub(":", "")
  if colons > 1 then
    return "ipv6"
  end

  if remainder:match("^[%d%.]+$") then
    return "ipv4"
  end

  return "name"
end


-- parses a hostname with an optional port
-- IPv6 addresses are always returned in square brackets
-- @param name the string to check (this may contain a port number)
-- @return `name/ip` + `port (or nil)` + `type ("ipv4", "ipv6" or "name")`
function _M.parse_hostname(name)
  local t = _M.hostname_type(name)
  if t == "ipv4" or t == "name" then
    local ip, port = name:match("^([^:]+)%:*(%d*)$")
    return ip, tonumber(port), t
  end

  -- ipv6
  if name:match("%[") then  -- brackets, so possibly a port
    local ip, port = name:match("^%[([^%]]+)%]*%:*(%d*)$")
    return "[" .. ip .. "]", tonumber(port), t
  end

  return "[" .. name .. "]", nil, t  -- no brackets also means no port
end


local function get_lines(path)
  if type(path) == "table" then
    return path
  end
  return readlines(path)
end


function _M.parse_hosts(path, enable_ipv6)
  local lines, err = get_lines(path or DEFAULT_HOSTS_FILE)
  if not lines then
    log(NOTICE, "Invalid hosts file: ", err)
    return DEFAULT_HOSTS
  end

  local hosts = {}

  for _, line in ipairs(lines) do
    -- Remove leading/trailing whitespaces and split by whitespace
    local parts = {}
    for part in line:gmatch("%S+") do
      if part:sub(1, 1) == '#' then
        break
      end
      table_insert(parts, part:lower())
    end

    -- Check if the line contains an IP address followed by hostnames
    if #parts >= 2 then
      local ip, _, family = _M.parse_hostname(parts[1])
      if family ~= "name" then    -- ipv4/ipv6
        for i = 2, #parts do
          local host = parts[i]
          local v = hosts[host]
          if not v then
            v = {}
            hosts[host] = v
          end
          v[family] = v[family] or ip -- prefer to use the first ip
        end
      end
    end
  end

  if not hosts.localhost then
    hosts.localhost = LOCALHOST
  end

  return hosts
end


-- TODO: need to rewrite it instead of calling parseResolvConf from the old library
function _M.parse_resolv_conf(path, enable_ipv6)
  local resolv, err = utils.parseResolvConf(path or DEFAULT_RESOLV_CONF)
  if not resolv then
    return nil, err
  end

  resolv = utils.applyEnv(resolv)
  resolv.options = resolv.options or {}
  resolv.ndots = resolv.options.ndots or 1
  resolv.search = resolv.search or (resolv.domain and { resolv.domain })

  -- check if timeout is 0s
  if resolv.options.timeout and resolv.options.timeout <= 0 then
    log(NOTICE, "A non-positive timeout of ", resolv.options.timeout,
                "s is configured in resolv.conf. Setting it to 2000ms.")
    resolv.options.timeout = 2000 -- 2000ms is lua-resty-dns default
  end

  -- remove special domain like "."
  if resolv.search then
    for i = #resolv.search, 1, -1 do
      if resolv.search[i] == "." then
        table_remove(resolv.search, i)
      end
    end
  end

  -- nameservers
  if resolv.nameserver then
    local nameservers = {}

    for _, address in ipairs(resolv.nameserver) do
      local ip, port, t = utils.parseHostname(address)
      if t == "ipv4" or
        (t == "ipv6" and not ip:find([[%]], nil, true) and enable_ipv6)
      then
        table_insert(nameservers, port and { ip, port } or ip)
      end
    end

    resolv.nameservers = nameservers
  end
  return resolv
end


function _M.is_fqdn(name, ndots)
  if name:sub(-1) == "." then
    return true
  end
  local _, dot_count = name:gsub("%.", "")
  return (dot_count >= ndots)
end


-- construct names from resolv options: search, ndots and domain
function _M.search_names(name, resolv, hosts)
  if not resolv.search or _M.is_fqdn(name, resolv.ndots) then
    return { name }
  end

  local names = {}
  for _, suffix in ipairs(resolv.search) do
    table_insert(names, name .. "." .. suffix)
  end

  if hosts and hosts[name] then
    table_insert(names, 1, name)
  else
    table_insert(names, name)
  end

  return names
end


function _M.ipv6_bracket(name)
  if name:match("^[^[].*:") then  -- not rigorous, but sufficient
    return "[" .. name .. "]"
  end
  return name
end


-- util APIs to balance @answers

function _M.get_round_robin_answers(answers)
  answers.last = (answers.last or 0) % #answers + 1
  return answers[answers.last]
end


-- based on the Nginx's SWRR algorithm and lua-resty-balancer
local function swrr_next(answers)
  local total = 0
  local best = nil    -- best answer in answers[]

  for _, answer in ipairs(answers) do
    -- 0.1 gives weight 0 record a minimal chance of being chosen (rfc 2782)
    local w = (answer.weight == 0) and 0.1 or answer.weight
    local cw = answer.cw + w
    answer.cw = cw
    if not best or cw > best.cw then
      best = answer
    end
    total = total + w
  end

  best.cw = best.cw - total
  return best
end


local function swrr_init(answers)
  for _, answer in ipairs(answers) do
    answer.cw = 0   -- current weight
  end

  -- random start
  for _ = 1, math_random(#answers) do
    swrr_next(answers)
  end
end


-- gather records with the lowest priority in SRV record
local function filter_lowest_priority_answers(answers)
  local lowest_priority = answers[1].priority
  local l = {}    -- lowest priority records list

  for _, answer in ipairs(answers) do
    if answer.priority < lowest_priority then
      lowest_priority = answer.priority
      l = { answer }

    elseif answer.priority == lowest_priority then
      table_insert(l, answer)
    end
  end

  answers.lowest_prio_records = l
  return l
end


function _M.get_weighted_round_robin_answers(answers)
  local l = answers.lowest_prio_records or filter_lowest_priority_answers(answers)

  -- perform round robin selection on lowest priority answers @l
  if not l[1].cw then
    swrr_init(l)
  end

  return swrr_next(l)
end


return _M
