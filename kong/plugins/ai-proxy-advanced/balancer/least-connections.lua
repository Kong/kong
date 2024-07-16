-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


--------------------------------------------------------------------------
-- Least-connections balancer.
--
-- This balancer implements a least-connections algorithm. The balancer will
-- honour the weights.
--
-- @author Thijs Schreijer
-- @copyright 2016-2020 Kong Inc. All rights reserved.
-- @license Apache 2.0

local balancers = require "kong.runloop.balancer.balancers"
local get_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".get_tried_targets
local clear_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".clear_tried_targets
local get_last_tried_target = require "kong.plugins.ai-proxy-advanced.balancer.state".get_last_tried_target
local binaryHeap = require "binaryheap"
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG

local EMPTY = setmetatable({},
        {__newindex = function() error("The 'EMPTY' table is read-only") end})


local lc = {}
lc.__index = lc

local function insertAddr(bh, addr)
  addr.connectionCount = addr.connectionCount or 0


  bh:insert((addr.connectionCount + 1) / addr.weight, addr)

end

-- @param delta number (+1 or -1) to update the connection count
local function updateConnectionCount(bh, addr, delta)
  addr.connectionCount = addr.connectionCount + delta

  if not bh then
    return
  end

  -- NOTE: we use `connectionCount + 1` this ensures that even on a balancer
  -- with 0 connections the heighest weighted entry is picked first. If we'd
  -- not add the `+1` then any target with 0 connections would always be the
  -- first to be picked (even if it has a very low eight)
  bh:update(addr, (addr.connectionCount + 1) / addr.weight)
end

-- Note: the `target` parameter is optional, if not provided it will use their as last tried targets
-- Currently this is only used in the `afterBalance` method test case.
function lc:afterBalance(target)
  local last_tried = target or get_last_tried_target()
  if last_tried then
    ngx_log(ngx_DEBUG, "least-connections: releasing last tried target")
    updateConnectionCount(self.binaryHeap, last_tried, -1)
  end
end

function lc:getPeer()
  local tried = get_tried_targets()
  self:afterBalance()

  local address
  do
    local reinsert
    repeat
      if address then
        -- this address we failed before, so temp store it and pop it from
        -- the tree. When we're done we'll reinsert them.
        reinsert = reinsert or {}
        reinsert[#reinsert + 1] = address
        self.binaryHeap:pop()
      end
      address = self.binaryHeap:peek()
    until address == nil or not (tried or EMPTY)[address.id]

    if address == nil and tried then
      -- we failed all addresses, so drop the list of failed ones, we are trying
      -- again, so we restart using the ones that previously failed us. Until
      -- eventually we hit the limit of retries (but that's up to the user).
      clear_tried_targets()
      address = reinsert[1]  -- the address to use is the first one, top of the heap
    end

    if reinsert then
    -- reinsert the ones we temporarily popped
      for i = 1, #reinsert do
        local addr = reinsert[i]
        insertAddr(self.binaryHeap, addr)
      end
      reinsert = nil -- luacheck: ignore
    end
  end
    -- check the address returned, and get an IP

  if address == nil then
    -- No peers are available
    return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
  end
  updateConnectionCount(self.binaryHeap, address, 1)
  return address, nil
end

local function clearHeap(bh)
  bh.payloads = {}
  bh.reverse = {}
  bh.values = {}
end

function lc:afterHostUpdate()
  clearHeap(self.binaryHeap)

  for _, target in ipairs(self.targets) do
    insertAddr(self.binaryHeap, target)
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
function lc.new(targets)
  local self = setmetatable({
    binaryHeap = binaryHeap.minUnique(),
    targets = targets or {},
  }, lc)

  self:afterHostUpdate()

  ngx_log(ngx_DEBUG, "least-connections balancer created")

  return self
end

return lc
