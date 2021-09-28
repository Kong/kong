
local balancers = require "kong.runloop.balancer.balancers"

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
  local new_wheel = {}
  local total_points = 0
  local total_weight = 0
  local divisor = 0

  local targets = self.balancer.targets or {}

  -- calculate the gcd to find the proportional weight of each address
  for _, target in ipairs(targets) do
    for _, address in ipairs(target.addresses) do
      local address_weight = address.weight
      divisor = gcd(divisor, address_weight)
      total_weight = total_weight + address_weight
    end
  end

  self.balancer.totalWeight = total_weight
  if total_weight == 0 then
    ngx.log(ngx.DEBUG, "trying to set a round-robin balancer with no addresses")
    return
  end

  if divisor > 0 then
    total_points = total_weight / divisor
  end

  -- add all addresses to the wheel
  for _, targets in ipairs(targets) do
    for _, address in ipairs(targets.addresses) do
      local address_points = address.weight / divisor
      for _ = 1, address_points do
        new_wheel[#new_wheel + 1] = address
      end
    end
  end

  -- store the shuffled wheel
  self.wheel = wheel_shuffle(new_wheel)
  self.wheelSize = total_points
end


function roundrobin_algorithm:getPeer(cacheOnly, handle, hashValue)
  if handle then
    -- existing handle, so it's a retry
    handle.retryCount = handle.retryCount + 1
  else
    -- no handle, so this is a first try
    handle = {}   -- self:getHandle()  -- no GC specific handler needed
    handle.retryCount = 0
  end

  local starting_pointer = self.pointer
  local address
  local ip, port, hostname
  repeat
    self.pointer = self.pointer + 1

    if self.pointer > self.wheelSize then
      self.pointer = 1
    end

    address = self.wheel[self.pointer]
    if address ~= nil and address.available and not address.disabled then
      ip, port, hostname = balancers.getAddressPeer(address, cacheOnly)
      if ip then
        -- success, update handle
        handle.address = address
        return ip, port, hostname, handle

      elseif port == balancers.errors.ERR_DNS_UPDATED then
        -- if healty we just need to try again
        if not self.balancer.healthy then
          return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
        end
      elseif port == balancers.errors.ERR_ADDRESS_UNAVAILABLE then
        ngx.log(ngx.DEBUG, "found address but it was unavailable. ",
          " trying next one.")
      else
        -- an unknown error occurred
        return nil, port
      end

    end

  until self.pointer == starting_pointer

  return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
end


function roundrobin_algorithm.new(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))

  local balancer = opts.balancer

  local self = setmetatable({
    health_threshold = balancer.health_threshold,
    balancer = balancer,

    pointer = 1,
    wheelSize = 0,
    maxWheelSize = balancer.maxWheelSize or balancer.wheelSize or MAX_WHEEL_SIZE,
    wheel = {},
  }, roundrobin_algorithm)

  self:afterHostUpdate()

  return self
end

return roundrobin_algorithm
