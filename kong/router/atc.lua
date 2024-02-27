local _M = {}
local _MT = { __index = _M, }


local buffer = require("string.buffer")
local lrucache = require("resty.lrucache")
local tb_new = require("table.new")
local utils = require("kong.router.utils")
local rat = require("kong.tools.request_aware_table")
local yield = require("kong.tools.yield").yield


local type = type
local assert = assert
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber


local max = math.max


local ngx           = ngx
local header        = ngx.header
local var           = ngx.var
local ngx_log       = ngx.log
local get_phase     = ngx.get_phase
local ngx_ERR       = ngx.ERR


local check_select_params  = utils.check_select_params
local get_service_info     = utils.get_service_info
local route_match_stat     = utils.route_match_stat


local DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


local LOGICAL_OR  = " || "
local LOGICAL_AND = " && "


local is_http = ngx.config.subsystem == "http"


-- reuse buffer object
local values_buf = buffer.new(64)


local get_atc_context
local get_atc_router
local get_atc_fields
do
  local schema = require("resty.router.schema")
  local context = require("resty.router.context")
  local router = require("resty.router.router")
  local fields = require("kong.router.fields")

  local function generate_schema(fields)
    local s = schema.new()

    for t, f in pairs(fields) do
      for _, v in ipairs(f) do
        assert(s:add_field(v, t))
      end
    end

    return s
  end

  -- used by validation
  local HTTP_SCHEMA   = generate_schema(fields.HTTP_FIELDS)
  local STREAM_SCHEMA = generate_schema(fields.STREAM_FIELDS)

  -- used by running router
  local CACHED_SCHEMA = is_http and HTTP_SCHEMA or STREAM_SCHEMA

  get_atc_context = function()
    return context.new(CACHED_SCHEMA)
  end

  get_atc_router = function(routes_n)
    return router.new(CACHED_SCHEMA, routes_n)
  end

  get_atc_fields = function(inst)
    return fields.new(inst:get_fields())
  end

  local protocol_to_schema = {
    http  = HTTP_SCHEMA,
    https = HTTP_SCHEMA,
    grpc  = HTTP_SCHEMA,
    grpcs = HTTP_SCHEMA,

    tcp   = STREAM_SCHEMA,
    udp   = STREAM_SCHEMA,
    tls   = STREAM_SCHEMA,

    tls_passthrough = STREAM_SCHEMA,
  }

  -- for db schema validation
  function _M.schema(protocols)
    return assert(protocol_to_schema[protocols[1]])
  end

  -- for unit testing
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

    fields._set_ngx(mock_ngx)
  end
end


local is_empty_field
do
  local null    = ngx.null
  local isempty = require("table.isempty")

  is_empty_field = function(f)
    return f == nil or f == null or isempty(f)
  end
end


local function escape_str(str)
  -- raw string
  if not str:find([["#]], 1, true) then
    return "r#\"" .. str .. "\"#"
  end

  -- standard string escaping (unlikely case)
  if str:find([[\]], 1, true) then
    str = str:gsub([[\]], [[\\]])
  end

  if str:find([["]], 1, true) then
    str = str:gsub([["]], [[\"]])
  end

  return "\"" .. str .. "\""
end


local function gen_for_field(name, op, vals, val_transform)
  if is_empty_field(vals) then
    return nil
  end

  local vals_n = #vals
  assert(vals_n > 0)

  values_buf:reset():put("(")

  for i = 1, vals_n do
    local p = vals[i]
    local op = (type(op) == "string") and op or op(p)

    if i > 1 then
      values_buf:put(LOGICAL_OR)
    end

    values_buf:putf("%s %s %s", name, op,
                    escape_str(val_transform and val_transform(op, p) or p))
  end

  -- consume the whole buffer
  -- returns a local variable instead of using a tail call
  -- to avoid NYI
  local str = values_buf:put(")"):get()

  return str
end


local function add_atc_matcher(inst, route, route_id,
                               get_exp_and_priority,
                               remove_existing)

  local exp, priority = get_exp_and_priority(route)

  if not exp then
    return nil, "could not find expression, route: " .. route_id
  end

  if remove_existing then
    assert(inst:remove_matcher(route_id))
  end

  local ok, err = inst:add_matcher(priority, route_id, exp)
  if not ok then
    return nil, "could not add route: " .. route_id .. ", err: " .. err
  end

  return true
end


local function new_from_scratch(routes, get_exp_and_priority)
  local phase = get_phase()

  local routes_n = #routes

  local inst = get_atc_router(routes_n)

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

    local ok, err = add_atc_matcher(inst, route, route_id,
                                    get_exp_and_priority, false)
    if ok then
      new_updated_at = max(new_updated_at, route.updated_at or 0)

    else
      ngx_log(ngx_ERR, err)

      routes_t[route_id] = nil
      services_t[route_id] = nil
    end

    yield(true, phase)
  end

  return setmetatable({
      context = get_atc_context(),
      fields = get_atc_fields(inst),
      router = inst,
      routes = routes_t,
      services = services_t,
      updated_at = new_updated_at,
      rebuilding = false,
    }, _MT)
end


local function new_from_previous(routes, get_exp_and_priority, old_router)
  if old_router.rebuilding then
    return nil, "concurrent incremental router rebuild without mutex, this is unsafe"
  end

  old_router.rebuilding = true

  local phase = get_phase()

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

    local ok = true
    local err

    if not old_route then
      -- route is new
      ok, err = add_atc_matcher(inst, route, route_id, get_exp_and_priority, false)

    elseif route_updated_at >= updated_at or
           route_updated_at ~= old_route.updated_at then

      -- route is modified (within a sec)
      ok, err = add_atc_matcher(inst, route, route_id, get_exp_and_priority, true)
    end

    if ok then
      new_updated_at = max(new_updated_at, route_updated_at)

    else
      ngx_log(ngx_ERR, err)

      old_routes[route_id] = nil
      old_services[route_id] = nil
    end

    yield(true, phase)
  end

  -- remove routes
  for id, r in pairs(old_routes) do
    if r.seen  then
      r.seen = nil

    else
      assert(inst:remove_matcher(id))

      old_routes[id] = nil
      old_services[id] = nil
    end

    yield(true, phase)
  end

  old_router.fields = get_atc_fields(inst)
  old_router.updated_at = new_updated_at
  old_router.rebuilding = false

  return old_router
end


function _M.new(routes, cache, cache_neg, old_router, get_exp_and_priority)
  if type(routes) ~= "table" then
    return error("expected arg #1 routes to be a table")
  end

  local router, err

  if not old_router then
    router, err = new_from_scratch(routes, get_exp_and_priority)

  else
    router, err = new_from_previous(routes, get_exp_and_priority, old_router)
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
local split_host_port
do
  local DEFAULT_HOSTS_LRUCACHE_SIZE = DEFAULT_MATCH_LRUCACHE_SIZE

  local memo_hp = lrucache.new(DEFAULT_HOSTS_LRUCACHE_SIZE)

  split_host_port = function(key)
    if not key then
      return nil, nil
    end

    local m = memo_hp:get(key)

    if m then
      return m[1], m[2]
    end

    local p = key:find(":", nil, true)
    if not p then
      memo_hp:set(key, { key, nil })
      return key, nil
    end

    local port = tonumber(key:sub(p + 1))

    if not port then
      memo_hp:set(key, { key, nil })
      return key, nil
    end

    local host = key:sub(1, p - 1)

    memo_hp:set(key, { host, port })

    return host, port
  end
end


local CACHE_PARAMS


if is_http then


local sanitize_uri_postfix = utils.sanitize_uri_postfix
local strip_uri_args       = utils.strip_uri_args
local add_debug_headers    = utils.add_debug_headers
local get_upstream_uri_v0  = utils.get_upstream_uri_v0


local function set_upstream_uri(req_uri, match_t)
  local matched_route = match_t.route

  local request_prefix = match_t.prefix or "/"
  local request_postfix = sanitize_uri_postfix(req_uri:sub(#request_prefix + 1))

  local upstream_base = match_t.upstream_url_t.path or "/"

  match_t.upstream_uri = get_upstream_uri_v0(matched_route, request_postfix,
                                             req_uri, upstream_base)
end


function _M:matching(params)
  local req_uri = params.uri
  local req_host = params.host

  check_select_params(params.method, req_uri, req_host, params.scheme,
                      params.src_ip, params.src_port,
                      params.dst_ip, params.dst_port,
                      params.sni, params.headers, params.queries)

  local host, port = split_host_port(req_host)

  params.host = host
  params.port = port

  self.context:reset()

  local c, err = self.fields:fill_atc_context(self.context, params)

  if not c then
    return nil, err
  end

  local matched = self.router:execute(c)
  if not matched then
    return nil
  end

  local uuid, matched_path, captures = c:get_result("http.path")

  local service = self.services[uuid]
  local matched_route = self.routes[uuid].original_route or self.routes[uuid]

  local service_protocol, _,  --service_type
        service_host, service_port,
        service_hostname_type, service_path = get_service_info(service)

  local request_prefix = matched_route.strip_path and matched_path or nil

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
      path = service_path,
    },
    upstream_scheme = service_protocol,
    upstream_host   = matched_route.preserve_host and req_host or nil,
  }
end


-- only for unit-testing
function _M:select(req_method, req_uri, req_host, req_scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni, req_headers, req_queries)

  local params = {
    method  = req_method,
    uri     = req_uri,
    host    = req_host,
    scheme  = req_scheme,
    sni     = sni,
    headers = req_headers,
    queries = req_queries,

    src_ip   = src_ip,
    src_port = src_port,
    dst_ip   = dst_ip,
    dst_port = dst_port,
  }

  return self:matching(params)
end


function _M:exec(ctx)
  local fields = self.fields

  local req_uri = ctx and ctx.request_uri or var.request_uri
  local req_host = var.http_host

  req_uri = strip_uri_args(req_uri)

  -- cache key calculation

  if not CACHE_PARAMS then
    CACHE_PARAMS = rat.new()
  end

  CACHE_PARAMS:clear()

  CACHE_PARAMS.uri  = req_uri
  CACHE_PARAMS.host = req_host

  local cache_key = fields:get_cache_key(CACHE_PARAMS)

  -- cache lookup

  local match_t = self.cache:get(cache_key)
  if not match_t then
    if self.cache_neg:get(cache_key) then
      route_match_stat(ctx, "neg")
      return nil
    end

    CACHE_PARAMS.scheme = ctx and ctx.scheme or var.scheme

    local err
    match_t, err = self:matching(CACHE_PARAMS)
    if not match_t then
      if err then
        ngx_log(ngx_ERR, "router returned an error: ", err,
                         ", 404 Not Found will be returned for the current request")
      end

      self.cache_neg:set(cache_key, true)
      return nil
    end

    self.cache:set(cache_key, match_t)

  else
    route_match_stat(ctx, "pos")

    -- preserve_host header logic, modify cache result
    if match_t.route.preserve_host then
      match_t.upstream_host = req_host
    end
  end

  -- found a match

  -- update upstream_uri in cache result
  set_upstream_uri(req_uri, match_t)

  -- debug HTTP request header logic
  add_debug_headers(var, header, match_t)

  return match_t
end

else  -- is stream subsystem


function _M:matching(params)
  local sni = params.sni

  check_select_params(nil, nil, nil, params.scheme,
                      params.src_ip, params.src_port,
                      params.dst_ip, params.dst_port,
                      sni)

  self.context:reset()

  local c, err = self.fields:fill_atc_context(self.context, params)
  if not c then
    return nil, err
  end

  local matched = self.router:execute(c)
  if not matched then
    return nil
  end

  local uuid = c:get_result()

  local service = self.services[uuid]
  local matched_route = self.routes[uuid]

  local service_protocol, _,  --service_type
        service_host, service_port,
        service_hostname_type = get_service_info(service)

  return {
    route          = matched_route,
    service        = service,
    upstream_url_t = {
      type = service_hostname_type,
      host = service_host,
      port = service_port,
    },
    upstream_scheme = service_protocol,
    upstream_host  = matched_route.preserve_host and sni or nil,
  }
end


-- only for unit-testing
function _M:select(_, _, _, scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni)

  local params = {
    scheme    = scheme,
    src_ip    = src_ip,
    src_port  = src_port,
    dst_ip    = dst_ip,
    dst_port  = dst_port,
    sni       = sni,
  }

  return self:matching(params)
end


function _M:exec(ctx)
  local fields = self.fields

  -- cache key calculation

  if not CACHE_PARAMS then
    CACHE_PARAMS = rat.new()
  end

  CACHE_PARAMS:clear()

  local cache_key = fields:get_cache_key(CACHE_PARAMS, ctx)

  -- cache lookup

  local match_t = self.cache:get(cache_key)
  if not match_t then
    if self.cache_neg:get(cache_key) then
      route_match_stat(ctx, "neg")
      return nil
    end

    local scheme
    if var.protocol == "UDP" then
      scheme = "udp"

    else
      scheme = CACHE_PARAMS.sni and "tls" or "tcp"
    end

    CACHE_PARAMS.scheme = scheme

    local err
    match_t, err = self:matching(CACHE_PARAMS)
    if not match_t then
      if err then
        ngx_log(ngx_ERR, "router returned an error: ", err)
      end

      self.cache_neg:set(cache_key, true)
      return nil
    end

    self.cache:set(cache_key, match_t)

  else
    route_match_stat(ctx, "pos")

    -- preserve_host logic, modify cache result
    if match_t.route.preserve_host then
      match_t.upstream_host = fields:get_value("tls.sni", CACHE_PARAMS)
    end
  end

  return match_t
end

end   -- if is_http


_M.LOGICAL_OR      = LOGICAL_OR
_M.LOGICAL_AND     = LOGICAL_AND

_M.escape_str      = escape_str
_M.is_empty_field  = is_empty_field
_M.gen_for_field   = gen_for_field
_M.split_host_port = split_host_port


return _M
