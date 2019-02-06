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
local singletons  = require "kong.singletons"
local certificate = require "kong.runloop.certificate"
local concurrency = require "kong.concurrency"


local kong        = kong
local ipairs      = ipairs
local tostring    = tostring
local tonumber    = tonumber
local sub         = string.sub
local find        = string.find
local lower       = string.lower
local fmt         = string.format
local sort        = table.sort
local ngx         = ngx
local log         = ngx.log
local ngx_now     = ngx.now
local re_match    = ngx.re.match
local re_find     = ngx.re.find
local update_time = ngx.update_time
local subsystem   = ngx.config.subsystem
local unpack      = unpack


local ERR         = ngx.ERR
local WARN        = ngx.WARN
local DEBUG       = ngx.DEBUG


local CACHE_ROUTER_OPTS = { ttl = 0 }
local SUBSYSTEMS = constants.PROTOCOLS_WITH_SUBSYSTEM
local EMPTY_T = {}



local get_router, build_router
local server_header = meta._SERVER_TOKENS
local _set_check_router_rebuild

local build_router_timeout


local function get_now()
  update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


do
  -- Given a protocol, return the subsystem that handles it
  local router
  local router_version

  local function should_process_route(route)
    for _, protocol in ipairs(route.protocols) do
      if SUBSYSTEMS[protocol] == subsystem then
        return true
      end
    end

    return false
  end

  local function get_service_for_route(db, route)
    local service_pk = route.service
    if not service_pk then
      return nil
    end

    local service, err = db.services:select(service_pk)
    if not service then
      return nil, "could not find service for route (" .. route.id .. "): " ..
                  err
    end

    -- TODO: this should not be needed as the schema should check it already
    if SUBSYSTEMS[service.protocol] ~= subsystem then
      log(WARN, "service with protocol '", service.protocol,
                "' cannot be used with '", subsystem, "' subsystem")

      return nil
    end

    return service
  end

  build_router = function(db, version)
    local routes, i = {}, 0

    for route, err in db.routes:each(1000) do
      if err then
        return nil, "could not load routes: " .. err
      end

      if should_process_route(route) then
        local service, err = get_service_for_route(db, route)
        if err then
          return nil, err
        end

        local r = {
          route   = route,
          service = service,
        }

        local service_subsystem
        if service then
          service_subsystem = SUBSYSTEMS[service.protocol]
        else
          service_subsystem = subsystem
        end

        if service_subsystem == "http" and route.hosts then
          -- TODO: headers should probably be moved to route
          r.headers = {
            host = route.hosts,
          }
        end

        i = i + 1
        routes[i] = r
      end
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

    local err
    router, err = Router.new(routes)
    if not router then
      return nil, "could not create router: " .. err
    end

    if version then
      router_version = version
    end

    singletons.router = router

    return true
  end


  local function check_router_rebuild()
    -- we might not need to rebuild the router (if we were not
    -- the first request in this process to enter this code path)
    -- check again and rebuild only if necessary
    local version, err = singletons.cache:get("router:version",
                                              CACHE_ROUTER_OPTS,
                                              utils.uuid)
    if err then
      log(ngx.CRIT, "could not ensure router is up to date: ", err)
      return nil, err
    end

    if version == router_version then
      return true
    end

    -- router needs to be rebuilt in this worker
    log(DEBUG, "rebuilding router")

    local ok, err = build_router(singletons.db, version)
    if not ok then
      log(ngx.CRIT, "could not rebuild router: ", err)
      return nil, err
    end

    return true
  end


  -- for unit-testing purposes only
  _set_check_router_rebuild = function(f)
    check_router_rebuild = f
  end


  get_router = function()
    local version, err = singletons.cache:get("router:version",
                                              CACHE_ROUTER_OPTS,
                                              utils.uuid)
    if err then
      log(ngx.CRIT, "could not ensure router is up to date: ", err)
      return nil, err
    end

    if version == router_version then
      return router
    end

    -- wrap router rebuilds in a per-worker mutex:
    -- this prevents dogpiling the database during rebuilds in
    -- high-concurrency traffic patterns;
    -- requests that arrive on this process during a router rebuild will be
    -- queued. once the lock is acquired we re-check the
    -- router version again to prevent unnecessary subsequent rebuilds

    local opts = {
      name = "build_router",
      timeout = build_router_timeout,
      on_timeout = "run_unlocked",
    }
    local ok, err = concurrency.with_coroutine_mutex(opts, check_router_rebuild)

    if not ok then
      return nil, err
    end

    return router
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

  do
    local s = service or EMPTY_T

    balancer_data.retries         = s.retries         or 5
    balancer_data.connect_timeout = s.connect_timeout or 60000
    balancer_data.send_timeout    = s.write_timeout   or 60000
    balancer_data.read_timeout    = s.read_timeout    or 60000
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
  build_router = build_router,

  -- exported for unit-testing purposes only
  _set_check_router_rebuild = _set_check_router_rebuild,

  init_worker = {
    before = function()
      reports.init_worker()

      -- initialize local local_events hooks
      local db             = singletons.db
      local cache          = singletons.cache
      local worker_events  = singletons.worker_events
      local cluster_events = singletons.cluster_events


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
        local _, err = worker_events.post("balancer", "targets", {
          operation = data.operation,
          entity = data.entity,
        })
        if err then
          log(ERR, "failed broadcasting target ",
              operation, " to workers: ", err)
        end
        -- => to cluster_events handler
        local key = fmt("%s:%s", operation, target.upstream.id)
        _, err = cluster_events:broadcast("balancer:targets", key)
        if err then
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
        local _, err = worker_events.post("balancer", "targets", {
          operation = operation,
          entity = {
            upstream = { id = key },
          }
        })
        if err then
          log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
        end
      end)


      -- manual health updates
      cluster_events:subscribe("balancer:post_health", function(data)
        local pattern = "([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)"
        local ip, port, health, id, name = data:match(pattern)
        port = tonumber(port)
        local upstream = { id = id, name = name }
        local _, err = balancer.post_health(upstream, ip, port, health == "1")
        if err then
          log(ERR, "failed posting health of ", name, " to workers: ", err)
        end
      end)


      -- upstream updates


      -- worker_events local handler: event received from DAO
      worker_events.register(function(data)
        local operation = data.operation
        local upstream = data.entity
        -- => to worker_events node handler
        local _, err = worker_events.post("balancer", "upstreams", {
          operation = data.operation,
          entity = data.entity,
        })
        if err then
          log(ERR, "failed broadcasting upstream ",
              operation, " to workers: ", err)
        end
        -- => to cluster_events handler
        local key = fmt("%s:%s:%s", operation, upstream.id, upstream.name)
        local ok, err = cluster_events:broadcast("balancer:upstreams", key)
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
        local _, err = worker_events.post("balancer", "upstreams", {
          operation = operation,
          entity = {
            id = id,
            name = name,
          }
        })
        if err then
          log(ERR, "failed broadcasting upstream ", operation, " to workers: ", err)
        end
      end)


      -- initialize balancers for active healthchecks
      ngx.timer.at(0, function()
        balancer.init()
      end)


      do
        build_router_timeout = 60
        if singletons.configuration.database == "cassandra" then
          -- cassandra_timeout is defined in ms
          build_router_timeout = kong.configuration.cassandra_timeout / 1000

        elseif singletons.configuration.database == "postgres" then
          -- pg_timeout is defined in ms
          build_router_timeout = kong.configuration.pg_timeout / 1000
        end
      end
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

      local route = match_t.route
      local service = match_t.service
      local upstream_url_t = match_t.upstream_url_t

      if not service then
        -----------------------------------------------------------------------
        -- Serviceless stream route
        -----------------------------------------------------------------------
        local service_scheme = ssl_termination_ctx and "tls" or "tcp"
        local service_host   = var.server_addr

        match_t.upstream_scheme = service_scheme
        upstream_url_t.scheme = service_scheme -- for completeness
        upstream_url_t.type = utils.hostname_type(service_host)
        upstream_url_t.host = service_host
        upstream_url_t.port = tonumber(var.server_port, 10)
      end

      balancer_setup_stage1(ctx, match_t.upstream_scheme,
                            upstream_url_t.type,
                            upstream_url_t.host,
                            upstream_url_t.port,
                            service, route)
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

      local scheme         = var.scheme
      local host           = var.host
      local port           = tonumber(var.server_port, 10)

      local route          = match_t.route
      local service        = match_t.service
      local upstream_url_t = match_t.upstream_url_t

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
        forwarded_proto = var.http_x_forwarded_proto or scheme
        forwarded_host  = var.http_x_forwarded_host  or host
        forwarded_port  = var.http_x_forwarded_port  or port

      else
        forwarded_proto = scheme
        forwarded_host  = host
        forwarded_port  = port
      end

      local protocols = route.protocols
      if (protocols and protocols.https and not protocols.http and
          forwarded_proto ~= "https")
      then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.2, HTTP/1.1"
        return kong.response.exit(426, { message = "Please use HTTPS protocol" })
      end

      if not service then
        -----------------------------------------------------------------------
        -- Serviceless HTTP / HTTPS / HTTP2 route
        -----------------------------------------------------------------------
        local service_scheme
        local service_host
        local service_port

        -- 1. try to find information from a request-line
        local request_line = var.request
        if request_line then
          local matches, err = re_match(request_line, [[\w+ (https?)://([^/?#\s]+)]], "ajos")
          if err then
            log(WARN, "pcre runtime error when matching a request-line: ", err)

          elseif matches then
            local uri_scheme = lower(matches[1])
            if uri_scheme == "https" or uri_scheme == "http" then
              service_scheme = uri_scheme
              service_host   = lower(matches[2])
            end
            --[[ TODO: check if these make sense here?
            elseif uri_scheme == "wss" then
              service_scheme = "https"
              service_host   = lower(matches[2])
            elseif uri_scheme == "ws" then
              service_scheme = "http"
              service_host   = lower(matches[2])
            end
            --]]
          end
        end

        -- 2. try to find information from a host header
        if not service_host then
          local http_host = var.http_host
          if http_host then
            service_scheme = scheme
            service_host   = lower(http_host)
          end
        end

        -- 3. split host to host and port
        if service_host then
          -- remove possible userinfo
          local pos = find(service_host, "@", 1, true)
          if pos then
            service_host = sub(service_host, pos + 1)
          end

          pos = find(service_host, ":", 2, true)
          if pos then
            service_port = sub(service_host, pos + 1)
            service_host = sub(service_host, 1, pos - 1)

            local found, _, err = re_find(service_port, [[[1-9]{1}\d{0,4}$]], "adjo")
            if err then
              log(WARN, "pcre runtime error when matching a port number: ", err)

            elseif found then
              service_port = tonumber(service_port, 10)
              if not service_port or service_port > 65535 then
                service_scheme = nil
                service_host   = nil
                service_port   = nil
              end

            else
              service_scheme = nil
              service_host   = nil
              service_port   = nil
            end
          end
        end

        -- 4. use known defaults
        if service_host and not service_port then
          if service_scheme == "http" then
            service_port = 80
          elseif service_scheme == "https" then
            service_port = 443
          else
            service_port = port
          end
        end

        -- 5. fall-back to server address
        if not service_host then
          service_scheme = scheme
          service_host   = var.server_addr
          service_port   = port
        end

        match_t.upstream_scheme = service_scheme
        upstream_url_t.scheme = service_scheme -- for completeness
        upstream_url_t.type = utils.hostname_type(service_host)
        upstream_url_t.host = service_host
        upstream_url_t.port = service_port
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
      if singletons.configuration.enabled_headers[upstream_status_header] then
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
        log(WARN, "failed to set the cookie for hash-based load balancing: ", err,
                  " (key=", hash_cookie.key,
                  ", path=", hash_cookie.path, ")")
      end
    end,
    after = function(ctx)
      local header = ngx.header

      if ctx.KONG_PROXIED then
        if singletons.configuration.enabled_headers[constants.HEADERS.UPSTREAM_LATENCY] then
          header[constants.HEADERS.UPSTREAM_LATENCY] = ctx.KONG_WAITING_TIME
        end

        if singletons.configuration.enabled_headers[constants.HEADERS.PROXY_LATENCY] then
          header[constants.HEADERS.PROXY_LATENCY] = ctx.KONG_PROXY_LATENCY
        end

        if singletons.configuration.enabled_headers[constants.HEADERS.VIA] then
          header[constants.HEADERS.VIA] = server_header
        end

      else
        if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
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
