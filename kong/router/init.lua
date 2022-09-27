local _M = {}
local _MT = { __index = _M, }


local kong = kong


local traditional = require("kong.router.traditional")
local expressions = require("kong.router.expressions")
local compat      = require("kong.router.compat")
local utils       = require("kong.router.utils")


local is_http = ngx.config.subsystem == "http"


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



local phonehome_statistics
do
  local reports = require("kong.reports")
  local nkeys = require("table.nkeys")
  local log = ngx.log
  local ERR = ngx.ERR

  local byte = string.byte
  local TILDE = byte("~")
  local function is_regex_magic(path)
    return byte(path) == TILDE
  end

  local empty_table = {}
  -- reuse tables to avoid cost of creating tables and garbage collection
  local protocols = {
    http = 0, -- { "http", "https" },
    stream = 0, -- { "tcp", "tls", "udp" },
    tls_passthrough = 0, -- { "tls_passthrough" },
    grpc = 0, -- { "grpc", "grpcs" },
  }
  local path_handlings = {
    v0 = 0,
    v1 = 0,
  }
  local route_report = {
    flavor = "unknown",
    paths = 0,
    headers = 0,
    routes = 0,
    regex_routes = 0,
    protocols = protocols,
    path_handlings = path_handlings,
  }

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
        if is_regex_magic(path) then
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

        else
          log(ERR, "unknown protocol: " .. protocol)
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

    route_report.paths = paths_count
    route_report.headers = headers_count
    route_report.regex_routes = regex_paths_count
    protocols.http = http
    protocols.stream = stream
    protocols.tls_passthrough = tls_passthrough
    protocols.grpc = grpc
    path_handlings.v0 = v0
    path_handlings.v1 = v1
  end

  function phonehome_statistics(routes)
    if not kong.configuration.anonymous_reports or ngx.worker.id() ~= 0 then
      return
    end

    route_report.flavor = kong.configuration.router_flavor
    route_report.routes = #routes

    if route_report.flavor ~= "expressions" then
      traditional_statistics(routes)

    else
      route_report.paths = nil
      route_report.regex_routes = nil
      route_report.headers = nil
      protocols.http = nil
      protocols.stream = nil
      protocols.tls_passthrough = nil
      protocols.grpc = nil
      path_handlings.v0 = nil
      path_handlings.v1 = nil
    end

    reports.add_ping_value("routes_count", route_report)
  end
end

_M.phonehome_statistics = phonehome_statistics

function _M.new(routes, cache, cache_neg, old_router)
  local flavor = kong and
                 kong.configuration and
                 kong.configuration.router_flavor

  phonehome_statistics(routes)
  if not is_http or
     not flavor or flavor == "traditional"
  then
    local trad, err = traditional.new(routes, cache, cache_neg)
    if not trad then
      return nil, err
    end

    return setmetatable({
      trad = trad,
    }, _MT)
  end

  if flavor == "expressions" then
    return expressions.new(routes, cache, cache_neg, old_router)
  end

  return compat.new(routes, cache, cache_neg, old_router)
end


_M._set_ngx = traditional._set_ngx
_M.split_port = traditional.split_port


return _M
