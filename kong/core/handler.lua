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
local stringy = require "stringy"
local resolver = require "kong.core.resolver"
local constants = require "kong.constants"
local certificate = require "kong.core.certificate"

local table_insert = table.insert
local math_floor = math.floor
local unpack = unpack
local ipairs = ipairs

local MULT = 10^3
local function round(num)
  return math_floor(num * MULT + 0.5) / MULT
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
      ngx.ctx.KONG_ACCESS_START = ngx.now()
      ngx.ctx.api, ngx.ctx.upstream_url, ngx.ctx.upstream_host = resolver.execute(ngx.var.request_uri, ngx.req.get_headers())
    end,
    -- Only executed if the `resolver` module found an API and allows nginx to proxy it.
    after = function()
      local now = ngx.now()
      ngx.ctx.KONG_ACCESS_TIME = now - ngx.ctx.KONG_ACCESS_START
      ngx.ctx.KONG_ACCESS_ENDED_AT = now
      ngx.ctx.KONG_PROXIED = true

      -- Append any querystring parameters modified during plugins execution
      local upstream_url = unpack(stringy.split(ngx.ctx.upstream_url, "?"))
      if utils.table_size(ngx.req.get_uri_args()) > 0 then
        upstream_url = upstream_url.."?"..ngx.encode_args(ngx.req.get_uri_args())
      end

      -- Set the `$upstream_url` and `$upstream_host` variables for the `proxy_pass` nginx
      -- directive in kong.yml.
      ngx.var.upstream_url = upstream_url
      ngx.var.upstream_host = ngx.ctx.upstream_host
    end
  },
  header_filter = {
    before = function()
      if ngx.ctx.KONG_PROXIED then
        ngx.ctx.KONG_HEADER_FILTER_STARTED_AT = ngx.now()
      end
    end,
    after = function()
      if ngx.ctx.KONG_PROXIED then
        local now = ngx.now()
        local proxy_started_at = ngx.ctx.KONG_ACCESS_ENDED_AT
        local proxy_ended_at = ngx.ctx.KONG_HEADER_FILTER_STARTED_AT
        local upstream_response_time = round(proxy_ended_at - proxy_started_at)
        local proxy_time = round(now - ngx.req.start_time() - upstream_response_time)

        ngx.ctx.KONG_HEADER_FILTER_TIME = now - ngx.ctx.KONG_HEADER_FILTER_STARTED_AT
        ngx.header[constants.HEADERS.UPSTREAM_LATENCY] = upstream_response_time * 1000 -- ms
        ngx.header[constants.HEADERS.PROXY_LATENCY] = proxy_time * 1000 -- ms
        ngx.header["Via"] = constants.NAME.."/"..constants.VERSION
      else
        ngx.header["Server"] = constants.NAME.."/"..constants.VERSION
      end
    end
  },
  -- `body_filter_by_lua` can be executed mutiple times depending on the size of the
  -- response body.
  -- To compute the time spent in Kong, we keep an array of size n,
  -- n being the number of times the directive ran:
  -- starts = {4312, 5423, 4532}
  -- ends = {4320, 5430, 4550}
  -- time = 8 + 7 + 18 = 33 = total time spent in `body_filter` in all plugins
  body_filter = {
    before = function()
      if ngx.ctx.KONG_BODY_FILTER_STARTS == nil then
        ngx.ctx.KONG_BODY_FILTER_STARTS = {}
        ngx.ctx.KONG_BODY_FILTER_EDINGS = {}
      end
      table_insert(ngx.ctx.KONG_BODY_FILTER_STARTS, ngx.now())
    end,
    after = function()
      table_insert(ngx.ctx.KONG_BODY_FILTER_EDINGS, ngx.now())

      if ngx.arg[2] then
        -- compute time spent in Kong's body_filters
        local total_time = 0
        for i in ipairs(ngx.ctx.KONG_BODY_FILTER_EDINGS) do
          total_time = total_time + (ngx.ctx.KONG_BODY_FILTER_EDINGS[i] - ngx.ctx.KONG_BODY_FILTER_STARTS[i])
        end
        ngx.ctx.KONG_BODY_FILTER_TIME = total_time
        ngx.ctx.KONG_BODY_FILTER_STARTS = nil
        ngx.ctx.KONG_BODY_FILTER_EDINGS = nil
      end
    end
  },
  log = function()
    reports.log()
  end
}
