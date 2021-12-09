local pl_tablex = require "pl.tablex"
local utils = require "kong.tools.utils"
local hooks = require "kong.hooks"
local get_certificate = require("kong.runloop.certificate").get_certificate
local recreate_request = require("ngx.balancer").recreate_request

local healthcheckers = require "kong.runloop.balancer.healthcheckers"
local balancers = require "kong.runloop.balancer.balancers"
local upstreams = require "kong.runloop.balancer.upstreams"
local targets = require "kong.runloop.balancer.targets"


-- due to startup/require order, cannot use the ones from 'kong' here
local dns_client = require "kong.resty.dns.client"


local toip = dns_client.toip
local sub = string.sub
local ngx = ngx
local log = ngx.log
local null = ngx.null
local header = ngx.header
local type = type
local pairs = pairs
local tostring = tostring
local table = table
local table_concat = table.concat
local timer_at = ngx.timer.at
local run_hook = hooks.run_hook
local var = ngx.var


local CRIT = ngx.CRIT
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local EMPTY_T = pl_tablex.readonly {}


local set_authority
local set_upstream_cert_and_key
if ngx.config.subsystem ~= "stream" then
  set_authority = require("resty.kong.grpc").set_authority
  set_upstream_cert_and_key = require("resty.kong.tls").set_upstream_cert_and_key
end


-- Calculates hash-value.
-- Will only be called once per request, on first try.
-- @param upstream the upstream entity
-- @return integer value or nil if there is no hash to calculate
local function get_value_to_hash(upstream, ctx)
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


local function set_cookie(cookie)
  local prefix = cookie.key .. "="
  local length = #prefix
  local path = cookie.path or "/"
  local cookie_value = prefix .. cookie.value .. "; Path=" .. path .. "; Same-Site=Lax; HttpOnly"
  local cookie_header = header["Set-Cookie"]
  local header_type = type(cookie_header)
  if header_type == "table" then
    local found
    local count = #cookie_header
    for i = 1, count do
      if sub(cookie_header[i], 1, length) == prefix then
        cookie_header[i] = cookie_value
        found = true
        break
      end
    end

    if not found then
      cookie_header[count+1] = cookie_value
    end

  elseif header_type == "string" and sub(cookie_header, 1, length) ~= prefix then
    cookie_header = { cookie_header, cookie_value }

  else
    cookie_header = cookie_value
  end

  header["Set-Cookie"] = cookie_header
end


--==============================================================================
-- Initialize balancers
--==============================================================================



local function init()
  targets.init()
  upstreams.init()
  balancers.init()
  healthcheckers.init()

  if kong.configuration.worker_consistency == "strict" then
    balancers.create_balancers()
    return
  end

  local upstreams_dict, err = upstreams.get_all_upstreams()
  if err then
    log(CRIT, "failed loading list of upstreams: ", err)
    return
  end

  for _, id in pairs(upstreams_dict) do
    local upstream
    upstream, err = upstreams.get_upstream_by_id(id)
    if upstream == nil or err then
      log(WARN, "failed loading upstream ", id, ": ", err)
    end

    _, err = balancers.create_balancer(upstream)
    if err then
      log(CRIT, "failed creating balancer for upstream ", upstream.name, ": ", err)
    end

    local target
    target, err = targets.fetch_targets(upstream)
    if target == nil or err then
      log(WARN, "failed loading targets for upstream ", id, ": ", err)
    end
  end

  local _
  local frequency = kong.configuration.worker_state_update_frequency or 1
  _, err = timer_at(frequency, upstreams.update_balancer_state)
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
-- @balancer_data target the data structure as defined in `core.access.before` where
-- it is created.
-- @return true on success, nil+error message+status code otherwise
local function execute(balancer_data, ctx)
  if balancer_data.type ~= "name" then
    -- it's an ip address (v4 or v6), so nothing we can do...
    balancer_data.ip       = balancer_data.host
    balancer_data.port     = balancer_data.port or 80 -- TODO: remove this fallback value
    balancer_data.hostname = balancer_data.host
    return true
  end

  -- when tries == 0,
  --   it runs before the `balancer` context (in the `access` context),
  -- when tries >= 2,
  --   then it performs a retry in the `balancer` context
  local dns_cache_only = balancer_data.try_count ~= 0
  local balancer, upstream, hash_value

  if dns_cache_only then
    -- retry, so balancer is already set if there was one
    balancer = balancer_data.balancer

  else
    -- first try, so try and find a matching balancer/upstream object
    balancer, upstream = balancers.get_balancer(balancer_data)
    if balancer == nil then -- `false` means no balancer, `nil` is error
      return nil, upstream, 500
    end

    if balancer then
      if not ctx then
        ctx = ngx.ctx
      end

      -- store for retries
      balancer_data.balancer = balancer

      -- calculate hash-value
      -- only add it if it doesn't exist, in case a plugin inserted one
      hash_value = balancer_data.hash_value
      if not hash_value then
        hash_value = get_value_to_hash(upstream, ctx) or ""
        balancer_data.hash_value = hash_value
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

          res, err = set_upstream_cert_and_key(cert.cert, cert.key)
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
    local hstate = run_hook("balancer:get_peer:pre", balancer_data.host)
    ip, port, hostname, handle = balancer:getPeer(dns_cache_only,
                                          balancer_data.balancer_handle,
                                          hash_value)
    run_hook("balancer:get_peer:post", hstate)
    if not ip and
      (port == "No peers are available" or port == "Balancer is unhealthy")
    then
      return nil, "failure to get a peer from the ring-balancer", 503
    end
    hostname = hostname or ip
    balancer_data.hash_value = hash_value
    balancer_data.balancer_handle = handle

  else
    -- have to do a regular DNS lookup
    local try_list
    local hstate = run_hook("balancer:to_ip:pre", balancer_data.host)
    ip, port, try_list = toip(balancer_data.host, balancer_data.port, dns_cache_only)
    run_hook("balancer:to_ip:post", hstate)
    hostname = balancer_data.host
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

  balancer_data.ip   = ip
  balancer_data.port = port
  if upstream and upstream.host_header ~= nil then
    balancer_data.hostname = upstream.host_header
  else
    balancer_data.hostname = hostname
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

  local balancer = balancers.get_balancer_by_id(upstream.id)
  if not balancer then
    return nil, "Upstream " .. tostring(upstream.name) .. " has no balancer"
  end

  local healthchecker = balancer.healthchecker
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


local function set_host_header(balancer_data, upstream_scheme, upstream_host, is_balancer_phase)
  if balancer_data.preserve_host then
    return true
  end

  -- set the upstream host header if not `preserve_host`
  local new_upstream_host = balancer_data.hostname

  local port = balancer_data.port
  if (port ~= 80  and port ~= 443)
  or (port == 80  and upstream_scheme ~= "http"  and upstream_scheme ~= "grpc")
  or (port == 443 and upstream_scheme ~= "https" and upstream_scheme ~= "grpcs")
  then
    new_upstream_host = new_upstream_host .. ":" .. port
  end

  if new_upstream_host ~= upstream_host then
    -- the nginx grpc module does not offer a way to override the
    -- :authority pseudo-header; use our internal API to do so
    if upstream_scheme == "grpc" or upstream_scheme == "grpcs" then
      local ok, err = set_authority(new_upstream_host)
      if not ok then
        log(ERR, "failed to set :authority header: ", err)
      end
    end

    var.upstream_host = new_upstream_host

    if is_balancer_phase then
      return recreate_request()
    end
  end

  return true
end



return {
  init = init,
  execute = execute,
  on_target_event = targets.on_target_event,
  on_upstream_event = upstreams.on_upstream_event,
  get_upstream_by_name = upstreams.get_upstream_by_name,
  --get_all_upstreams = get_all_upstreams,
  post_health = post_health,
  subscribe_to_healthcheck_events = healthcheckers.subscribe_to_healthcheck_events,
  unsubscribe_from_healthcheck_events = healthcheckers.unsubscribe_from_healthcheck_events,
  get_upstream_health = healthcheckers.get_upstream_health,
  get_upstream_by_id = upstreams.get_upstream_by_id,
  get_balancer_health = healthcheckers.get_balancer_health,
  stop_healthcheckers = healthcheckers.stop_healthcheckers,
  set_host_header = set_host_header,
  set_cookie = set_cookie,

  -- ones below are exported for test purposes only
  --_create_balancer = create_balancer,
  --_get_balancer = get_balancer,
  --_get_healthchecker = _get_healthchecker,
  --_load_upstreams_dict_into_memory = _load_upstreams_dict_into_memory,
  --_load_upstream_into_memory = _load_upstream_into_memory,
  --_load_targets_into_memory = _load_targets_into_memory,
  --_get_value_to_hash = get_value_to_hash,
}
