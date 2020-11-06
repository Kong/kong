--------------------------------------------------------------------------
-- Ring-balancer.
--
-- This balancer implements a consistent-hashing algorithm as well as a
-- weighted-round-robin.
--
-- This loadbalancer is designed for consistent hashing approaches and
-- to retain consistency on a maximum level while dealing with dynamic
-- changes like adding/removing hosts/targets (ketama principle).
--
-- Due to its deterministic way of operating it is also capable of running
-- identical balancers (identical consistent rings) on multiple servers/workers
-- (though it does not implement inter-server/worker communication).
--
-- Only dns is non-deterministic as it might occur when a peer is requested,
-- and hence should be avoided (by directly inserting ip addresses).
-- Adding/deleting hosts, etc (as long as done in the same order) is always
-- deterministic.
--
-- Whenever dns resolution fails for a hostname, the host will relinguish all
-- the indices it owns, and they will be reassigned to other targets.
-- Periodically the query for the hostname will be retried, and if it succeeds
-- it will get (different) indices reassigned to it.
--
-- When using `setAddressStatus` to mark a peer as unavailable, the slots it owns
-- will not be reassigned. So after a recovery, hashing will be restored.
--
--
-- __NOTE:__ This documentation only described the altered user methods/properties,
-- see the `user properties` from the `balancer_base` for a complete overview.
--
-- @author Thijs Schreijer
-- @copyright 2016-2020 Kong Inc. All rights reserved.
-- @license Apache 2.0


local balancer_base = require "resty.dns.balancer.base"
local lrandom = require "random"
local bit = require "bit"
local math_floor = math.floor
local string_sub = string.sub
local table_sort = table.sort
local ngx_md5 = ngx.md5_bin
local bxor = bit.bxor
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN

local EMPTY = setmetatable({},
  {__newindex = function() error("The 'EMPTY' table is read-only") end})

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
      new_tab = function() return {} end
  end
end


local _M = {}
local ring_balancer = {}


-- ===========================================================================
-- address object.
-- ===========================================================================

local ring_address = {}

-- Adds a list of indices to the address. The indices added to the address will
-- be removed from the provided `availableIndicesList`.
-- @param availableIndicesList a list of wheel-indices available for adding
-- @param count the number of indices to take from the list provided, defaults to ALL if omitted
-- @return the address object
function ring_address:addIndices(availableIndicesList, count)
  count = count or #availableIndicesList
  if count > 0 then
    local myWheelIndices = self.indices
    local size = #myWheelIndices
    if count > #availableIndicesList then
      error("more indices requested to be added ("..count..") than provided ("..#availableIndicesList..
            ") for host '"..self.host.hostname..":"..self.port.."' ("..tostring(self.ip)..")")
    end

    local wheel = self.host.balancer.wheel
    local lsize = #availableIndicesList + 1
    for i = 1, count do
      local availableIdx = lsize - i
      local wheelIdx = availableIndicesList[availableIdx]
      availableIndicesList[availableIdx] = nil
      myWheelIndices[size + i] = wheelIdx

      wheel[wheelIdx] = self
    end
    -- track maximum table size reached
    local max = count + size
    if max > self.indicesMax then
      self.indicesMax = max
    end
  end
  return self
end


-- Drop an amount of indices and return them to the overall balancer.
-- @param availableIndicesList The list to add the dropped indices to
-- @param count (optional) The number of indices to drop, defaults to ALL if omitted
-- @return availableIndicesList with added to it the indices removed from this address
function ring_address:dropIndices(availableIndicesList, count)
  local myWheelIndices = self.indices
  local size = #myWheelIndices
  count = count or size
  if count > 0 then
    if count > size then
      error("more indices requested to drop ("..count..") than available ("..size..
            ") in address '"..self.host.hostname..":"..self.port.."' ("..self.ip..")")
    end

    local wheel = self.host.balancer.wheel
    local lsize = #availableIndicesList
    for i = 1, count do
      local myIdx = size + 1 - i
      local wheelIdx = myWheelIndices[myIdx]
      myWheelIndices[myIdx] = nil
      availableIndicesList[lsize + i] = wheelIdx

      wheel[wheelIdx] = nil
    end
    -- track table size reduction
    size = size - count
    if size * 2 < self.indicesMax then
      -- table was reduced by at least half, so drop the original to reduce
      -- memory footprint
      self.indicesMax = size
      --[[ next line disabled due to LuaJIT/ARM issue, see https://github.com/Kong/lua-resty-dns-client/issues/93
      self.indices = table.move(self.indices, 1, size, 1, {})
      Below a pure-Lua implementation --]]
      local replacement = {}
      for i = 1, size do
        replacement[i] = self.indices[i]
      end
      self.indices = replacement
    end
  end
  return availableIndicesList
end


function ring_address:delete()
  assert(#self.indices == 0, "Cannot delete address while it owns indices")
  return self.super.delete(self)
end


function ring_balancer:newAddress(addr)
  addr = self.super.newAddress(self, addr)

  -- inject additional properties
  addr.indices = {}     -- the indices of the wheel assigned to this address
  addr.indicesMax = 0   -- max size reached for 'indices' table

  -- inject overridden methods
  for name, method in pairs(ring_address) do
    addr[name] = method
  end

  return addr
end


-- ===========================================================================
-- Host object.
-- ===========================================================================

--local ring_host = {}

--function ring_balancer:newHost(host)
--  host = self.super.newHost(self, host)

--  -- inject additional properties

--  -- inject overridden methods
--  for name, method in pairs(ring_host) do
--    host[name] = method
--  end

--  return host
--end


-- ===========================================================================
-- Balancer object.
-- ===========================================================================

-- Recalculates the weights. Updates the indices assigned for all hostnames.
-- Must be called whenever a weight might have changed; added/removed hosts.
-- @return balancer object
function ring_balancer:redistributeIndices()
  local totalWeight = self.weight
  local movingIndexList = self.unassignedWheelIndices

  -- NOTE: calculations are based on the "remaining" indices and weights, to
  -- prevent issues due to rounding: eg. 10 equal systems with 19 indices.
  -- Calculated to get each 1.9 indices => 9 systems would get 1, last system would get 10
  -- by using "remaining" indices, the first would get 1 index, the other 9 would get 2.

  -- first; reclaim extraneous indices
  local weightLeft = totalWeight
  local indicesLeft = self.wheelSize
  local addList = {}      -- addresses that need additional indices
  local addListCount = {} -- how many extra indices the address needs
  local addCount = 0
  local dropped, added = 0, 0

  for weight, address, _ in self:addressIter() do

    local count
    if weightLeft == 0 then
      count = 0
    else
      count = math_floor(indicesLeft * (weight / weightLeft) + 0.0001) -- 0.0001 to bypass float arithmetic issues
    end
    local drop = #address.indices - count
    if drop > 0 then
      -- we need to reclaim some indices
      address:dropIndices(movingIndexList, drop)
      dropped = dropped + drop
    elseif drop < 0 then
      -- this one needs extra indices, so record the changes needed
      addCount = addCount + 1
      addList[addCount] = address
      addListCount[addCount] = -drop  -- negate because we need to add them
    end
    indicesLeft = indicesLeft - count
    weightLeft = weightLeft - weight
  end

  -- second: add freed indices to the recorded addresses that were short of them
  for i, address in ipairs(addList) do
    address:addIndices(movingIndexList, addListCount[i])
    added = added + addListCount[i]
  end

  ngx_log( #movingIndexList == 0 and ngx_DEBUG or ngx_WARN,
          self.log_prefix, "redistributed indices, size=", self.wheelSize,
          ", dropped=", dropped, ", assigned=", added,
          ", left unassigned=", #movingIndexList)

  return self
end


function ring_balancer:addHost(hostname, port, weight)
  self.super.addHost(self, hostname, port, weight)

  if #self.unassignedWheelIndices == 0 then
    self.unassignedWheelIndices = {}  -- replace table because of initial memory footprint
  end
  return self
end


function ring_balancer:afterHostUpdate(host)
  -- recalculate to move indices of added/disabled addresses
  self:redistributeIndices()
end


function ring_balancer:beforeHostDelete(host)
  -- recalculate to move indices of disabled hosts
  self:redistributeIndices()
end


function ring_balancer:removeHost(hostname, port)
  self.super.removeHost(self, hostname, port)

  if #self.unassignedWheelIndices == 0 then
    self.unassignedWheelIndices = {}  -- replace table because of initial memory footprint
  end
  return self
end


function ring_balancer:getPeer(cacheOnly, handle, hashValue)
  if not self.healthy then
    return nil, balancer_base.errors.ERR_BALANCER_UNHEALTHY
  end

  if handle then
    -- existing handle, so it's a retry
    if hashValue then
      -- we have a new hashValue, use it anyway
      handle.hashValue = hashValue
    else
      hashValue = handle.hashValue  -- reuse existing (if any) hashvalue
    end
    handle.retryCount = handle.retryCount + 1
    --handle.address:release(handle, true)  -- not needed, nothing to release
  else
    -- no handle, so this is a first try
    handle = self:getHandle()  -- no GC specific handler needed
    handle.retryCount = 0
    handle.hashValue = hashValue
  end

  -- calculate starting point
  local pointer
  if hashValue then
    hashValue = hashValue + handle.retryCount
    pointer = 1 + (hashValue % self.wheelSize)
  else
    -- no hash, so get the next one, round-robin like
    pointer = self.pointer
    if pointer < self.wheelSize then
      self.pointer = pointer + 1
    else
      self.pointer = 1
    end
  end

  local initial_pointer = pointer
  while true do
    local address = self.wheel[pointer]
    local ip, port, hostname = address:getPeer(cacheOnly)
    if ip then
      -- success, update handle
      handle.address = address
      return ip, port, hostname, handle

    elseif port == balancer_base.errors.ERR_DNS_UPDATED then
      -- we just need to retry the same index, no change for 'pointer', just
      -- in case of dns updates, we need to check our health again.
      if not self.healthy then
        return nil, balancer_base.errors.ERR_BALANCER_UNHEALTHY
      end

    elseif port == balancer_base.errors.ERR_ADDRESS_UNAVAILABLE then
      -- fall through to the next wheel index
      if hashValue then
        pointer = pointer + 1
        if pointer > self.wheelSize then pointer = 1 end

      else
        pointer = self.pointer
        if pointer < self.wheelSize then
          self.pointer = pointer + 1
        else
          self.pointer = 1
        end
      end

      if pointer == initial_pointer then
        -- we went around, but still nothing...
        return nil, balancer_base.errors.ERR_NO_PEERS_AVAILABLE
      end

    else
      -- an unknown error occured
      return nil, port
    end
  end

end


local randomlist_cache = {}

local function randomlist(size)
  if randomlist_cache[size] then
    return randomlist_cache[size]
  end
  -- create a new randomizer with just any seed, we do not care about
  -- uniqueness, only about distribution, and repeatability, each orderlist
  -- must be identical!
  local randomizer = lrandom.new(158841259)
  local rnds = new_tab(size, 0)
  local out = new_tab(size, 0)
  for i = 1, size do
    local n = math_floor(randomizer() * size) + 1
    while rnds[n] do
      n = n + 1
      if n > size then
        n = 1
      end
    end
    out[i] = n
    rnds[n] = true
  end
  randomlist_cache[size] = out
  return out
end

--- Creates a new balancer. The balancer is based on a wheel with a number of
-- positions (the index on the wheel). The
-- indices will be randomly distributed over the targets. The number of indices
-- assigned will be relative to the weight.
--
-- The options table has the following fields, additional to the ones from
-- the `balancer_base`;
--
-- - `hosts` (optional) containing hostnames, ports and weights. If omitted,
-- ports and weights default respectively to 80 and 10. The list will be sorted
-- before being added, so the order of entry is deterministic.
-- - `wheelSize` (optional) for total number of positions in the balancer (the
-- indices), if omitted
-- the size of `order` is used, or 1000 if `order` is not provided. It is important
-- to have enough indices to keep the ring properly randomly distributed. If there
-- are to few indices for the number of targets then the load distribution might
-- become to coarse. Consider the maximum number of targets expected, as new
-- hosts can be dynamically added, and dns renewals might yield larger record
-- sets. The `wheelSize` cannot be altered, only a new wheel can be created, but
-- then all consistency would be lost. On a similar note; making it too big,
-- will have a performance impact when the wheel is modified as too many indices
-- will have to be moved between targets. A value of 50 to 200 indices per entry
-- seems about right.
-- - `order` (optional) if given, a list of random numbers, size `wheelSize`, used to
-- randomize the wheel. Duplicates are not allowed in the list.
-- @param opts table with options
-- @return new balancer object or nil+error
-- @usage -- hosts example
-- local hosts = {
--   "konghq.com",                                      -- name only, as string
--   { name = "github.com" },                           -- name only, as table
--   { name = "getkong.org", port = 80, weight = 25 },  -- fully specified, as table
-- }
function _M.new(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))
  if not opts.log_prefix then
    opts.log_prefix = "ringbalancer"
  end

  local self = assert(balancer_base.new(opts))

  if (not opts.wheelSize) and opts.order then
    opts.wheelSize = #opts.order
  end
  if opts.order then
    assert(opts.order and (opts.wheelSize == #opts.order), "mismatch between size of 'order' and 'wheelSize'")
  end

  -- inject additional properties
  self.wheel = nil   -- wheel with entries (fully randomized)
  self.pointer = nil -- pointer to next-up index for the round robin scheme
  self.wheelSize = opts.wheelSize or 1000 -- number of entries (indices) in the wheel
  self.unassignedWheelIndices = nil -- list to hold unassigned indices (initially, and when all hosts fail)

  -- inject overridden methods
  for name, method in pairs(ring_balancer) do
    self[name] = method
  end

  -- initialize the balancer

  self.wheel = new_tab(self.wheelSize, 0)
  self.unassignedWheelIndices = new_tab(self.wheelSize, 0)
  self.pointer = math.random(1, self.wheelSize)  -- ensure each worker starts somewhere else

  -- Create a list of entries, and randomize them.
  local unassignedWheelIndices = self.unassignedWheelIndices
  local duplicateCheck = new_tab(self.wheelSize, 0)
  local orderlist = opts.order or randomlist(self.wheelSize)

  for i = 1, self.wheelSize do
    local order = orderlist[i]
    if duplicateCheck[order] then  -- no duplicates allowed! order must be deterministic!
      -- it was a user provided value, so error out
      error("the 'order' list contains duplicates")
    end
    duplicateCheck[order] = true

    unassignedWheelIndices[i] = order
  end

  -- Sort the hosts, to make order deterministic
  local hosts = {}
  for i, host in ipairs(opts.hosts or EMPTY) do
    if type(host) == "table" then
      hosts[i] = host
    else
      hosts[i] = { name = host }
    end
  end
  table_sort(hosts, function(a,b) return (a.name..":"..(a.port or "") < b.name..":"..(b.port or "")) end)
  -- Insert the hosts
  for _, host in ipairs(hosts) do
    local ok, err = self:addHost(host.name, host.port, host.weight)
    if not ok then
      return ok, "Failed creating a balancer: "..tostring(err)
    end
  end

  ngx_log(ngx_DEBUG, self.log_prefix, "ringbalancer created")

  return self
end


--- Creates a MD5 hash value from a string.
-- The string will be hashed using MD5, and then shortened to 4 bytes.
-- The returned hash value can be used as input for the `getpeer` function.
-- @function hashMd5
-- @param str (string) value to create the hash from
-- @return 32-bit numeric hash
_M.hashMd5 = function(str)
  local md5 = ngx_md5(str)
  return bxor(
    tonumber(string_sub(md5, 1, 4), 16),
    tonumber(string_sub(md5, 5, 8), 16)
  )
end


--- Creates a CRC32 hash value from a string.
-- The string will be hashed using CRC32. The returned hash value can be
-- used as input for the `getpeer` function. This is simply a shortcut to
-- `ngx.crc32_short`.
-- @function hashCrc32
-- @param str (string) value to create the hash from
-- @return 32-bit numeric hash
_M.hashCrc32 = ngx.crc32_short


return _M
