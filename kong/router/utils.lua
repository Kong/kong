local constants = require("kong.constants")
local hostname_type = require("kong.tools.utils").hostname_type
local normalize = require("kong.tools.uri").normalize


local type = type
local error = error
local ipairs = ipairs
local find = string.find
local sub = string.sub
local byte = string.byte


local SLASH  = byte("/")


local DEFAULT_HOSTNAME_TYPE = hostname_type("")


local protocol_subsystem = constants.PROTOCOLS_WITH_SUBSYSTEM


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 5 MiBs

LRU size must be: (5 * 2^20) / 1024 = 5120
Floored: 5000 items should be a good default
--]]
local DEFAULT_MATCH_LRUCACHE_SIZE = 5000


local function sanitize_uri_postfix(uri_postfix)
  if not uri_postfix or uri_postfix == "" then
    return uri_postfix
  end

  if uri_postfix == "." or uri_postfix == ".." then
    return ""
  end

  if sub(uri_postfix, 1, 2) == "./" then
    return sub(uri_postfix, 3)
  end

  if sub(uri_postfix, 1, 3) == "../" then
    return sub(uri_postfix, 4)
  end

  return uri_postfix
end


local function strip_uri_args(req_uri)
  local idx = find(req_uri, "?", 2, true)
  if idx then
    req_uri = sub(req_uri, 1, idx - 1)
  end

  return normalize(req_uri, true)
end


local function check_select_params(req_method, req_uri, req_host, req_scheme,
                                   src_ip, src_port,
                                   dst_ip, dst_port,
                                   sni, req_headers, req_queries)
  if req_method and type(req_method) ~= "string" then
    error("method must be a string", 2)
  end
  if req_uri and type(req_uri) ~= "string" then
    error("uri must be a string", 2)
  end
  if req_host and type(req_host) ~= "string" then
    error("host must be a string", 2)
  end
  if req_scheme and type(req_scheme) ~= "string" then
    error("scheme must be a string", 2)
  end
  if src_ip and type(src_ip) ~= "string" then
    error("src_ip must be a string", 2)
  end
  if src_port and type(src_port) ~= "number" then
    error("src_port must be a number", 2)
  end
  if dst_ip and type(dst_ip) ~= "string" then
    error("dst_ip must be a string", 2)
  end
  if dst_port and type(dst_port) ~= "number" then
    error("dst_port must be a number", 2)
  end
  if sni and type(sni) ~= "string" then
    error("sni must be a string", 2)
  end
  if req_headers and type(req_headers) ~= "table" then
    error("headers must be a table", 2)
  end
  if req_queries and type(req_queries) ~= "table" then
    error("queries must be a table", 2)
  end
end


local function add_debug_headers(var, header, match_t)
  if not var.http_kong_debug then
    return
  end

  if not kong.configuration.allow_debug_header then
    return
  end

  local route = match_t.route
  if route then
    if route.id then
      header["Kong-Route-Id"] = route.id
    end

    if route.name then
      header["Kong-Route-Name"] = route.name
    end
  end

  local service = match_t.service
  if service then
    if service.id then
      header["Kong-Service-Id"] = service.id
    end

    if service.name then
      header["Kong-Service-Name"] = service.name
    end
  end
end


local function get_upstream_uri_v0(matched_route, request_postfix, req_uri,
                                   upstream_base)

  local strip_path = matched_route.strip_path or matched_route.strip_uri

  if byte(upstream_base, -1) == SLASH then
    -- ends with / and strip_path = true
    if strip_path then
      if request_postfix == "" then
        if upstream_base == "/" then
          return "/"
        end

        if byte(req_uri, -1) == SLASH then
          return upstream_base
        end

        return sub(upstream_base, 1, -2)
      end -- if request_postfix

      if byte(request_postfix, 1) == SLASH then
        -- double "/", so drop the first
        return sub(upstream_base, 1, -2) .. request_postfix
      end

      -- ends with / and strip_path = true, no double slash
      return upstream_base .. request_postfix
    end -- if strip_path

    -- ends with / and strip_path = false
    -- we retain the incoming path, just prefix it with the upstream
    -- path, but skip the initial slash
    return upstream_base .. sub(req_uri, 2)
  end -- byte(upstream_base, -1) == SLASH

  -- does not end with / and strip_path = true
  if strip_path then
    if request_postfix == "" then
      if #req_uri > 1 and byte(req_uri, -1) == SLASH then
        return upstream_base .. "/"
      end

      return upstream_base
    end -- if request_postfix

    if byte(request_postfix, 1) == SLASH then
      return upstream_base .. request_postfix
    end

    return upstream_base .. "/" .. request_postfix
  end -- if strip_path

  -- does not end with / and strip_path = false
  if req_uri == "/" then
    return upstream_base
  end

  return upstream_base .. req_uri
end


local function get_service_info(service)
  local service_protocol
  local service_type
  local service_host
  local service_port

  if service then
    service_protocol = service.protocol
    service_host = service.host
    service_port = service.port
  end

  if service_protocol then
    service_type = protocol_subsystem[service_protocol]
  end

  local service_hostname_type
  if service_host then
    service_hostname_type = hostname_type(service_host)
  end

  if not service_port then
    if service_protocol == "https" then
      service_port = 443
    elseif service_protocol == "http" then
      service_port = 80
    end
  end

  local service_path
  if service_type == "http" then
    service_path = service and service.path or "/"
  end

  return service_protocol, service_type,
         service_host, service_port,
         service_hostname_type or DEFAULT_HOSTNAME_TYPE,
         service_path
end


local function route_match_stat(ctx, tag)
  if ctx then
    ctx.route_match_cached = tag
  end
end


local is_regex_magic
local phonehome_statistics
do
  local reports = require("kong.reports")
  local nkeys = require("table.nkeys")
  local yield = require("kong.tools.yield").yield
  local worker_id = ngx.worker.id
  local get_phase = ngx.get_phase

  local TILDE = byte("~")
  is_regex_magic = function(path)
    return byte(path) == TILDE
  end

  local empty_table = {}
  -- reuse tables to avoid cost of creating tables and garbage collection
  local protocols = {
    http            = 0, -- { "http", "https" },
    stream          = 0, -- { "tcp", "tls", "udp" },
    tls_passthrough = 0, -- { "tls_passthrough" },
    grpc            = 0, -- { "grpc", "grpcs" },
    unknown         = 0, -- all other protocols,
  }
  local path_handlings = {
    v0 = 0,
    v1 = 0,
  }
  local route_report = {
    flavor         = "unknown",
    paths          = 0,
    headers        = 0,
    routes         = 0,
    regex_routes   = 0,
    protocols      = protocols,
    path_handlings = path_handlings,
  }

  local function traditional_statistics(routes)
    local paths           = 0
    local headers         = 0
    local regex_routes    = 0
    local http            = 0
    local stream          = 0
    local tls_passthrough = 0
    local grpc            = 0
    local unknown         = 0
    local v0              = 0
    local v1              = 0

    local phase = get_phase()

    for _, route in ipairs(routes) do
      yield(true, phase)

      local r = route.route

      local paths_t     = r.paths or empty_table
      local headers_t   = r.headers or empty_table
      local protocols_t = r.protocols or empty_table

      paths   = paths + #paths_t
      headers = headers + nkeys(headers_t)

      for _, path in ipairs(paths_t) do
        if is_regex_magic(path) then
          regex_routes = regex_routes + 1
          break
        end
      end

      local protocol = protocols_t[1]   -- only check first protocol

      if protocol then
        if protocol == "http" or protocol == "https" then
          http = http + 1

        elseif protocol == "tcp" or protocol == "tls" or protocol == "udp" then
          stream = stream + 1

        elseif protocol == "tls_passthrough" then
          tls_passthrough = tls_passthrough + 1

        elseif protocol == "grpc" or protocol == "grpcs" then
          grpc = grpc + 1

        else
          unknown = unknown + 1
        end
      end

      local path_handling = r.path_handling or "v0"
      if path_handling == "v0" then
        v0 = v0 + 1

      elseif path_handling == "v1" then
        v1 = v1 + 1
      end
    end   -- for routes

    route_report.paths        = paths
    route_report.headers      = headers
    route_report.regex_routes = regex_routes
    protocols.http            = http
    protocols.stream          = stream
    protocols.tls_passthrough = tls_passthrough
    protocols.grpc            = grpc
    protocols.unknown         = unknown
    path_handlings.v0         = v0
    path_handlings.v1         = v1
  end

  function phonehome_statistics(routes)
    local configuration = kong.configuration

    if not configuration.anonymous_reports or worker_id() ~= 0 then
      return
    end

    local flavor = configuration.router_flavor

    route_report.flavor = flavor
    route_report.routes = #routes

    if flavor ~= "expressions" then
      traditional_statistics(routes)

    else
      route_report.paths        = nil
      route_report.regex_routes = nil
      route_report.headers      = nil
      protocols.http            = nil
      protocols.stream          = nil
      protocols.tls_passthrough = nil
      protocols.grpc            = nil
      path_handlings.v0         = nil
      path_handlings.v1         = nil
    end

    reports.add_ping_value("routes_count", route_report)
  end
end


local parse_ip_addr
do
  local bit = require("bit")
  local ipmatcher = require("resty.ipmatcher")

  local band, lshift, rshift = bit.band, bit.lshift, bit.rshift

  parse_ip_addr = function(ip)
    local addr, mask = ipmatcher.split_ip(ip)

    if not mask then
      return addr
    end

    local ipv4 = ipmatcher.parse_ipv4(addr)

    -- FIXME: support ipv6
    if not ipv4 then
      return addr, mask
    end

    local cidr = lshift(rshift(ipv4, 32 - mask), 32 - mask)

    local n1 = band(       cidr     , 0xff)
    local n2 = band(rshift(cidr,  8), 0xff)
    local n3 = band(rshift(cidr, 16), 0xff)
    local n4 = band(rshift(cidr, 24), 0xff)

    return n4 .. "." .. n3 .. "." .. n2 .. "." .. n1, mask
  end
end


return {
  DEFAULT_MATCH_LRUCACHE_SIZE  = DEFAULT_MATCH_LRUCACHE_SIZE,

  sanitize_uri_postfix = sanitize_uri_postfix,
  check_select_params  = check_select_params,
  strip_uri_args       = strip_uri_args,
  get_service_info     = get_service_info,
  add_debug_headers    = add_debug_headers,
  get_upstream_uri_v0  = get_upstream_uri_v0,

  route_match_stat     = route_match_stat,
  is_regex_magic       = is_regex_magic,
  phonehome_statistics = phonehome_statistics,

  parse_ip_addr        = parse_ip_addr,
}
