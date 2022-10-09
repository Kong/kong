local _M = {}
local _MT = { __index = _M, }


local schema = require("resty.router.schema")
local router = require("resty.router.router")
local context = require("resty.router.context")
local lrucache = require("resty.lrucache")
local server_name = require("ngx.ssl").server_name
local tb_new = require("table.new")
local tb_clear = require("table.clear")
local utils = require("kong.router.utils")
local yield = require("kong.tools.utils").yield


local type = type
local assert = assert
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber


local max = math.max
local tb_concat = table.concat
local tb_sort = table.sort


local ngx           = ngx
local null          = ngx.null
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


local MAX_REQ_HEADERS  = 100
local DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


-- reuse table objects
local gen_values_t = tb_new(10, 0)


local CACHED_SCHEMA
do
  local str_fields = {"net.protocol", "tls.sni",
                      "http.method", "http.host",
                      "http.path", "http.raw_path",
                      "http.headers.*",
  }

  local int_fields = {"net.port",
  }

  CACHED_SCHEMA = schema.new()

  for _, v in ipairs(str_fields) do
    assert(CACHED_SCHEMA:add_field(v, "String"))
  end

  for _, v in ipairs(int_fields) do
    assert(CACHED_SCHEMA:add_field(v, "Int"))
  end
end


local function atc_escape_str(str)
  return "\"" .. str:gsub([[\]], [[\\]]):gsub([["]], [[\"]]) .. "\""
end


local function gen_for_field(name, op, vals, val_transform)
  if not vals or vals == null then
    return nil
  end

  tb_clear(gen_values_t)

  local values_n = 0
  local values   = gen_values_t

  for _, p in ipairs(vals) do
    values_n = values_n + 1
    local op = (type(op) == "string") and op or op(p)
    values[values_n] = name .. " " .. op .. " " ..
                       atc_escape_str(val_transform and val_transform(op, p) or p)
  end

  if values_n > 0 then
    return "(" .. tb_concat(values, " || ") .. ")"
  end

  return nil
end


local function add_atc_matcher(inst, route, route_id,
                               get_exp_priority,
                               remove_existing)

  local exp, priority = get_exp_priority(route)

  if not exp then
    return
  end

  if remove_existing then
    assert(inst:remove_matcher(route_id))
  end

  assert(inst:add_matcher(priority, route_id, exp))
end


local function has_header_matching_field(fields)
  for _, field in ipairs(fields) do
    if field:sub(1, 13) == "http.headers." then
      return true
    end
  end

  return false
end


local function new_from_scratch(routes, get_exp_priority)
  local s = CACHED_SCHEMA
  local inst = router.new(s)

  local routes_n   = #routes
  local routes_t   = tb_new(0, routes_n)
  local services_t = tb_new(0, routes_n)

  local new_updated_at = 0

  for _, r in ipairs(routes) do
    local route = r.route
    local route_id = route.id

    if not route_id then
      return nil, "could not categorize route"
    end

    routes_t[route_id] = route
    services_t[route_id] = r.service

    add_atc_matcher(inst, route, route_id, get_exp_priority, false)

    new_updated_at = max(new_updated_at, route.updated_at or 0)

    yield(true)
  end

  local fields = inst:get_fields()
  local match_headers = has_header_matching_field(fields)

  return setmetatable({
      schema = s,
      router = inst,
      routes = routes_t,
      services = services_t,
      fields = fields,
      match_headers = match_headers,
      updated_at = new_updated_at,
      rebuilding = false,
    }, _MT)
end


local function new_from_previous(routes, get_exp_priority, old_router)
  if old_router.rebuilding then
    return nil, "concurrent incremental router rebuild without mutex, this is unsafe"
  end

  old_router.rebuilding = true

  local inst = old_router.router
  local old_routes = old_router.routes
  local old_services = old_router.services

  local updated_at = old_router.updated_at
  local new_updated_at = 0

  -- create or update routes
  for _, r in ipairs(routes) do
    local route = r.route
    local route_id = route.id

    if not route_id then
      return nil, "could not categorize route"
    end

    local old_route = old_routes[route_id]
    local route_updated_at = route.updated_at

    route.seen = true

    old_routes[route_id] = route
    old_services[route_id] = r.service

    if not old_route then
      -- route is new
      add_atc_matcher(inst, route, route_id, get_exp_priority, false)

    elseif route_updated_at >= updated_at or
           route_updated_at ~= old_route.updated_at then

      -- route is modified (within a sec)
      add_atc_matcher(inst, route, route_id, get_exp_priority, true)
    end

    new_updated_at = max(new_updated_at, route_updated_at)

    yield(true)
  end

  -- remove routes
  for id, r in pairs(old_routes) do
    if r.seen  then
      r.seen = nil

    else
      inst:remove_matcher(id)
      old_routes[id] = nil
      old_services[id] = nil
    end

    yield(true)
  end

  local fields = inst:get_fields()

  old_router.fields = fields
  old_router.match_headers = has_header_matching_field(fields)
  old_router.updated_at = new_updated_at
  old_router.rebuilding = false

  return old_router
end


function _M.new(routes, cache, cache_neg, old_router, get_exp_priority)
  if type(routes) ~= "table" then
    return error("expected arg #1 routes to be a table")
  end

  local router, err

  if not old_router then
    router, err = new_from_scratch(routes, get_exp_priority)

  else
    router, err = new_from_previous(routes, get_exp_priority, old_router)
  end

  if not router then
    return nil, err
  end

  router.cache = cache or lrucache.new(DEFAULT_MATCH_LRUCACHE_SIZE)
  router.cache_neg = cache_neg or lrucache.new(DEFAULT_MATCH_LRUCACHE_SIZE)

  return router
end


-- split port in host, ignore form '[...]'
-- example.com:123 => example.com, 123
-- example.*:123 => example.*, 123
local function split_host_port(h)
  if not h then
    return nil, nil
  end

  local p = h:find(":", nil, true)
  if not p then
    return h, nil
  end

  local port = tonumber(h:sub(p + 1))

  if not port then
    return h, nil
  end

  local host = h:sub(1, p - 1)

  return host, port
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

  local host, port = split_host_port(req_host)

  for _, field in ipairs(self.fields) do
    if field == "http.method" then
      assert(c:add_value("http.method", req_method))

    elseif field == "http.path" then
      assert(c:add_value("http.path", req_uri))

    elseif field == "http.host" then
      assert(c:add_value("http.host", host))

    elseif field == "net.port" then
     assert(c:add_value("net.port", port))

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
  local sni = server_name()

  local headers, headers_key
  if self.match_headers then
    local err
    headers, err = get_headers(MAX_REQ_HEADERS)
    if err == "truncated" then
      ngx_log(ngx_WARN, "retrieved ", MAX_REQ_HEADERS, " headers for evaluation ",
                        "(max) but request had more; other headers will be ignored")
    end

    headers["host"] = nil

    headers_key = get_headers_key(headers)
  end

  req_uri = strip_uri_args(req_uri)

  -- cache lookup

  local cache_key = (req_method or "") .. "|" ..
                    (req_uri    or "") .. "|" ..
                    (req_host   or "") .. "|" ..
                    (sni        or "") .. (headers_key or "")

  local match_t = self.cache:get(cache_key)
  if not match_t then
    if self.cache_neg:get(cache_key) then
      return nil
    end

    local req_scheme = ctx and ctx.scheme or var.scheme

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


_M.atc_escape_str  = atc_escape_str
_M.gen_for_field   = gen_for_field
_M.split_host_port = split_host_port


return _M
