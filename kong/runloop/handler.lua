-- Kong runloop

local meta         = require "kong.meta"
local utils        = require "kong.tools.utils"
local Router       = require "kong.router"
local balancer     = require "kong.runloop.balancer"
local reports      = require "kong.reports"
local constants    = require "kong.constants"
local certificate  = require "kong.runloop.certificate"
local concurrency  = require "kong.concurrency"
local workspaces   = require "kong.workspaces"
local lrucache     = require "resty.lrucache"
local marshall     = require "kong.cache.marshall"


local PluginsIterator = require "kong.runloop.plugins_iterator"
local instrumentation = require "kong.tracing.instrumentation"


local kong              = kong
local type              = type
local ipairs            = ipairs
local tostring          = tostring
local tonumber          = tonumber
local setmetatable      = setmetatable
local max               = math.max
local min               = math.min
local ceil              = math.ceil
local sub               = string.sub
local byte              = string.byte
local gsub              = string.gsub
local find              = string.find
local lower             = string.lower
local fmt               = string.format
local ngx               = ngx
local var               = ngx.var
local log               = ngx.log
local exit              = ngx.exit
local exec              = ngx.exec
local header            = ngx.header
local timer_at          = ngx.timer.at
local subsystem         = ngx.config.subsystem
local clear_header      = ngx.req.clear_header
local http_version      = ngx.req.http_version
local unpack            = unpack
local escape            = require("kong.tools.uri").escape


local is_http_module   = subsystem == "http"
local is_stream_module = subsystem == "stream"


local DEFAULT_MATCH_LRUCACHE_SIZE = Router.DEFAULT_MATCH_LRUCACHE_SIZE


local ROUTER_CACHE_SIZE = DEFAULT_MATCH_LRUCACHE_SIZE
local ROUTER_CACHE = lrucache.new(ROUTER_CACHE_SIZE)
local ROUTER_CACHE_NEG = lrucache.new(ROUTER_CACHE_SIZE)


local NOOP = function() end


local ERR   = ngx.ERR
local CRIT  = ngx.CRIT
local NOTICE = ngx.NOTICE
local WARN  = ngx.WARN
local DEBUG = ngx.DEBUG
local COMMA = byte(",")
local SPACE = byte(" ")
local QUESTION_MARK = byte("?")
local ARRAY_MT = require("cjson.safe").array_mt


local HOST_PORTS = {}


local SUBSYSTEMS = constants.PROTOCOLS_WITH_SUBSYSTEM
local CLEAR_HEALTH_STATUS_DELAY = constants.CLEAR_HEALTH_STATUS_DELAY
local TTL_ZERO = { ttl = 0 }


local ROUTER
local ROUTER_VERSION
local ROUTER_SYNC_OPTS

local PLUGINS_ITERATOR
local PLUGINS_ITERATOR_SYNC_OPTS

local RECONFIGURE_OPTS
local GLOBAL_QUERY_OPTS = { workspace = ngx.null, show_ws_id = true }

local SERVER_HEADER = meta._SERVER_TOKENS


local STREAM_TLS_TERMINATE_SOCK
local STREAM_TLS_PASSTHROUGH_SOCK


local set_upstream_cert_and_key
local set_upstream_ssl_verify
local set_upstream_ssl_verify_depth
local set_upstream_ssl_trusted_store
local set_authority
if is_http_module then
  local tls = require("resty.kong.tls")
  set_upstream_cert_and_key = tls.set_upstream_cert_and_key
  set_upstream_ssl_verify = tls.set_upstream_ssl_verify
  set_upstream_ssl_verify_depth = tls.set_upstream_ssl_verify_depth
  set_upstream_ssl_trusted_store = tls.set_upstream_ssl_trusted_store
  set_authority = require("resty.kong.grpc").set_authority
end


local disable_proxy_ssl
if is_stream_module then
  disable_proxy_ssl = require("resty.kong.tls").disable_proxy_ssl
end


local update_lua_mem
do
  local pid = ngx.worker.pid
  local ngx_time = ngx.time
  local kong_shm = ngx.shared.kong

  local LUA_MEM_SAMPLE_RATE = 10 -- seconds
  local last = ngx_time()

  local collectgarbage = collectgarbage

  update_lua_mem = function(force)
    local time = ngx_time()

    if force or time - last >= LUA_MEM_SAMPLE_RATE then
      local count = collectgarbage("count")

      local ok, err = kong_shm:safe_set("kong:mem:" .. pid(), count)
      if not ok then
        log(ERR, "could not record Lua VM allocated memory: ", err)
      end

      last = time
    end
  end
end


local function csv_iterator(s, b)
  if b == -1 then
    return
  end

  local e = find(s, ",", b, true)
  local v
  local l
  if e then
    if e == b then
      return csv_iterator(s, b + 1) -- empty string
    end
    v = sub(s, b, e - 1)
    l = e - b
    b = e + 1

  else
    if b > 1 then
      v = sub(s, b)
    else
      v = s
    end

    l = #v
    b = -1 -- end iteration
  end

  if l == 1 and (byte(v) == SPACE or byte(v) == COMMA) then
    return csv_iterator(s, b)
  end

  if byte(v, 1, 1) == SPACE then
    v = gsub(v, "^%s+", "")
  end

  if byte(v, -1) == SPACE then
    v = gsub(v, "%s+$", "")
  end

  if v == "" then
    return csv_iterator(s, b)
  end

  return b, v
end


local function csv(s)
  if type(s) ~= "string" or s == "" then
    return csv_iterator, s, -1
  end

  s = lower(s)
  if s == "close" or s == "upgrade" or s == "keep-alive" then
    return csv_iterator, s, -1
  end

  return csv_iterator, s, 1
end


-- @param name "router" or "plugins_iterator"
-- @param callback A function that will update the router or plugins_iterator
-- @param version target version
-- @param opts concurrency options, including lock name and timeout.
-- @returns true if callback was either successfully executed synchronously,
-- enqueued via async timer, or not needed (because current_version == target).
-- nil otherwise (callback was neither called successfully nor enqueued,
-- or an error happened).
-- @returns error message as a second return value in case of failure/error
local function rebuild(name, callback, version, opts)
  local current_version, err = kong.core_cache:get(name .. ":version", TTL_ZERO, utils.uuid)
  if err then
    return nil, "failed to retrieve " .. name .. " version: " .. err
  end

  if current_version == version then
    return true
  end

  return concurrency.with_coroutine_mutex(opts, callback)
end


-- Given a protocol, return the subsystem that handles it
local function should_process_route(route)
  for _, protocol in ipairs(route.protocols) do
    if SUBSYSTEMS[protocol] == subsystem then
      return true
    end
  end

  return false
end


local function load_service_from_db(service_pk)
  local service, err = kong.db.services:select(service_pk, GLOBAL_QUERY_OPTS)
  if service == nil then
    -- the third value means "do not cache"
    return nil, err, -1
  end
  return service
end


local function build_services_init_cache(db)
  local services_init_cache = {}
  local services = db.services
  local page_size
  if services.pagination then
    page_size = services.pagination.max_page_size
  end

  for service, err in services:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, err
    end

    services_init_cache[service.id] = service
  end

  return services_init_cache
end


local function get_service_for_route(db, route, services_init_cache)
  local service_pk = route.service
  if not service_pk then
    return nil
  end

  local id = service_pk.id
  local service = services_init_cache[id]
  if service then
    return service
  end

  local err

  -- kong.core_cache is available, not in init phase
  if kong.core_cache and db.strategy ~= "off" then
    local cache_key = db.services:cache_key(service_pk.id, nil, nil, nil, nil,
                                            route.ws_id)
    service, err = kong.core_cache:get(cache_key, TTL_ZERO,
                                       load_service_from_db, service_pk)

  else -- dbless or init phase, kong.core_cache not needed/available

    -- A new service/route has been inserted while the initial route
    -- was being created, on init (perhaps by a different Kong node).
    -- Load the service individually and update services_init_cache with it
    service, err = load_service_from_db(service_pk)
    services_init_cache[id] = service
  end

  if err then
    return nil, "error raised while finding service for route (" .. route.id .. "): " ..
                err

  elseif not service then
    return nil, "could not find service for route (" .. route.id .. ")"
  end


  -- TODO: this should not be needed as the schema should check it already
  if SUBSYSTEMS[service.protocol] ~= subsystem then
    log(WARN, "service with protocol '", service.protocol,
              "' cannot be used with '", subsystem, "' subsystem")

    return nil
  end

  return service
end


local function get_router_version()
  return kong.core_cache:get("router:version", TTL_ZERO, utils.uuid)
end


local function new_router(version)
  local db = kong.db
  local routes, i = {}, 0

  local err
  -- The router is initially created on init phase, where kong.core_cache is
  -- still not ready. For those cases, use a plain Lua table as a cache
  -- instead
  local services_init_cache = {}
  if not kong.core_cache and db.strategy ~= "off" then
    services_init_cache, err = build_services_init_cache(db)
    if err then
      services_init_cache = {}
      log(WARN, "could not build services init cache: ", err)
    end
  end

  local detect_changes = db.strategy ~= "off" and kong.core_cache
  local counter = 0
  local page_size = db.routes.pagination.max_page_size
  for route, err in db.routes:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, "could not load routes: " .. err
    end

    if detect_changes then
      if counter > 0 and counter % page_size == 0 then
        local new_version, err = get_router_version()
        if err then
          return nil, "failed to retrieve router version: " .. err
        end

        if new_version ~= version then
          return nil, "router was changed while rebuilding it"
        end
      end
      counter = counter + 1
    end

    if should_process_route(route) then
      local service, err = get_service_for_route(db, route, services_init_cache)
      if err then
        return nil, err
      end

      -- routes with no services are added to router
      -- but routes where the services.enabled == false are not put in router
      if service == nil or service.enabled ~= false then
        local r = {
          route   = route,
          service = service,
        }

        i = i + 1
        routes[i] = r
      end
    end
  end

  local n = DEFAULT_MATCH_LRUCACHE_SIZE
  local cache_size = min(ceil(max(i / n, 1)) * n, n * 20)

  if cache_size ~= ROUTER_CACHE_SIZE then
    ROUTER_CACHE = lrucache.new(cache_size)
    ROUTER_CACHE_SIZE = cache_size
  end

  local new_router, err = Router.new(routes, ROUTER_CACHE, ROUTER_CACHE_NEG, ROUTER)
  if not new_router then
    return nil, "could not create router: " .. err
  end

  return new_router
end


local function build_router(version)
  local router, err = new_router(version)
  if not router then
    return nil, err
  end

  ROUTER = router

  if version then
    ROUTER_VERSION = version
  end

  ROUTER_CACHE:flush_all()
  ROUTER_CACHE_NEG:flush_all()

  return true
end


local function update_router()
  -- we might not need to rebuild the router (if we were not
  -- the first request in this process to enter this code path)
  -- check again and rebuild only if necessary
  local version, err = get_router_version()
  if err then
    return nil, "failed to retrieve router version: " .. err
  end

  if version == ROUTER_VERSION then
    return true
  end

  local ok, err = build_router(version)
  if not ok then
    return nil, --[[ 'err' fully formatted ]] err
  end

  return true
end


local function rebuild_router(opts)
  return rebuild("router", update_router, ROUTER_VERSION, opts)
end


local function get_updated_router()
  if kong.db.strategy ~= "off" and kong.configuration.worker_consistency == "strict" then
    local ok, err = rebuild_router(ROUTER_SYNC_OPTS)
    if not ok then
      -- If an error happens while updating, log it and return non-updated
      -- version.
      log(ERR, "could not rebuild router: ", err, " (stale router will be used)")
    end
  end
  return ROUTER
end


-- for tests only
local function _set_update_router(f)
  update_router = f
end

local function _set_build_router(f)
  build_router = f
end

local function _set_router(r)
  ROUTER = r
end

local function _set_router_version(v)
  ROUTER_VERSION = v
end


local new_plugins_iterator = PluginsIterator.new


local function build_plugins_iterator(version)
  local plugins_iterator, err = new_plugins_iterator(version)
  if not plugins_iterator then
    return nil, err
  end
  PLUGINS_ITERATOR = plugins_iterator
  return true
end


local function update_plugins_iterator()
  local version, err = kong.core_cache:get("plugins_iterator:version", TTL_ZERO, utils.uuid)
  if err then
    return nil, "failed to retrieve plugins iterator version: " .. err
  end

  if PLUGINS_ITERATOR and PLUGINS_ITERATOR.version == version then
    return true
  end

  local ok, err = build_plugins_iterator(version)
  if not ok then
    return nil, --[[ 'err' fully formatted ]] err
  end

  return true
end


local function rebuild_plugins_iterator(opts)
  local plugins_iterator_version = PLUGINS_ITERATOR and PLUGINS_ITERATOR.version
  return rebuild("plugins_iterator", update_plugins_iterator, plugins_iterator_version, opts)
end


local function get_updated_plugins_iterator()
  if kong.db.strategy ~= "off" and kong.configuration.worker_consistency == "strict" then
    local ok, err = rebuild_plugins_iterator(PLUGINS_ITERATOR_SYNC_OPTS)
    if not ok then
      -- If an error happens while updating, log it and return non-updated
      -- version
      log(ERR, "could not rebuild plugins iterator: ", err,
               " (stale plugins iterator will be used)")
    end
  end
  return PLUGINS_ITERATOR
end


local function get_plugins_iterator()
  return PLUGINS_ITERATOR
end


-- for tests only
local function _set_update_plugins_iterator(f)
  update_plugins_iterator = f
end


local function register_balancer_events(core_cache, worker_events, cluster_events)
  -- target updates
  -- worker_events local handler: event received from DAO
  worker_events.register(function(data)
    local operation = data.operation
    local target = data.entity
    -- => to worker_events node handler
    local ok, err = worker_events.post("balancer", "targets", {
        operation = operation,
        entity = target,
      })
    if not ok then
      log(ERR, "failed broadcasting target ",
        operation, " to workers: ", err)
    end
    -- => to cluster_events handler
    local key = fmt("%s:%s", operation, target.upstream.id)
    ok, err = cluster_events:broadcast("balancer:targets", key)
    if not ok then
      log(ERR, "failed broadcasting target ", operation, " to cluster: ", err)
    end
  end, "crud", "targets")


  -- worker_events node handler
  worker_events.register(function(data)
    local operation = data.operation
    local target = data.entity

    -- => to balancer update
    balancer.on_target_event(operation, target)
  end, "balancer", "targets")


  -- cluster_events handler
  cluster_events:subscribe("balancer:targets", function(data)
    local operation, key = unpack(utils.split(data, ":"))
    local entity
    if key ~= "all" then
      entity = {
        upstream = { id = key },
      }
    else
      entity = "all"
    end
    -- => to worker_events node handler
    local ok, err = worker_events.post("balancer", "targets", {
        operation = operation,
        entity = entity
      })
    if not ok then
      log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
    end
  end)


  -- manual health updates
  cluster_events:subscribe("balancer:post_health", function(data)
    local pattern = "([^|]+)|([^|]*)|([^|]+)|([^|]+)|([^|]+)|(.*)"
    local hostname, ip, port, health, id, name = data:match(pattern)
    port = tonumber(port)
    local upstream = { id = id, name = name }
    if ip == "" then
      ip = nil
    end
    local _, err = balancer.post_health(upstream, hostname, ip, port, health == "1")
    if err then
      log(ERR, "failed posting health of ", name, " to workers: ", err)
    end
  end)


  -- upstream updates
  -- worker_events local handler: event received from DAO
  worker_events.register(function(data)
    local operation = data.operation
    local upstream = data.entity
    local ws_id = workspaces.get_workspace_id()
    if not upstream.ws_id then
      log(DEBUG, "Event crud ", operation, " for upstream ", upstream.id,
          " received without ws_id, adding.")
      upstream.ws_id = ws_id
    end
    -- => to worker_events node handler
    local ok, err = worker_events.post("balancer", "upstreams", {
        operation = operation,
        entity = upstream,
      })
    if not ok then
      log(ERR, "failed broadcasting upstream ",
        operation, " to workers: ", err)
    end
    -- => to cluster_events handler
    local key = fmt("%s:%s:%s:%s", operation, data.entity.ws_id, upstream.id, upstream.name)
    local ok, err = cluster_events:broadcast("balancer:upstreams", key)
    if not ok then
      log(ERR, "failed broadcasting upstream ", operation, " to cluster: ", err)
    end
  end, "crud", "upstreams")


  -- worker_events node handler
  worker_events.register(function(data)
    local operation = data.operation
    local upstream = data.entity

    if not upstream.ws_id then
      log(CRIT, "Operation ", operation, " for upstream ", upstream.id,
          " received without workspace, discarding.")
      return
    end

    core_cache:invalidate_local("balancer:upstreams")
    core_cache:invalidate_local("balancer:upstreams:" .. upstream.id)

    -- => to balancer update
    balancer.on_upstream_event(operation, upstream)
  end, "balancer", "upstreams")


  cluster_events:subscribe("balancer:upstreams", function(data)
    local operation, ws_id, id, name = unpack(utils.split(data, ":"))
    local entity = {
      id = id,
      name = name,
      ws_id = ws_id,
    }
    -- => to worker_events node handler
    local ok, err = worker_events.post("balancer", "upstreams", {
        operation = operation,
        entity = entity
      })
    if not ok then
      log(ERR, "failed broadcasting upstream ", operation, " to workers: ", err)
    end
  end)
end


local function _register_balancer_events(f)
  register_balancer_events = f
end


local function register_events()
  -- initialize local local_events hooks
  local db             = kong.db
  local core_cache     = kong.core_cache
  local worker_events  = kong.worker_events
  local cluster_events = kong.cluster_events

  if db.strategy == "off" then

    -- declarative config updates

    local current_router_hash
    local current_plugins_hash
    local current_balancer_hash

    local exiting = ngx.worker.exiting
    local function is_exiting()
      if not exiting() then
        return false
      end
      log(NOTICE, "declarative reconfigure canceled: process exiting")
      return true
    end

    worker_events.register(function(data)
      if is_exiting() then
        return true
      end

      local default_ws
      local router_hash
      local plugins_hash
      local balancer_hash

      if type(data) == "table" then
        default_ws = data[1]
        router_hash = data[2]
        plugins_hash = data[3]
        balancer_hash = data[4]
      end

      local ok, err = concurrency.with_coroutine_mutex(RECONFIGURE_OPTS, function()
        -- below you are encouraged to yield for cooperative threading

        local rebuild_balancer = balancer_hash == nil or balancer_hash ~= current_balancer_hash
        if rebuild_balancer then
          balancer.stop_healthcheckers(CLEAR_HEALTH_STATUS_DELAY)
        end

        kong.default_workspace = default_ws
        ngx.ctx.workspace = default_ws

        local router, err
        if router_hash == nil or router_hash ~= current_router_hash then
          router, err = new_router()
          if not router then
            return nil, err
          end
        end

        local plugins_iterator
        if plugins_hash == nil or plugins_hash ~= current_plugins_hash then
          plugins_iterator, err = new_plugins_iterator()
          if not plugins_iterator then
            return nil, err
          end
        end

        -- below you are not supposed to yield and this should be fast and atomic

        -- TODO: we should perhaps only purge the configuration related cache.
        kong.core_cache:purge()
        kong.cache:purge()

        if router then
          ROUTER = router
          ROUTER_CACHE:flush_all()
          ROUTER_CACHE_NEG:flush_all()
          current_router_hash = router_hash
        end

        if plugins_iterator then
          PLUGINS_ITERATOR = plugins_iterator
          current_plugins_hash = plugins_hash
        end

        if rebuild_balancer then
          -- TODO: balancer is a big blob of global state and you cannot easily
          --       initialize new balancer and then atomically flip it.
          balancer.init()
          current_balancer_hash = balancer_hash
        end

        return true
      end)

      if not ok then
        log(ERR, "reconfigure failed: ", err)
      end
    end, "declarative", "reconfigure")

    return
  end

  -- events dispatcher

  worker_events.register(function(data)
    if not data.schema then
      log(ERR, "[events] missing schema in crud subscriber")
      return
    end

    if not data.entity then
      log(ERR, "[events] missing entity in crud subscriber")
      return
    end

    -- invalidate this entity anywhere it is cached if it has a
    -- caching key

    local cache_key = db[data.schema.name]:cache_key(data.entity)
    local cache_obj = kong[constants.ENTITY_CACHE_STORE[data.schema.name]]

    if cache_key then
      cache_obj:invalidate(cache_key)
    end

    -- if we had an update, but the cache key was part of what was updated,
    -- we need to invalidate the previous entity as well

    if data.old_entity then
      local old_cache_key = db[data.schema.name]:cache_key(data.old_entity)
      if old_cache_key and cache_key ~= old_cache_key then
        cache_obj:invalidate(old_cache_key)
      end
    end

    if not data.operation then
      log(ERR, "[events] missing operation in crud subscriber")
      return
    end

    -- public worker events propagation

    local entity_channel           = data.schema.table or data.schema.name
    local entity_operation_channel = fmt("%s:%s", entity_channel,
      data.operation)

    -- crud:routes
    local ok, err = worker_events.post_local("crud", entity_channel, data)
    if not ok then
      log(ERR, "[events] could not broadcast crud event: ", err)
      return
    end

    -- crud:routes:create
    ok, err = worker_events.post_local("crud", entity_operation_channel, data)
    if not ok then
      log(ERR, "[events] could not broadcast crud event: ", err)
      return
    end
  end, "dao:crud")


  -- local events (same worker)


  worker_events.register(function()
    log(DEBUG, "[events] Route updated, invalidating router")
    core_cache:invalidate("router:version")
  end, "crud", "routes")


  worker_events.register(function(data)
    if data.operation ~= "create" and
      data.operation ~= "delete"
      then
      -- no need to rebuild the router if we just added a Service
      -- since no Route is pointing to that Service yet.
      -- ditto for deletion: if a Service if being deleted, it is
      -- only allowed because no Route is pointing to it anymore.
      log(DEBUG, "[events] Service updated, invalidating router")
      core_cache:invalidate("router:version")
    end
  end, "crud", "services")


  worker_events.register(function(data)
    log(DEBUG, "[events] Plugin updated, invalidating plugins iterator")
    core_cache:invalidate("plugins_iterator:version")
  end, "crud", "plugins")


  -- SSL certs / SNIs invalidations


  worker_events.register(function(data)
    log(DEBUG, "[events] SNI updated, invalidating cached certificates")
    local sni = data.old_entity or data.entity
    local sni_wild_pref, sni_wild_suf = certificate.produce_wild_snis(sni.name)
    core_cache:invalidate("snis:" .. sni.name)

    if sni_wild_pref then
      core_cache:invalidate("snis:" .. sni_wild_pref)
    end

    if sni_wild_suf then
      core_cache:invalidate("snis:" .. sni_wild_suf)
    end
  end, "crud", "snis")

  register_balancer_events(core_cache, worker_events, cluster_events)
end


local balancer_prepare
do
  local get_certificate = certificate.get_certificate
  local get_ca_certificate_store = certificate.get_ca_certificate_store

  local function sleep_once_for_balancer_init()
    ngx.sleep(0)
    sleep_once_for_balancer_init = NOOP
  end

  function balancer_prepare(ctx, scheme, host_type, host, port,
                            service, route)

    sleep_once_for_balancer_init()

    local retries
    local connect_timeout
    local send_timeout
    local read_timeout

    if service then
      retries         = service.retries
      connect_timeout = service.connect_timeout
      send_timeout    = service.write_timeout
      read_timeout    = service.read_timeout
    end

    local balancer_data = {
      scheme             = scheme,    -- scheme for balancer: http, https
      type               = host_type, -- type of 'host': ipv4, ipv6, name
      host               = host,      -- target host per `service` entity
      port               = port,      -- final target port
      try_count          = 0,         -- retry counter

      retries            = retries         or 5,
      connect_timeout    = connect_timeout or 60000,
      send_timeout       = send_timeout    or 60000,
      read_timeout       = read_timeout    or 60000,

      -- stores info per try, metatable is needed for basic log serializer
      -- see #6390
      tries              = setmetatable({}, ARRAY_MT),
      -- ip              = nil,       -- final target IP address
      -- balancer        = nil,       -- the balancer object, if any
      -- hostname        = nil,       -- hostname of the final target IP
      -- hash_cookie     = nil,       -- if Upstream sets hash_on_cookie
      -- balancer_handle = nil,       -- balancer handle for the current connection
    }

    ctx.service          = service
    ctx.route            = route
    ctx.balancer_data    = balancer_data

    if is_http_module and service then
      local res, err
      local client_certificate = service.client_certificate

      if client_certificate then
        local cert, err = get_certificate(client_certificate)
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

      local tls_verify = service.tls_verify
      if tls_verify then
        res, err = set_upstream_ssl_verify(tls_verify)
        if not res then
          log(CRIT, "unable to set upstream TLS verification to: ",
                   tls_verify, ", err: ", err)
        end
      end

      local tls_verify_depth = service.tls_verify_depth
      if tls_verify_depth then
        res, err = set_upstream_ssl_verify_depth(tls_verify_depth)
        if not res then
          log(CRIT, "unable to set upstream TLS verification to: ",
                   tls_verify, ", err: ", err)
          -- in case verify can not be enabled, request can no longer be
          -- processed without potentially compromising security
          return kong.response.exit(500)
        end
      end

      local ca_certificates = service.ca_certificates
      if ca_certificates then
        res, err = get_ca_certificate_store(ca_certificates)
        if not res then
          log(CRIT, "unable to get upstream TLS CA store, err: ", err)

        else
          res, err = set_upstream_ssl_trusted_store(res)
          if not res then
            log(CRIT, "unable to set upstream TLS CA store, err: ", err)
          end
        end
      end
    end

    if is_stream_module and scheme == "tcp" then
      local res, err = disable_proxy_ssl()
      if not res then
        log(ERR, "unable to disable upstream TLS handshake: ", err)
      end
    end
  end
end


local function balancer_execute(ctx)
  local balancer_data = ctx.balancer_data
  local ok, err, errcode = balancer.execute(balancer_data, ctx)
  if not ok and errcode == 500 then
    err = "failed the initial dns/balancer resolve for '" ..
          balancer_data.host .. "' with: " .. tostring(err)
  end
  return ok, err, errcode
end


local function set_init_versions_in_cache()
  -- because of worker events, kong.cache can not be initialized in `init` phase
  -- therefore, we need to use the shdict API directly to set the initial value
  assert(kong.configuration.role ~= "control_plane")
  assert(ngx.get_phase() == "init")
  local core_cache_shm = ngx.shared["kong_core_db_cache"]

  -- ttl = forever is okay as "*:versions" keys are always manually invalidated
  local marshalled_value = marshall("init", 0, 0)

  -- see kong.cache.safe_set function
  local ok, err = core_cache_shm:safe_set("kong_core_db_cacherouter:version", marshalled_value)
  if not ok then
    return nil, "failed to set initial router version in cache: " .. tostring(err)
  end

  ok, err = core_cache_shm:safe_set("kong_core_db_cacheplugins_iterator:version", marshalled_value)
  if not ok then
    return nil, "failed to set initial plugins iterator version in cache: " .. tostring(err)
  end

  return true
end


-- in the table below the `before` and `after` is to indicate when they run:
-- before or after the plugins
return {
  build_router = build_router,
  update_router = update_router,
  build_plugins_iterator = build_plugins_iterator,
  update_plugins_iterator = update_plugins_iterator,
  get_plugins_iterator = get_plugins_iterator,
  get_updated_plugins_iterator = get_updated_plugins_iterator,
  set_init_versions_in_cache = set_init_versions_in_cache,

  -- exposed only for tests
  _set_router = _set_router,
  _set_update_router = _set_update_router,
  _set_build_router = _set_build_router,
  _set_router_version = _set_router_version,
  _set_update_plugins_iterator = _set_update_plugins_iterator,
  _get_updated_router = get_updated_router,
  _update_lua_mem = update_lua_mem,
  _register_balancer_events = _register_balancer_events,

  init_worker = {
    before = function()
      -- TODO: PR #9337 may affect the following line
      local prefix = kong.configuration.prefix or ngx.config.prefix()

      STREAM_TLS_TERMINATE_SOCK = fmt("unix:%s/stream_tls_terminate.sock", prefix)
      STREAM_TLS_PASSTHROUGH_SOCK = fmt("unix:%s/stream_tls_passthrough.sock", prefix)

      if kong.configuration.host_ports then
        HOST_PORTS = kong.configuration.host_ports
      end

      if kong.configuration.anonymous_reports then
        reports.configure_ping(kong.configuration)
        reports.add_ping_value("database_version", kong.db.infos.db_ver)
        reports.toggle(true)
        reports.init_worker()
      end

      update_lua_mem(true)

      if kong.configuration.role == "control_plane" then
        return
      end

      register_events()

      -- initialize balancers for active healthchecks
      timer_at(0, function()
        balancer.init()
      end)

      local strategy = kong.db.strategy

      do
        local rebuild_timeout = 60

        if strategy == "cassandra" then
          rebuild_timeout = kong.configuration.cassandra_timeout / 1000
        end

        if strategy == "postgres" then
          rebuild_timeout = kong.configuration.pg_timeout / 1000
        end

        if strategy == "off" then
          RECONFIGURE_OPTS = {
            name = "reconfigure",
            timeout = rebuild_timeout,
          }

        elseif kong.configuration.worker_consistency == "strict" then
          ROUTER_SYNC_OPTS = {
            name = "router",
            timeout = rebuild_timeout,
            on_timeout = "run_unlocked",
          }

          PLUGINS_ITERATOR_SYNC_OPTS = {
            name = "plugins_iterator",
            timeout = rebuild_timeout,
            on_timeout = "run_unlocked",
          }
        end
      end

      if strategy ~= "off" then
        local worker_state_update_frequency = kong.configuration.worker_state_update_frequency or 1

        local router_async_opts = {
          name = "router",
          timeout = 0,
          on_timeout = "return_true",
        }

        local function rebuild_router_timer(premature)
          if premature then
            return
          end

          -- Don't wait for the semaphore (timeout = 0) when updating via the
          -- timer.
          -- If the semaphore is locked, that means that the rebuild is
          -- already ongoing.
          local ok, err = rebuild_router(router_async_opts)
          if not ok then
            log(ERR, "could not rebuild router via timer: ", err)
          end
        end

        local _, err = kong.timer:named_every("router-rebuild",
                                         worker_state_update_frequency,
                                         rebuild_router_timer)
        if err then
          log(ERR, "could not schedule timer to rebuild router: ", err)
        end

        local plugins_iterator_async_opts = {
          name = "plugins_iterator",
          timeout = 0,
          on_timeout = "return_true",
        }

        local function rebuild_plugins_iterator_timer(premature)
          if premature then
            return
          end

          local _, err = rebuild_plugins_iterator(plugins_iterator_async_opts)
          if err then
            log(ERR, "could not rebuild plugins iterator via timer: ", err)
          end
        end

        local _, err = kong.timer:named_every("plugins-iterator-rebuild",
                                         worker_state_update_frequency,
                                         rebuild_plugins_iterator_timer)
        if err then
          log(ERR, "could not schedule timer to rebuild plugins iterator: ", err)
        end

      end
    end,
    after = NOOP,
  },
  certificate = {
    before = function(ctx) -- Note: ctx here is for a connection (not for a single request)
      certificate.execute()
    end,
    after = NOOP,
  },
  preread = {
    before = function(ctx)
      local server_port = var.server_port
      ctx.host_port = HOST_PORTS[server_port] or server_port

      local router = get_updated_router()

      local match_t = router:exec(ctx)
      if not match_t then
        log(ERR, "no Route found with those values")
        return exit(500)
      end

      local route = match_t.route
      -- if matched route doesn't do tls_passthrough and we are in the preread server block
      -- this request should be TLS terminated; return immediately and not run further steps
      -- (even bypassing the balancer)
      if var.kong_tls_preread_block == "1" then
        local protocols = route.protocols
        if protocols and protocols.tls then
          log(DEBUG, "TLS termination required, return to second layer proxying")
          var.kong_tls_preread_block_upstream = STREAM_TLS_TERMINATE_SOCK

        elseif protocols and protocols.tls_passthrough then
          var.kong_tls_preread_block_upstream = STREAM_TLS_PASSTHROUGH_SOCK

        else
          log(ERR, "unexpected protocols in matched Route")
          return exit(500)
        end

        return true
      end


      ctx.workspace = match_t.route and match_t.route.ws_id

      local service = match_t.service
      local upstream_url_t = match_t.upstream_url_t

      balancer_prepare(ctx, match_t.upstream_scheme,
                       upstream_url_t.type,
                       upstream_url_t.host,
                       upstream_url_t.port,
                       service, route)
    end,
    after = function(ctx)
      local ok, err, errcode = balancer_execute(ctx)
      if not ok then
        local body = utils.get_default_exit_body(errcode, err)
        return kong.response.exit(errcode, body)
      end
    end
  },
  rewrite = {
    before = function(ctx)
      local server_port = var.server_port
      ctx.host_port = HOST_PORTS[server_port] or server_port
      instrumentation.request(ctx)
    end,
    after = NOOP,
  },
  access = {
    before = function(ctx)
      -- if there is a gRPC service in the context, don't re-execute the pre-access
      -- phase handler - it has been executed before the internal redirect
      if ctx.service and (ctx.service.protocol == "grpc" or
                          ctx.service.protocol == "grpcs")
      then
        return
      end

      ctx.scheme = var.scheme
      ctx.request_uri = var.request_uri

      -- trace router
      local span = instrumentation.router()

      -- routing request
      local router = get_updated_router()
      local match_t = router:exec(ctx)
      if not match_t then
        -- tracing
        if span then
          span:set_status(2)
          span:finish()
        end

        return kong.response.exit(404, { message = "no Route matched with those values" })
      end

      -- ends tracing span
      if span then
        span:finish()
      end

      ctx.workspace = match_t.route and match_t.route.ws_id

      local host           = var.host
      local port           = tonumber(ctx.host_port, 10)
                          or tonumber(var.server_port, 10)

      local route          = match_t.route
      local service        = match_t.service
      local upstream_url_t = match_t.upstream_url_t

      local realip_remote_addr = var.realip_remote_addr
      local forwarded_proto
      local forwarded_host
      local forwarded_port
      local forwarded_path
      local forwarded_prefix

      -- X-Forwarded-* Headers Parsing
      --
      -- We could use $proxy_add_x_forwarded_for, but it does not work properly
      -- with the realip module. The realip module overrides $remote_addr and it
      -- is okay for us to use it in case no X-Forwarded-For header was present.
      -- But in case it was given, we will append the $realip_remote_addr that
      -- contains the IP that was originally in $remote_addr before realip
      -- module overrode that (aka the client that connected us).

      local trusted_ip = kong.ip.is_trusted(realip_remote_addr)
      if trusted_ip then
        forwarded_proto  = var.http_x_forwarded_proto  or ctx.scheme
        forwarded_host   = var.http_x_forwarded_host   or host
        forwarded_port   = var.http_x_forwarded_port   or port
        forwarded_path   = var.http_x_forwarded_path
        forwarded_prefix = var.http_x_forwarded_prefix

      else
        forwarded_proto  = ctx.scheme
        forwarded_host   = host
        forwarded_port   = port
      end

      if not forwarded_path then
        forwarded_path = ctx.request_uri
        local p = find(forwarded_path, "?", 2, true)
        if p then
          forwarded_path = sub(forwarded_path, 1, p - 1)
        end
      end

      if not forwarded_prefix and match_t.prefix ~= "/" then
        forwarded_prefix = match_t.prefix
      end

      local protocols = route.protocols
      if (protocols and protocols.https and not protocols.http and
          forwarded_proto ~= "https")
      then
        local redirect_status_code = route.https_redirect_status_code or 426

        if redirect_status_code == 426 then
          return kong.response.exit(426, { message = "Please use HTTPS protocol" }, {
            ["Connection"] = "Upgrade",
            ["Upgrade"]    = "TLS/1.2, HTTP/1.1",
          })
        end

        if redirect_status_code == 301
        or redirect_status_code == 302
        or redirect_status_code == 307
        or redirect_status_code == 308
        then
          header["Location"] = "https://" .. forwarded_host .. ctx.request_uri
          return kong.response.exit(redirect_status_code)
        end
      end

      local protocol_version = http_version()
      if protocols.grpc or protocols.grpcs then
        -- perf: branch usually not taken, don't cache var outside
        local content_type = var.content_type

        if content_type and sub(content_type, 1, #"application/grpc") == "application/grpc" then
          if protocol_version ~= 2 then
            -- mismatch: non-http/2 request matched grpc route
            return kong.response.exit(426, { message = "Please use HTTP2 protocol" }, {
              ["connection"] = "Upgrade",
              ["upgrade"]    = "HTTP/2",
            })
          end

        else
          -- mismatch: non-grpc request matched grpc route
          return kong.response.exit(415, { message = "Non-gRPC request matched gRPC route" })
        end

        if not protocols.grpc and forwarded_proto ~= "https" then
          -- mismatch: grpc request matched grpcs route
          return kong.response.exit(200, nil, {
            ["content-type"] = "application/grpc",
            ["grpc-status"] = 1,
            ["grpc-message"] = "gRPC request matched gRPCs route",
          })
        end
      end

      balancer_prepare(ctx, match_t.upstream_scheme,
                       upstream_url_t.type,
                       upstream_url_t.host,
                       upstream_url_t.port,
                       service, route)

      ctx.router_matches = match_t.matches

      -- `uri` is the URI with which to call upstream, as returned by the
      --       router, which might have truncated it (`strip_uri`).
      -- `host` is the original header to be preserved if set.
      var.upstream_scheme = match_t.upstream_scheme -- COMPAT: pdk
      var.upstream_uri    = escape(match_t.upstream_uri)
      if match_t.upstream_host then
        var.upstream_host = match_t.upstream_host
      end

      -- Keep-Alive and WebSocket Protocol Upgrade Headers
      local upgrade = var.http_upgrade
      if upgrade and lower(upgrade) == "websocket" then
        var.upstream_connection = "keep-alive, Upgrade"
        var.upstream_upgrade    = "websocket"

      else
        var.upstream_connection = "keep-alive"
      end

      -- X-Forwarded-* Headers
      local http_x_forwarded_for = var.http_x_forwarded_for
      if http_x_forwarded_for then
        var.upstream_x_forwarded_for = http_x_forwarded_for .. ", " ..
                                       realip_remote_addr

      else
        var.upstream_x_forwarded_for = var.remote_addr
      end

      var.upstream_x_forwarded_proto  = forwarded_proto
      var.upstream_x_forwarded_host   = forwarded_host
      var.upstream_x_forwarded_port   = forwarded_port
      var.upstream_x_forwarded_path   = forwarded_path
      var.upstream_x_forwarded_prefix = forwarded_prefix

      -- At this point, the router and `balancer_setup_stage1` have been
      -- executed; detect requests that need to be redirected from `proxy_pass`
      -- to `grpc_pass`. After redirection, this function will return early
      if service and var.kong_proxy_mode == "http" then
        if service.protocol == "grpc" or service.protocol == "grpcs" then
          return exec("@grpc")
        end

        if protocol_version == 1.1 then
          if route.request_buffering == false then
            if route.response_buffering == false then
              return exec("@unbuffered")
            end

            return exec("@unbuffered_request")
          end

          if route.response_buffering == false then
            return exec("@unbuffered_response")
          end
        end
      end
    end,
    -- Only executed if the `router` module found a route and allows nginx to proxy it.
    after = function(ctx)
      -- Nginx's behavior when proxying a request with an empty querystring
      -- `/foo?` is to keep `$is_args` an empty string, hence effectively
      -- stripping the empty querystring.
      -- We overcome this behavior with our own logic, to preserve user
      -- desired semantics.
      -- perf: branch usually not taken, don't cache var outside
      if byte(ctx.request_uri or var.request_uri, -1) == QUESTION_MARK then
        var.upstream_uri = var.upstream_uri .. "?"
      elseif var.is_args == "?" then
        var.upstream_uri = var.upstream_uri .. "?" .. (var.args or "")
      end

      local upstream_scheme = var.upstream_scheme

      local balancer_data = ctx.balancer_data
      balancer_data.scheme = upstream_scheme -- COMPAT: pdk

      -- The content of var.upstream_host is only set by the router if
      -- preserve_host is true
      --
      -- We can't rely on var.upstream_host for balancer retries inside
      -- `set_host_header` because it would never be empty after the first -- balancer try
      local upstream_host = var.upstream_host
      if upstream_host ~= nil and upstream_host ~= "" then
        balancer_data.preserve_host = true

        -- the nginx grpc module does not offer a way to override the
        -- :authority pseudo-header; use our internal API to do so
        -- this call applies to routes with preserve_host=true; for
        -- preserve_host=false, the header is set in `set_host_header`,
        -- so that it also applies to balancer retries
        if upstream_scheme == "grpc" or upstream_scheme == "grpcs" then
          local ok, err = set_authority(upstream_host)
          if not ok then
            log(ERR, "failed to set :authority header: ", err)
          end
        end
      end

      local ok, err, errcode = balancer_execute(ctx)
      if not ok then
        local body = utils.get_default_exit_body(errcode, err)
        return kong.response.exit(errcode, body)
      end

      local ok, err = balancer.set_host_header(balancer_data, upstream_scheme, "upstream_host")
      if not ok then
        log(ERR, "failed to set balancer Host header: ", err)
        return exit(500)
      end

      -- clear hop-by-hop request headers:
      local http_connection = var.http_connection
      if http_connection ~= "keep-alive" and
         http_connection ~= "close"      and
         http_connection ~= "upgrade"
      then
        for _, header_name in csv(http_connection) do
          -- some of these are already handled by the proxy module,
          -- upgrade being an exception that is handled below with
          -- special semantics.
          if header_name == "upgrade" then
            if var.upstream_connection == "keep-alive" then
              clear_header(header_name)
            end

          else
            clear_header(header_name)
          end
        end
      end

      -- add te header only when client requests trailers (proxy removes it)
      local http_te = var.http_te
      if http_te then
        if http_te == "trailers" then
          var.upstream_te = "trailers"

        else
          for _, header_name in csv(http_te) do
            if header_name == "trailers" then
              var.upstream_te = "trailers"
              break
            end
          end
        end
      end

      if var.http_proxy then
        clear_header("Proxy")
      end

      if var.http_proxy_connection then
        clear_header("Proxy-Connection")
      end
    end
  },
  response = {
    before = NOOP,
    after = NOOP,
  },
  header_filter = {
    before = function(ctx)
      if not ctx.KONG_PROXIED then
        return
      end

      -- clear hop-by-hop response headers:
      local upstream_http_connection = var.upstream_http_connection
      if upstream_http_connection ~= "keep-alive" and
         upstream_http_connection ~= "close"      and
         upstream_http_connection ~= "upgrade"
      then
        for _, header_name in csv(upstream_http_connection) do
          if header_name ~= "close" and header_name ~= "upgrade" and header_name ~= "keep-alive" then
            header[header_name] = nil
          end
        end
      end

      local upgrade = var.upstream_http_upgrade
      if upgrade and lower(upgrade) ~= lower(var.upstream_upgrade) then
        header["Upgrade"] = nil
      end

      -- remove trailer response header when client didn't ask for them
      if var.upstream_te == "" and var.upstream_http_trailer then
        header["Trailer"] = nil
      end

      local upstream_status_header = constants.HEADERS.UPSTREAM_STATUS
      if kong.configuration.enabled_headers[upstream_status_header] then
        header[upstream_status_header] = tonumber(sub(var.upstream_status or "", -3))
        if not header[upstream_status_header] then
          log(ERR, "failed to set ", upstream_status_header, " header")
        end
      end

      -- if this is the last try and it failed, save its state to correctly log it
      local status = ngx.status
      if status > 499 and ctx.balancer_data then
        local balancer_data = ctx.balancer_data
        local try_count = balancer_data.try_count
        local retries = balancer_data.retries
        if try_count > retries then
          local current_try = balancer_data.tries[try_count]
          current_try.state = "failed"
          current_try.code = status
        end
      end

      local hash_cookie = ctx.balancer_data.hash_cookie
      if hash_cookie then
        balancer.set_cookie(hash_cookie)
      end
    end,
    after = function(ctx)
      local enabled_headers = kong.configuration.enabled_headers
      local headers = constants.HEADERS
      if ctx.KONG_PROXIED then
        if enabled_headers[headers.UPSTREAM_LATENCY] then
          header[headers.UPSTREAM_LATENCY] = ctx.KONG_WAITING_TIME
        end

        if enabled_headers[headers.PROXY_LATENCY] then
          header[headers.PROXY_LATENCY] = ctx.KONG_PROXY_LATENCY
        end

        if enabled_headers[headers.VIA] then
          header[headers.VIA] = SERVER_HEADER
        end

      else
        if enabled_headers[headers.RESPONSE_LATENCY] then
          header[headers.RESPONSE_LATENCY] = ctx.KONG_RESPONSE_LATENCY
        end

        -- Some plugins short-circuit the request with Via-header, and in those cases
        -- we don't want to set the Server-header, if the Via-header matches with
        -- the Kong server header.
        if not (enabled_headers[headers.VIA] and header[headers.VIA] == SERVER_HEADER) then
          if enabled_headers[headers.SERVER] then
            header[headers.SERVER] = SERVER_HEADER

          else
            header[headers.SERVER] = nil
          end
        end
      end
    end
  },
  log = {
    before = function(ctx)
      instrumentation.runloop_log_before(ctx)
    end,
    after = function(ctx)
      instrumentation.runloop_log_after(ctx)

      update_lua_mem()

      if kong.configuration.anonymous_reports then
        reports.log(ctx)
      end

      if not ctx.KONG_PROXIED then
        return
      end

      -- If response was produced by an upstream (ie, not by a Kong plugin)
      -- Report HTTP status for health checks
      local balancer_data = ctx.balancer_data
      if balancer_data and balancer_data.balancer_handle then
        local status = ngx.status
        if status == 504 then
          balancer_data.balancer.report_timeout(balancer_data.balancer_handle)
        else
          balancer_data.balancer.report_http_status(
            balancer_data.balancer_handle, status)
        end
        -- release the handle, so the balancer can update its statistics
        if balancer_data.balancer_handle.release then
          balancer_data.balancer_handle:release()
        end
      end
    end
  }
}
