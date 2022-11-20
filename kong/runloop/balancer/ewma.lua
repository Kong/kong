--------------------------------------------------------------------------
-- ewma balancer algorithm
--
-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala


local balancers = require "kong.runloop.balancer.balancers"

local ngx_now = ngx.now
local ngx_log = ngx.log
local ngx_CRIT = ngx.CRIT
local ngx_DEBUG = ngx.DEBUG

local floor = math.floor
local table_sort = table.sort
local table_insert = table.insert

local DECAY_TIME = 10 -- this value is in seconds
local PICK_SET_SIZE = 2

local ewma = {}
ewma.__index = ewma

local function decay_ewma(ewma, last_touched_at, rtt, now)
    local td = now - last_touched_at
    td = (td > 0) and td or 0
    local weight = math.exp(-td/DECAY_TIME)
  
    ewma = ewma * weight + rtt * (1.0 - weight)
    return ewma
end


-- slow_start_ewma is something we use to avoid sending too many requests
-- to the newly introduced endpoints. We currently use average ewma values
-- of existing endpoints.
local function calculate_slow_start_ewma(self)
    local total_ewma = 0
    self.address_count = 0
  
    for _, target in ipairs(self.balancer.targets) do
        for _, address in ipairs(target.addresses) do
            local ewma = self.ewma[address] or 0
            self.address_count = self.address_count + 1
            total_ewma = total_ewma + ewma
        end
    end
  
    if self.address_count == 0 then
      ngx_log(ngx_DEBUG, "no ewma value exists for the endpoints")
      return nil
    end
  
    return total_ewma / self.address_count
end


function ewma:afterHostUpdate()
  local new_addresses = {}
  
  for _, target in ipairs(self.balancer.targets) do
    for _, address in ipairs(target.addresses) do
      new_addresses[address] = true
    end
  end

  for address, _ in pairs(self.ewma) do
    if not new_addresses[address] then
      self.ewma[address] = nil
      self.ewma_last_touched_at[address] = nil
    end
  end
  
  local slow_start_ewma = calculate_slow_start_ewma(self)
  if slow_start_ewma ~= nil then
    local now = ngx_now()
    for address, _ in pairs(new_addresses) do
      self.ewma[address] = slow_start_ewma
      self.ewma_last_touched_at[address] = now
    end
  end
end


local function get_or_update_ewma(self, address, rtt, update)
  local ewma = self.ewma[address] or 0
  local now = ngx_now()
  local last_touched_at = self.ewma_last_touched_at[address] or 0
  ewma = decay_ewma(ewma, last_touched_at, rtt, now)
  if not update then
    return ewma
  end

  self.ewma_last_touched_at[address] = now
  self.ewma[address] = ewma
  return ewma
end


function ewma:afterBalance(ctx, handle)
  ngx.log(ngx.ERR, "after balancer")
  local response_time = tonumber(ngx.var.upstream_response_time) or 0
  local connect_time = tonumber(ngx.var.upstream_connect_time) or 0
  local rtt = connect_time + response_time
  local upstream = ngx.var.upstream_addr
  local address = handle.address

  if not upstream then
      return nil, "no upstream addr found"
  end

  return get_or_update_ewma(self, address, rtt, true)
end


-- implementation similar to https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
-- or https://en.wikipedia.org/wiki/Random_permutation
-- loop from 1 .. k
-- pick a random value r from the remaining set of unpicked values (i .. n)
-- swap the value at position i with the value at position r
local function shuffle_address(address, k)
  for i=1, k do
    local rand_index = math.random(i,#address)
    address[i], address[rand_index] = address[rand_index], address[i]
  end
  -- peers[1 .. k] will now contain a randomly selected k from #peers
end

local function pick_and_score(self, address, k)
  shuffle_address(address, k)
  local lowest_score_index = 1
  local lowest_score = get_or_update_ewma(self, address[lowest_score_index], 0, false) / address[lowest_score_index].weight
  for i = 2, k do
    local new_score = get_or_update_ewma(self, address[i], 0, false) / address[lowest_score_index].weight
    if new_score < lowest_score then
      lowest_score_index, lowest_score = i, new_score
    end
  end
  return address[lowest_score_index], lowest_score
end


function ewma:getPeer(cacheOnly, handle, valueToHash)
  if handle then
    -- existing handle, so it's a retry
    handle.retryCount = handle.retryCount + 1

    -- keep track of failed addresses
    handle.failedAddresses = handle.failedAddresses or setmetatable({}, {__mode = "k"})
    handle.failedAddresses[handle.address] = true
  else
    handle = {
        failedAddresses = setmetatable({}, {__mode = "k"}),
        retryCount = 0
    }
  end

  if not self.balancer.healthy then
    return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
  end

  -- select first address
  local address
  for addr, ewma in pairs(self.ewma) do
    address = addr
    break
  end

  if address == nil then
    -- No peers are available
    return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE, nil
  end

  local address, ip, port, host
  local balancer = self.balancer
  while true do
    -- retry end
    if #handle.failedAddresses == self.address_count then
      return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
    end

    if self.address_count > 1 then
      local k = (tonumber(self.address_count) < PICK_SET_SIZE) and tonumber(self.address_count) or PICK_SET_SIZE
      local filtered_address = {}
      if not handle.failedAddresses then
        handle.failedAddresses = setmetatable({}, {__mode = "k"})
      end
  
      for address, ewma in pairs(self.ewma) do
        if not handle.failedAddresses[address] then
          table_insert(filtered_address, address)
        end
      end
  
      if #filtered_address == 0 then
        ngx_log(ngx.WARN, "all endpoints have been retried")
        return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
      end
      local ewma_score
      if #filtered_address > 1 then
        k = #filtered_address > k and #filtered_address or k
        address, ewma_score = pick_and_score(self, filtered_address, k)
      else
        address, ewma_score = filtered_address[1], get_or_update_ewma(self, filtered_address[1], 0, false)
      end
    end
    -- check the address returned, and get an IP

    ip, port, host = balancers.getAddressPeer(address, cacheOnly)
    if ip then
      -- success, exit
      handle.address = address
      break
    end

    handle.failedAddresses[address] = true
    if port ~= balancers.errors.ERR_DNS_UPDATED then
      -- an unknown error
      break
    end
  end

  if ip then
    return ip, port, host, handle
  else
    return nil, port
  end
end


function ewma.new(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))
  local balancer = opts.balancer

  local self = setmetatable({
    ewma = {},
    ewma_last_touched_at = {},
    balancer = balancer,
    address_count = 0,
    balancer = balancer
  }, ewma)

  self:afterHostUpdate()

  ngx_log(ngx_DEBUG, "ewma balancer created")

  return self
end

return ewma
