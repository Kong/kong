local _M = {}
local _MT = { __index = _M, }


local kong = kong


local traditional = require("kong.router.traditional")
local atc_compat = require("kong.router.atc_compat")
local utils = require("kong.router.utils")
local is_http = ngx.config.subsystem == "http"


local phonehome_statistics
do
  local reports = require("kong.reports")
  local nkeys = require("table.nkeys")
  local empty_table = {}
  -- reuse tables to avoid cost of creating tables and garbage collection
  local protocol_counts = {
    http = 0, -- { "http", "https" },
    stream = 0, -- { "tcp", "tls", "udp" },
    tls_passthrough = 0, -- { "tls_passthrough" },
    grpc = 0, -- { "grpc", "grpcs" },
  }
  local path_handling_counts = {
    v0 = 0,
    v1 = 0,
  }
  local route_report = {
    flavor = "unknown",
    paths_count = 0,
    headers_count = 0,
    total = 0,
    regex_paths_count = 0,
    protocols = protocol_counts,
    path_handling = path_handling_counts,
  }

  local function send_report()
    reports.send("routes", route_report)
  end

  local function traditional_statistics(routes)
    local paths_count = 0
    local headers_count = 0
    local regex_paths_count = 0
    local http = 0
    local stream = 0
    local tls_passthrough = 0
    local grpc = 0
    local v0 = 0
    local v1 = 0
  
    for _, route in ipairs(routes) do
      route = route.route
      local paths = route.paths or empty_table
      local headers = route.headers or empty_table

      paths_count = paths_count + #paths
      headers_count = headers_count + nkeys(headers)
      for _, path in ipairs(paths) do
        if path:sub(1, 1) == "~" then
          regex_paths_count = regex_paths_count + 1
          break
        end
      end

      for _, protocol in ipairs(route.protocols or empty_table) do -- luacheck: ignore 512
        if protocol == "http" or protocol == "https" then
          http = http + 1

        elseif protocol == "tcp" or protocol == "tls" or protocol == "udp" then

          stream = stream + 1

        elseif protocol == "tls_passthrough" then
          tls_passthrough = tls_passthrough + 1

        elseif protocol == "grpc" or protocol == "grpcs" then
          grpc = grpc + 1
        end
        break
      end

      local path_handling = route.path_handling or "v0"
      if path_handling == "v0" then
        v0 = v0 + 1

      elseif path_handling == "v1" then
        v1 = v1 + 1
      end
    end

    route_report.paths_count = paths_count
    route_report.headers_count = headers_count
    route_report.regex_paths_count = regex_paths_count
    protocol_counts.http = http
    protocol_counts.stream = stream
    protocol_counts.tls_passthrough = tls_passthrough
    protocol_counts.grpc = grpc
    path_handling_counts.v0 = v0
    path_handling_counts.v1 = v1
  end

  function phonehome_statistics(routes)
    if not kong.configuration.anonymous_reports or ngx.worker.id() ~= 0 or
      ngx.get_phase() == "init" then
      return
    end

    -- reset the report table
    route_report.flavor = kong.configuration.router_flavor
    route_report.total = #routes

    if route_report.flavor ~= "expressions" then
      traditional_statistics(routes)

    else
      route_report.paths_count = 0
      route_report.regex_paths_count = 0
      route_report.headers_count = 0
      protocol_counts.http = 0
      protocol_counts.stream = 0
      protocol_counts.tls_passthrough = 0
      protocol_counts.grpc = 0
      path_handling_counts.v0 = 0
      path_handling_counts.v1 = 0
    end

    -- do not localize timer.at or we will be using vanilla Lua's timer
    ngx.timer.at(0, send_report)
    -- ngx.log(ngx.ERR, require "inspect"(route_report))
  end
end

_M.phonehome_statistics = phonehome_statistics

_M.DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


function _M:exec(ctx)
  return self.trad.exec(ctx)
end


function _M:select(req_method, req_uri, req_host, req_scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni, req_headers)
  return self.trad.select(req_method, req_uri, req_host, req_scheme,
                          src_ip, src_port,
                          dst_ip, dst_port,
                          sni, req_headers)
end


function _M.new(routes, cache, cache_neg, old_router)
  phonehome_statistics(routes)

  if not is_http or
     not kong or
     not kong.configuration or
     kong.configuration.router_flavor == "traditional"
  then
    local trad, err = traditional.new(routes, cache, cache_neg)
    if not trad then
      return nil, err
    end

    return setmetatable({
      trad = trad,
    }, _MT)
  end

  return atc_compat.new(routes, cache, cache_neg, old_router)
end


_M._set_ngx = traditional._set_ngx
_M.split_port = traditional.split_port


return _M
