--------------------------------------------------------------------------
-- Consistent-Hashing balancer algorithm
--
-- Implements a consistent-hashing algorithm based on the
-- Ketama algorithm.
--
-- @author Vinicius Mignot
-- @copyright 2020 Kong Inc. All rights reserved.
-- @license Apache 2.0


local balancers = require "kong.runloop.balancer.balancers"
local xxhash32 = require "luaxxhash"

local ngx_log = ngx.log
local ngx_CRIT = ngx.CRIT
local ngx_DEBUG = ngx.DEBUG

local floor = math.floor
local table_sort = table.sort


-- constants
local DEFAULT_CONTINUUM_SIZE = 1000
local MAX_CONTINUUM_SIZE = 2^32
local MIN_CONTINUUM_SIZE = 1000
local SERVER_POINTS = 160 -- number of points when all targets have same weight
local SEP = " " -- string separator to be used when hashing hostnames


local consistent_hashing = {}
consistent_hashing.__index = consistent_hashing

-- returns the index a value will point to in a generic continuum, based on
-- continuum size
local function get_continuum_index(value, points)
  return ((xxhash32(tostring(value)) % points) + 1)
end


-- hosts and addresses must be sorted lexically before adding to the continuum,
-- so they are added always in the same order. This makes sure that collisions
-- will be treated always the same way.
local function sort_hosts_and_addresses(balancer)
  if type(balancer) ~= "table" then
    error("balancer must be a table")
  end

  if balancer.targets == nil or balancer.targets[1] == nil then
    return
  end

  table_sort(balancer.targets, function(a, b)
    local ta = tostring(a.name)
    local tb = tostring(b.name)
    return ta < tb or (ta == tb and tonumber(a.port) < tonumber(b.port))
  end)

  for _, target in ipairs(balancer.targets) do
    table_sort(target.addresses, function(a, b)
      return (tostring(a.ip) .. ":" .. tostring(a.port)) <
             (tostring(b.ip) .. ":" .. tostring(b.port))
    end)
  end

end


--- Actually adds the addresses to the continuum.
-- This function should not be called directly, as it will called by
-- `addHost()` after adding the new host.
-- This function makes sure the continuum will be built identically every
-- time, no matter the order the hosts are added.
function consistent_hashing:afterHostUpdate()
  local points = self.points
  local balancer = self.balancer
  local new_continuum = {}
  local total_weight = balancer.totalWeight
  local targets_count = #balancer.targets
  local total_collision = 0

  sort_hosts_and_addresses(balancer)

  for _, target in ipairs(balancer.targets) do
    for _, address in ipairs(target.addresses) do
      local weight = address.weight
      local addr_prop = weight / total_weight
      local entries = floor(addr_prop * targets_count * SERVER_POINTS)
      if weight > 0 and entries == 0 then
        entries = 1
      end

      local port = address.port and ":" .. tostring(address.port) or ""
      local i = 1
      while i <= entries do
        local name = tostring(address.ip) .. ":" .. port .. SEP .. tostring(i)
        local index = get_continuum_index(name, points)
        if new_continuum[index] == nil then
          new_continuum[index] = address
        else
          entries = entries + 1 -- move the problem forward
          total_collision = total_collision + 1
        end
        i = i + 1
        if i > self.points then
          -- this should happen only if there are an awful amount of hosts with
          -- low relative weight.
          ngx_log(ngx_CRIT, "consistent hashing balancer requires more entries ",
                  "to add the number of hosts requested, please increase the ",
                  "wheel size")
          return
        end
      end
    end
  end

  ngx_log(ngx_DEBUG, "continuum of size ", self.points,
          " updated with ", total_collision, " collisions")

  self.continuum = new_continuum
end


--- Gets an IP/port/hostname combo for the value to hash
-- This function will hash the `valueToHash` param and use it as an index
-- in the continuum. It will return the address that is at the hashed
-- value or the first one found going counter-clockwise in the continuum.
-- @param cacheOnly If truthy, no dns lookups will be done, only cache.
-- @param handle the `handle` returned by a previous call to `getPeer`.
-- This will retain some state over retries. See also `setAddressStatus`.
-- @param valueToHash value for consistent hashing. Please note that this
-- value will be hashed, so no need to hash it prior to calling this
-- function.
-- @return `ip + port + hostheader` + `handle`, or `nil+error`
function consistent_hashing:getPeer(cacheOnly, handle, valueToHash)
  ngx_log(ngx_DEBUG, "trying to get peer with value to hash: [", valueToHash, "]")
  local balancer = self.balancer
  --if not balancer.healthy then
  --  return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
  --end

  if handle then
    -- existing handle, so it's a retry
    handle.retryCount = handle.retryCount + 1
  else
    -- no handle, so this is a first try
    handle = { retryCount = 0 }
  end

  if not handle.hashValue then
    if not valueToHash then
      error("can't getPeer with no value to hash", 2)
    end
    handle.hashValue = get_continuum_index(valueToHash, self.points)
  end

  local address
  local index = handle.hashValue
  local ip, port, hostname
  while (index - 1) ~= handle.hashValue do
    if index == 0 then
      index = self.points
    end

    address = self.continuum[index]
    if address ~= nil and address.available and not address.disabled then
      ip, port, hostname = balancers.getAddressPeer(address, cacheOnly)
      if ip then
        -- success, update handle
        handle.address = address
        return ip, port, hostname, handle

      elseif port == balancers.errors.ERR_DNS_UPDATED then
        -- we just need to retry the same index, no change for 'pointer', just
        -- in case of dns updates, we need to check our health again.
        if not balancer.healthy then
          return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
        end
      elseif port == balancers.errors.ERR_ADDRESS_UNAVAILABLE then
        ngx_log(ngx_DEBUG, "found address but it was unavailable. ",
                " trying next one.")
      else
        -- an unknown error occured
        return nil, port
      end

    end

    index = index - 1
  end

  return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
end

--- Creates a new algorithm.
--
-- The algorithm is based on a wheel (continuum) with a number of points
-- between MIN_CONTINUUM_SIZE and MAX_CONTINUUM_SIZE points. Key points
-- will be assigned to addresses based on their IP and port. The number
-- of points each address will be assigned is proportional to their weight.
--
-- Takes the `wheelSize` field from the balancer, pinnging or defaulting
-- as necessary.  Note that this can't be changed without rebuilding the
-- object.
--
-- If the balancer already has targets and addresses, the wheel is
-- constructed here by calling `self:afterHostUpdate()`
function consistent_hashing.new(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))
  local balancer = opts.balancer

  local self = setmetatable({
    continuum = {},
    points = (balancer.wheelSize and
              balancer.wheelSize >= MIN_CONTINUUM_SIZE and
              balancer.wheelSize <= MAX_CONTINUUM_SIZE) and
              balancer.wheelSize or DEFAULT_CONTINUUM_SIZE,
    balancer = balancer,
  }, consistent_hashing)

  self:afterHostUpdate()

  ngx_log(ngx_DEBUG, "consistent_hashing balancer created")

  return self
end

return consistent_hashing
