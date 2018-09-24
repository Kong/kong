-- Kong core
--
-- This consists of local_events that need to
-- be ran at the very beginning and very end of the lua-nginx-module contexts.
-- It mainly carries information related to a request from one context to the next one,
-- through the `ngx.ctx` table.
--
-- In the `access_by_lua` phase, it is responsible for retrieving the route being proxied by
-- a consumer. Then it is responsible for loading the plugins to execute on this request.
local utils       = require "kong.tools.utils"
local Router      = require "kong.core.router"
local ApiRouter   = require "kong.core.api_router"
local reports     = require "kong.core.reports"
local balancer    = require "kong.core.balancer"
local constants   = require "kong.constants"
local responses   = require "kong.tools.responses"
local singletons  = require "kong.singletons"
local certificate = require "kong.core.certificate"
local workspaces = require "kong.workspaces"


local tostring    = tostring
local sub         = string.sub
local lower       = string.lower
local fmt         = string.format
local sort        = table.sort
local ngx         = ngx
local log         = ngx.log
local null        = ngx.null
local ngx_now     = ngx.now
local update_time = ngx.update_time
local unpack      = unpack


local ERR         = ngx.ERR
local DEBUG       = ngx.DEBUG


local CACHE_ROUTER_OPTS = { ttl = 0 }
local EMPTY_T = {}


local router, router_version, router_err
local api_router, api_router_version, api_router_err
local server_header = _KONG._NAME .. "/" .. _KONG._VERSION


local function get_now()
  update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function build_api_router(dao, version)
  local apis, err = dao.apis:find_all()
  if err then
    return nil, "could not load APIs: " .. err
  end

  for i = 1, #apis do
    -- alias since the router expects 'headers' as a map
    if apis[i].hosts then
      apis[i].headers = { host = apis[i].hosts }
    end
  end

  sort(apis, function(api_a, api_b)
    return api_a.created_at < api_b.created_at
  end)

  api_router, err = ApiRouter.new(apis)
  if not api_router then
    return nil, "could not create api router: " .. err
  end

  if version then
    api_router_version = version
  end

  singletons.api_router = api_router

  return true
end


local function build_router(db, version)
  local routes, i = {}, 0
  local routes_iterator = db.routes:each()

  local route, err = routes_iterator()
  while route do
    local service_pk = route.service

    if not service_pk then
      return nil, "route (" .. route.id .. ") is not associated with service"
    end

    local service

    -- TODO: db requests in loop, problem or not
    service, err = db.services:select(service_pk)
    if not service then
      return nil, "could not find service for route (" .. route.id .. "): " .. err
    end

    local r = {
      route   = route,
      service = service,
    }

    if route.hosts ~= null then
      -- TODO: headers should probably be moved to route
      r.headers = {
        host = route.hosts,
      }
    end

    i = i + 1
    routes[i] = r

    route, err = routes_iterator()
  end

  if err then
    return nil, "could not load routes: " .. err
  end

  -- inject internal proxies into the router
  local _, err = singletons.internal_proxies:build_routes(i, routes)
  if err then
    return nil, err
  end

  sort(routes, function(r1, r2)
    r1, r2 = r1.route, r2.route
    if r1.regex_priority == r2.regex_priority then
      return r1.created_at < r2.created_at
    end
    return r1.regex_priority > r2.regex_priority
  end)

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


-- in the table below the `before` and `after` is to indicate when they run:
-- before or after the plugins
return {
  build_router     = build_router,
  build_api_router = build_api_router,

  init_worker = {
    before = function()
      reports.init_worker()

      -- initialize local local_events hooks

      local dao            = singletons.dao
      local cache          = singletons.cache
      local worker_events  = singletons.worker_events
      local cluster_events = singletons.cluster_events


      -- events dispatcher


      worker_events.register(function(data)
        -- invalidate this entity anywhere it is cached if it has a
        -- caching key

        if not data.new_db then
          if not data.schema then
            log(ngx.ERR, "[events] missing schema in crud subscriber")
            return
          end

          local workspaces, err = dao.workspace_entities:find_all({
            entity_id = data.entity[data.schema.primary_key[1]],
            __skip_rbac = true,
          })
          if err then
            log(ngx.ERR, "[events] could not fetch workspaces: ", err)
            return
          end

          local cache_key = dao[data.schema.table]:entity_cache_key(data.entity)
          if cache_key then
            cache:invalidate(cache_key, workspaces)
          end

          if not data.entity then
            log(ngx.ERR, "[events] missing entity in crud subscriber")
            return
          end

          -- invalidate this entity anywhere it is cached if it has a
          -- caching key

          local cache_key = dao[data.schema.table]:entity_cache_key(data.entity)
          if cache_key then
            cache:invalidate(cache_key, workspaces)
          end

          -- if we had an update, but the cache key was part of what was updated,
          -- we need to invalidate the previous entity as well

          if data.old_entity then
            cache_key = dao[data.schema.table]:entity_cache_key(data.old_entity)
            if cache_key then
              cache:invalidate(cache_key, workspaces)
            end
          end

          if not data.operation then
            log(ngx.ERR, "[events] missing operation in crud subscriber")
            return
          end
        end

        -- new DB module and old DAO: public worker events propagation

        local entity_channel           = data.schema.table or data.schema.name
        local entity_operation_channel = fmt("%s:%s", data.schema.table,
                                             data.operation)

        -- crud:routes
        local ok, err = worker_events.post_local("crud", entity_channel, data)
        if not ok then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end

        -- crud:routes:create
        ok, err = worker_events.post_local("crud", entity_operation_channel, data)
        if not ok then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end
      end, "dao:crud")


      -- local events (same worker)

      worker_events.register(function()
        log(DEBUG, "[events] API updated, invalidating API router")
        cache:invalidate("api_router:version")
      end, "crud", "apis")


      worker_events.register(function()
        log(DEBUG, "[events] Route updated, invalidating router")
        cache:invalidate("router:version")
      end, "crud", "routes")


      worker_events.register(function(data)
        -- assume an update doesnt also change the whole entity!
        if data.operation ~= "update" then
          log(DEBUG, "[events] Plugin updated, invalidating plugin map")
          cache:invalidate("plugins_map:version")
        end
      end, "crud", "plugins")


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


      -- SSL certs / SNIs invalidations


      worker_events.register(function(data)
        log(DEBUG, "[events] SNI updated, invalidating cached certificates")
        local sni = data.entity

        cache:invalidate("pem_ssl_certificates:"    .. sni.name)
        cache:invalidate("parsed_ssl_certificates:" .. sni.name)
      end, "crud", "ssl_servers_names")


      worker_events.register(function(data)
        log(DEBUG, "[events] SSL cert updated, invalidating cached certificates")
        local certificate = data.entity

        local rows, err = dao.ssl_servers_names:find_all {
          ssl_certificate_id = certificate.id
        }
        if not rows then
          log(ERR, "[events] could not find associated SNIs for certificate: ",
                   err)
        end

        for i = 1, #rows do
          local sni = rows[i]

          cache:invalidate("pem_ssl_certificates:"    .. sni.name)
          cache:invalidate("parsed_ssl_certificates:" .. sni.name)
        end
      end, "crud", "ssl_certificates")


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
        local key = fmt("%s:%s", operation, target.upstream_id)
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
            upstream_id = key,
          }
        })
        if not ok then
          log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
        end
      end)


      -- manual health updates
      cluster_events:subscribe("balancer:post_health", function(data)
        local ip, port, health, name = data:match("([^|]+)|([^|]+)|([^|]+)|(.*)")
        port = tonumber(port)
        local upstream = { name = name }
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

      worker_events.register(function(data)
        log(DEBUG, "[events] workspace_entites updated, invalidating API workspace scope")
        local target = data.entity
        if target.entity_type == "apis" or target.entity_type == "routes" then
          local ws_scope_key = fmt("apis_ws_resolution:%s", target.entity_id)
          cache:invalidate(ws_scope_key)
        end
      end, "crud", "workspace_entities")

      -- initialize balancers for active healthchecks
      ngx.timer.at(0, function()
        balancer.init()
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
    end,
    after = function (ctx)
      ctx.KONG_REWRITE_TIME = get_now() - ctx.KONG_REWRITE_START -- time spent in Kong's rewrite_by_lua
    end
  },
  access = {
    before = function(ctx)
      -- ensure routers are up-to-date
      local cache = singletons.cache

      -- router for APIs (legacy)

      local version, err = cache:get("api_router:version", CACHE_ROUTER_OPTS, utils.uuid)
      if err then
        log(ngx.CRIT, "could not ensure API router is up to date: ", err)

      elseif api_router_version ~= version then
        log(DEBUG, "rebuilding API router")

        local ok, err = build_api_router(singletons.dao, version)
        if not ok then
          api_router_err = err
          log(ngx.CRIT, "could not rebuild API router: ", err)
        end
      end

      if not api_router then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("no API router to " ..
                  "route request (reason: " .. tostring(api_router_err) .. ")")
      end

      -- router for Routes/Services

      local version, err = cache:get("router:version", CACHE_ROUTER_OPTS, utils.uuid)
      if err then
        log(ngx.CRIT, "could not ensure router is up to date: ", err)

      elseif router_version ~= version then
        -- router needs to be rebuilt in this worker
        log(DEBUG, "rebuilding router")

        local ok, err = build_router(singletons.db, version)
        if not ok then
          router_err = err
          log(ngx.CRIT, "could not rebuild router: ", err)
        end
      end

      if not router then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("no router to " ..
                  "route request (reason: " .. tostring(router_err) .. ")")
      end

      -- routing request

      local var = ngx.var

      ctx.KONG_ACCESS_START = get_now()

      local match_t = router.exec(ngx)
      if not match_t then
        match_t = api_router.exec(ngx)
        if not match_t then
          return responses.send_HTTP_NOT_FOUND("no route and no API found with those values")
        end
      end

      local api                = match_t.api or EMPTY_T
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

      local trusted_ip = singletons.ip.trusted(realip_remote_addr)
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
      or (api.https_only and not utils.check_https(trusted_ip,
                                                   api.http_if_terminated))
      then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.2, HTTP/1.1"
        return responses.send(426, "Please use HTTPS protocol")
      end

      local balancer_address = {
        type                 = upstream_url_t.type,  -- the type of `host`; ipv4, ipv6 or name
        host                 = upstream_url_t.host,  -- target host per `upstream_url`
        port                 = upstream_url_t.port,  -- final target port
        try_count            = 0,                    -- retry counter
        tries                = {},                   -- stores info per try
        -- ip                = nil,                  -- final target IP address
        -- balancer          = nil,                  -- the balancer object, in case of a balancer
        -- hostname          = nil,                  -- the hostname belonging to the final target IP
      }

      -- TODO: this is probably not optimal
      do
        local retries = service.retries or api.retries
        if retries ~= null then
          balancer_address.retries = retries

        else
          balancer_address.retries = 5
        end

        local connect_timeout = service.connect_timeout or
                                api.upstream_connect_timeout
        if connect_timeout ~= null then
          balancer_address.connect_timeout = connect_timeout

        else
          balancer_address.connect_timeout = 60000
        end

        local send_timeout = service.write_timeout or
                             api.upstream_send_timeout
        if send_timeout ~= null then
          balancer_address.send_timeout = send_timeout

        else
          balancer_address.send_timeout = 60000
        end

        local read_timeout = service.read_timeout or
                             api.upstream_read_timeout
        if read_timeout ~= null then
          balancer_address.read_timeout = read_timeout

        else
          balancer_address.read_timeout = 60000
        end
      end

      -- TODO: this needs to be removed when references to ctx.api are removed
      ctx.api              = api
      ctx.service          = service
      ctx.route            = route
      ctx.router_matches   = match_t.matches
      ctx.balancer_address = balancer_address

      -- Add internal flag to requests which communicate through the internal
      -- proxies to reduce repeated lookups throughout the codebase
      local internal_proxies = singletons.internal_proxies
      if ctx.service and internal_proxies:has_service(ctx.service.id) then
        ctx.is_internal = true
      end

      -- `scheme` is the scheme to use for the upstream call
      -- `uri` is the URI with which to call upstream, as returned by the
      --       router, which might have truncated it (`strip_uri`).
      -- `host` is the original header to be preserved if set.
      var.upstream_scheme = match_t.upstream_scheme
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

      local err
      ctx.workspaces, err = workspaces.resolve_ws_scope(ctx, route.protocols and route or api)
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("failed to retrieve workspace " ..
          "for the request (reason: " .. tostring(err) .. ")")
      end
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

      local ok, err, errcode = balancer.execute(ctx.balancer_address)
      if not ok then
        if errcode == 500 then
          err = "failed the initial dns/balancer resolve for '" ..
                ctx.balancer_address.host .. "' with: "         ..
                tostring(err)
        end
        return responses.send(errcode, err)
      end

      do
        -- set the upstream host header if not `preserve_host`
        local upstream_host = var.upstream_host

        if not upstream_host or upstream_host == "" then
          local addr = ctx.balancer_address
          upstream_host = addr.hostname

          local upstream_scheme = var.upstream_scheme
          if upstream_scheme == "http"  and addr.port ~= 80 or
             upstream_scheme == "https" and addr.port ~= 443
          then
            upstream_host = upstream_host .. ":" .. addr.port
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
    before = function()
      local addr = ngx.ctx.balancer_address
      local current_try = addr.tries[addr.try_count]
      current_try.balancer_start = get_now()
    end,
    after = function ()
      local ctx = ngx.ctx
      local addr = ctx.balancer_address
      local current_try = addr.tries[addr.try_count]

      -- record try-latency
      local try_latency = get_now() - current_try.balancer_start
      current_try.balancer_latency = try_latency

      -- record overall latency
      ctx.KONG_BALANCER_TIME = (ctx.KONG_BALANCER_TIME or 0) + try_latency
    end
  },
  header_filter = {
    before = function(ctx)
      if ctx.KONG_PROXIED then
        local now = get_now()
        -- time spent waiting for a response from upstream
        ctx.KONG_WAITING_TIME             = now - ctx.KONG_ACCESS_ENDED_AT
        ctx.KONG_HEADER_FILTER_STARTED_AT = now
      end
    end,
    after = function(ctx)
      local header = ngx.header

      if ctx.KONG_PROXIED then
        if singletons.configuration.latency_tokens then
          header[constants.HEADERS.UPSTREAM_LATENCY] = ctx.KONG_WAITING_TIME
          header[constants.HEADERS.PROXY_LATENCY]    = ctx.KONG_PROXY_LATENCY
        end

        if singletons.configuration.server_tokens then
          header["Via"] = server_header
        end

      else
        if singletons.configuration.server_tokens then
          header["Server"] = server_header

        else
          header["Server"] = nil
        end
      end
    end
  },
  body_filter = {
    after = function(ctx)
      if ngx.arg[2] then
        local now = get_now()
        ctx.KONG_BODY_FILTER_ENDED_AT = now
        if ctx.KONG_PROXIED then
          -- time spent receiving the response (header_filter + body_filter)
          -- we could use $upstream_response_time but we need to distinguish the waiting time
          -- from the receiving time in our logging plugins (especially ALF serializer).
          ctx.KONG_RECEIVE_TIME = now - ctx.KONG_HEADER_FILTER_STARTED_AT
        end
      end
    end
  },
  log = {
    after = function(ctx)
      reports.log()
      local addr = ctx.balancer_address

      -- If response was produced by an upstream (ie, not by a Kong plugin)
      if ctx.KONG_PROXIED == true then
        -- Report HTTP status for health checks
        if addr and addr.balancer and addr.ip then
          local ip, port = addr.ip, addr.port
          local status = ngx.status
          if status == 504 then
            addr.balancer.report_timeout(ip, port)
          else
            addr.balancer.report_http_status(ip, port, status)
          end
        end
      end
    end
  }
}
