local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local get_certificate = require "kong.runloop.certificate".get_certificate

local balancers = require "kong.runloop.balancer.balancers"
local upstreams = require "kong.runloop.balancer.upstreams"
local healthcheck -- delay initialization

local ngx = ngx
local log = ngx.log
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local assert = assert

local ERR = ngx.ERR
local WARN = ngx.WARN

local healthcheckers_M = {}

local healthcheck_subscribers = {}

function healthcheckers_M.init()
  healthcheck = require("resty.healthcheck") -- delayed initialization
end


function healthcheckers_M.stop_healthchecker(balancer, delay)
  local healthchecker = balancer.healthchecker
  if healthchecker then
    local ok, err
    if delay and delay > 0 then
      ok, err = healthchecker:delayed_clear(delay)
    else
      ok, err = healthchecker:clear()
    end

    if not ok then
      log(ERR, "[healthchecks] error clearing healthcheck data: ", err)
    end
    healthchecker:stop()
    local hc_callback = balancer.healthchecker_callbacks
    kong.worker_events.unregister(hc_callback, healthchecker.EVENT_SOURCE)
  end
end


local function populate_healthchecker(hc, balancer, upstream)
  balancer:eachAddress(function(address, target)
    if address.weight > 0 then
      local ipaddr = address.ip
      local port = address.port
      local hostname = target.name
      local ok, err = hc:add_target(ipaddr, port, hostname, true,
        upstream.host_header)
      if ok then
        -- Get existing health status which may have been initialized
        -- with data from another worker, and apply to the new balancer.
        local tgt_status = hc:get_target_status(ipaddr, port, hostname)
        if tgt_status ~= nil then
          balancer:setAddressStatus(address, tgt_status)
        end

      else
        log(ERR, "[healthchecks] failed adding target: ", err)
      end
    end
  end)
end


------------------------------------------------------------------------------
-- Callback function that informs the healthchecker when targets are added
-- or removed to a balancer and when targets health status change.
-- @param balancer the ring balancer object that triggers this callback.
-- @param action "added", "removed", or "health"
-- @param address balancer address object
-- @param ip string
-- @param port number
-- @param hostname string
local function ring_balancer_callback(balancer, action, address, ip, port, hostname)
  if kong == nil then
    -- kong is being run in unit-test mode
    return
  end
  local healthchecker = balancer.healthchecker
  if not healthchecker then
    return
  end

  if action == "health" then
    local balancer_status
    if address then
      balancer_status = "HEALTHY"
    else
      balancer_status = "UNHEALTHY"
    end
    log(WARN, "[healthchecks] balancer ", healthchecker.name,
      " reported health status changed to ", balancer_status)

  else
    local upstream = balancers.get_upstream(balancer)

    if upstream then
      if action == "added" then
        local ok, err = healthchecker:add_target(ip, port, hostname, true,
          upstream.host_header)
        if not ok then
          log(WARN, "[healthchecks] failed adding a target: ", err)
        end

      elseif action == "removed" then
        local ok, err = healthchecker:remove_target(ip, port, hostname)
        if not ok then
          log(ERR, "[healthchecks] failed removing a target: ", err)
        end

      else
        log(WARN, "[healthchecks] unknown status from balancer: ",
          tostring(action))
      end

    else
      log(ERR, "[healthchecks] upstream ", hostname, " (", ip, ":", port,
        ") not found for received status: ", tostring(action))
    end

  end
end

-- @param hc The healthchecker object
-- @param balancer The balancer object
local function attach_healthchecker_to_balancer(hc, balancer)
  local function hc_callback(tgt, event)
    local status
    if event == hc.events.healthy then
      status = true
    elseif event == hc.events.unhealthy then
      status = false
    else
      return
    end

    local ok, err
    ok, err = balancer:setAddressStatus(balancer:findAddress(tgt.ip, tgt.port, tgt.hostname), status)

    do
      local health = status and "healthy" or "unhealthy"
      for _, subscriber in ipairs(healthcheck_subscribers) do
        subscriber(balancer.upstream_id, tgt.ip, tgt.port, tgt.hostname, health)
      end
    end

    if not ok then
      log(WARN, "[healthchecks] failed setting peer status (upstream: ", hc.name, "): ", err)
    end
  end

  -- Register event using a weak-reference in worker-events,
  -- and attach lifetime of callback to that of the balancer.
  kong.worker_events.register_weak(hc_callback, hc.EVENT_SOURCE)
  balancer.healthchecker_callbacks = hc_callback
  balancer.healthchecker = hc

  balancer.report_http_status = function(handle, status)
    local address = handle.address
    local ip, port = address.ip, address.port
    local hostname = address.target and address.target.name or nil
    local _, err = hc:report_http_status(ip, port, hostname, status, "passive")
    if err then
      log(ERR, "[healthchecks] failed reporting status: ", err)
    end
  end

  balancer.report_tcp_failure = function(handle)
    local address = handle.address
    local ip, port = address.ip, address.port
    local hostname = address.target and address.target.name or nil
    local _, err = hc:report_tcp_failure(ip, port, hostname, nil, "passive")
    if err then
      log(ERR, "[healthchecks] failed reporting status: ", err)
    end
  end

  balancer.report_timeout = function(handle)
    local address = handle.address
    local ip, port = address.ip, address.port
    local hostname = address.target and address.target.name or nil
    local _, err = hc:report_timeout(ip, port, hostname, "passive")
    if err then
      log(ERR, "[healthchecks] failed reporting status: ", err)
    end
  end
end


-- add empty healthcheck functions to balancer when hc is not used
local function populate_balancer(balancer)
  balancer.report_http_status = function()
    return true
  end

  balancer.report_tcp_failure = function()
    return true
  end

  balancer.report_timeout = function()
    return true
  end

  return true
end


local parsed_cert, parsed_key
local function parse_global_cert_and_key()
  if not parsed_cert then
    local pl_file = require("pl.file")
    parsed_cert = assert(pl_file.read(kong.configuration.client_ssl_cert))
    parsed_key = assert(pl_file.read(kong.configuration.client_ssl_cert_key))
  end

  return parsed_cert, parsed_key
end


local function is_upstream_using_healthcheck(upstream)
  if upstream ~= nil then
    return upstream.healthchecks.active.healthy.interval ~= 0
           or upstream.healthchecks.active.unhealthy.interval ~= 0
           or upstream.healthchecks.passive.unhealthy.tcp_failures ~= 0
           or upstream.healthchecks.passive.unhealthy.timeouts ~= 0
           or upstream.healthchecks.passive.unhealthy.http_failures ~= 0
  end

  return false
end


----------------------------------------------------------------------------
-- Create a healthchecker object.
-- @param upstream An upstream entity table.
function healthcheckers_M.create_healthchecker(balancer, upstream)
  -- Do not run active healthchecks in `stream` module
  local checks = upstream.healthchecks
  if (ngx.config.subsystem == "stream" and checks.active.type ~= "tcp")
    or (ngx.config.subsystem == "http" and checks.active.type == "tcp")
  then
    checks = cycle_aware_deep_copy(checks)
    checks.active.healthy.interval = 0
    checks.active.unhealthy.interval = 0
  end

  if not is_upstream_using_healthcheck(upstream) then
    return populate_balancer(balancer)
  end

  local ssl_cert, ssl_key
  if upstream.client_certificate then
    local cert, err = get_certificate(upstream.client_certificate)
    if not cert then
      log(ERR, "unable to fetch upstream client TLS certificate ",
        upstream.client_certificate.id, ": ", err)
      return nil, err
    end

    ssl_cert = cert.cert
    ssl_key = cert.key

  elseif kong.configuration.client_ssl then
    ssl_cert, ssl_key = parse_global_cert_and_key()
  end

  local events_module = "resty.events"
  local healthchecker, err = healthcheck.new({
    name = assert(upstream.ws_id) .. ":" .. upstream.name,
    shm_name = "kong_healthchecks",
    checks = checks,
    ssl_cert = ssl_cert,
    ssl_key = ssl_key,
    events_module = events_module,
  })

  if not healthchecker then
    return nil, err
  end

  populate_healthchecker(healthchecker, balancer, upstream)

  attach_healthchecker_to_balancer(healthchecker, balancer, upstream.id)

  balancer:setCallback(ring_balancer_callback)

  return true
end


--------------------------------------------------------------------------------
-- Get healthcheck information for an upstream.
-- @param upstream_id the id of the upstream.
-- @return one of three possible returns:
-- * if healthchecks are enabled, a table mapping keys ("ip:port") to booleans;
-- * if healthchecks are disabled, nil;
-- * in case of errors, nil and an error message.
function healthcheckers_M.get_upstream_health(upstream_id)

  local upstream = upstreams.get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local using_hc = is_upstream_using_healthcheck(upstream)

  local balancer = balancers.get_balancer_by_id(upstream_id)
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker
  if using_hc then
    healthchecker = balancer.healthchecker
    if not healthchecker then
      return nil, "healthchecker not found"
    end
  end

  local health_info = {}
  for _, target in ipairs(balancer.targets) do
    local key = target.name .. ":" .. target.port
    health_info[key] = balancer:getTargetStatus(target)
    for _, address in ipairs(health_info[key].addresses) do
      if using_hc and target.weight > 0 then
        address.health = address.healthy and "HEALTHY" or "UNHEALTHY"
      else
        address.health = "HEALTHCHECKS_OFF"
      end
      address.healthy = nil
    end
  end

  return health_info
end

--------------------------------------------------------------------------------
-- Get healthcheck information for a balancer.
-- @param upstream_id the id of the upstream.
-- @return table with balancer health info
function healthcheckers_M.get_balancer_health(upstream_id)

  local upstream = upstreams.get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local balancer = balancers.get_balancer_by_id(upstream_id)
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker

  local balancer_status = balancer:getStatus()
  local balancer_health = balancer_status.healthy and "HEALTHY" or "UNHEALTHY"

  local health = "HEALTHCHECKS_OFF"
  if is_upstream_using_healthcheck(upstream) then
    healthchecker = balancer.healthchecker
    if not healthchecker then
      return nil, "healthchecker not found"
    end

    health = balancer_health
  end

  return {
    health = health,
    balancer_health = balancer_health,
    id = upstream_id,
    details = balancer_status,
  }
end


--------------------------------------------------------------------------------
-- Subscribe to events produced by health checkers.
-- There is no guarantee that the event reported is different from the
-- previous report (in other words, you may get two "healthy" events in
-- a row for the same target).
-- @param callback Function to be called whenever a target has its
-- status updated. The function should have the following signature:
-- `function(upstream_id, target_ip, target_port, target_hostname, health)`
-- where `upstream_id` is the entity id of the upstream,
-- `target_ip`, `target_port` and `target_hostname` identify the target,
-- and `health` is a string: "healthy", "unhealthy"
-- The return value of the callback function is ignored.
function healthcheckers_M.subscribe_to_healthcheck_events(callback)
  healthcheck_subscribers[#healthcheck_subscribers + 1] = callback
end


--------------------------------------------------------------------------------
-- Unsubscribe from events produced by health checkers.
-- @param callback Function that was added as the callback.
-- Note that this must be the same closure used for subscribing.
function healthcheckers_M.unsubscribe_from_healthcheck_events(callback)
  for i, c in ipairs(healthcheck_subscribers) do
    if c == callback then
      table.remove(healthcheck_subscribers, i)
      return
    end
  end
end


--------------------------------------------------------------------------------
-- Stop all health checkers.
-- @param delay Delay before actually removing the health checker from memory.
-- When a upstream with the same targets might be created right after stopping
-- the health checker, this parameter is useful to avoid throwing away current
-- health status.
function healthcheckers_M.stop_healthcheckers(delay)
  local all_upstreams, err = upstreams.get_all_upstreams()
  if err then
    log(ERR, "[healthchecks] failed to retrieve all upstreams: ", err)
    return
  end
  for _, id in pairs(all_upstreams) do
    local balancer = balancers.get_balancer_by_id(id)
    if balancer then
      healthcheckers_M.stop_healthchecker(balancer, delay)
    end

    balancers.set_balancer(id, nil)
  end
end


return healthcheckers_M
