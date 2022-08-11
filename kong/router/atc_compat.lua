local _M = {}
local _MT = { __index = _M, }

local atc = require("kong.router.atc")
local utils = require("kong.router.utils")
local router = require("resty.router.router")
local context = require("resty.router.context")
local bit = require("bit")
local lrucache = require("resty.lrucache")
local ffi = require("ffi")
local server_name = require("ngx.ssl").server_name
local normalize = require("kong.tools.uri").normalize
local tb_new = require("table.new")
local tb_clear = require("table.clear")
local tb_nkeys = require("table.nkeys")


local ngx = ngx
local tb_concat = table.concat
local tb_insert = table.insert
local tb_sort = table.sort
local byte = string.byte
local sub = string.sub
local setmetatable = setmetatable
local pairs = pairs
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


local sanitize_uri_postfix = utils.sanitize_uri_postfix
local check_select_params  = utils.check_select_params
local strip_uri_args       = utils.strip_uri_args
local get_service_info     = utils.get_service_info
local add_debug_headers    = utils.add_debug_headers
local get_upstream_uri_v0  = utils.get_upstream_uri_v0


local TILDE            = byte("~")
local MAX_HEADER_COUNT = 255
local MAX_REQ_HEADERS  = 100


local MATCH_LRUCACHE_SIZE = utils.MATCH_LRUCACHE_SIZE


-- reuse table objects
local gen_values_t        = tb_new(10, 0)
local atc_out_t           = tb_new(10, 0)
local atc_headers_t       = tb_new(10, 0)
local atc_single_header_t = tb_new(10, 0)


local function is_regex_magic(path)
  return byte(path) == TILDE
end


local function regex_partation(paths)
  if not paths then
    return
  end

  tb_sort(paths, function(a, b)
      return is_regex_magic(a) and not is_regex_magic(b)
    end)
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


local function gen_for_field(name, op, vals, vals_transform)
  if not vals then
    return nil
  end

  tb_clear(gen_values_t)

  local values_n = 0
  local values   = gen_values_t

  for _, p in ipairs(vals) do
    values_n = values_n + 1
    local op = (type(op) == "string") and op or op(p)
    values[values_n] = name .. " " .. op ..
                       " \"" .. (vals_transform and vals_transform(op, p) or p) .. "\""
  end

  if values_n > 0 then
    return "(" .. tb_concat(values, " || ") .. ")"
  end

  return nil
end


local OP_EQUAL    = "=="
local OP_PREFIX   = "^="
local OP_POSTFIX  = "=^"
local OP_REGEX    = "~"


local function get_atc(route)
  tb_clear(atc_out_t)
  local out = atc_out_t

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

  -- move regex paths to the front
  regex_partation(route.paths)

  local gen = gen_for_field("http.path", function(path)
    return is_regex_magic(path) and OP_REGEX or OP_PREFIX
  end, route.paths, function(op, p)
    if op == OP_REGEX then
      -- Rust only recognize form '?P<>'
      return sub(p, 2):gsub("?<", "?P<"):gsub("\\", "\\\\")
    end

    return normalize(p, true)
  end)
  if gen then
    tb_insert(out, gen)
  end

  if route.headers then
    tb_clear(atc_headers_t)
    local headers = atc_headers_t
    for h, v in pairs(route.headers) do
      tb_clear(atc_single_header_t)
      local single_header = atc_single_header_t
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


local lshift_uint64
do
  local ffi_uint = ffi_new("uint64_t")

  lshift_uint64 = function(v, offset)
    ffi_uint = v
    return lshift(ffi_uint, offset)
  end
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

  local match_weight = lshift_uint64(match_weight, 61)
  local headers_count = lshift_uint64(headers_count, 52)
  local regex_priority = lshift_uint64(regex_url and r.regex_priority or 0, 19)
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

  local routes_n   = #routes
  local routes_t   = tb_new(0, routes_n)
  local services_t = tb_new(0, routes_n)

  local is_traditional_compatible =
          kong and kong.configuration and
          kong.configuration.router_flavor == "traditional_compatible"

  for _, r in ipairs(routes) do
    local route = r.route
    local route_id = route.id
    routes_t[route_id] = route
    services_t[route_id] = r.service

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

  end

  return setmetatable({
      schema = s,
      router = inst,
      routes = routes_t,
      services = services_t,
      fields = inst:get_fields(),
      cache = cache,
      cache_neg = cache_neg,
    }, _MT)
end


function _M:select(req_method, req_uri, req_host, req_scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni, req_headers)

  check_select_params(req_method, req_uri, req_host, req_scheme,
                      src_ip, src_port,
                      dst_ip, dst_port,
                      sni, req_headers)

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

  local service = self.services[uuid]
  local matched_route = self.routes[uuid]

  local service_protocol, _,  --service_type
        service_host, service_port,
        service_hostname_type, service_path = get_service_info(service)

  local request_prefix = matched_route.strip_path and matched_path or nil
  local request_postfix = request_prefix and req_uri:sub(#matched_path + 1) or req_uri:sub(2, -1)
  request_postfix = sanitize_uri_postfix(request_postfix) or ""
  local upstream_base = service_path or "/"

  local upstream_uri = get_upstream_uri_v0(matched_route, request_postfix, req_uri,
                                           upstream_base)

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


local get_headers_key
do
  local headers_t = tb_new(8, 0)

  get_headers_key = function(headers)
    tb_clear(headers_t)

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

      headers_t[headers_count + 1] = "|"
      headers_t[headers_count + 2] = name
      headers_t[headers_count + 3] = "="
      headers_t[headers_count + 4] = value

      headers_count = headers_count + 4
    end

    return tb_concat(headers_t, nil, 1, headers_count)
  end
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

  req_uri = strip_uri_args(req_uri)

  -- cache lookup

  local cache_key = (req_method or "") .. "|" .. (req_uri or "") ..
                    "|" .. (req_host or "") .. "|" .. (sni or "") ..
                    get_headers_key(headers)

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
  add_debug_headers(var, header, match_t)

  return match_t
end


return _M
