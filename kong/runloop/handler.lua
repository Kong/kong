-- Kong runloop
--
-- This consists of local_events that need to
-- be ran at the very beginning and very end of the lua-nginx-module contexts.
-- It mainly carries information related to a request from one context to the next one,
-- through the `ngx.ctx` table.
--
-- In the `access_by_lua` phase, it is responsible for retrieving the route being proxied by
-- a consumer. Then it is responsible for loading the plugins to execute on this request.
local ck          = require "resty.cookie"
local meta        = require "kong.meta"
local utils       = require "kong.tools.utils"
local Router      = require "kong.router"
local reports     = require "kong.reports"
local balancer    = require "kong.runloop.balancer"
local mesh        = require "kong.runloop.mesh"
local constants   = require "kong.constants"
local semaphore   = require "ngx.semaphore"
local singletons  = require "kong.singletons"
local certificate = require "kong.runloop.certificate"


local kong        = kong
local pcall       = pcall
local tostring    = tostring
local tonumber    = tonumber
local sub         = string.sub
local lower       = string.lower
local fmt         = string.format
local sort        = table.sort
local ngx         = ngx
local log         = ngx.log
local sleep       = ngx.sleep
local ngx_now     = ngx.now
local update_time = ngx.update_time
local subsystem   = ngx.config.subsystem
local unpack      = unpack


local ERR         = ngx.ERR
local CRIT        = ngx.CRIT
local DEBUG       = ngx.DEBUG
local NOTICE      = ngx.NOTICE


local CACHE_ROUTER_OPTS = { ttl = 0 }
local EMPTY_T = {}


local init_router
local get_router
local build_router
local rebuild_router
local build_router_semaphore
local _set_rebuild_router


local server_header = meta._SERVER_TOKENS


local function get_now()
  update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


do
  -- Given a protocol, return the subsystem that handles it
  local protocol_subsystem = {
    http = "http",
    https = "http",
    tcp = "stream",
    tls = "stream",
  }

  local function cache_services()
    if not kong.db or not kong.cache then
      return true
    end

    for service, err in kong.db.services:each(1000) do
      if err then
        return nil, err
      end

      local cache_key = kong.db.services:cache_key(service.id)
      service, err = kong.cache:get(cache_key, CACHE_ROUTER_OPTS, function()
        return service
      end)
      if err then
        return nil, err
      end
    end

    return true
  end

  local function load_service_db(service_pk)
    local service, err = kong.db.services:select(service_pk)
    return service, err
  end

  local function load_service(service_pk)
    local service, err
    if kong.cache then
      local cache_key = kong.db.services:cache_key(service_pk.id)
      service, err = kong.cache:get(cache_key, CACHE_ROUTER_OPTS,
                                    load_service_db, service_pk)

    else
      service, err = load_service_db(service_pk)
    end

    return service, err
  end

  local router
  local router_version

  local function lock_router(wait)
    local ok, err = build_router_semaphore:wait(wait or 0)
    if not ok then
      if err ~= "timeout" then
        log(ERR, "error attempting to acquire router lock: " .. err)
      elseif wait and wait > 0 then
        log(NOTICE, "timeout attempting to acquire router lock")
      end

      return false
    end

    return true
  end

  local function unlock_router()
    build_router_semaphore:post()
  end

  local function get_router_version()
    if not kong.cache then
      return "init"
    end

    local version, err = kong.cache:get("router:version", CACHE_ROUTER_OPTS, utils.uuid)
    if err then
      log(CRIT, "could not ensure router is up to date: ", err)
      return nil
    end

    return version
  end

  init_router = function()
    local _, err = cache_services()
    if err then
      log(ERR, "could not cache services: ", err)
    end

    build_router_semaphore, err = semaphore.new(1)
    if err then
      log(CRIT, "failed to create build router semaphore: ", err)
    end

    local timeout = kong.configuration.router_timeout
    if timeout then
      timeout = timeout / 1000
    else
      timeout = 5
    end

    if timeout < 0 then
      get_router = function()
        return router
      end

    else
      get_router = function()
        rebuild_router(timeout)
        return router
      end
    end
  end

  build_router = function(version, recurse, tries)
    tries = tries or 1

    local current_version
    current_version = get_router_version()
    if version ~= current_version then
      return build_router(current_version, recurse, tries)
    end

    local routes, i, counter = {}, 0, 0

    for route, err in kong.db.routes:each(1000) do
      if err then
        current_version = get_router_version()
        if version ~= current_version then
          return build_router(current_version, recurse, tries)
        end

        if recurse and tries < 6 then
          kong.db:setkeepalive()
          log(NOTICE,  "could not load routes: " .. err)
          sleep(0.01 * tries * tries)
          kong.db:connect()
          return build_router(current_version, recurse, tries + 1)
        end

        return nil, "could not load routes: " .. err
      end

      if recurse and counter % 1000 then
        current_version = get_router_version()
        if version ~= current_version then
          return build_router(current_version, recurse, tries)
        end
      end

      local service_pk = route.service
      if not service_pk then
        current_version = get_router_version()
        if version ~= current_version then
          return build_router(current_version, recurse, tries)
        end

        if recurse and tries < 6 then
          kong.db:setkeepalive()
          log(NOTICE,  "route (" .. route.id .. ") is not associated with service")
          sleep(0.01 * tries * tries)
          kong.db:connect()
          return build_router(current_version, recurse, tries + 1)
        end

        return nil, "route (" .. route.id .. ") is not associated with service"
      end

      local service, err = load_service(service_pk)
      if not service then
        current_version = get_router_version()
        if version ~= current_version then
          return build_router(current_version, recurse, tries)
        end

        if recurse and tries < 6 then
          kong.db:setkeepalive()
          log(NOTICE,  "could not find service for route (", route.id, "): ", err)
          sleep(0.01 * tries * tries)
          kong.db:connect()
          return build_router(current_version, recurse, tries + 1)
        end

        return nil, "could not find service for route (" .. route.id .. "): " ..
                    err
      end

      local stype = protocol_subsystem[service.protocol]
      if subsystem == stype then
        local r = {
          route   = route,
          service = service,
        }

        if stype == "http" and route.hosts then
          -- TODO: headers should probably be moved to route
          r.headers = {
            host = route.hosts,
          }
        end

        i = i + 1
        routes[i] = r
      end

      counter = counter + 1
    end

    sort(routes, function(r1, r2)
      r1, r2 = r1.route, r2.route

      local rp1 = r1.regex_priority or 0
      local rp2 = r2.regex_priority or 0

      if rp1 == rp2 then
        return r1.created_at < r2.created_at
      end

      return rp1 > rp2
    end)

    local new_router, err = Router.new(routes)
    if not new_router then
      return nil, "could not create router: " .. err
    end

    router_version = version
    router = new_router

    singletons.router = new_router

    if recurse then
      current_version = get_router_version()
      if version ~= current_version then
        return build_router(current_version, recurse, tries)
      end
    end

    return true
  end

  local function rebuild_router_timer(premature, version)
    if premature then
      unlock_router()
      return
    end

    kong.db:connect()

    local pok, ok, err = pcall(build_router, version, true)
    if not pok or not ok then
      log(CRIT, "could not asynchronously rebuild router: ", ok or err)
    end

    unlock_router()

    kong.db:setkeepalive()
  end

  local function rebuild_router_sync(version)
    kong.db:connect()

    local pok, ok, err = pcall(build_router, version)
    if not pok or not ok then
      log(CRIT, "could not synchronously rebuild router: ", ok or err)
    end

    kong.db:setkeepalive()
  end

  local function rebuild_router_async(version)
    local ok, err = ngx.timer.at(0, rebuild_router_timer, version)
    if not ok then
      log(CRIT, "could not create rebuild router timer: ", err)
      return false
    end

    return true
  end

  rebuild_router = function(wait)
    local version = get_router_version()
    if version == router_version then
      return
    end

    local ok = lock_router(wait)
    if not ok then
      if wait and wait > 0 then
        rebuild_router_sync(version)
      end

      return
    end

    version = get_router_version()
    if version == router_version then
      unlock_router()
      return
    end

    log(DEBUG, "rebuilding router")

    if wait and wait > 0 then
      rebuild_router_sync(version)
      unlock_router()

    else
      ok = rebuild_router_async(version)
      if not ok and wait == 0 then
        rebuild_router_sync(version)
        unlock_router()
      end
    end
  end

  -- for unit-testing purposes only
  _set_rebuild_router = function(f)
    rebuild_router = f
  end
end


local function balancer_setup_stage1(ctx, scheme, host_type, host, port,
                                     service, route)
  local balancer_data = {
    scheme         = scheme,    -- scheme for balancer: http, https
    type           = host_type, -- type of 'host': ipv4, ipv6, name
    host           = host,      -- target host per `upstream_url`
    port           = port,      -- final target port
    try_count      = 0,         -- retry counter
    tries          = {},        -- stores info per try
    ssl_ctx        = kong.default_client_ssl_ctx, -- SSL_CTX* to use
    -- ip          = nil,       -- final target IP address
    -- balancer    = nil,       -- the balancer object, if any
    -- hostname    = nil,       -- hostname of the final target IP
    -- hash_cookie = nil,       -- if Upstream sets hash_on_cookie
  }

  -- TODO: this is probably not optimal
  do
    local retries = service.retries
    if retries then
      balancer_data.retries = retries

    else
      balancer_data.retries = 5
    end

    local connect_timeout = service.connect_timeout
    if connect_timeout then
      balancer_data.connect_timeout = connect_timeout

    else
      balancer_data.connect_timeout = 60000
    end

    local send_timeout = service.write_timeout
    if send_timeout then
      balancer_data.send_timeout = send_timeout

    else
      balancer_data.send_timeout = 60000
    end

    local read_timeout = service.read_timeout
    if read_timeout then
      balancer_data.read_timeout = read_timeout

    else
      balancer_data.read_timeout = 60000
    end
  end

  ctx.service          = service
  ctx.route            = route
  ctx.balancer_data    = balancer_data
  ctx.balancer_address = balancer_data -- for plugin backward compatibility
end


local function balancer_setup_stage2(ctx)
  local balancer_data = ctx.balancer_data

  do -- Check for KONG_ORIGINS override
    local origin_key = balancer_data.scheme .. "://" ..
                       utils.format_host(balancer_data)
    local origin = singletons.origins[origin_key]
    if origin then
      balancer_data.scheme = origin.scheme
      balancer_data.type = origin.type
      balancer_data.host = origin.host
      balancer_data.port = origin.port
    end
  end

  local ok, err, errcode = balancer.execute(balancer_data, ctx)
  if not ok and errcode == 500 then
    err = "failed the initial dns/balancer resolve for '" ..
          balancer_data.host .. "' with: " .. tostring(err)
  end

  return ok, err, errcode
end


-- in the table below the `before` and `after` is to indicate when they run:
-- before or after the plugins
return {
  build_router     = build_router,

  -- exported for unit-testing purposes only
  _set_rebuild_router = _set_rebuild_router,

  init = {
    after = function()
      build_router("init")
    end
  },

  init_worker = {
    before = function()
      reports.init_worker()

      -- initialize local local_events hooks
      local db             = kong.db
      local cache          = kong.cache
      local worker_events  = kong.worker_events
      local cluster_events = kong.cluster_events


      -- events dispatcher


      worker_events.register(function(data)
        if not data.schema then
          log(ngx.ERR, "[events] missing schema in crud subscriber")
          return
        end

        if not data.entity then
          log(ngx.ERR, "[events] missing entity in crud subscriber")
          return
        end

        -- invalidate this entity anywhere it is cached if it has a
        -- caching key

        local cache_key = db[data.schema.name]:cache_key(data.entity)

        if cache_key then
          cache:invalidate(cache_key)
        end

        -- if we had an update, but the cache key was part of what was updated,
        -- we need to invalidate the previous entity as well

        if data.old_entity then
          cache_key = db[data.schema.name]:cache_key(data.old_entity)
          if cache_key then
            cache:invalidate(cache_key)
          end
        end

        if not data.operation then
          log(ngx.ERR, "[events] missing operation in crud subscriber")
          return
        end

        -- public worker events propagation

        local entity_channel           = data.schema.table or data.schema.name
        local entity_operation_channel = fmt("%s:%s", entity_channel,
                                             data.operation)

        -- crud:routes
        local _, err = worker_events.post_local("crud", entity_channel, data)
        if err then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end

        -- crud:routes:create
        _, err = worker_events.post_local("crud", entity_operation_channel, data)
        if err then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end
      end, "dao:crud")


      -- local events (same worker)


      worker_events.register(function()
        log(DEBUG, "[events] Route updated, invalidating router")
        cache:invalidate("router:version")
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
          cache:invalidate("router:version")
        end
      end, "crud", "services")


      worker_events.register(function(data)
        log(DEBUG, "[events] Plugin updated, invalidating plugins map")
        cache:invalidate("plugins_map:version")
      end, "crud", "plugins")


      -- SSL certs / SNIs invalidations


      worker_events.register(function(data)
        log(DEBUG, "[events] SNI updated, invalidating cached certificates")
        local sn = data.entity

        cache:invalidate("certificates:" .. sn.name)
      end, "crud", "snis")


      worker_events.register(function(data)
        log(DEBUG, "[events] SSL cert updated, invalidating cached certificates")
        local certificate = data.entity

        for sn, err in db.snis:each_for_certificate({ id = certificate.id }, 1000) do
          if err then
            log(ERR, "[events] could not find associated snis for certificate: ",
                     err)
            break
          end

          cache:invalidate("certificates:" .. sn.name)
        end
      end, "crud", "certificates")


      -- target updates


      -- worker_events local handler: event received from DAO
      worker_events.register(function(data)
        local operation = data.operation
        local target = data.entity
        -- => to worker_events node handler
        local ok, err = worker_events.post("balancer", "targets", {
          operation = data.operation,
          entity = data.entity,
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
        -- => to worker_events node handler
        local ok, err = worker_events.post("balancer", "targets", {
          operation = operation,
          entity = {
            upstream = { id = key },
          }
        })
        if not ok then
          log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
        end
      end)


      -- manual health updates
      cluster_events:subscribe("balancer:post_health", function(data)
        local pattern = "([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)"
        local ip, port, health, id, name = data:match(pattern)
        port = tonumber(port)
        local upstream = { id = id, name = name }
        local ok, err = balancer.post_health(upstream, ip, port, health == "1")
        if not ok then
          log(ERR, "failed posting health of ", name, " to workers: ", err)
        end
      end)


      -- upstream updates


      -- worker_events local handler: event received from DAO
      worker_events.register(function(data)
        local operation = data.operation
        local upstream = data.entity
        -- => to worker_events node handler
        local ok, err = worker_events.post("balancer", "upstreams", {
          operation = data.operation,
          entity = data.entity,
        })
        if not ok then
          log(ERR, "failed broadcasting upstream ",
              operation, " to workers: ", err)
        end
        -- => to cluster_events handler
        local key = fmt("%s:%s:%s", operation, upstream.id, upstream.name)
        ok, err = cluster_events:broadcast("balancer:upstreams", key)
        if not ok then
          log(ERR, "failed broadcasting upstream ", operation, " to cluster: ", err)
        end
      end, "crud", "upstreams")


      -- worker_events node handler
      worker_events.register(function(data)
        local operation = data.operation
        local upstream = data.entity

        -- => to balancer update
        balancer.on_upstream_event(operation, upstream)
      end, "balancer", "upstreams")


      cluster_events:subscribe("balancer:upstreams", function(data)
        local operation, id, name = unpack(utils.split(data, ":"))
        -- => to worker_events node handler
        local ok, err = worker_events.post("balancer", "upstreams", {
          operation = operation,
          entity = {
            id = id,
            name = name,
          }
        })
        if not ok then
          log(ERR, "failed broadcasting upstream ", operation, " to workers: ", err)
        end
      end)


      -- initialize balancers for active healthchecks
      ngx.timer.at(0, function()
        balancer.init()
      end)

      init_router()

      ngx.timer.every(1, function(premature)
        if premature then
          return
        end

        rebuild_router()
      end)
    end
  },
  certificate = {
    before = function(_)
      certificate.execute()
    end
  },
  rewrite = {
    before = function(ctx)
      ctx.KONG_REWRITE_START = get_now()
      mesh.rewrite(ctx)
    end,
    after = function(ctx)
      ctx.KONG_REWRITE_TIME = get_now() - ctx.KONG_REWRITE_START -- time spent in Kong's rewrite_by_lua
    end
  },
  preread = {
    before = function(ctx)
      local router, err = get_router()
      if not router then
        log(ERR, "no router to route connection (reason: " .. err .. ")")
        return ngx.exit(500)
      end

      local match_t = router.exec(ngx)
      if not match_t then
        log(ERR, "no Route found with those values")
        return ngx.exit(500)
      end

      local var = ngx.var

      local ssl_termination_ctx -- OpenSSL SSL_CTX to use for termination

      local ssl_preread_alpn_protocols = var.ssl_preread_alpn_protocols
      -- ssl_preread_alpn_protocols is a comma separated list
      -- see https://trac.nginx.org/nginx/ticket/1616
      if ssl_preread_alpn_protocols and
         ssl_preread_alpn_protocols:find(mesh.get_mesh_alpn(), 1, true) then
        -- Is probably an incoming service mesh connection
        -- terminate service-mesh Mutual TLS
        ssl_termination_ctx = mesh.mesh_server_ssl_ctx
        ctx.is_service_mesh_request = true
      else
        -- TODO: stream router should decide if TLS is terminated or not
        -- XXX: for now, use presence of SNI to terminate.
        local sni = var.ssl_preread_server_name
        if sni then
          ngx.log(ngx.DEBUG, "SNI: ", sni)

          local err
          ssl_termination_ctx, err = certificate.find_certificate(sni)
          if not ssl_termination_ctx then
            ngx.log(ngx.ERR, err)
            return ngx.exit(ngx.ERROR)
          end

          -- TODO Fake certificate phase?

          ngx.log(ngx.INFO, "attempting to terminate TLS")
        end
      end

      -- Terminate TLS
      if ssl_termination_ctx and not ngx.req.starttls(ssl_termination_ctx) then -- luacheck: ignore
        -- errors are logged by nginx core
        return ngx.exit(ngx.ERROR)
      end

      ctx.KONG_PREREAD_START = get_now()

      local api = match_t.api or EMPTY_T
      local route = match_t.route or EMPTY_T
      local service = match_t.service or EMPTY_T
      local upstream_url_t = match_t.upstream_url_t

      balancer_setup_stage1(ctx, match_t.upstream_scheme,
                            upstream_url_t.type,
                            upstream_url_t.host,
                            upstream_url_t.port,
                            service, route, api)
    end,
    after = function(ctx)
      local ok, err, errcode = balancer_setup_stage2(ctx)
      if not ok then
        local body = utils.get_default_exit_body(errcode, err)
        return kong.response.exit(errcode, body)
      end

      local now = get_now()

      -- time spent in Kong's preread_by_lua
      ctx.KONG_PREREAD_TIME     = now - ctx.KONG_PREREAD_START
      ctx.KONG_PREREAD_ENDED_AT = now
      -- time spent in Kong before sending the request to upstream
      -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ctx.KONG_PROXY_LATENCY   = now - ngx.req.start_time() * 1000
      ctx.KONG_PROXIED         = true
    end
  },
  access = {
    before = function(ctx)
      -- router for Routes/Services

      local router, err = get_router()
      if not router then
        kong.log.err("no router to route request (reason: " .. tostring(err) ..  ")")
        return kong.response.exit(500, { message  = "An unexpected error occurred" })
      end

      -- routing request

      local var = ngx.var

      ctx.KONG_ACCESS_START = get_now()

      local match_t = router.exec(ngx)
      if not match_t then
        return kong.response.exit(404, { message = "no Route matched with those values" })
      end

      local route              = match_t.route or EMPTY_T
      local service            = match_t.service or EMPTY_T
      local upstream_url_t     = match_t.upstream_url_t

      local realip_remote_addr = var.realip_remote_addr
      local forwarded_proto
      local forwarded_host
      local forwarded_port

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
        forwarded_proto = var.http_x_forwarded_proto or var.scheme
        forwarded_host  = var.http_x_forwarded_host  or var.host
        forwarded_port  = var.http_x_forwarded_port  or var.server_port

      else
        forwarded_proto = var.scheme
        forwarded_host  = var.host
        forwarded_port  = var.server_port
      end

      local protocols = route.protocols
      if (protocols and
          protocols.https and not protocols.http and forwarded_proto ~= "https")
      then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.2, HTTP/1.1"
        return kong.response.exit(426, { message = "Please use HTTPS protocol" })
      end

      balancer_setup_stage1(ctx, match_t.upstream_scheme,
                            upstream_url_t.type,
                            upstream_url_t.host,
                            upstream_url_t.port,
                            service, route)

      ctx.router_matches = match_t.matches

      -- `uri` is the URI with which to call upstream, as returned by the
      --       router, which might have truncated it (`strip_uri`).
      -- `host` is the original header to be preserved if set.
      var.upstream_scheme = match_t.upstream_scheme -- COMPAT: pdk
      var.upstream_uri    = match_t.upstream_uri
      var.upstream_host   = match_t.upstream_host

      -- Keep-Alive and WebSocket Protocol Upgrade Headers
      if var.http_upgrade and lower(var.http_upgrade) == "websocket" then
        var.upstream_connection = "upgrade"
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

      var.upstream_x_forwarded_proto = forwarded_proto
      var.upstream_x_forwarded_host  = forwarded_host
      var.upstream_x_forwarded_port  = forwarded_port
    end,
    -- Only executed if the `router` module found a route and allows nginx to proxy it.
    after = function(ctx)
      local var = ngx.var

      do
        -- Nginx's behavior when proxying a request with an empty querystring
        -- `/foo?` is to keep `$is_args` an empty string, hence effectively
        -- stripping the empty querystring.
        -- We overcome this behavior with our own logic, to preserve user
        -- desired semantics.
        local upstream_uri = var.upstream_uri

        if var.is_args == "?" or sub(var.request_uri, -1) == "?" then
          var.upstream_uri = upstream_uri .. "?" .. (var.args or "")
        end
      end

      local balancer_data = ctx.balancer_data
      balancer_data.scheme = var.upstream_scheme -- COMPAT: pdk

      local ok, err, errcode = balancer_setup_stage2(ctx)
      if not ok then
        local body = utils.get_default_exit_body(errcode, err)
        return kong.response.exit(errcode, body)
      end

      var.upstream_scheme = balancer_data.scheme

      do
        -- set the upstream host header if not `preserve_host`
        local upstream_host = var.upstream_host

        if not upstream_host or upstream_host == "" then
          upstream_host = balancer_data.hostname

          local upstream_scheme = var.upstream_scheme
          if upstream_scheme == "http"  and balancer_data.port ~= 80 or
             upstream_scheme == "https" and balancer_data.port ~= 443
          then
            upstream_host = upstream_host .. ":" .. balancer_data.port
          end

          var.upstream_host = upstream_host
        end
      end

      local now = get_now()

      -- time spent in Kong's access_by_lua
      ctx.KONG_ACCESS_TIME     = now - ctx.KONG_ACCESS_START
      ctx.KONG_ACCESS_ENDED_AT = now
      -- time spent in Kong before sending the request to upstream
      -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ctx.KONG_PROXY_LATENCY   = now - ngx.req.start_time() * 1000
      ctx.KONG_PROXIED         = true
    end
  },
  balancer = {
    before = function(ctx)
      local balancer_data = ctx.balancer_data
      local current_try = balancer_data.tries[balancer_data.try_count]
      current_try.balancer_start = get_now()
    end,
    after = function(ctx)
      local balancer_data = ctx.balancer_data
      local current_try = balancer_data.tries[balancer_data.try_count]

      -- record try-latency
      local try_latency = get_now() - current_try.balancer_start
      current_try.balancer_latency = try_latency

      -- record overall latency
      ctx.KONG_BALANCER_TIME = (ctx.KONG_BALANCER_TIME or 0) + try_latency
    end
  },
  header_filter = {
    before = function(ctx)
      local header = ngx.header

      if not ctx.KONG_PROXIED then
        return
      end

      local now = get_now()
      -- time spent waiting for a response from upstream
      ctx.KONG_WAITING_TIME             = now - ctx.KONG_ACCESS_ENDED_AT
      ctx.KONG_HEADER_FILTER_STARTED_AT = now

      local upstream_status_header = constants.HEADERS.UPSTREAM_STATUS
      if kong.configuration.enabled_headers[upstream_status_header] then
        header[upstream_status_header] = tonumber(sub(ngx.var.upstream_status or "", -3))
        if not header[upstream_status_header] then
          log(ERR, "failed to set ", upstream_status_header, " header")
        end
      end

      local hash_cookie = ctx.balancer_data.hash_cookie
      if not hash_cookie then
        return
      end

      local cookie = ck:new()
      local ok, err = cookie:set(hash_cookie)

      if not ok then
        log(ngx.WARN, "failed to set the cookie for hash-based load balancing: ", err,
                      " (key=", hash_cookie.key,
                      ", path=", hash_cookie.path, ")")
      end
    end,
    after = function(ctx)
      local header = ngx.header

      if ctx.KONG_PROXIED then
        if kong.configuration.enabled_headers[constants.HEADERS.UPSTREAM_LATENCY] then
          header[constants.HEADERS.UPSTREAM_LATENCY] = ctx.KONG_WAITING_TIME
        end

        if kong.configuration.enabled_headers[constants.HEADERS.PROXY_LATENCY] then
          header[constants.HEADERS.PROXY_LATENCY] = ctx.KONG_PROXY_LATENCY
        end

        if kong.configuration.enabled_headers[constants.HEADERS.VIA] then
          header[constants.HEADERS.VIA] = server_header
        end

      else
        if kong.configuration.enabled_headers[constants.HEADERS.SERVER] then
          header[constants.HEADERS.SERVER] = server_header

        else
          header[constants.HEADERS.SERVER] = nil
        end
      end
    end
  },
  body_filter = {
    after = function(ctx)
      if not ngx.arg[2] then
        return
      end

      local now = get_now()
      ctx.KONG_BODY_FILTER_ENDED_AT = now

      if ctx.KONG_PROXIED then
        -- time spent receiving the response (header_filter + body_filter)
        -- we could use $upstream_response_time but we need to distinguish the waiting time
        -- from the receiving time in our logging plugins (especially ALF serializer).
        ctx.KONG_RECEIVE_TIME = now - ctx.KONG_HEADER_FILTER_STARTED_AT
      end
    end
  },
  log = {
    after = function(ctx)
      reports.log()

      if not ctx.KONG_PROXIED then
        return
      end

      -- If response was produced by an upstream (ie, not by a Kong plugin)
      -- Report HTTP status for health checks
      local balancer_data = ctx.balancer_data
      if balancer_data and balancer_data.balancer and balancer_data.ip then
        local ip, port = balancer_data.ip, balancer_data.port

        local status = ngx.status
        if status == 504 then
          balancer_data.balancer.report_timeout(ip, port)
        else
          balancer_data.balancer.report_http_status(ip, port, status)
        end
      end
    end
  }
}
