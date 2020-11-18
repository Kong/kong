local pl_tablex = require "pl.tablex"
local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local utils = require "kong.tools.utils"
local hooks = require "kong.hooks"
local get_certificate = require("kong.runloop.certificate").get_certificate
local recreate_request = require("ngx.balancer").recreate_request


-- due to startup/require order, cannot use the ones from 'kong' here
local dns_client = require "resty.dns.client"


local toip = dns_client.toip
local ngx = ngx
local log = ngx.log
local sleep = ngx.sleep
local null = ngx.null
local min = math.min
local max = math.max
local type = type
local sub = string.sub
local find = string.find
local match = string.match
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local assert = assert
local table = table
local table_concat = table.concat
local table_remove = table.remove
local timer_at = ngx.timer.at
local run_hook = hooks.run_hook
local var = ngx.var
local get_phase = ngx.get_phase


local CRIT = ngx.CRIT
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local EMPTY_T = pl_tablex.readonly {}
local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


-- FIFO queue of upstream events for the eventual worker consistency
local upstream_events_queue = {}


-- for unit-testing purposes only
local _load_upstreams_dict_into_memory
local _load_upstream_into_memory
local _load_targets_into_memory


--==============================================================================
-- Ring-balancer based resolution
--==============================================================================


-- table holding our balancer objects, indexed by upstream id
local balancers = {}


-- objects whose lifetimes are bound to that of a balancer
local healthcheckers = {}
local healthchecker_callbacks = {}
local upstream_ids = {}
local upstream_by_name = {}


-- health check API callbacks to be called on healthcheck events
local healthcheck_subscribers = {}


-- Caching logic
--
-- We retain 3 entities in cache:
--
-- 1) `"balancer:upstreams"` - a list of upstreams
--    to be invalidated on any upstream change
-- 2) `"balancer:upstreams:" .. id` - individual upstreams
--    to be invalidated on individual basis
-- 3) `"balancer:targets:" .. id`
--    target for an upstream along with the upstream it belongs to
--
-- Distinction between 1 and 2 makes it possible to invalidate individual
-- upstreams, instead of all at once forcing to rebuild all balancers


-- functions forward-declarations
local create_balancers
local set_upstream_events_queue
local get_upstream_events_queue

local function set_balancer(upstream_id, balancer)
  local prev = balancers[upstream_id]
  if prev then
    healthcheckers[prev] = nil
    healthchecker_callbacks[prev] = nil
    upstream_ids[prev] = nil
  end
  balancers[upstream_id] = balancer
end


local function stop_healthchecker(balancer)
  local healthchecker = healthcheckers[balancer]
  if healthchecker then
    local ok, err = healthchecker:clear()
    if not ok then
      log(ERR, "[healthchecks] error clearing healthcheck data: ", err)
    end
    healthchecker:stop()
    local hc_callback = healthchecker_callbacks[balancer]
    singletons.worker_events.unregister(hc_callback, healthchecker.EVENT_SOURCE)
  end
  healthcheckers[balancer] = nil
end


------------------------------------------------------------------------------
-- Loads a single upstream entity.
-- @param upstream_id string
-- @return the upstream table, or nil+error
local function load_upstream_into_memory(upstream_id)
  local upstream, err = singletons.db.upstreams:select({id = upstream_id}, GLOBAL_QUERY_OPTS)
  if not upstream then
    return nil, err
  end

  return upstream
end
_load_upstream_into_memory = load_upstream_into_memory


local function get_upstream_by_id(upstream_id)
  local upstream_cache_key = "balancer:upstreams:" .. upstream_id

  return singletons.core_cache:get(upstream_cache_key, nil,
                                   load_upstream_into_memory, upstream_id)
end


------------------------------------------------------------------------------
-- Loads the targets from the DB.
-- @param upstream_id Upstream uuid for which to load the target
-- @return The target array, with target entity tables.
local function load_targets_into_memory(upstream_id)

  local targets, err, err_t =
    singletons.db.targets:select_by_upstream_raw({ id = upstream_id }, GLOBAL_QUERY_OPTS)

  if not targets then
    return nil, err, err_t
  end

  -- perform some raw data updates
  for _, target in ipairs(targets) do
    -- split `target` field into `name` and `port`
    local port
    target.name, port = match(target.target, "^(.-):(%d+)$")
    target.port = tonumber(port)
  end

  return targets
end
_load_targets_into_memory = load_targets_into_memory


------------------------------------------------------------------------------
-- Fetch targets, from cache or the DB.
-- @param upstream The upstream entity object
-- @return The targets array, with target entity tables.
local function fetch_targets(upstream)
  local targets_cache_key = "balancer:targets:" .. upstream.id

  return singletons.core_cache:get(targets_cache_key, nil,
                              load_targets_into_memory, upstream.id)
end


--------------------------------------------------------------------------------
-- Add targets to the balancer.
-- @param balancer balancer object
-- @param targets list of targets to be applied
local function add_targets(balancer, targets)

  for _, target in ipairs(targets) do
    if target.weight > 0 then
      assert(balancer:addHost(target.name, target.port, target.weight))
    else
      assert(balancer:removeHost(target.name, target.port))
    end

  end
end


local function populate_healthchecker(hc, balancer, upstream)
  for weight, addr, host in balancer:addressIter() do
    if weight > 0 then
      local ipaddr = addr.ip
      local port = addr.port
      local ok, err = hc:add_target(ipaddr, port, host.hostname, true,
                                    upstream.host_header)
      if ok then
        -- Get existing health status which may have been initialized
        -- with data from another worker, and apply to the new balancer.
        local tgt_status = hc:get_target_status(ipaddr, port, host.hostname)
        if tgt_status ~= nil then
          balancer:setAddressStatus(tgt_status, ipaddr, port, host.hostname)
        end

      else
        log(ERR, "[healthchecks] failed adding target: ", err)
      end
    end
  end
end


local create_balancer
local create_healthchecker
local wait
do
  local balancer_types

  do
    local healthcheck -- delay initialization

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
      local healthchecker = healthcheckers[balancer]
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
        local upstream_id = upstream_ids[balancer]
        local upstream = upstream_id and get_upstream_by_id(upstream_id) or nil

        if upstream then
          if action == "added" then
            local ok, err = healthchecker:add_target(ip, port, hostname, true,
                                                    upstream.host_header)
            if not ok then
              log(ERR, "[healthchecks] failed adding a target: ", err)
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
    -- @param upstream_id The upstream id
    local function attach_healthchecker_to_balancer(hc, balancer, upstream_id)
      local hc_callback = function(tgt, event)
        local status
        if event == hc.events.healthy then
          status = true
        elseif event == hc.events.unhealthy then
          status = false
        else
          return
        end

        local hostname = tgt.hostname
        local ok, err
        ok, err = balancer:setAddressStatus(status, tgt.ip, tgt.port, hostname)

        local health = status and "healthy" or "unhealthy"
        for _, subscriber in ipairs(healthcheck_subscribers) do
          subscriber(upstream_id, tgt.ip, tgt.port, hostname, health)
        end

        if not ok then
          log(WARN, "[healthchecks] failed setting peer status (upstream: ", hc.name, "): ", err)
        end
      end

      -- Register event using a weak-reference in worker-events,
      -- and attach lifetime of callback to that of the balancer.
      singletons.worker_events.register_weak(hc_callback, hc.EVENT_SOURCE)
      healthchecker_callbacks[balancer] = hc_callback

      -- The lifetime of the healthchecker is based on that of the balancer.
      healthcheckers[balancer] = hc

      balancer.report_http_status = function(handle, status)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_http_status(ip, port, hostname, status, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end

      balancer.report_tcp_failure = function(handle)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_tcp_failure(ip, port, hostname, nil, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end

      balancer.report_timeout = function(handle)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_timeout(ip, port, hostname, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end
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
    ----------------------------------------------------------------------------
    -- Create a healthchecker object.
    -- @param upstream An upstream entity table.
    create_healthchecker = function(balancer, upstream)
      if not healthcheck then
        healthcheck = require("resty.healthcheck") -- delayed initialization
      end

      -- Do not run active healthchecks in `stream` module
      local checks = upstream.healthchecks
      if (ngx.config.subsystem == "stream" and checks.active.type ~= "tcp")
      or (ngx.config.subsystem == "http"   and checks.active.type == "tcp")
      then
        checks = pl_tablex.deepcopy(checks)
        checks.active.healthy.interval = 0
        checks.active.unhealthy.interval = 0
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

      local healthchecker, err = healthcheck.new({
        name = assert(upstream.ws_id) .. ":" .. upstream.name,
        shm_name = "kong_healthchecks",
        checks = checks,
        ssl_cert = ssl_cert,
        ssl_key = ssl_key,
      })

      if not healthchecker then
        return nil, err
      end

      populate_healthchecker(healthchecker, balancer, upstream)

      attach_healthchecker_to_balancer(healthchecker, balancer, upstream.id)

      balancer:setCallback(ring_balancer_callback)

      return true
    end
  end

  local creating = {}

  wait = function(id, name)
    local timeout = 30
    local step = 0.001
    local ratio = 2
    local max_step = 0.5
    while timeout > 0 do
      sleep(step)
      timeout = timeout - step
      if id ~= nil then
        if not creating[id] then
          return true
        end
      else
        if upstream_by_name[name] ~= nil then
          return true
        end
        local phase = get_phase()
        if phase ~= "init_worker" and phase ~= "init" then
          return false
        end
      end
      if timeout <= 0 then
        break
      end
      step = min(max(0.001, step * ratio), timeout, max_step)
    end
    return nil, "timeout"
  end

  ------------------------------------------------------------------------------
  -- The mutually-exclusive section used internally by the
  -- 'create_balancer' operation.
  -- @param upstream (table) A db.upstreams entity
  -- @return The new balancer object, or nil+error
  local function create_balancer_exclusive(upstream)
    local health_threshold = upstream.healthchecks and
                              upstream.healthchecks.threshold or nil

    if balancer_types == nil then
      balancer_types = {
        ["consistent-hashing"] = require("resty.dns.balancer.consistent_hashing"),
        ["least-connections"] = require("resty.dns.balancer.least_connections"),
        ["round-robin"] = require("resty.dns.balancer.ring"),
      }
    end
    local balancer, err = balancer_types[upstream.algorithm].new({
      log_prefix = "upstream:" .. upstream.name,
      wheelSize = upstream.slots,  -- will be ignored by least-connections
      dns = dns_client,
      healthThreshold = health_threshold,
    })
    if not balancer then
      return nil, "failed creating balancer:" .. err
    end

    local targets, err = fetch_targets(upstream)
    if not targets then
      return nil, "failed fetching targets:" .. err
    end

    add_targets(balancer, targets)

    upstream_ids[balancer] = upstream.id

    local ok, err = create_healthchecker(balancer, upstream)
    if not ok then
      log(ERR, "[healthchecks] error creating health checker: ", err)
    end

    -- only make the new balancer available for other requests after it
    -- is fully set up.
    set_balancer(upstream.id, balancer)

    return balancer
  end

  ------------------------------------------------------------------------------
  -- Create a balancer object, its healthchecker and attach them to the
  -- necessary data structures. The creation of the balancer happens in a
  -- per-worker mutual exclusion section, such that no two requests create the
  -- same balancer at the same time.
  -- @param upstream (table) A db.upstreams entity
  -- @param recreate (boolean, optional) create new balancer even if one exists
  -- @return The new balancer object, or nil+error
  create_balancer = function(upstream, recreate)

    if balancers[upstream.id] and not recreate then
      return balancers[upstream.id]
    end

    if creating[upstream.id] then
      local ok = wait(upstream.id)
      if not ok then
        return nil, "timeout waiting for balancer for " .. upstream.id
      end
      return balancers[upstream.id]
    end

    creating[upstream.id] = true

    local balancer, err = create_balancer_exclusive(upstream)

    creating[upstream.id] = nil
    local ws_id = workspaces.get_workspace_id()
    upstream_by_name[ws_id .. ":" .. upstream.name] = upstream

    return balancer, err
  end
end


local function load_upstreams_dict_into_memory()
  local upstreams_dict = {}

  -- build a dictionary, indexed by the upstream name
  for up, err in singletons.db.upstreams:each(nil, GLOBAL_QUERY_OPTS) do
    if err then
      log(CRIT, "could not obtain list of upstreams: ", err)
      return nil
    end

    upstreams_dict[up.ws_id .. ":" .. up.name] = up.id
  end

  return upstreams_dict
end
_load_upstreams_dict_into_memory = load_upstreams_dict_into_memory


local opts = { neg_ttl = 10 }


------------------------------------------------------------------------------
-- Implements a simple dictionary with all upstream-ids indexed
-- by their name.
-- @return The upstreams dictionary (a map with upstream names as string keys
-- and upstream entity tables as values), or nil+error
local function get_all_upstreams()
  local upstreams_dict, err = singletons.core_cache:get("balancer:upstreams", opts,
                                                        load_upstreams_dict_into_memory)
  if err then
    return nil, err
  end

  return upstreams_dict or {}
end


------------------------------------------------------------------------------
-- Finds and returns an upstream entity. This function covers
-- caching, invalidation, db access, et al.
-- @param upstream_name string.
-- @return upstream table, or `false` if not found, or nil+error
local function get_upstream_by_name(upstream_name)
  local ws_id = workspaces.get_workspace_id()
  local key = ws_id .. ":" .. upstream_name

  if upstream_by_name[key] then
    return upstream_by_name[key]
  end

  -- wait until upstream is loaded on init()
  local ok = wait(nil, key)

  if ok == false then
    -- no upstream by this name
    return false
  end

  if ok == nil then
    return nil, "timeout waiting upstream to be loaded: " .. key
  end

  if upstream_by_name[key] then
    return upstream_by_name[key]
  end

  -- couldn't find upstream at upstream_by_name[key] and there was no timeout
  -- when waiting for the upstream to be loaded on init().
  -- this is a worst-case scenario, so as a last option, we will try to load
  -- all upstreams from the DB into memory to find the upstream
  local upstreams_dict, err = get_all_upstreams()
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[key]
  if not upstream_id then
    return false -- no upstream by this name
  end

  local upstream, err = get_upstream_by_id(upstream_id)
  if err then
    return nil, err
  end

  upstream_by_name[key] = upstream

  return upstream
end


-- looks up a balancer for the target.
-- @param target the table with the target details
-- @param no_create (optional) if true, do not attempt to create
-- (for thorough testing purposes)
-- @return balancer if found, `false` if not found, or nil+error on error
local function get_balancer(target, no_create)
  -- NOTE: only called upon first lookup, so `cache_only` limitations
  -- do not apply here
  local hostname = target.host


  -- first go and find the upstream object, from cache or the db
  local upstream, err = get_upstream_by_name(hostname)
  if upstream == false then
    return false -- no upstream by this name
  end
  if err then
    return nil, err -- there was an error
  end

  local balancer = balancers[upstream.id]
  if not balancer then
    if no_create then
      return nil, "balancer not found"
    else
      log(ERR, "balancer not found for ", upstream.name, ", will create it")
      return create_balancer(upstream), upstream
    end
  end

  return balancer, upstream
end


--==============================================================================
-- Event Callbacks
--==============================================================================


--------------------------------------------------------------------------------
-- Called on any changes to a target.
-- @param operation "create", "update" or "delete"
-- @param target Target table with `upstream.id` field
local function on_target_event(operation, target)
  local upstream_id = target.upstream.id
  local upstream_name = target.upstream.name

  log(DEBUG, "target ", operation, " for upstream ", upstream_id,
      upstream_name and " (" .. upstream_name ..")" or "")

  singletons.core_cache:invalidate_local("balancer:targets:" .. upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    log(ERR, "target ", operation, ": upstream not found for ", upstream_id,
        upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

  local balancer = balancers[upstream_id]
  if not balancer then
    log(ERR, "target ", operation, ": balancer not found for ", upstream_id,
        upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

  local new_balancer, err = create_balancer(upstream, true)
  if not new_balancer then
    return nil, err
  end

  return true
end


local function do_upstream_event(operation, upstream_data)
  local upstream_id = upstream_data.id
  local upstream_name = upstream_data.name
  local ws_id = workspaces.get_workspace_id()
  local by_name_key = ws_id .. ":" .. upstream_name

  if operation == "create" then
    local upstream, err = get_upstream_by_id(upstream_id)
    if err then
      return nil, err
    end

    if not upstream then
      log(ERR, "upstream not found for ", upstream_id)
      return
    end

    local _, err = create_balancer(upstream)
    if err then
      log(CRIT, "failed creating balancer for ", upstream_name, ": ", err)
    end

  elseif operation == "delete" or operation == "update" then
    local target_cache_key = "balancer:targets:"   .. upstream_id
    if singletons.db.strategy ~= "off" then
      singletons.core_cache:invalidate_local(target_cache_key)
    end

    local balancer = balancers[upstream_id]
    if balancer then
      stop_healthchecker(balancer)
    end

    if operation == "delete" then
      set_balancer(upstream_id, nil)
      upstream_by_name[by_name_key] = nil

    else
      local upstream = get_upstream_by_id(upstream_id)

      if not upstream then
        log(ERR, "upstream not found for ", upstream_id)
        return
      end

      local _, err = create_balancer(upstream, true)
      if err then
        log(ERR, "failed recreating balancer for ", upstream_name, ": ", err)
      end
    end

  end

end


--------------------------------------------------------------------------------
-- Called on any changes to an upstream.
-- @param operation "create", "update" or "delete"
-- @param upstream_data table with `id` and `name` fields
local function on_upstream_event(operation, upstream_data)
  if kong.configuration.worker_consistency == "strict" then
    local _, err = do_upstream_event(operation, upstream_data)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
    end
  else
    set_upstream_events_queue(operation, upstream_data)
  end
end


-- Calculates hash-value.
-- Will only be called once per request, on first try.
-- @param upstream the upstream entity
-- @return integer value or nil if there is no hash to calculate
local get_value_to_hash = function(upstream, ctx)
  local hash_on = upstream.hash_on
  if hash_on == "none" or hash_on == nil or hash_on == null then
    return -- not hashing, exit fast
  end

  local identifier
  local header_field_name = "hash_on_header"

  for _ = 1,2 do

   if hash_on == "consumer" then
      if not ctx then
        ctx = ngx.ctx
      end

      -- consumer, fallback to credential
      identifier = (ctx.authenticated_consumer or EMPTY_T).id or
                   (ctx.authenticated_credential or EMPTY_T).id

    elseif hash_on == "ip" then
      identifier = var.remote_addr

    elseif hash_on == "header" then
      identifier = ngx.req.get_headers()[upstream[header_field_name]]
      if type(identifier) == "table" then
        identifier = table_concat(identifier)
      end

    elseif hash_on == "cookie" then
      identifier = var["cookie_" .. upstream.hash_on_cookie]

      -- If the cookie doesn't exist, create one and store in `ctx`
      -- to be added to the "Set-Cookie" header in the response
      if not identifier then
        if not ctx then
          ctx = ngx.ctx
        end

        identifier = utils.uuid()

        ctx.balancer_data.hash_cookie = {
          key = upstream.hash_on_cookie,
          value = identifier,
          path = upstream.hash_on_cookie_path
        }
      end

    end

    if identifier then
      return identifier
    end

    -- we missed the first, so now try the fallback
    hash_on = upstream.hash_fallback
    header_field_name = "hash_fallback_header"
    if hash_on == "none" then
      return nil
    end
  end
  -- nothing found, leave without a hash
end


--==============================================================================
-- Initialize balancers
--==============================================================================


do
  create_balancers = function()
    local upstreams, err = get_all_upstreams()
    if not upstreams then
      log(CRIT, "failed loading initial list of upstreams: ", err)
      return
    end

    local oks, errs = 0, 0
    for ws_and_name, id in pairs(upstreams) do
      local name = sub(ws_and_name, (find(ws_and_name, ":", 1, true)))

      local upstream = get_upstream_by_id(id)
      local ok, err
      if upstream ~= nil then
        ok, err = create_balancer(upstream)
      end
      if ok ~= nil then
        oks = oks + 1
      else
        log(CRIT, "failed creating balancer for ", name, ": ", err)
        errs = errs + 1
      end
    end
    log(DEBUG, "initialized ", oks, " balancer(s), ", errs, " error(s)")
  end

  set_upstream_events_queue = function(operation, upstream_data)
    -- insert the new event into the end of the queue
    upstream_events_queue[#upstream_events_queue + 1] = {
      operation = operation,
      upstream_data = upstream_data,
    }
  end


  get_upstream_events_queue = function()
    return utils.deep_copy(upstream_events_queue)
  end

end


local function update_balancer_state(premature)
  if premature then
    return
  end

  local events_queue = get_upstream_events_queue()

  for i, v in ipairs(events_queue) do
    -- handle the oldest (first) event from the queue
    local _, err = do_upstream_event(v.operation, v.upstream_data, v.workspaces)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
      return
    end

    -- if no err, remove the upstream event from the queue
    table_remove(upstream_events_queue, i)
  end

  local frequency = kong.configuration.worker_state_update_frequency or 1
  local _, err = timer_at(frequency, update_balancer_state)
  if err then
    log(CRIT, "unable to reschedule update proxy state timer: ", err)
  end

end


local function init()
  if kong.configuration.worker_consistency == "strict" then
    create_balancers()
    return
  end

  local opts = { neg_ttl = 10 }
  local upstreams_dict, err = singletons.core_cache:get("balancer:upstreams",
                                      opts, load_upstreams_dict_into_memory)
  if err then
    log(CRIT, "failed loading list of upstreams: ", err)
    return
  end

  for _, id in pairs(upstreams_dict) do
    local upstream_cache_key = "balancer:upstreams:" .. id
    local upstream, err = singletons.core_cache:get(upstream_cache_key, opts,
                    load_upstream_into_memory, id)

    if upstream == nil or err then
      log(WARN, "failed loading upstream ", id, ": ", err)
    end

    local _, err = create_balancer(upstream)

    if err then
      log(CRIT, "failed creating balancer for upstream ", upstream.name, ": ", err)
    end

    local target_cache_key = "balancer:targets:" .. id
    local target, err = singletons.core_cache:get(target_cache_key, opts,
              load_targets_into_memory, id)
    if target == nil or err then
      log(WARN, "failed loading targets for upstream ", id, ": ", err)
    end
  end

  local frequency = kong.configuration.worker_state_update_frequency or 1
  local _, err = timer_at(frequency, update_balancer_state)
  if err then
    log(CRIT, "unable to start update proxy state timer: ", err)
  else
    log(DEBUG, "update proxy state timer scheduled")
  end
end


--==============================================================================
-- Main entry point when resolving
--==============================================================================


--------------------------------------------------------------------------------
-- Resolves the target structure in-place (fields `ip`, `port`, and `hostname`).
--
-- If the hostname matches an 'upstream' pool, then it must be balanced in that
-- pool, in this case any port number provided will be ignored, as the pool
-- provides it.
--
-- @param target the data structure as defined in `core.access.before` where
-- it is created.
-- @return true on success, nil+error message+status code otherwise
local function execute(target, ctx)
  if target.type ~= "name" then
    -- it's an ip address (v4 or v6), so nothing we can do...
    target.ip = target.host
    target.port = target.port or 80 -- TODO: remove this fallback value
    target.hostname = target.host
    return true
  end

  -- when tries == 0,
  --   it runs before the `balancer` context (in the `access` context),
  -- when tries >= 2,
  --   then it performs a retry in the `balancer` context
  local dns_cache_only = target.try_count ~= 0
  local balancer, upstream, hash_value

  if dns_cache_only then
    -- retry, so balancer is already set if there was one
    balancer = target.balancer

  else
    -- first try, so try and find a matching balancer/upstream object
    balancer, upstream = get_balancer(target)
    if balancer == nil then -- `false` means no balancer, `nil` is error
      return nil, upstream, 500
    end

    if balancer then
      if not ctx then
        ctx = ngx.ctx
      end

      -- store for retries
      target.balancer = balancer

      -- calculate hash-value
      -- only add it if it doesn't exist, in case a plugin inserted one
      hash_value = target.hash_value
      if not hash_value then
        hash_value = get_value_to_hash(upstream, ctx)
        target.hash_value = hash_value
      end

      if ctx and ctx.service and not ctx.service.client_certificate then
        -- service level client_certificate is not set
        local cert, res, err
        local client_certificate = upstream.client_certificate

        -- does the upstream object contains a client certificate?
        if client_certificate then
          cert, err = get_certificate(client_certificate)
          if not cert then
            log(ERR, "unable to fetch upstream client TLS certificate ",
                     client_certificate.id, ": ", err)
            return
          end

          res, err = kong.service.set_tls_cert_key(cert.cert, cert.key)
          if not res then
            log(ERR, "unable to apply upstream client TLS certificate ",
                     client_certificate.id, ": ", err)
          end
        end
      end
    end
  end

  local ip, port, hostname, handle
  if balancer then
    -- have to invoke the ring-balancer
    local hstate = run_hook("balancer:get_peer:pre", target.host)
    ip, port, hostname, handle = balancer:getPeer(dns_cache_only,
                                          target.balancer_handle,
                                          hash_value)
    run_hook("balancer:get_peer:post", hstate)
    if not ip and
      (port == "No peers are available" or port == "Balancer is unhealthy") then
      return nil, "failure to get a peer from the ring-balancer", 503
    end
    hostname = hostname or ip
    target.hash_value = hash_value
    target.balancer_handle = handle

  else
    -- have to do a regular DNS lookup
    local try_list
    local hstate = run_hook("balancer:to_ip:pre", target.host)
    ip, port, try_list = toip(target.host, target.port, dns_cache_only)
    run_hook("balancer:to_ip:post", hstate)
    hostname = target.host
    if not ip then
      log(ERR, "DNS resolution failed: ", port, ". Tried: ", tostring(try_list))
      if port == "dns server error: 3 name error" or
         port == "dns client error: 101 empty record received" then
        return nil, "name resolution failed", 503
      end
    end
  end

  if not ip then
    return nil, port, 500
  end

  target.ip = ip
  target.port = port
  if upstream and upstream.host_header ~= nil then
    target.hostname = upstream.host_header
  else
    target.hostname = hostname
  end
  return true
end


--------------------------------------------------------------------------------
-- Update health status and broadcast to workers
-- @param upstream a table with upstream data: must have `name` and `id`
-- @param hostname target hostname
-- @param ip target entry. if nil updates all entries
-- @param port target port
-- @param is_healthy boolean: true if healthy, false if unhealthy
-- @return true if posting event was successful, nil+error otherwise
local function post_health(upstream, hostname, ip, port, is_healthy)

  local balancer = balancers[upstream.id]
  if not balancer then
    return nil, "Upstream " .. tostring(upstream.name) .. " has no balancer"
  end

  local healthchecker = healthcheckers[balancer]
  if not healthchecker then
    return nil, "no healthchecker found for " .. tostring(upstream.name)
  end

  local ok, err
  if ip then
    ok, err = healthchecker:set_target_status(ip, port, hostname, is_healthy)
  else
    ok, err = healthchecker:set_all_target_statuses_for_hostname(hostname, port, is_healthy)
  end

  -- adjust API because the healthchecker always returns a second argument
  if ok then
    err = nil
  end

  return ok, err
end


--==============================================================================
-- Health check API
--==============================================================================


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
local function subscribe_to_healthcheck_events(callback)
  healthcheck_subscribers[#healthcheck_subscribers + 1] = callback
end


--------------------------------------------------------------------------------
-- Unsubscribe from events produced by health checkers.
-- @param callback Function that was added as the callback.
-- Note that this must be the same closure used for subscribing.
local function unsubscribe_from_healthcheck_events(callback)
  for i, c in ipairs(healthcheck_subscribers) do
    if c == callback then
      table.remove(healthcheck_subscribers, i)
      return
    end
  end
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


--------------------------------------------------------------------------------
-- Get healthcheck information for an upstream.
-- @param upstream_id the id of the upstream.
-- @return one of three possible returns:
-- * if healthchecks are enabled, a table mapping keys ("ip:port") to booleans;
-- * if healthchecks are disabled, nil;
-- * in case of errors, nil and an error message.
local function get_upstream_health(upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local using_hc = is_upstream_using_healthcheck(upstream)

  local balancer = balancers[upstream_id]
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker
  if using_hc then
    healthchecker = healthcheckers[balancer]
    if not healthchecker then
      return nil, "healthchecker not found"
    end
  end

  local health_info = {}
  local hosts = balancer.hosts
  for _, host in ipairs(hosts) do
    local key = host.hostname .. ":" .. host.port
    health_info[key] = host:getStatus()
    for _, address in ipairs(health_info[key].addresses) do
      if using_hc then
        address.health = address.healthy and "HEALTHY" or "UNHEALTHY"
      else
        address.health = "HEALTHCHECKS_OFF"
      end
      address.healthy = nil
    end
  end

  return health_info
end


local function set_host_header(balancer_data)
  if balancer_data.preserve_host == true then
    return true
  end

  -- set the upstream host header if not `preserve_host`
  local upstream_host = var.upstream_host
  local orig_upstream_host = upstream_host
  local phase = get_phase()


  if phase == "balancer" then
    upstream_host = balancer_data.hostname

    local upstream_scheme = var.upstream_scheme
    if upstream_scheme == "http"  and balancer_data.port ~= 80 or
       upstream_scheme == "https" and balancer_data.port ~= 443 or
       upstream_scheme == "grpc"  and balancer_data.port ~= 80 or
       upstream_scheme == "grpcs" and balancer_data.port ~= 443
    then
      upstream_host = upstream_host .. ":" .. balancer_data.port
    end

    if upstream_host ~= orig_upstream_host then
      var.upstream_host = upstream_host

      if phase == "balancer" then
        return recreate_request()
      end
    end

  end

  return true
end


--------------------------------------------------------------------------------
-- Get healthcheck information for a balancer.
-- @param upstream_id the id of the upstream.
-- @return table with balancer health info
local function get_balancer_health(upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local balancer = balancers[upstream_id]
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker
  local balancer_status
  local health = "HEALTHCHECKS_OFF"
  if is_upstream_using_healthcheck(upstream) then
    healthchecker = healthcheckers[balancer]
    if not healthchecker then
      return nil, "healthchecker not found"
    end

    balancer_status = balancer:getStatus()
    health = balancer_status.healthy and "HEALTHY" or "UNHEALTHY"
  end

  return {
    health = health,
    id = upstream_id,
    details = balancer_status,
  }
end


local function stop_healthcheckers()
  local upstreams = get_all_upstreams()
  for _, id in pairs(upstreams) do
    local balancer = balancers[id]
    if balancer then
      stop_healthchecker(balancer)
    end

    set_balancer(id, nil)
  end
end


--------------------------------------------------------------------------------
-- for unit-testing purposes only
local function _get_healthchecker(balancer)
  return healthcheckers[balancer]
end


return {
  init = init,
  execute = execute,
  on_target_event = on_target_event,
  on_upstream_event = on_upstream_event,
  get_upstream_by_name = get_upstream_by_name,
  get_all_upstreams = get_all_upstreams,
  post_health = post_health,
  subscribe_to_healthcheck_events = subscribe_to_healthcheck_events,
  unsubscribe_from_healthcheck_events = unsubscribe_from_healthcheck_events,
  get_upstream_health = get_upstream_health,
  get_upstream_by_id = get_upstream_by_id,
  get_balancer_health = get_balancer_health,
  stop_healthcheckers = stop_healthcheckers,
  set_host_header = set_host_header,

  -- ones below are exported for test purposes only
  _create_balancer = create_balancer,
  _get_balancer = get_balancer,
  _get_healthchecker = _get_healthchecker,
  _load_upstreams_dict_into_memory = _load_upstreams_dict_into_memory,
  _load_upstream_into_memory = _load_upstream_into_memory,
  _load_targets_into_memory = _load_targets_into_memory,
  _get_value_to_hash = get_value_to_hash,
}
