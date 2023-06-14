local _M = {}
local _MT = { __index = _M, }


local buffer = require("string.buffer")
local schema = require("resty.router.schema")
local router = require("resty.router.router")
local context = require("resty.router.context")
local lrucache = require("resty.lrucache")
local server_name = require("ngx.ssl").server_name
local tb_new = require("table.new")
local utils = require("kong.router.utils")
local yield = require("kong.tools.utils").yield


local type = type
local assert = assert
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs


local max = math.max


local ngx           = ngx
local header        = ngx.header
local var           = ngx.var
local ngx_log       = ngx.log
local get_phase     = ngx.get_phase
local get_method    = ngx.req.get_method
local get_headers   = ngx.req.get_headers
local ngx_ERR       = ngx.ERR


local sanitize_uri_postfix = utils.sanitize_uri_postfix
local check_select_params  = utils.check_select_params
local strip_uri_args       = utils.strip_uri_args
local get_service_info     = utils.get_service_info
local add_debug_headers    = utils.add_debug_headers
local get_upstream_uri_v0  = utils.get_upstream_uri_v0
local route_match_stat     = utils.route_match_stat


local DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


local LOGICAL_OR  = " || "
local LOGICAL_AND = " && "


local is_http = ngx.config.subsystem == "http"

-- reuse buffer object
local values_buf = buffer.new(64)


local CACHED_SCHEMA
do
  local FIELDS

  if is_http then
    FIELDS = {

      ["String"] = {"net.protocol", "tls.sni",
                    "http.method", "http.host",
                    "http.path", "http.raw_path",
                    "http.headers.*",
                   },

      ["Int"]    = {"net.port",
                   },
    }

  else  -- stream subsystem
    FIELDS = {

      ["String"] = { "net.protocol", "tls.sni", },

      ["Int"]    = { "net.src_port", "net.dst_port", },

      ["IpAddr"] = { "net.src_ip", "net.dst_ip", },

      ["IpCidr"] = { "net.cidr", },
    }
  end

  CACHED_SCHEMA = schema.new()

  for typ, fields in pairs(FIELDS) do
    for _, v in ipairs(fields) do
      assert(CACHED_SCHEMA:add_field(v, typ))
    end
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
  return values_buf:put(")"):get()
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


local function is_http_headers_field(field)
  return field:sub(1, 13) == "http.headers."
end


local function has_header_matching_field(fields)
  for _, field in ipairs(fields) do
    if is_http_headers_field(field) then
      return true
    end
  end

  return false
end


local function new_from_scratch(routes, get_exp_and_priority)
  local phase = get_phase()

  local routes_n = #routes

  local inst = router.new(CACHED_SCHEMA, routes_n)

  local routes_t   = tb_new(0, routes_n)
  local services_t = tb_new(0, routes_n)

  local new_updated_at = 0

  for i = 1, routes_n do
    local r = routes[i]

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

  local fields = inst:get_fields()
  local match_headers = has_header_matching_field(fields)

  return setmetatable({
      schema = CACHED_SCHEMA,
      router = inst,
      routes = routes_t,
      services = services_t,
      fields = fields,
      match_headers = match_headers,
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
  for i = 1, #routes do
    local r = routes[i]

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

  local fields = inst:get_fields()

  old_router.fields = fields
  old_router.match_headers = has_header_matching_field(fields)
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
  local tonumber = tonumber
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


if is_http then

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
      assert(c:add_value(field, req_method))

    elseif field == "http.path" then
      local res, err = c:add_value(field, req_uri)
      if not res then
        return nil, err
      end

    elseif field == "http.host" then
      local res, err = c:add_value(field, host)
      if not res then
        return nil, err
      end

    elseif field == "net.port" then
     assert(c:add_value(field, port))

    elseif field == "net.protocol" then
      assert(c:add_value(field, req_scheme))

    elseif field == "tls.sni" then
      local res, err = c:add_value(field, sni)
      if not res then
        return nil, err
      end

    elseif req_headers and is_http_headers_field(field) then
      local h = field:sub(14)
      local v = req_headers[h]

      if v then
        if type(v) == "string" then
          local res, err = c:add_value(field, v:lower())
          if not res then
            return nil, err
          end

        else
          for _, v in ipairs(v) do
            local res, err = c:add_value(field, v:lower())
            if not res then
              return nil, err
            end
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
  local matched_route = self.routes[uuid].original_route or self.routes[uuid]

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
  local tb_sort = table.sort
  local tb_concat = table.concat

  local headers_buf = buffer.new(64)

  get_headers_key = function(headers)
    headers_buf:reset()

    -- NOTE: DO NOT yield until headers_buf:get()
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

      headers_buf:putf("|%s=%s", name, value)
    end

    return headers_buf:get()
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
    headers, err = get_headers()
    if err == "truncated" then
      local lua_max_req_headers = kong and kong.configuration and kong.configuration.lua_max_req_headers or 100
      ngx_log(ngx_ERR, "router: not all request headers were read in order to determine the route as ",
                       "the request contains more than ", lua_max_req_headers, " headers, route selection ",
                       "may be inaccurate, consider increasing the 'lua_max_req_headers' configuration value ",
                       "(currently at ", lua_max_req_headers, ")")
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
      route_match_stat(ctx, "neg")
      return nil
    end

    local req_scheme = ctx and ctx.scheme or var.scheme

    local err
    match_t, err = self:select(req_method, req_uri, req_host, req_scheme,
                          nil, nil, nil, nil,
                          sni, headers)
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
  end

  -- found a match

  -- debug HTTP request header logic
  add_debug_headers(var, header, match_t)

  return match_t
end

else  -- is stream subsystem

function _M:select(scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni)

  check_select_params(nil, nil, nil, scheme,
                      src_ip, src_port,
                      dst_ip, dst_port,
                      sni, nil)

  local c = context.new(self.schema)

  for _, field in ipairs(self.fields) do
    if field == "net.protocol" then
      assert(c:add_value(field, scheme))

    elseif field == "tls.sni" then
      local res, err = c:add_value(field, sni)
      if not res then
        return nil, err
      end

    elseif field == "net.src_ip" then
      assert(c:add_value(field, src_ip))

    elseif field == "net.dst_ip" then
      assert(c:add_value(field, dst_ip))

    elseif field == "net.src_port" then
      assert(c:add_value(field, src_port))

    elseif field == "net.dst_port" then
      assert(c:add_value(field, dst_port))

    end -- if
  end -- for

  local matched = self.router:execute(c)
  if not matched then
    return nil
  end

  local uuid = c:get_result()

  local service = self.services[uuid]
  local matched_route = self.routes[uuid]

  local service_protocol = get_service_info(service)

  return {
    route           = matched_route,
    service         = service,
    upstream_scheme = service_protocol,
  }
end


function _M:exec(ctx)
  local src_ip = var.remote_addr
  local dst_ip = var.server_addr
  local src_port = tonumber(var.remote_port, 10)
  local dst_port = tonumber((ctx or ngx.ctx).host_port, 10)
                or tonumber(var.server_port, 10)
  -- error value for non-TLS connections ignored intentionally
  local sni = server_name()
  -- fallback to preread SNI if current connection doesn't terminate TLS
  if not sni then
    sni = var.ssl_preread_server_name
  end

  local scheme
  if var.protocol == "UDP" then
    scheme = "udp"
  else
    scheme = sni and "tls" or "tcp"
  end

  -- when proxying TLS request in second layer or doing TLS passthrough
  -- rewrite the dst_ip, port back to what specified in proxy_protocol
  if var.kong_tls_passthrough_block == "1" or var.ssl_protocol then
    dst_ip = var.proxy_protocol_server_addr
    dst_port = tonumber(var.proxy_protocol_server_port)
  end

  local match_t, err = self:select(scheme,
                                   src_ip, src_port,
                                   dst_ip, dst_port,
                                   sni)
  if not match_t then
    if err then
      ngx_log(ngx_ERR, "router returned an error: ", err)
    end

    return nil
  end

  return match_t
end

end   -- if is_http


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


_M.schema          = CACHED_SCHEMA

_M.LOGICAL_OR      = LOGICAL_OR
_M.LOGICAL_AND     = LOGICAL_AND

_M.escape_str      = escape_str
_M.is_empty_field  = is_empty_field
_M.gen_for_field   = gen_for_field
_M.split_host_port = split_host_port


return _M
