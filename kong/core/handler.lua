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


local router
local ngx_now = ngx.now
local server_header = _KONG._NAME.."/".._KONG._VERSION


local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function build_router()
  local apis, err = singletons.dao.apis:find_all()
  if err then
    ngx.log(ngx.CRIT, "[router] could not load APIs: ", err)
    return
  end

  for i = 1, #apis do
    -- alias since the router expects 'headers'
    -- as a map
    if apis[i].hosts then
      apis[i].headers = { host = apis[i].hosts }
    end
  end

  router, err = Router.new(apis)
  if not router then
    ngx.log(ngx.CRIT, "[router] could not create router: ", err)
    return
  end
end


-- in the table below the `before` and `after` is to indicate when they run; before or after the plugins
return {
  init_worker = {
    before = function()
      reports.init_worker()
      cluster.init_worker()

      build_router()

      local worker_events = require "resty.worker.events"

      worker_events.register(function(data, event, source, pid)
        if data and data.collection == "apis" then
          --local inspect = require "inspect"
          --print("CHANGE IN APIS DATA: ", source, inspect(event), inspect(source), inspect(data))
          build_router()
        end
      end)
    end
  },
  certificate = {
    before = function()
      certificate.execute()
    end
  },
  access = {
    before = function()
      local ctx = ngx.ctx
      local var = ngx.var

      ctx.KONG_ACCESS_START = get_now()

      local api, upstream_scheme, upstream_host, upstream_port = router.exec(ngx)
      if not api then
        return responses.send_HTTP_NOT_FOUND("no API found")
      end

      if api.https_only and not utils.check_https(api.http_if_terminated) then
        ngx.header["connection"] = "Upgrade"
        ngx.header["upgrade"]    = "TLS/1.0, HTTP/1.1"
        return responses.send(426, "Please use HTTPS protocol")
      end

      local balancer_address = {
        type                 = utils.hostname_type(upstream_host),  -- the type of `upstream.host`; ipv4, ipv6 or name
        host                 = upstream_host,  -- supposed target host
        port                 = upstream_port,  -- final target port
        tries                = 0,              -- retry counter
        retries              = api.retries,    -- number of retries for the balancer
        --  ip               = nil,            -- final target IP address
        -- failures          = nil,            -- for each failure an entry { name = "...", code = xx }
        -- balancer          = nil,            -- the balancer object, in case of a balancer
      }

      var.upstream_scheme = upstream_scheme
      var.upstream_host = upstream_host

      ctx.api = api
      ctx.balancer_address = balancer_address

      local ok, err = balancer_execute(balancer_address)
      if not ok then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("failed the initial "..
          "dns/balancer resolve for '"..balancer_address.upstream.host..
          "' with: "..tostring(err))
      end

      if balancer_address.hostname and not ngx.ctx.api.preserve_host then
        ngx.var.upstream_host = balancer_address.hostname
      else
        ngx.var.upstream_host = upstream_host
      end

    end,
    -- Only executed if the `resolver` module found an API and allows nginx to proxy it.
    after = function()
      local ctx = ngx.ctx

      local now = get_now()
      ctx.KONG_ACCESS_TIME = now - ngx.ctx.KONG_ACCESS_START -- time spent in Kong's access_by_lua
      ctx.KONG_ACCESS_ENDED_AT = now
      -- time spent in Kong before sending the reqeust to upstream
      ctx.KONG_PROXY_LATENCY = now - ngx.req.start_time() * 1000 -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ctx.KONG_PROXIED = true
    end
  },
  header_filter = {
    before = function()
      if ngx.ctx.KONG_PROXIED then
        local now = get_now()
        ngx.ctx.KONG_WAITING_TIME = now - ngx.ctx.KONG_ACCESS_ENDED_AT -- time spent waiting for a response from upstream
        ngx.ctx.KONG_HEADER_FILTER_STARTED_AT = now
      end
    end,
    after = function()
      if ngx.ctx.KONG_PROXIED then
        ngx.header[constants.HEADERS.UPSTREAM_LATENCY] = ngx.ctx.KONG_WAITING_TIME
        ngx.header[constants.HEADERS.PROXY_LATENCY] = ngx.ctx.KONG_PROXY_LATENCY
        ngx.header["Via"] = server_header
      else
        ngx.header["Server"] = server_header
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
