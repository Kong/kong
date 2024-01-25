local buffer = require("string.buffer")


local type = type
local ipairs = ipairs
local assert = assert
local tonumber = tonumber
local setmetatable = setmetatable
local tb_sort = table.sort
local tb_concat = table.concat
local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


local var           = ngx.var
local get_method    = ngx.req.get_method
local get_headers   = ngx.req.get_headers
local get_uri_args  = ngx.req.get_uri_args
local server_name   = require("ngx.ssl").server_name


local PREFIX_LEN = 13 -- #"http.headers."
local HTTP_HEADERS_PREFIX = "http.headers."
local HTTP_QUERIES_PREFIX = "http.queries."


local HTTP_FIELDS = {

  ["String"] = {"net.protocol", "tls.sni",
                "http.method", "http.host",
                "http.path",
                "http.path.segments.*",
                "http.headers.*",
                "http.queries.*",
               },

  ["Int"]    = {"net.src.port", "net.dst.port",
                "http.path.segments.len",
               },

  ["IpAddr"] = {"net.src.ip", "net.dst.ip",
               },
}


local STREAM_FIELDS = {

  ["String"] = {"net.protocol", "tls.sni",
               },

  ["Int"]    = {"net.src.port", "net.dst.port",
               },

  ["IpAddr"] = {"net.src.ip", "net.dst.ip",
               },
}


local FIELDS_FUNCS = {
  -- http.*

  ["http.method"] =
  function(params)
    if not params.method then
      params.method = get_method()
    end

    return params.method
  end,

  ["http.path"] =
  function(params)
    return params.uri
  end,

  ["http.host"] =
  function(params)
    return params.host
  end,

  -- net.*

  ["net.src.ip"] =
  function(params)
    if not params.src_ip then
      params.src_ip = var.remote_addr
    end

    return params.src_ip
  end,

  ["net.src.port"] =
  function(params)
    if not params.src_port then
      params.src_port = tonumber(var.remote_port, 10)
    end

    return params.src_port
  end,

  -- below are atc context only

  ["net.protocol"] =
  function(params)
    return params.scheme
  end,
}


local is_http = ngx.config.subsystem == "http"


if is_http then
  -- tls.*

  FIELDS_FUNCS["tls.sni"] =
  function(params)
    if not params.sni then
      params.sni = server_name()
    end

    return params.sni
  end

  -- net.*

  FIELDS_FUNCS["net.dst.ip"] =
  function(params)
    if not params.dst_ip then
      params.dst_ip = var.server_addr
    end

    return params.dst_ip
  end

  FIELDS_FUNCS["net.dst.port"] =
  function(params, ctx)
    if params.port then
      return params.port
    end

    if not params.dst_port then
      params.dst_port = tonumber((ctx or ngx.ctx).host_port, 10) or
                        tonumber(var.server_port, 10)
    end

    return params.dst_port
  end

else  -- stream

  -- tls.*
  -- error value for non-TLS connections ignored intentionally
  -- fallback to preread SNI if current connection doesn't terminate TLS

  FIELDS_FUNCS["tls.sni"] =
  function(params)
    if not params.sni then
      params.sni = server_name() or var.ssl_preread_server_name
    end

    return params.sni
  end

  -- net.*
  -- when proxying TLS request in second layer or doing TLS passthrough
  -- rewrite the dst_ip, port back to what specified in proxy_protocol

  FIELDS_FUNCS["net.dst.ip"] =
  function(params)
    if not params.dst_ip then
      if var.kong_tls_passthrough_block == "1" or var.ssl_protocol then
        params.dst_ip = var.proxy_protocol_server_addr

      else
        params.dst_ip = var.server_addr
      end
    end

    return params.dst_ip
  end

  FIELDS_FUNCS["net.dst.port"] =
  function(params, ctx)
    if not params.dst_port then
      if var.kong_tls_passthrough_block == "1" or var.ssl_protocol then
        params.dst_port = tonumber(var.proxy_protocol_server_port)

      else
        params.dst_port = tonumber((ctx or ngx.ctx).host_port, 10) or
                          tonumber(var.server_port, 10)
      end
    end

    return params.dst_port
  end

end -- is_http


-- stream subsystem needs not to generate func
local function get_field_accessor(funcs, field)
  error("unknown router matching schema field: " .. field)
end


if is_http then

  local fmt = string.format
  local ngx_null = ngx.null
  local re_split = require("ngx.re").split


  local HTTP_SEGMENTS_PREFIX = "http.path.segments."
  local HTTP_SEGMENTS_PREFIX_LEN = #HTTP_SEGMENTS_PREFIX
  local HTTP_SEGMENTS_OFFSET = 1


  local get_http_segments
  do
    local HTTP_SEGMENTS_REG_CTX = { pos = 2, }  -- skip first '/'

    get_http_segments = function(params)
      if not params.segments then
        HTTP_SEGMENTS_REG_CTX.pos = 2 -- reset ctx, skip first '/'
        params.segments = re_split(params.uri, "/", "jo", HTTP_SEGMENTS_REG_CTX)
      end

      return params.segments
    end
  end


  FIELDS_FUNCS["http.path.segments.len"] =
  function(params)
    local segments = get_http_segments(params)

    return #segments
  end


  -- func => get_headers or get_uri_args
  -- name => "headers" or "queries"
  -- max_config_option => "lua_max_req_headers" or "lua_max_uri_args"
  local function get_http_params(func, name, max_config_option)
    local params, err = func()
    if err == "truncated" then
      local max = kong and kong.configuration and kong.configuration[max_config_option] or 100
      ngx.log(ngx.ERR,
              fmt("router: not all request %s were read in order to determine the route " ..
                  "as the request contains more than %d %s, " ..
                  "route selection may be inaccurate, " ..
                  "consider increasing the '%s' configuration value " ..
                  "(currently at %d)",
                  name, max, name, max_config_option, max))
    end

    return params
  end


  get_field_accessor = function(funcs, field)
    local f = funcs[field]
    if f then
      return f
    end

    local prefix = field:sub(1, PREFIX_LEN)

    -- generate for http.headers.*

    if prefix == HTTP_HEADERS_PREFIX then
      local name = field:sub(PREFIX_LEN + 1)

      f = function(params)
        if not params.headers then
          params.headers = get_http_params(get_headers, "headers", "lua_max_req_headers")
        end

        return params.headers[name]
      end -- f

      funcs[field] = f
      return f
    end -- if prefix == HTTP_HEADERS_PREFIX

    -- generate for http.queries.*

    if prefix == HTTP_QUERIES_PREFIX then
      local name = field:sub(PREFIX_LEN + 1)

      f = function(params)
        if not params.queries then
          params.queries = get_http_params(get_uri_args, "queries", "lua_max_uri_args")
        end

        return params.queries[name]
      end -- f

      funcs[field] = f
      return f
    end -- if prefix == HTTP_QUERIES_PREFIX

    -- generate for http.path.segments.*

    if field:sub(1, HTTP_SEGMENTS_PREFIX_LEN) == HTTP_SEGMENTS_PREFIX then
      local range = field:sub(HTTP_SEGMENTS_PREFIX_LEN + 1)

      f = function(params)
        local segments = get_http_segments(params)

        local value = segments[range]

        if value then
          return value ~= ngx_null and value or nil
        end

        -- "/a/b/c" => 1="a", 2="b", 3="c"
        -- http.path.segments.0 => params.segments[1 + 0] => a
        -- http.path.segments.1_2 => b/c

        local p = range:find("_", 1, true)

        -- only one segment, e.g. http.path.segments.1

        if not p then
          local pos = tonumber(range)

          value = pos and segments[HTTP_SEGMENTS_OFFSET + pos] or nil
          segments[range] = value or ngx_null

          return value
        end

        -- (pos1, pos2) defines a segment range, e.g. http.path.segments.1_2

        local pos1 = tonumber(range:sub(1, p - 1))
        local pos2 = tonumber(range:sub(p + 1))
        local segs_count = #segments - HTTP_SEGMENTS_OFFSET

        if not pos1 or not pos2 or
           pos1 >= pos2 or pos1 > segs_count or pos2 > segs_count
        then
          segments[range] = ngx_null
          return nil
        end

        local buf = buffer.new()

        for p = pos1, pos2 - 1 do
          buf:put(segments[HTTP_SEGMENTS_OFFSET + p], "/")
        end
        buf:put(segments[HTTP_SEGMENTS_OFFSET + pos2])

        value = buf:get()
        segments[range] = value

        return value
      end -- f

      funcs[field] = f
      return f
    end -- if field:sub(1, HTTP_SEGMENTS_PREFIX_LEN)

    -- others are error
    error("unknown router matching schema field: " .. field)
  end

end -- is_http


local function visit_for_cache_key(field, value, str_buf)
  -- these fields were not in cache key
  if field == "net.protocol" then
    return true
  end

  local headers_or_queries = field:sub(1, PREFIX_LEN)

  if headers_or_queries == HTTP_HEADERS_PREFIX then
    headers_or_queries = true
    field = replace_dashes_lower(field)

  elseif headers_or_queries == HTTP_QUERIES_PREFIX then
    headers_or_queries = true

  else
    headers_or_queries = false
  end

  if not headers_or_queries then
    str_buf:put(value or "", "|")

  else  -- headers or queries
    if type(value) == "table" then
      tb_sort(value)
      value = tb_concat(value, ",")
    end

    str_buf:putf("%s=%s|", field, value or "")
  end

  return true
end


local function visit_for_context(field, value, ctx)
  local v_type = type(value)

  -- multiple values for a single header/query parameter, like /?foo=bar&foo=baz
  if v_type == "table" then
    for _, v in ipairs(value) do
      local res, err = ctx:add_value(field, v)
      if not res then
        return nil, err
      end
    end

    return true
  end -- if v_type

  -- the header/query parameter has only one value, like /?foo=bar
  -- the query parameter has no value, like /?foo,
  -- get_uri_arg will get a boolean `true`
  -- we think it is equivalent to /?foo=
  if v_type == "boolean" then
    value = ""
  end

  return ctx:add_value(field, value)
end


local _M = {}
local _MT = { __index = _M, }


_M.HTTP_FIELDS = HTTP_FIELDS
_M.STREAM_FIELDS = STREAM_FIELDS


function _M.new(fields)
  return setmetatable({
      fields = fields,
      funcs = {},
    }, _MT)
end


function _M:get_value(field, params, ctx)
  local func = FIELDS_FUNCS[field] or
               get_field_accessor(self.funcs, field)

  return func(params, ctx)
end


function _M:fields_visitor(params, ctx, cb, cb_arg)
  for _, field in ipairs(self.fields) do
    local value = self:get_value(field, params, ctx)

    local res, err = cb(field, value, cb_arg)
    if not res then
      return nil, err
    end
  end -- for fields

  return true
end


-- cache key string
local str_buf = buffer.new(64)


function _M:get_cache_key(params, ctx)
  str_buf:reset()

  local res = self:fields_visitor(params, ctx,
                                  visit_for_cache_key, str_buf)
  assert(res)

  return str_buf:get()
end


function _M:fill_atc_context(c, params)
  local res, err = self:fields_visitor(params, nil,
                                       visit_for_context, c)

  if not res then
    return nil, err
  end

  return c
end


function _M._set_ngx(mock_ngx)
  if mock_ngx.var then
    var = mock_ngx.var
  end

  if type(mock_ngx.req) == "table" then
    if mock_ngx.req.get_method then
      get_method = mock_ngx.req.get_method
    end

    if mock_ngx.req.get_headers then
      get_headers = mock_ngx.req.get_headers
    end

    if mock_ngx.req.get_uri_args then
      get_uri_args = mock_ngx.req.get_uri_args
    end
  end
end


return _M
