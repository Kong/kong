-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local balancers = require "kong.runloop.balancer.balancers"
local get_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".get_tried_targets
local random = math.random

local MAX_WHEEL_SIZE = 2^32

local roundrobin_algorithm = {}
roundrobin_algorithm.__index = roundrobin_algorithm

-- calculate the greater common divisor, used to find the smallest wheel
-- possible
local function gcd(a, b)
  if b == 0 then
    return a
  end

  return gcd(b, a % b)
end


local function wheel_shuffle(wheel)
  for i = #wheel, 2, -1 do
    local j = random(i)
    wheel[i], wheel[j] = wheel[j], wheel[i]
  end
  return wheel
end


function roundrobin_algorithm:afterHostUpdate()
  local total_points = 0
  local total_weight = 0
  local divisor = 0

  local targets = self.targets

  -- calculate the gcd to find the proportional weight of each address
  for _, target in ipairs(targets) do
    assert(target.id)
    local target_weight = target.weight
    divisor = gcd(divisor, target_weight)
    total_weight = total_weight + target_weight
  end

  self.totalWeight = total_weight
  assert(total_weight > 0, "trying to set a round-robin balancer with no addresses")

  if divisor > 0 then
    total_points = total_weight / divisor
  end

  -- add all addresses to the wheel
  local new_wheel = {}
  local idx = 1

  for _, target in ipairs(targets) do
    local target_points = target.weight / divisor
    for _ = 1, target_points do
      new_wheel[idx] = target
      idx = idx + 1
    end
  end

  -- store the shuffled wheel
  self.wheel = wheel_shuffle(new_wheel)
  self.wheelSize = total_points
end


function roundrobin_algorithm:getPeer(_)
  -- if handle then
  --   -- existing handle, so it's a retry
  --   handle.retryCount = handle.retryCount + 1

  -- else
  --   -- no handle, so this is a first try
  --   handle = {}   -- self:getHandle()  -- no GC specific handler needed
  --   handle.retryCount = 0
  -- end

  local starting_pointer = self.pointer
  local target

  local tried = get_tried_targets()

  repeat
    self.pointer = self.pointer + 1

    if self.pointer > self.wheelSize then
      self.pointer = 1
    end

    target = self.wheel[self.pointer]

    if target and not tried[target.id] then
      return target
    end

  until self.pointer == starting_pointer

  return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
end


function roundrobin_algorithm:afterBalance()
  return true -- noop
end

function roundrobin_algorithm:cleanup()
  return true -- noop
end

function roundrobin_algorithm.new(targets)
  local self = setmetatable({
    pointer = 1,
    wheelSize = 0,
    maxWheelSize = MAX_WHEEL_SIZE,
    totalWeight = 0,
    wheel = {},
    targets = targets or {},
  }, roundrobin_algorithm)

  self:afterHostUpdate()

  return self
end

return roundrobin_algorithm
