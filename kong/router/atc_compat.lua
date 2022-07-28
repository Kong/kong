local _M = {}
local _MT = { __index = _M, }

local atc = require("kong.router.atc")
local router = require("resty.router.router")
local context = require("resty.router.context")
local constants = require("kong.constants")
local bit = require("bit")
local lrucache = require("resty.lrucache")
local ffi = require("ffi")
local server_name = require("ngx.ssl").server_name
local normalize = require("kong.tools.uri").normalize
local hostname_type = require("kong.tools.utils").hostname_type
local tb_nkeys = require("table.nkeys")


local ngx = ngx
local tb_concat = table.concat
local tb_insert = table.insert
local tb_sort = table.sort
local find = string.find
local byte = string.byte
local sub = string.sub
local setmetatable = setmetatable
local ipairs = ipairs
local type = type
local get_schema = atc.get_schema
local ffi_new = ffi.new
local max = math.max
local bor, band, lshift = bit.bor, bit.band, bit.lshift
local header        = ngx.header
local var           = ngx.var
local ngx_log       = ngx.log
local get_method    = ngx.req.get_method
local get_headers   = ngx.req.get_headers
local ngx_WARN      = ngx.WARN



local SLASH            = byte("/")
local MAX_HEADER_COUNT = 255
local MAX_REQ_HEADERS  = 100


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 5 MiBs

LRU size must be: (5 * 2^20) / 1024 = 5120
Floored: 5000 items should be a good default
--]]
local MATCH_LRUCACHE_SIZE = 5e3


local function is_regex_magic(path)
  return sub(path, 1, 1) == "~"
end


function _M._set_ngx(mock_ngx)
  if type(mock_ngx) ~= "table" then
    return
  end

  if mock_ngx.header then
    header = mock_ngx.header
  end

  if mock_ngx.var then
    var = mock_ngx.var
  end

  if mock_ngx.log then
    ngx_log = mock_ngx.log
  end

  if type(mock_ngx.req) == "table" then
    if mock_ngx.req.get_method then
      get_method = mock_ngx.req.get_method
    end

    if mock_ngx.req.get_headers then
      get_headers = mock_ngx.req.get_headers
    end
  end
end


local protocol_subsystem = constants.PROTOCOLS_WITH_SUBSYSTEM


local function gen_for_field(name, op, vals, vals_transform)
  local values_n = 0
  local values = {}

  if vals then
    for _, p in ipairs(vals) do
      values_n = values_n + 1
      local op = (type(op) == "string") and op or op(p)
      values[values_n] = name .. " " .. op ..
                         " \"" .. (vals_transform and vals_transform(op, p) or p) .. "\""
    end

    if values_n > 0 then
      return "(" .. tb_concat(values, " || ") .. ")"
    end
  end

  return nil
end


local OP_EQUAL = "=="
local OP_PREFIX = "^="
local OP_POSTFIX = "=^"
local OP_REGEX = "~"


local function get_atc(route)
  local out = {}

  --local gen = gen_for_field("net.protocol", OP_EQUAL, route.protocols)
  --if gen then
  --  tb_insert(out, gen)
  --end

  local gen = gen_for_field("http.method", OP_EQUAL, route.methods)
  if gen then
    tb_insert(out, gen)
  end

  local gen = gen_for_field("tls.sni", OP_EQUAL, route.snis)
  if gen then
    -- See #6425, if `net.protocol` is not `https`
    -- then SNI matching should simply not be considered
    gen = "net.protocol != \"https\" || " .. gen
    tb_insert(out, gen)
  end

  local gen = gen_for_field("http.host", function(host)
    if host:sub(1, 1) == "*" then
      -- postfix matching
      return OP_POSTFIX
    end

    if host:sub(-1) == "*" then
      -- prefix matching
      return OP_PREFIX
    end

    return OP_EQUAL
  end, route.hosts, function(op, p)
    if op == OP_POSTFIX then
      return p:sub(2)
    end

    if op == OP_PREFIX then
      return p:sub(1, -2)
    end

    return p
  end)
  if gen then
    tb_insert(out, gen)
  end

  local gen = gen_for_field("http.path", function(path)
    return is_regex_magic(path) and OP_REGEX or OP_PREFIX
  end, route.paths, function(op, p)
    if op == OP_REGEX then
      return sub(p, 2):gsub("\\", "\\\\")
    end

    return normalize(p, true)
  end)
  if gen then
    tb_insert(out, gen)
  end

  if route.headers then
    local headers = {}
    for h, v in pairs(route.headers) do
      local single_header = {}
      for _, ind in ipairs(v) do
        local name = "any(http.headers." .. h:gsub("-", "_"):lower() .. ")"
        local value = ind
        local op = OP_EQUAL
        if ind:sub(1, 2) == "~*" then
          value = ind:sub(3):gsub("\\", "\\\\")
          op = OP_REGEX
        end

        tb_insert(single_header, name .. " " .. op .. " \"" .. value:lower() .. "\"")
      end

      tb_insert(headers, "(" .. tb_concat(single_header, " || ") .. ")")
    end

    tb_insert(out, tb_concat(headers, " && "))
  end

  return tb_concat(out, " && ")
end


-- convert a route to a priority value for use in the ATC router
-- priority must be a 64-bit non negative integer
-- format (big endian):
--  0                   1                   2                   3
--  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
-- +-----+-+---------------+-+-------------------------------------+
-- | W   |P| Header        |R|  Regex                              |
-- | G   |L|               |G|  Priority                           |
-- | T   |N| Count         |X|                                     |
-- +-----+-+-----------------+-------------------------------------+
-- |  Regex Priority         |   Max Length                        |
-- |  (cont)                 |                                     |
-- |                         |                                     |
-- +-------------------------+-------------------------------------+
local function route_priority(r)
  local match_weight = 0

  if r.methods and #r.methods > 0 then
    match_weight = match_weight + 1
  end

  if r.hosts and #r.hosts > 0 then
    match_weight = match_weight + 1
  end

  if r.paths and #r.paths > 0 then
    match_weight = match_weight + 1
  end

  local headers_count = r.headers and tb_nkeys(r.headers) or 0

  if headers_count > 0 then
    match_weight = match_weight + 1
  end

  if headers_count > MAX_HEADER_COUNT then
    ngx_log(ngx_WARN, "too many headers in route ", r.id,
                      " headers count capped at 255 when sorting")
    headers_count = MAX_HEADER_COUNT
  end

  if r.snis and #r.snis > 0 then
    match_weight = match_weight + 1
  end

  local plain_host_only = not not r.hosts

  if r.hosts then
    for _, h in ipairs(r.hosts) do
      if h:find("*", nil, true) then
        plain_host_only = false
        break
      end
    end
  end

  local max_uri_length = 0
  local regex_url = false

  if r.paths then
    for _, p in ipairs(r.paths) do
      if is_regex_magic(p) then
        regex_url = true

      else
        -- plain URI or URI prefix
        max_uri_length = max(max_uri_length, #p)
      end
    end
  end

  match_weight = lshift(ffi_new("uint64_t", match_weight), 61)
  headers_count = lshift(ffi_new("uint64_t", headers_count), 52)
  local regex_priority = lshift(ffi_new("uint64_t", regex_url and r.regex_priority or 0), 19)
  local max_length = band(max_uri_length, 0x7FFFF)

  local priority =  bor(match_weight,
                        plain_host_only and lshift(0x01ULL, 60) or 0,
                        regex_url and lshift(0x01ULL, 51) or 0,
                        headers_count,
                        regex_priority,
                        max_length)

  return priority
end


function _M.new(routes, cache, cache_neg)
  if type(routes) ~= "table" then
    return error("expected arg #1 routes to be a table")
  end

  local s = get_schema()
  local inst = router.new(s)

  if not cache then
    cache = lrucache.new(MATCH_LRUCACHE_SIZE)
  end

  if not cache_neg then
    cache_neg = lrucache.new(MATCH_LRUCACHE_SIZE)
  end

  local router = setmetatable({
    schema = s,
    router = inst,
    routes = {},
    services = {},
    fields = {},
    cache = cache,
    cache_neg = cache_neg,
  }, _MT)

  local is_traditional_compatible =
          kong and kong.configuration and
          kong.configuration.router_flavor == "traditional_compatible"

  for _, r in ipairs(routes) do
    local route = r.route
    local route_id = route.id
    router.routes[route_id] = route
    router.services[route_id] = r.service

    if is_traditional_compatible then
      assert(inst:add_matcher(route_priority(route), route_id, get_atc(route)))

    else
      local atc = route.atc

      local gen = gen_for_field("net.protocol", OP_EQUAL, route.protocols)
      if gen then
        atc = atc .. " && " .. gen
      end

      assert(inst:add_matcher(route.priority, route_id, atc))
    end

    router.fields = inst:get_fields()
  end

  return router
end


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


function _M:select(req_method, req_uri, req_host, req_scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni, req_headers)
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

  local c = context.new(self.schema)

  for _, field in ipairs(self.fields) do
    if field == "http.method" then
      assert(c:add_value("http.method", req_method))

    elseif field == "http.path" then
      assert(c:add_value("http.path", req_uri))

    elseif field == "http.host" then
      assert(c:add_value("http.host", req_host))

    elseif field == "net.protocol" then
      assert(c:add_value("net.protocol", req_scheme))

    elseif field == "tls.sni" then
      assert(c:add_value("tls.sni", sni))

    elseif req_headers and field:sub(1, 13) == "http.headers." then
      local h = field:sub(14)
      local v = req_headers[h]

      if v then
        if type(v) == "string" then
          assert(c:add_value(field, v:lower()))

        else
          for _, v in ipairs(v) do
            assert(c:add_value(field, v:lower()))
          end
        end
      end
    end
  end

  local matched = self.router:execute(c)
  if not matched then
    return nil
  end

  local uuid, matched_path, captures = c:get_result("http.path")

  local service_protocol
  local service_type
  local service_host
  local service_port
  local service = self.services[uuid]
  local matched_route = self.routes[uuid]

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

  local request_prefix = matched_route.strip_path and matched_path or nil
  local upstream_uri
  local request_postfix = request_prefix and req_uri:sub(#matched_path + 1) or req_uri:sub(2, -1)
  request_postfix = sanitize_uri_postfix(request_postfix) or ""
  local upstream_base = service_path or "/"

  -- TODO: refactor and share with old router
  if byte(upstream_base, -1) == SLASH then
    -- ends with / and strip_path = true
    if matched_route.strip_path then
      if request_postfix == "" then
        if upstream_base == "/" then
          upstream_uri = "/"
        elseif byte(req_uri, -1) == SLASH then
          upstream_uri = upstream_base
        else
          upstream_uri = sub(upstream_base, 1, -2)
        end
      elseif byte(request_postfix, 1, 1) == SLASH then
        -- double "/", so drop the first
        upstream_uri = sub(upstream_base, 1, -2) .. request_postfix
      else -- ends with / and strip_path = true, no double slash
        upstream_uri = upstream_base .. request_postfix
      end

    else -- ends with / and strip_path = false
      -- we retain the incoming path, just prefix it with the upstream
      -- path, but skip the initial slash
      upstream_uri = upstream_base .. sub(req_uri, 2)
    end

  else -- does not end with /
    -- does not end with / and strip_path = true
    if matched_route.strip_path then
      if request_postfix == "" then
        if #req_uri > 1 and byte(req_uri, -1) == SLASH then
          upstream_uri = upstream_base .. "/"
        else
          upstream_uri = upstream_base
        end
      elseif byte(request_postfix, 1, 1) == SLASH then
        upstream_uri = upstream_base .. request_postfix
      else
        upstream_uri = upstream_base .. "/" .. request_postfix
      end

    else -- does not end with / and strip_path = false
      if req_uri == "/" then
        upstream_uri = upstream_base
      else
        upstream_uri = upstream_base .. req_uri
      end
    end
  end

  return {
    route           = matched_route,
    service         = service,
    prefix          = request_prefix,
    matches = {
      uri_captures = (captures and captures[1]) and captures or nil,
    },
    upstream_url_t = {
      type = service_hostname_type,
      host = service_host,
      port = service_port,
    },
    upstream_scheme = service_protocol,
    upstream_uri    = upstream_uri,
    upstream_host   = matched_route.preserve_host and req_host or nil,
  }
end


function _M:exec(ctx)
  local req_method = get_method()
  local req_uri = ctx and ctx.request_uri or var.request_uri
  local req_host = var.http_host
  local req_scheme = ctx and ctx.scheme or var.scheme
  local sni = server_name()

  local headers, err = get_headers(MAX_REQ_HEADERS)
  if err == "truncated" then
    ngx_log(ngx_WARN, "retrieved ", MAX_REQ_HEADERS, " headers for evaluation ",
                  "(max) but request had more; other headers will be ignored")
  end

  headers["host"] = nil

  local idx = find(req_uri, "?", 2, true)
  if idx then
    req_uri = sub(req_uri, 1, idx - 1)
  end

  req_uri = normalize(req_uri, true)

  local headers_key do
    local headers_count = 0
    for name, value in pairs(headers) do
      local name = name:gsub("-", "_"):lower()

      if type(value) == "table" then
        for i, v in ipairs(value) do
          value[i] = v:lower()
        end
        tb_sort(value)
        value = tb_concat(value, ", ")

      else
        value = value:lower()
      end

      if headers_count == 0 then
        headers_key = { "|", name, "=", value }

      else
        headers_key[headers_count + 1] = "|"
        headers_key[headers_count + 2] = name
        headers_key[headers_count + 3] = "="
        headers_key[headers_count + 4] = value
      end

      headers_count = headers_count + 4
    end

    headers_key = headers_key and tb_concat(headers_key, nil, 1, headers_count) or ""
  end

  -- cache lookup

  local cache_key = (req_method or "") .. "|" .. (req_uri or "") ..
                    "|" .. (req_host or "") .. "|" .. (sni or "") ..
                    headers_key
  local match_t = self.cache:get(cache_key)
  if not match_t then
    if self.cache_neg:get(cache_key) then
      return nil
    end

    match_t = self:select(req_method, req_uri, req_host, req_scheme,
                          nil, nil, nil, nil,
                          sni, headers)
    if not match_t then
      self.cache_neg:set(cache_key, true)
      return nil
    end

    self.cache:set(cache_key, match_t)
  end

  -- found a match

  -- debug HTTP request header logic
  if var.http_kong_debug then
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

  return match_t
end


return _M
