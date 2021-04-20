local hooks = require "kong.hooks"
local get_certificate = require("kong.runloop.certificate").get_certificate

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
local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }

local upstreams = require "kong.runloop.balancer.upstreams"

local old_module = require "kong.runloop.balancer.old_balancer"
local algorithm  = 'round_robin'

local module_names = {
  round_robin = require "kong.runloop.balancer.round_robin",
}

local balancer_by_upstream_id = {}
local upstream_id_by_balancer = {}
local balancer_M = {}



------------------------------------------------------------------------------
-- The mutually-exclusive section used internally by the
-- 'create_balancer' operation.
-- @param upstream (table) A db.upstreams entity
-- @return The new balancer object, or nil+error
local function create_balancer_exclusive(upstream)
  local health_threshold = upstream.healthchecks and
                            upstream.healthchecks.threshold or nil

  local targets = assert(upstreams.fetch_targets(upstream))

  local balancer, err = module_names[upstream.algorithm].new({
    log_prefix = "upstream:" .. upstream.name,
    wheelSize = upstream.slots,  -- will be ignored by least-connections
    dns = dns_client,
    healthThreshold = health_threshold,
    hosts = targets,
  })
  if not balancer then
    return nil, "failed creating balancer:" .. err
  end

  upstream_id_by_balancer[balancer] = upstream.id

  local ok, err = create_healthchecker(balancer, upstream)
  if not ok then
    log(ERR, "[healthchecks] error creating health checker: ", err)
  end

  -- only make the new balancer available for other requests after it
  -- is fully set up.
  set_balancer(upstream.id, balancer)

  return balancer
end


local _creating_balancer = {}
local function create_balancer(upstream)
  if _creating_balancer[upstream.id] then
    local ok = wait(upstream.id)
    if not ok then
      return nil, "timeout waiting for balancer for " .. upstream.id
    end
    return balancers[upstream.id]
  end

  _creating_balancer[upstream.id] = true

  local balancer, err = create_balancer_exclusive(upstream)

  _creating_balancer[upstream.id] = nil

  return balancer, err
end


-- looks up a balancer for the target.
-- @param target the table with the target details
-- @return balancer if found, `false` if not found, or nil+error on error
local function get_balancer(target)
  local upstream, err = upstreams.get_upstream_by_name(target.host)
  if upstream == false then
    return false -- no upstream by this name
  end
  if err then
    return nil, err -- there was an error
  end

  local balancer = balancer_by_upstream_id[upstream.id]
  if not balancer then
    if no_create then
      return nil, "balancer not found"
    else
      log(ERR, "balancer not found for ", upstream.name, ", will create it")
      balancer = create_balancer(upstream)
      balancer_by_upstream_id[upstream.id] = balancer
      return balancer, upstream
    end
  end

  return balancer, upstream
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
function balancer_M.execute(target, ctx)
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
        hash_value = old_module._get_value_to_hash(upstream, ctx)
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


balancer_M.set_host_header = old_module.set_host_header

return setmetatable(balancer_M, {
  __index = function(t, k) error(string.format("%q unimplemented", k)) end,
})
