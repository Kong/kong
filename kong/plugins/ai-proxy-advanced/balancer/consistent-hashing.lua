-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
local get_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".get_tried_targets

local xxhash32 = require "luaxxhash"


local floor = math.floor
local table_sort = table.sort


-- constants
local DEFAULT_CONTINUUM_SIZE = 1000
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
local function sort_targets(targets)
  if targets == nil or targets[1] == nil then
    return
  end

  table_sort(targets, function(a, b)
    return a.id < b.id
  end)
end


--- Actually adds the addresses to the continuum.
-- This function should not be called directly, as it will called by
-- `addHost()` after adding the new host.
-- This function makes sure the continuum will be built identically every
-- time, no matter the order the hosts are added.
function consistent_hashing:afterHostUpdate()
  local points = self.points
  local new_continuum = {}
  local targets_count = #self.targets
  local total_collision = 0

  local total_weight =  0
  -- calculate the gcd to find the proportional weight of each address
  for _, target in ipairs(self.targets) do
    local target_weight = target.weight
    total_weight = total_weight + target_weight
  end

  self.totalWeight = total_weight

  sort_targets(self.targets)

  for _, target in ipairs(self.targets) do
    assert(target.id)
    local weight = target.weight
    local target_prop = weight / total_weight
    local entries = floor(target_prop * targets_count * SERVER_POINTS)
    if weight > 0 and entries == 0 then
      entries = 1
    end

    local i = 1
    while i <= entries do
      local name = target.id .. SEP .. tostring(i)
      local index = get_continuum_index(name, points)
      if new_continuum[index] == nil then
        new_continuum[index] = target
      else
        entries = entries + 1 -- move the problem forward
        total_collision = total_collision + 1
      end
      i = i + 1
      if i > self.points then
        -- this should happen only if there are an awful amount of hosts with
        -- low relative weight.
        kong.log.crit("consistent hashing balancer requires more entries ",
                "to add the number of hosts requested, please increase the ",
                "wheel size")
        return
      end
    end
  end

  kong.log.debug("continuum of size ", self.points,
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
function consistent_hashing:getPeer(_, _, valueToHash)
  -- kong.log.debug("trying to get peer with value to hash: [", valueToHash, "]")
  --if not balancer.healthy then
  --  return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
  --end

  -- if handle then
  --   -- existing handle, so it's a retry
  --   handle.retryCount = handle.retryCount + 1
  -- else
  --   -- no handle, so this is a first try
  --   handle = { retryCount = 0 }
  -- end

  -- if not handle.hashValue then
  --   if not valueToHash then
  --     error("can't getPeer with no value to hash", 2)
  --   end
  --   handle.hashValue = get_continuum_index(valueToHash, self.points)
  -- end

  local tried = get_tried_targets()

  local target
  local hashValue = get_continuum_index(valueToHash, self.points)
  local index = hashValue
  while (index - 1) ~= hashValue do
    if index == 0 then
      index = self.points
    end

    target = self.continuum[index]
    if target and not tried[target.id] then
      return target
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
function consistent_hashing.new(targets, conf)
  local self = setmetatable({
    continuum = {},
    totalWeight = 0,
    points = (conf and conf.balancer and conf.balancer.slots) or DEFAULT_CONTINUUM_SIZE,
    targets = targets or {},
  }, consistent_hashing)

  self:afterHostUpdate()

  return self
end

return consistent_hashing
