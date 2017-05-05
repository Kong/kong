-- Kong core
--
-- This consists of events that need to
-- be ran at the very beginning and very end of the lua-nginx-module contexts.
-- It mainly carries information related to a request from one context to the next one,
-- through the `ngx.ctx` table.
--
-- In the `access_by_lua` phase, it is responsible for retrieving the API being proxied by
-- a Consumer. Then it is responsible for loading the plugins to execute on this request.
local utils = require "kong.tools.utils"
local Router = require "kong.core.router"
local reports = require "kong.core.reports"
local cluster = require "kong.core.cluster"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local certificate = require "kong.core.certificate"
local balancer_execute = require("kong.core.balancer").execute


local router, router_err
local ngx_now = ngx.now
local server_header = _KONG._NAME.."/".._KONG._VERSION


local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


-- in the table below the `before` and `after` is to indicate when they run:
-- before or after the plugins
return {
  build_router = function()
    local apis

    apis, router_err = singletons.dao.apis:find_all()
    if router_err then
      return nil, "could not load APIs: " .. router_err
    end

    for i = 1, #apis do
      -- alias since the router expects 'headers'
      -- as a map
      if apis[i].hosts then
        apis[i].headers = { host = apis[i].hosts }
      end
    end

    router, router_err = Router.new(apis)
    if not router then
      return nil, "could not create router: " .. router_err
    end

    return true
  end,

  init_worker = {
    before = function()
      reports.init_worker()
      cluster.init_worker()
    end
  },
  certificate = {
    before = function()
      certificate.execute()
    end
  },
  rewrite = {
    before = function()
      ngx.ctx.KONG_REWRITE_START = get_now()
    end,
    after = function ()
      local ctx = ngx.ctx
      ctx.KONG_REWRITE_TIME = get_now() - ctx.KONG_REWRITE_START -- time spent in Kong's rewrite_by_lua
    end
  },
  access = {
    before = function()
      if not router then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(
          "no router to route request (reason: " .. tostring(router_err) .. ")"
        )
      end

      local ctx = ngx.ctx
      local var = ngx.var

      ctx.KONG_ACCESS_START = get_now()

      local api, upstream, host_header = router.exec(ngx)
      if not api then
        return responses.send_HTTP_NOT_FOUND("no API found with those values")
      end

      if api.https_only and not utils.check_https(api.http_if_terminated) then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.2, HTTP/1.1"

        return responses.send(426, "Please use HTTPS protocol")
      end

      local balancer_address = {
        type                 = utils.hostname_type(upstream.host),  -- the type of `host`; ipv4, ipv6 or name
        host                 = upstream.host,  -- target host per `upstream_url`
        port                 = upstream.port,  -- final target port
        try_count            = 0,              -- retry counter
        tries                = {},             -- stores info per try
        retries              = api.retries,    -- number of retries for the balancer
        connect_timeout      = api.upstream_connect_timeout or 60000,
        send_timeout         = api.upstream_send_timeout or 60000,
        read_timeout         = api.upstream_read_timeout or 60000,
        -- ip                = nil,            -- final target IP address
        -- failures          = nil,            -- for each failure an entry { name = "...", code = xx }
        -- balancer          = nil,            -- the balancer object, in case of a balancer
        -- hostname          = nil,            -- the hostname belonging to the final target IP
      }

      var.upstream_scheme = upstream.scheme

      ctx.api              = api
      ctx.balancer_address = balancer_address

      local ok, err = balancer_execute(balancer_address)
      if not ok then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("failed the initial "..
          "dns/balancer resolve for '"..balancer_address.host..
          "' with: "..tostring(err))
      end

      -- if set `host_header` is the original header to be preserved
      var.upstream_host = host_header or
          balancer_address.hostname..":"..balancer_address.port

    end,
    -- Only executed if the `router` module found an API and allows nginx to proxy it.
    after = function()
      local ctx = ngx.ctx
      local now = get_now()

      ctx.KONG_ACCESS_TIME = now - ctx.KONG_ACCESS_START -- time spent in Kong's access_by_lua
      ctx.KONG_ACCESS_ENDED_AT = now
      -- time spent in Kong before sending the reqeust to upstream
      ctx.KONG_PROXY_LATENCY = now - ngx.req.start_time() * 1000 -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ctx.KONG_PROXIED = true
    end
  },
  header_filter = {
    before = function()
      local ctx = ngx.ctx

      if ctx.KONG_PROXIED then
        local now = get_now()
        ctx.KONG_WAITING_TIME = now - ctx.KONG_ACCESS_ENDED_AT -- time spent waiting for a response from upstream
        ctx.KONG_HEADER_FILTER_STARTED_AT = now
      end
    end,
    after = function()
      local ctx, header = ngx.ctx, ngx.header

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
    after = function()
      if ngx.arg[2] and ngx.ctx.KONG_PROXIED then
        -- time spent receiving the response (header_filter + body_filter)
        -- we could uyse $upstream_response_time but we need to distinguish the waiting time
        -- from the receiving time in our logging plugins (especially ALF serializer).
        ngx.ctx.KONG_RECEIVE_TIME = get_now() - ngx.ctx.KONG_HEADER_FILTER_STARTED_AT
      end
    end
  },
  log = {
    after = function()
      reports.log()
    end
  }
}
