-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


--------------------------------------------------------------------------
-- ewma balancer algorithm
--
-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala


-- This module is used as a super class for the lowest-latency and lowest-usage

local balancers = require "kong.runloop.balancer.balancers"
local get_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".get_tried_targets

local pairs = pairs
local ipairs = ipairs
local math = math
local math_exp = math.exp
local ngx_now = ngx.now


local DECAY_TIME = 10 -- this value is in seconds
local PICK_SET_SIZE = 2

local new_addresses = {}

local ewma = {}
ewma.__index = ewma

local function decay_ewma(ewma, last_touched_at, data_point, now)
  local td = now - last_touched_at
  td = (td > 0) and td or 0
  local weight = math_exp(-td / DECAY_TIME)

  ewma = ewma * weight + data_point * (1.0 - weight)
  return ewma
end


-- slow_start_ewma is something we use to avoid sending too many requests
-- to the newly introduced endpoints. We currently use average ewma values
-- of existing endpoints.
local function calculate_slow_start_ewma(self)
  local total_ewma = 0
  local target_count = 0

  for _, target in ipairs(self.targets) do
    local ewma = self.ewma[target.id] or 0
    target_count = target_count + 1
    total_ewma = total_ewma + ewma
  end

  if target_count == 0 then
    kong.log.debug("no ewma value exists for the endpoints")
    return nil
  end

  self.target_count = target_count
  return total_ewma / target_count
end


function ewma:afterHostUpdate()
  local ewma = self.ewma
  local ewma_last_touched_at = self.ewma_last_touched_at
  for target, _ in pairs(ewma) do
    assert(target.id)
    if not new_addresses[target.id] then
      ewma[target.id] = nil
      ewma_last_touched_at[target.id] = nil
    end
  end

  local slow_start_ewma = calculate_slow_start_ewma(self)
  if slow_start_ewma == nil then
    return
  end

  local now = ngx_now()
  for _, target in pairs(self.targets) do
    if not ewma[target.id] then
      ewma[target.id] = slow_start_ewma
      ewma_last_touched_at[target.id] = now
    end
  end

  return true
end


local function get_or_update_ewma(self, target, data_point, update)
  local ewma = self.ewma[target.id] or 0
  local now = ngx_now()
  local last_touched_at = self.ewma_last_touched_at[target.id] or 0
  ewma = decay_ewma(ewma, last_touched_at, data_point, now)
  if update then
    self.ewma_last_touched_at[target.id] = now
    self.ewma[target.id] = ewma
  end

  return ewma
end


function ewma:afterBalance(target, data_point)
  assert(target.id and self.ewma[target.id], "target not found in ewma table")
  assert(type(data_point) == "number", "data_point must be a number")

  return get_or_update_ewma(self, target, data_point, true)
end


local function pick_and_score(self, addresses, k)
  local tried = get_tried_targets()

  local lowest_score_index
  local lowest_score = math.huge
  for i = 1, k do
    local new_score = get_or_update_ewma(self, addresses[i], 0, false) / addresses[i].weight
    if new_score < lowest_score and not tried[addresses[i].id] then
      lowest_score_index = i
      lowest_score = new_score
    end
  end
  return lowest_score_index and addresses[lowest_score_index], lowest_score
end


function ewma:getPeer(_, _)
  -- if handle then
  --   -- existing handle, so it's a retry
  --   handle.retryCount = handle.retryCount + 1

  --   -- keep track of failed addresses
  --   handle.failedAddresses = handle.failedAddresses or setmetatable({}, {__mode = "k"})
  --   handle.failedAddresses[handle.address] = true
  -- else
  --   handle = {
  --       failedAddresses = setmetatable({}, {__mode = "k"}),
  --       retryCount = 0,
  --   }
  -- end

  -- select first address
  local target
  for t, ewma in pairs(self.ewma) do
    if ewma ~= nil then
      target = t
      break
    end
  end

  if target == nil then
    -- No peers are available
    return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE, nil
  end

  local target_count = self.target_count
  if target_count > 1 then
    local k = (target_count < PICK_SET_SIZE) and target_count or PICK_SET_SIZE

    local score
    if self.target_count > 1 then
      k = self.target_count > k and self.target_count or k
      target, score = pick_and_score(self, self.targets, k)
    else
      target = self.targets[1]
      score = get_or_update_ewma(self, target, 0, false)
    end
    kong.log.debug("get ewma score: ", score)
  end

  return target, not target and balancers.errors.ERR_NO_PEERS_AVAILABLE
end


function ewma:cleanup()
  return true -- noop
end

function ewma.new(targets)
  local self = setmetatable({
    ewma = {},
    ewma_last_touched_at = {},
    target_count = 0,
    targets = targets or {},
  }, ewma)

  self:afterHostUpdate()

  return self
end


return ewma
