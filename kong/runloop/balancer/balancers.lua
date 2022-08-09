

local upstreams = require "kong.runloop.balancer.upstreams"
local targets
local healthcheckers
local dns_utils = require "kong.resty.dns.utils"
local constants = require "kong.constants"

local ngx = ngx
local log = ngx.log
local sleep = ngx.sleep
local min = math.min
local max = math.max
local sub = string.sub
local find = string.find
local pairs = pairs
local table_remove = table.remove


local CRIT = ngx.CRIT
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

--local DEFAULT_WEIGHT = 10   -- default weight for a host, if not provided
--local DEFAULT_PORT = 80     -- Default port to use (A and AAAA only) when not provided
local TTL_0_RETRY = 60      -- Maximum life-time for hosts added with ttl=0, requery after it expires
local REQUERY_INTERVAL = 30 -- Interval for requerying failed dns queries
local SRV_0_WEIGHT = 1      -- SRV record with weight 0 should be hit minimally, hence we replace by 1
local CLEAR_HEALTH_STATUS_DELAY = constants.CLEAR_HEALTH_STATUS_DELAY


local balancers_M = {}

local balancer_mt = {}
balancer_mt.__index = balancer_mt

local balancers_by_id = {}
local algorithm_types


balancers_M.errors = setmetatable({
  ERR_DNS_UPDATED = "Cannot get peer, a DNS update changed the balancer structure, please retry",
  ERR_ADDRESS_UNAVAILABLE = "Address is marked as unavailable",
  ERR_NO_PEERS_AVAILABLE = "No peers are available",
  ERR_BALANCER_UNHEALTHY = "Balancer is unhealthy",
}, {
  __index = function(_, key)
    error("invalid key: " .. tostring(key))
  end
})


function balancers_M.init()
  targets = require "kong.runloop.balancer.targets"
  healthcheckers = require "kong.runloop.balancer.healthcheckers"
end


function balancers_M.get_balancer_by_id(id)
  return balancers_by_id[id]
end

function balancers_M.set_balancer(upstream_id, balancer)
  balancers_by_id[upstream_id] = balancer
end


function balancers_M.get_upstream(balancer)
  local upstream_id = balancer.upstream_id
  return upstream_id and upstreams.get_upstream_by_id(upstream_id)
end


local creating = {}

local function wait(id)
  local timeout = 30
  local step = 0.001
  local ratio = 2
  local max_step = 0.5
  while timeout > 0 do
    sleep(step)
    timeout = timeout - step
    if not creating[id] then
      return true
    end
    if timeout <= 0 then
      break
    end
    step = min(max(0.001, step * ratio), timeout, max_step)
  end
  return nil, "timeout"
end


------------------------------------------------------------------------------
-- The mutually-exclusive section used internally by the
-- 'create_balancer' operation.
-- @param upstream (table) A db.upstreams entity
-- @return The new balancer object, or nil+error
local function create_balancer_exclusive(upstream)
  local health_threshold = upstream.healthchecks and
    upstream.healthchecks.threshold or nil

  local targets_list, err = targets.fetch_targets(upstream)
  if not targets_list then
    return nil, "failed fetching targets:" .. err
  end

  if algorithm_types == nil then
    algorithm_types = {
      ["consistent-hashing"] = require("kong.runloop.balancer.consistent_hashing"),
      ["least-connections"] = require("kong.runloop.balancer.least_connections"),
      ["round-robin"] = require("kong.runloop.balancer.round_robin"),
      ["ewma"] = require("kong.runloop.balancer.ewma"),
    }
  end

  local opts = {}    -- TODO: see if we should use config or something

  local balancer = setmetatable({
    upstream_id = upstream.id,
    log_prefix = "upstream:" .. upstream.name,
    wheelSize = upstream.slots,  -- will be ignored by least-connections
    targets = targets_list,
    totalWeight = 0,
    unavailableWeight = 0,

    resolveTimer = nil,
    requeryInterval = opts.requery or REQUERY_INTERVAL,  -- how often to requery failed dns lookups (seconds)
    ttl0Interval = opts.ttl0 or TTL_0_RETRY, -- refreshing ttl=0 records
    healthy = false, -- initial healthstatus of the balancer
    healthThreshold = health_threshold or 0, -- % healthy weight for overall balancer health
    useSRVname = upstream.use_srv_name,
  }, balancer_mt)

  for _, target in ipairs(targets_list) do
    target.balancer = balancer
  end

  targets_list, err = targets.resolve_targets(targets_list)
  if not targets_list then
    return nil, "failed resolving targets:" .. err
  end

  if not algorithm_types[upstream.algorithm] then
    return nil, "unknown algorithm " .. upstream.algorithm
  end

  balancer.algorithm, err = algorithm_types[upstream.algorithm].new({
    balancer = balancer,
    upstream = upstream,
  })
  if not balancer.algorithm then
    return nil, "failed instantiating the " .. upstream.algorithm .. " algorithm:" .. err
  end

  local ok
  ok, err = healthcheckers.create_healthchecker(balancer, upstream)
  if not ok then
    log(ERR, "[healthchecks] error creating health checker: ", err)
  end

  -- only make the new balancer available for other requests after it
  -- is fully set up.
  balancers_M.set_balancer(upstream.id, balancer)

  return balancer
end

------------------------------------------------------------------------------
-- Create a balancer object, its healthchecker and attach them to the
-- necessary data structures. The creation of the balancer happens in a
-- per-worker mutual exclusion section, such that no two requests create the
-- same balancer at the same time.
-- @param upstream (table) A db.upstreams entity
-- @param recreate (boolean, optional) create new balancer even if one exists
-- @return The new balancer object, or nil+error
function balancers_M.create_balancer(upstream, recreate)
  local existing_balancer = balancers_by_id[upstream.id]
  if existing_balancer then
    if recreate then
      healthcheckers.stop_healthchecker(existing_balancer, CLEAR_HEALTH_STATUS_DELAY)
    else
      return existing_balancer
    end
  end

  if creating[upstream.id] then
    local ok = wait(upstream.id)
    if not ok then
      return nil, "timeout waiting for balancer for " .. upstream.id
    end
    return balancers_by_id[upstream.id]
  end

  creating[upstream.id] = true

  local balancer, err = create_balancer_exclusive(upstream)

  creating[upstream.id] = nil
  upstreams.setUpstream_by_name(upstream)

  return balancer, err
end


-- looks up a balancer for the target.
-- @param balancer_data the table with the target details
-- @param no_create (optional) if true, do not attempt to create
-- (for thorough testing purposes)
-- @return balancer if found, `false` if not found, or nil+error on error
function balancers_M.get_balancer(balancer_data, no_create)
  -- NOTE: only called upon first lookup, so `cache_only` limitations
  -- do not apply here
  local hostname = balancer_data.host

  -- first go and find the upstream object, from cache or the db
  local upstream, err = upstreams.get_upstream_by_name(hostname)
  if upstream == false then
    return false -- no upstream by this name
  end
  if err then
    return nil, err -- there was an error
  end

  local balancer = balancers_by_id[upstream.id]
  if not balancer then
    if no_create then
      return nil, "balancer not found"
    else
      log(DEBUG, "balancer not found for ", upstream.name, ", will create it")
      return balancers_M.create_balancer(upstream), upstream
    end
  end

  return balancer, upstream
end


function balancers_M.create_balancers()
  local all_upstreams, err = upstreams.get_all_upstreams()
  if not all_upstreams then
    log(CRIT, "failed loading initial list of upstreams: ", err)
    return
  end

  local oks, errs = 0, 0
  for ws_and_name, id in pairs(all_upstreams) do
    local name = sub(ws_and_name, (find(ws_and_name, ":", 1, true)))

    local upstream = upstreams.get_upstream_by_id(id)
    local ok
    if upstream ~= nil then
      ok, err = balancers_M.create_balancer(upstream)
    end
    if ok ~= nil then
      oks = oks + 1
    else
      log(CRIT, "failed creating balancer for ", name, ": ", err)
      errs = errs + 1
    end
  end
  log(DEBUG, "initialized ", oks, " balancer(s), ", errs, " error(s)")
end


--------- balancer object methods

function balancer_mt:eachAddress(f, ...)
  for _, target in ipairs(self.targets) do
    for _, address in ipairs(target.addresses) do
      f(address, target, ...)
    end
  end
end

function balancer_mt:findAddress(ip, port, hostname)
  for _, target in ipairs(self.targets) do
    if target.name == hostname then
      for _, address in ipairs(target.addresses) do
        if address.ip == ip and address.port == port then
          return address
        end
      end
    end
  end
end


function balancer_mt:setAddressStatus(address, available)
  if type(address) ~= "table"
    or type(address.target) ~= "table"
    or address.target.balancer ~= self
  then
    return nil, "not a known address"
  end

  if address.available == available then
    return true, "already set"
  end

  address.available = available
  local delta = address.weight
  if available then
    delta = -delta
  end
  address.target.unavailableWeight = address.target.unavailableWeight + delta
  self.unavailableWeight = self.unavailableWeight + delta
  self:updateStatus()
  if self.algorithm and self.algorithm.afterHostUpdate then
    self.algorithm:afterHostUpdate()
  end
  return true
end


function balancer_mt:disableAddress(target, entry)
  -- from host:disableAddress()
  local address = self:changeWeight(target, entry, 0)
  if address then
    address.disabled = true
  end
end


local function setHostHeader(addr)
  local target = addr.target

  if target.nameType ~= "name" then
    -- hostname is an IP address
    addr.hostHeader = nil
  else
    -- hostname is an actual name
    if addr.ipType ~= "name" then
      -- the address is an ip, so use the hostname as header value
      addr.hostHeader = target.name
    else
      -- the address itself is a nested name (SRV)
      if addr.useSRVname then
        addr.hostHeader = addr.ip
      else
        addr.hostHeader = target.name
      end
    end
  end
end

function balancer_mt:addAddress(target, entry)
  -- from host:addAddress
  if type(entry) ~= "table"
    or type(target) ~= "table"
    or target.balancer ~= self
  then
    return nil, "invalid input or non-owned target"
  end

  local entry_ip = entry.address or entry.target
  local entry_port = (entry.port ~= 0 and entry.port) or target.port
  local addresses = target.addresses

  local weight = entry.weight  -- this is nil for anything else than SRV
  if weight == 0 then
    -- Special case: SRV with weight = 0 should be included, but with
    -- the lowest possible probability of being hit. So we force it to
    -- weight 1.
    weight = SRV_0_WEIGHT
  end
  weight = weight or target.weight
  local addr = {
    ip = entry_ip,
    port = entry_port,
    weight = weight,
    target = target,
    useSRVname = self.useSRVname,

    ipType = dns_utils.hostnameType(entry_ip),  -- 'ipv4', 'ipv6' or 'name'
    available = true,
    disabled = false,
  }
  setHostHeader(addr)
  addresses[#addresses + 1] = addr

  target.totalWeight = target.totalWeight + weight
  self.totalWeight = self.totalWeight + weight
  self:updateStatus()

  if self.callback then
    self:callback("added", addr, addr.ip, addr.port, addr.target.name, addr.hostHeader)
  end

  if self.algorithm and self.algorithm.afterHostUpdate then
    self.algorithm:afterHostUpdate()
  end

  return true
end


function balancer_mt:changeWeight(target, entry, newWeight)
  -- from host:findAddress() + address:change()

  local entry_ip = entry.address or entry.target
  local entry_port = (entry.port ~= 0 and entry.port) or target.port

  for _, addr in ipairs(target.addresses) do
    if (addr.ip == entry_ip) and addr.port == entry_port then
      local delta = newWeight - addr.weight

      target.totalWeight = target.totalWeight + delta
      self.totalWeight = self.totalWeight + delta

      if not addr.available then
        target.unavailableWeight = target.unavailableWeight + delta
        self.unavailableWeight = self.unavailableWeight + delta
      end

      addr.weight = newWeight
      self:updateStatus()
      if self.algorithm and self.algorithm.afterHostUpdate then
        self.algorithm:afterHostUpdate()
      end
      return addr
    end
  end
end


function balancer_mt:deleteDisabledAddresses(target)
  -- from host:deleteAddresses
  local addresses = target.addresses
  local dirty = false

  for i = #addresses, 1, -1 do -- deleting entries, hence reverse traversal
    local addr = addresses[i]

    if addr.disabled then
      if type(self.callback) == "function" then
        self:callback("removed", addr, addr.ip, addr.port,
                      target.name, addr.hostHeader)
      end
      dirty = true
      table_remove(addresses, i)
    end
  end

  if dirty then
    if self.algorithm and self.algorithm.afterHostUpdate then
      self.algorithm:afterHostUpdate()
    end
  end
end


function balancer_mt:updateStatus()
  local old_status = self.healthy

  if self.totalWeight == 0 then
    self.healthy = false
  else
    self.healthy = ((self.totalWeight - self.unavailableWeight) / self.totalWeight * 100 > self.healthThreshold)
  end

  if self.callback and self.healthy ~= old_status then
    self:callback("health", self.healthy)
  end
end


function balancer_mt:setCallback(callback)
  assert(type(callback) == "function", "expected a callback function")

  self.callback = function(balancer, action, address, ip, port, hostname, hostheader)
    local ok, err = ngx.timer.at(0, function()
      callback(balancer, action, address, ip, port, hostname, hostheader)
    end)

    if not ok then
      ngx.log(ngx.ERR, self.log_prefix, "failed to create the timer: ", err)
    end
  end

  return true
end


local function get_dns_source(dns_record)
  if not dns_record then
    return "unknown"
  end

  if dns_record.__dnsError then
    return dns_record.__dnsError
  end

  if dns_record.__ttl0Flag then
    return "ttl=0, virtual SRV"
  end

  return targets.get_dns_name_from_record_type(dns_record[1] and dns_record[1].type)
end

function balancer_mt:getTargetStatus(target)
  local addresses = {}
  local status = {
    host = target.name,
    port = target.port,
    dns = get_dns_source(target.lastQuery),
    nodeWeight = target.nodeWeight or target.weight,
    weight = {
      total = target.totalWeight,
      unavailable = target.unavailableWeight,
      available = target.totalWeight - target.unavailableWeight,
    },
    addresses = addresses,
  }

  for i, addr in ipairs(target.addresses) do
    addresses[i] = {
      ip = addr.ip,
      port = addr.port,
      weight = addr.weight,
      healthy = addr.available,
    }
  end

  return status
end

function balancer_mt:getStatus()
  local hosts = {}
  local status = {
    healthy = self.healthy,
    weight = {
      total = self.totalWeight,
      unavailable = self.unavailableWeight,
      available = self.totalWeight - self.unavailableWeight,
    },
    hosts = hosts,
  }

  for i, target in ipairs(self.targets) do
    hosts[i] = self:getTargetStatus(target)
  end

  return status
end

function balancer_mt:afterHostUpdate()
  if not self.algorithm or not self.algorithm.afterHostUpdate then
    return
  end

  return self.algorithm:afterHostUpdate()
end


function balancers_M.getAddressPeer(address, cacheOnly)
  return targets.getAddressPeer(address, cacheOnly)
end


function balancer_mt:getPeer(...)
  if not self.healthy then
    return nil, "Balancer is unhealthy"
  end

  if not self.algorithm or not self.algorithm.afterHostUpdate then
    return
  end

  return self.algorithm:getPeer(...)
end

function balancer_mt:afterBalance(...)
  if not self.healthy then
    return nil, "Balancer is unhealthy"
  end

  if not self.algorithm or not self.algorithm.afterBalance then
    return
  end

  return self.algorithm:afterBalance(...)
end

return balancers_M
