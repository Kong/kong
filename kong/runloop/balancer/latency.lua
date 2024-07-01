--------------------------------------------------------------------------
-- ewma balancer algorithm
--
-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala


local balancers = require "kong.runloop.balancer.balancers"

local pairs = pairs
local ipairs = ipairs
local math = math
local math_exp = math.exp
local ngx_now = ngx.now
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG

local table_nkeys = table.nkeys
local table_clear = table.clear
local table_insert = table.insert

local DECAY_TIME = 10 -- this value is in seconds
local PICK_SET_SIZE = 2

local new_addresses = {}

local ewma = {}
ewma.__index = ewma

local function decay_ewma(ewma, last_touched_at, rtt, now)
  local td = now - last_touched_at
  td = (td > 0) and td or 0
  local weight = math_exp(-td / DECAY_TIME)

  ewma = ewma * weight + rtt * (1.0 - weight)
  return ewma
end


-- slow_start_ewma is something we use to avoid sending too many requests
-- to the newly introduced endpoints. We currently use average ewma values
-- of existing endpoints.
local function calculate_slow_start_ewma(self)
  local total_ewma = 0
  local address_count = 0

  for _, target in ipairs(self.balancer.targets) do
    for _, address in ipairs(target.addresses) do
      if address.available then
        local ewma = self.ewma[address] or 0
        address_count = address_count + 1
        total_ewma = total_ewma + ewma
      end
    end
  end

  if address_count == 0 then
    ngx_log(ngx_DEBUG, "no ewma value exists for the endpoints")
    return nil
  end

  self.address_count = address_count
  return total_ewma / address_count
end


function ewma:afterHostUpdate()
  table_clear(new_addresses)

  for _, target in ipairs(self.balancer.targets) do
    for _, address in ipairs(target.addresses) do
      if address.available then
        new_addresses[address] = true
      end
    end
  end

  local ewma = self.ewma
  local ewma_last_touched_at = self.ewma_last_touched_at
  for address, _ in pairs(ewma) do
    if not new_addresses[address] then
      ewma[address] = nil
      ewma_last_touched_at[address] = nil
    end
  end

  local slow_start_ewma = calculate_slow_start_ewma(self)
  if slow_start_ewma == nil then
    return
  end

  local now = ngx_now()
  for address, _ in pairs(new_addresses) do
    if not ewma[address] then
      ewma[address] = slow_start_ewma
      ewma_last_touched_at[address] = now      
    end
  end
end


local function get_or_update_ewma(self, address, rtt, update)
  local ewma = self.ewma[address] or 0
  local now = ngx_now()
  local last_touched_at = self.ewma_last_touched_at[address] or 0
  ewma = decay_ewma(ewma, last_touched_at, rtt, now)
  if update then
    self.ewma_last_touched_at[address] = now
    self.ewma[address] = ewma
  end

  return ewma
end


function ewma:afterBalance(_, handle)
  local ngx_var = ngx.var
  local response_time = tonumber(ngx_var.upstream_response_time) or 0
  local connect_time = tonumber(ngx_var.upstream_connect_time) or 0
  local rtt = connect_time + response_time
  local upstream = ngx_var.upstream_addr
  local address = handle.address
  if upstream then
    ngx_log(ngx_DEBUG, "ewma after balancer rtt: ", rtt)
    return get_or_update_ewma(self, address, rtt, true)
  end

  return nil, "no upstream addr found"
end


local function pick_and_score(self, addresses, k)
  local lowest_score_index = 1
  local lowest_score = get_or_update_ewma(self, addresses[lowest_score_index], 0, false) / addresses[lowest_score_index].weight
  for i = 2, k do
    local new_score = get_or_update_ewma(self, addresses[i], 0, false) / addresses[i].weight
    if new_score < lowest_score then
      lowest_score_index = i
      lowest_score = new_score
    end
  end
  return addresses[lowest_score_index], lowest_score
end


function ewma:getPeer(cache_only, handle)
  if handle then
    -- existing handle, so it's a retry
    handle.retryCount = handle.retryCount + 1

    -- keep track of failed addresses
    handle.failedAddresses = handle.failedAddresses or setmetatable({}, {__mode = "k"})
    handle.failedAddresses[handle.address] = true
  else
    handle = {
        failedAddresses = setmetatable({}, {__mode = "k"}),
        retryCount = 0,
    }
  end

  if not self.balancer.healthy then
    return nil, balancers.errors.ERR_BALANCER_UNHEALTHY
  end

  -- select first address
  local address
  for addr, ewma in pairs(self.ewma) do
    if ewma ~= nil then
      address = addr
      break
    end
  end

  if address == nil then
    -- No peers are available
    return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE, nil
  end

  local address_count = self.address_count
  local ip, port, host
  while true do
    -- retry end
    if address_count > 1 then
      local k = (address_count < PICK_SET_SIZE) and address_count or PICK_SET_SIZE
      local filtered_addresses = {}

      for addr, ewma in pairs(self.ewma) do
        if not handle.failedAddresses[addr] then
          table_insert(filtered_addresses, addr)
        end
      end

      local filtered_addresses_num = table_nkeys(filtered_addresses)
      if filtered_addresses_num == 0 then
        ngx_log(ngx_WARN, "all endpoints have been retried")
        return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE
      end

      local score
      if filtered_addresses_num > 1 then
        k = filtered_addresses_num > k and filtered_addresses_num or k
        address, score = pick_and_score(self, filtered_addresses, k)
      else
        address = filtered_addresses[1]
        score = get_or_update_ewma(self, filtered_addresses[1], 0, false)
      end
      ngx_log(ngx_DEBUG, "get ewma score: ", score)
    end
    -- check the address returned, and get an IP

    ip, port, host = balancers.getAddressPeer(address, cache_only)
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

  return ip, port, host, handle
end


function ewma.new(opts)
  assert(type(opts) == "table", "Expected an options table, but got: "..type(opts))
  local balancer = opts.balancer

  local self = setmetatable({
    ewma = {},
    ewma_last_touched_at = {},
    balancer = balancer,
    address_count = 0,
  }, ewma)

  self:afterHostUpdate()

  ngx_log(ngx_DEBUG, "latency balancer created")

  return self
end


return ewma
