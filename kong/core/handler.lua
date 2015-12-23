-- Kong core
--
-- This consists of events than need to
-- be ran at the very beginning and very end of the lua-nginx-module contexts.
-- It mainly carries information related to a request from one context to the next one,
-- through the `ngx.ctx` table.
--
-- In the `access_by_lua` phase, it is responsible for retrieving the API being proxied by
-- a Consumer. Then it is responsible for loading the plugins to execute on this request.
--
-- In other phases, we create different variables and timers.
-- Variables:
--   `plugins_to_execute`: an array of plugin to be executed for this request.
-- Timers:
--   `KONG_<CONTEXT_NAME>_STARTED_AT`: time at which a given context is started to be executed by all Kong plugins.
--   `KONG_<CONTEXT_NAME>_ENDED_AT`: time at which all plugins have been executed by Kong for this context.
--   `KONG_<CONTEXT_NAME>_TIME`: time taken by Kong to execute all the plugins for this context
--
-- @see https://github.com/openresty/lua-nginx-module#ngxctx

local utils = require "kong.tools.utils"
local reports = require "kong.core.reports"
local resolver = require "kong.core.resolver"
local constants = require "kong.constants"
local certificate = require "kong.core.certificate"

local ngx_now = ngx.now

local function get_now()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end

return {
  init_worker = function()
    reports.init_worker()
  end,
  certificate = function()
    ngx.ctx.api = certificate.execute()
  end,
  access = {
    before = function()
      ngx.ctx.KONG_ACCESS_START = get_now()
      ngx.ctx.api, ngx.ctx.upstream_url, ngx.var.upstream_host = resolver.execute(ngx.var.request_uri, ngx.req.get_headers())
    end,
    -- Only executed if the `resolver` module found an API and allows nginx to proxy it.
    after = function()
      -- Append any querystring parameters modified during plugins execution
      local upstream_url = ngx.ctx.upstream_url
      local uri_args = ngx.req.get_uri_args()
      if utils.table_size(uri_args) > 0 then
        upstream_url = upstream_url.."?"..utils.encode_args(uri_args)
      end

      -- Set the `$upstream_url` and `$upstream_host` variables for the `proxy_pass` nginx
      -- directive in kong.yml.
      ngx.var.upstream_url = upstream_url

      local now = get_now()
      ngx.ctx.KONG_ACCESS_TIME = now - ngx.ctx.KONG_ACCESS_START -- time spent in Kong's access_by_lua
      ngx.ctx.KONG_ACCESS_ENDED_AT = now
      -- time spent in Kong before sending the reqeust to upstream
      ngx.ctx.KONG_PROXY_LATENCY = now - ngx.req.start_time() * 1000 -- ngx.req.start_time() is kept in seconds with millisecond resolution.
      ngx.ctx.KONG_PROXIED = true
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
        ngx.header["Via"] = constants.NAME.."/"..constants.VERSION
      else
        ngx.header["Server"] = constants.NAME.."/"..constants.VERSION
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
  log = function()
    reports.log()
  end
}
