-- Kong core
--
-- This consists of local_events that need to
-- be ran at the very beginning and very end of the lua-nginx-module contexts.
-- It mainly carries information related to a request from one context to the next one,
-- through the `ngx.ctx` table.
--
-- In the `access_by_lua` phase, it is responsible for retrieving the API being proxied by
-- a Consumer. Then it is responsible for loading the plugins to execute on this request.
local utils = require "kong.tools.utils"
local Router = require "kong.core.router"
local reports = require "kong.core.reports"
local balancer = require "kong.core.balancer"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local certificate = require "kong.core.certificate"


local tostring = tostring
local sub      = string.sub
local lower    = string.lower
local fmt      = string.format
local ngx      = ngx
local ERR      = ngx.ERR
local DEBUG    = ngx.DEBUG
local log      = ngx.log
local ngx_now  = ngx.now
local unpack   = unpack


local router, router_err, router_version
local server_header = _KONG._NAME.."/".._KONG._VERSION


local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function build_router(dao, version)
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

  table.sort(apis, function(api_a, api_b)
    return api_a.created_at < api_b.created_at
  end)

  router, err = Router.new(apis)
  if not router then
    return nil, "could not create router: " .. err
  end

  if version then
    router_version = version
  end

  return true
end


-- in the table below the `before` and `after` is to indicate when they run:
-- before or after the plugins
return {
  build_router = build_router,

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

        local cache_key = dao[data.schema.table]:entity_cache_key(data.entity)
        if cache_key then
          cache:invalidate(cache_key)
        end

        -- if we had an update, but the cache key was part of what was updated,
        -- we need to invalidate the previous entity as well

        if data.old_entity then
          cache_key = dao[data.schema.table]:entity_cache_key(data.old_entity)
          if cache_key then
            cache:invalidate(cache_key)
          end
        end

        if not data.operation then
          log(ngx.ERR, "[events] missing operation in crud subscriber")
          return
        end

        local entity_channel           = data.schema.table
        local entity_operation_channel = fmt("%s:%s", data.schema.table,
                                             data.operation)

        -- crud:apis
        local _, err = worker_events.post_local("crud", entity_channel, data)
        if err then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end

        -- crud:apis:create
        _, err = worker_events.post_local("crud", entity_operation_channel, data)
        if err then
          log(ngx.ERR, "[events] could not broadcast crud event: ", err)
          return
        end
      end, "dao:crud")


      -- local events (same worker)


      worker_events.register(function()
        log(DEBUG, "[events] API updated, invalidating router")
        cache:invalidate("router:version")
      end, "crud", "apis")


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


      -- initialize balancers for active healthchecks
      ngx.timer.at(0, function()
        balancer.init()
      end)

    end
  },
  certificate = {
    before = function(ctx)
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

      -- ensure router is up-to-date

      local version, err = singletons.cache:get("router:version", {
        ttl = 0
      }, function() return utils.uuid() end)
      if err then
        log(ngx.CRIT, "could not ensure router is up to date: ", err)

      elseif router_version ~= version then
        -- router needs to be rebuilt in this worker
        log(DEBUG, "rebuilding router")

        local ok, err = build_router(singletons.dao, version)
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
        return responses.send_HTTP_NOT_FOUND("no API found with those values")
      end

      local api = match_t.api
      local upstream_url_t = match_t.upstream_url_t

      local realip_remote_addr = var.realip_remote_addr
      local trusted_ip = singletons.ip.trusted(realip_remote_addr)
      if api.https_only and not utils.check_https(trusted_ip,
                                                  api.http_if_terminated)
      then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.2, HTTP/1.1"
        return responses.send(426, "Please use HTTPS protocol")
      end

      local balancer_address = {
        type                 = utils.hostname_type(upstream_url_t.host),  -- the type of `host`; ipv4, ipv6 or name
        host                 = upstream_url_t.host,  -- target host per `upstream_url`
        port                 = upstream_url_t.port,  -- final target port
        try_count            = 0,              -- retry counter
        tries                = {},             -- stores info per try
        retries              = api.retries,    -- number of retries for the balancer
        connect_timeout      = api.upstream_connect_timeout or 60000,
        send_timeout         = api.upstream_send_timeout or 60000,
        read_timeout         = api.upstream_read_timeout or 60000,
        -- ip                = nil,            -- final target IP address
        -- balancer          = nil,            -- the balancer object, in case of a balancer
        -- hostname          = nil,            -- the hostname belonging to the final target IP
        -- hash_value        = nil,            -- balancer hash (integer)
      }

      ctx.api              = api
      ctx.router_matches   = match_t.matches
      ctx.balancer_address = balancer_address

      -- `scheme` is the scheme to use for the upstream call
      -- `uri` is the URI with which to call upstream, as returned by the
      --       router, which might have truncated it (`strip_uri`).
      -- `host_header` is the original header to be preserved if set.
      var.upstream_scheme = upstream_url_t.scheme
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
      --
      -- We could use $proxy_add_x_forwarded_for, but it does not work properly
      -- with the realip module. The realip module overrides $remote_addr and
      -- it is okay for us to use it in case no X-Forwarded-For header was
      -- present. But in case it was given, we will append the
      -- $realip_remote_addr that contains the IP that was originally in
      -- $remote_addr before realip module overrode that (aka the client that
      -- connected us).

      local http_x_forwarded_for = var.http_x_forwarded_for

      if http_x_forwarded_for then
        var.upstream_x_forwarded_for = http_x_forwarded_for .. ", " ..
                                       realip_remote_addr

      else
        var.upstream_x_forwarded_for = var.remote_addr
      end

      if trusted_ip then
        var.upstream_x_forwarded_proto = var.http_x_forwarded_proto or
                                         var.scheme

        var.upstream_x_forwarded_host  = var.http_x_forwarded_host  or
                                         var.host

        var.upstream_x_forwarded_port  = var.http_x_forwarded_port  or
                                         var.server_port

      else
        var.upstream_x_forwarded_proto = var.scheme
        var.upstream_x_forwarded_host  = var.host
        var.upstream_x_forwarded_port  = var.server_port
      end
    end,
    -- Only executed if the `router` module found an API and allows nginx to proxy it.
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

      ctx.KONG_ACCESS_TIME = now - ctx.KONG_ACCESS_START -- time spent in Kong's access_by_lua
      ctx.KONG_ACCESS_ENDED_AT = now
      -- time spent in Kong before sending the reqeust to upstream
      ctx.KONG_PROXY_LATENCY = now - ngx.req.start_time() * 1000 -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ctx.KONG_PROXIED = true
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
      current_try.balancer_start = nil

      -- record overall latency
      ctx.KONG_BALANCER_TIME = (ctx.KONG_BALANCER_TIME or 0) + try_latency
    end
  },
  header_filter = {
    before = function(ctx)
      if ctx.KONG_PROXIED then
        local now = get_now()
        ctx.KONG_WAITING_TIME = now - ctx.KONG_ACCESS_ENDED_AT -- time spent waiting for a response from upstream
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
      if ngx.arg[2] and ctx.KONG_PROXIED then
        -- time spent receiving the response (header_filter + body_filter)
        -- we could uyse $upstream_response_time but we need to distinguish the waiting time
        -- from the receiving time in our logging plugins (especially ALF serializer).
        ctx.KONG_RECEIVE_TIME = get_now() - ctx.KONG_HEADER_FILTER_STARTED_AT
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
          addr.balancer.report_http_status(addr.ip, addr.port, ngx.status)
        end
      end
    end
  }
}
