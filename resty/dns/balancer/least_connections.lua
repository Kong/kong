--------------------------------------------------------------------------
-- Least-connections balancer.
--
-- This balancer implements a least-connections algorithm. The balancer will
-- honour the weights. See the base-balancer for details on how the weights
-- are set.
--
-- __NOTE:__ This documentation only described the altered user methods/properties
-- from the base-balancer. See the `user properties` from the `balancer_base` for a
-- complete overview.
--
-- @author Thijs Schreijer
-- @copyright 2016-2020 Kong Inc. All rights reserved.
-- @license Apache 2.0


local balancer_base = require "resty.dns.balancer.base"
local binaryHeap = require "binaryheap"
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG

local EMPTY = setmetatable({},
  {__newindex = function() error("The 'EMPTY' table is read-only") end})

local _M = {}
local lc = {}
local lcAddr = {}


-- @param delta number (+1 or -1) to update the connection count
function lcAddr:updateConnectionCount(delta)
  self.connectionCount = self.connectionCount + delta

  if not self.available then
    return
  end

  -- go update the heap position
  local bh = ((self.host or EMPTY).balancer or EMPTY).binaryHeap
  if bh then
    -- NOTE: we use `connectionCount + 1` this ensures that even on a balancer
    -- with 0 connections the heighest weighted entry is picked first. If we'd
    -- not add the `+1` then any target with 0 connections would always be the
    -- first to be picked (even if it has a very low eight)
    bh:update(self, (self.connectionCount + 1) / self.weight)
  end
end


function lcAddr:release(handle, ignore)
  self:updateConnectionCount(-1)
end


function lcAddr:setState(available)
  local old_available = self.available
  self.super.setState(self, available)
  if old_available == self.available then
    -- nothing changed
    return
  end

  local bh = self.host.balancer.binaryHeap
  if self.available then
    bh:insert((self.connectionCount + 1) / self.weight, self)
  else
    bh:remove(self)
  end
end


function lc:newAddress(addr)
  addr = self.super.newAddress(self, addr)

  -- inject additional properties
  addr.connectionCount = 0

  -- inject additioanl methods
  for name, method in pairs(lcAddr) do
    addr[name] = method
  end

  -- insert self in binary heap
  if addr.available then
    self.binaryHeap:insert((addr.connectionCount + 1) / addr.weight, addr)
  end

  return addr
end


-- removing the address, so delete from binaryHeap
function lc:onRemoveAddress(address)
  self.binaryHeap:remove(address)
end



function lc:getPeer(cacheOnly, handle, hashValue)
  if handle then
    -- existing handle, so it's a retry
    handle.retryCount = handle.retryCount + 1

    -- keep track of failed addresses
    handle.failedAddresses = handle.failedAddresses or setmetatable({}, {__mode = "k"})
    handle.failedAddresses[handle.address] = true
    -- let go of previous connection
    handle.address:release()
    handle.address = nil
  else
    -- no handle, so this is a first try
    handle = self:getHandle() -- no specific GC method required
    handle.retryCount = 0
  end

  local address, ip, port, host, reinsert
  while true do
    if not self.healthy then
      -- Balancer unhealthy, nothing we can do.
      -- This check must be inside the loop, since calling getPeer could
      -- cause a DNS update.
      ip, port, host = nil, self.errors.ERR_BALANCER_UNHEALTHY, nil
      break
    end


    -- go and find the next `address` object according to the LB policy
    do
      repeat
        if address then
          -- this address we failed before, so temp store it and pop it from
          -- the tree. When we're done we'll reinsert them.
          reinsert = reinsert or {}
          reinsert[#reinsert + 1] = address
          self.binaryHeap:pop()
        end
        address = self.binaryHeap:peek()
      until address == nil or not (handle.failedAddresses or EMPTY)[address]

      if address == nil and handle.failedAddresses then
        -- we failed all addresses, so drop the list of failed ones, we are trying
        -- again, so we restart using the ones that previously failed us. Until
        -- eventually we hit the limit of retries (but that's up to the user).
        handle.failedAddresses = nil
        address = reinsert[1]  -- the address to use is the first one, top of the heap
      end

      if reinsert then
        -- reinsert the ones we temporarily popped
        for i = 1, #reinsert do
          local addr = reinsert[i]
          self.binaryHeap:insert((addr.connectionCount + 1) / addr.weight, addr)
        end
        reinsert = nil
      end
    end


    -- check the address returned, and get an IP

    if address == nil then
      -- No peers are available
      ip, port, host = nil, self.errors.ERR_NO_PEERS_AVAILABLE, nil
      break
    end

    ip, port, host = address:getPeer(cacheOnly)
    if ip then
      -- success, exit
      handle.address = address
      address:updateConnectionCount(1)
      break
    end

    if port ~= self.errors.ERR_DNS_UPDATED then
      -- an unknown error
      break
    end

    -- if here, we're going to retry because we already tried this address,
    -- or because of a dns update
  end

  if ip then
    return ip, port, host, handle
  else
    handle.address = nil
    handle:release(true)
    return nil, port
  end
end


--- Creates a new balancer. The balancer is based on a binary heap tracking
-- the number of active connections. The number of connections
-- assigned will be relative to the weight.
--
-- The options table has the following fields, additional to the ones from
-- the `balancer_base`;
--
-- - `hosts` (optional) containing hostnames, ports and weights. If omitted,
-- ports and weights default respectively to 80 and 10.
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
    opts.log_prefix = "least-connections"
  end

  local self = assert(balancer_base.new(opts))

  -- inject overridden methods
  for name, method in pairs(lc) do
    self[name] = method
  end

  -- inject properties
  self.binaryHeap = binaryHeap.minUnique() -- binaryheap tracking next up address

  -- add the hosts provided
  for _, host in ipairs(opts.hosts or EMPTY) do
    if type(host) ~= "table" then
      host = { name = host }
    end

    local ok, err = self:addHost(host.name, host.port, host.weight)
    if not ok then
      return ok, "Failed creating a balancer: "..tostring(err)
    end
  end

  ngx_log(ngx_DEBUG, self.log_prefix, "balancer created")

  return self
end

return _M
