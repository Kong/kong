-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local buffer = require("string.buffer")


local type = type
local ipairs = ipairs
local assert = assert
local tonumber = tonumber
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


if is_http then

  local fmt = string.format

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


  setmetatable(FIELDS_FUNCS, {
  __index = function(_, field)
    local prefix = field:sub(1, PREFIX_LEN)

    if prefix == HTTP_HEADERS_PREFIX then
      return function(params)
        if not params.headers then
          params.headers = get_http_params(get_headers, "headers", "lua_max_req_headers")
        end

        return params.headers[field:sub(PREFIX_LEN + 1)]
      end

    elseif prefix == HTTP_QUERIES_PREFIX then
      return function(params)
        if not params.queries then
          params.queries = get_http_params(get_uri_args, "queries", "lua_max_uri_args")
        end

        return params.queries[field:sub(PREFIX_LEN + 1)]
      end
    end

    -- others return nil
  end
  })

end -- is_http


local function get_value(field, params, ctx)
  local func = FIELDS_FUNCS[field]

  if not func then  -- unknown field
    error("unknown router matching schema field: " .. field)
  end -- if func

  return func(params, ctx)
end


local function fields_visitor(fields, params, ctx, cb)
  for _, field in ipairs(fields) do
    local value = get_value(field, params, ctx)

    local res, err = cb(field, value)
    if not res then
      return nil, err
    end
  end -- for fields

  return true
end


-- cache key string
local str_buf = buffer.new(64)


local function get_cache_key(fields, params, ctx)
  str_buf:reset()

  local res =
  fields_visitor(fields, params, ctx, function(field, value)

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
      str_buf:put(value or ""):put("|")

    else  -- headers or queries
      if type(value) == "table" then
        tb_sort(value)
        value = tb_concat(value, ",")
      end

      str_buf:putf("%s=%s|", field, value or "")
    end

    return true
  end)  -- fields_visitor

  assert(res)

  return str_buf:get()
end


local function fill_atc_context(context, fields, params)
  local c = context

  local res, err =
  fields_visitor(fields, params, nil, function(field, value)

    local prefix = field:sub(1, PREFIX_LEN)

    if prefix == HTTP_HEADERS_PREFIX or prefix == HTTP_QUERIES_PREFIX then
      local v_type = type(value)

      -- multiple values for a single query parameter, like /?foo=bar&foo=baz
      if v_type == "table" then
        for _, v in ipairs(value) do
          local res, err = c:add_value(field, v)
          if not res then
            return nil, err
          end
        end

        return true
      end -- if v_type

      -- the query parameter has only one value, like /?foo=bar
      -- the query parameter has no value, like /?foo,
      -- get_uri_arg will get a boolean `true`
      -- we think it is equivalent to /?foo=
      if v_type == "boolean" then
        value = ""
      end
    end

    return c:add_value(field, value)
  end)  -- fields_visitor

  if not res then
    return nil, err
  end

  return c
end


local function _set_ngx(mock_ngx)
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


return {
  get_value = get_value,

  get_cache_key = get_cache_key,
  fill_atc_context = fill_atc_context,

  _set_ngx = _set_ngx,
}
