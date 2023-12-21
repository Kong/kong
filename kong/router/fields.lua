local buffer = require("string.buffer")
local context = require("resty.router.context")
--local utils = require("kong.router.utils")


local type = type
--local pairs = pairs
local ipairs = ipairs
local tb_sort = table.sort
local tb_concat = table.concat
--local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


local var           = ngx.var
local get_method    = ngx.req.get_method
local get_headers   = ngx.req.get_headers
local get_uri_args  = ngx.req.get_uri_args
local server_name   = require("ngx.ssl").server_name


--local strip_uri_args       = utils.strip_uri_args


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
    function(params, ctx)
      --if not params.uri then
      --  params.uri = strip_uri_args(ctx and ctx.request_uri or var.request_uri)
      --end

      return params.uri
    end,

    ["http.host"] =
    function(params)
      --if not params.host then
      --  params.host = var.http_host
      --end
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

    ["net.port"] =
    function(params)
      return params.port
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
      if not params.dst_port then
        params.dst_port = tonumber((ctx or ngx.ctx).host_port, 10) or
                          tonumber(var.server_port, 10)
      end
      return params.dst_port
    end

else

    -- tls.*

    FIELDS_FUNCS["tls.sni"] =
    function(params)
      if not params.sni then
        params.sni = server_name() or var.ssl_preread_server_name
      end
      return params.sni
    end

    -- net.*

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

  -- func => get_headers or get_uri_args
  -- name => "headers" or "queries"
  -- max_config_option => "lua_max_req_headers" or "lua_max_uri_args"
  local function get_http_params(func, name, max_config_option)
    local params, err = func()
    if err == "truncated" then
      local max = kong and kong.configuration and kong.configuration[max_config_option] or 100
      ngx.log(ngx.ERR,
              string.format("router: not all request %s were read in order to determine the route " ..
                            "as the request contains more than %d %s, " ..
                            "route selection may be inaccurate, " ..
                            "consider increasing the '%s' configuration value " ..
                            "(currently at %d)",
                            name, max, name, max_config_option, max))
    end

    return params
  end


  setmetatable(FIELDS_FUNCS, {
  __index = function(t, field)
    local prefix = field:sub(1, PREFIX_LEN)

    if prefix == HTTP_HEADERS_PREFIX then
      return function(params)
        if not params.headers then
          local headers = get_http_params(get_headers, "headers", "lua_max_req_headers")
          --headers["host"] = nil
          params.headers = headers
        end

        return params.headers[field:sub(PREFIX_LEN + 1)]
      end
    end

    if prefix == HTTP_QUERIES_PREFIX then
      return function(params)
        if not params.queries then
          params.queries = get_http_params(get_uri_args, "queries", "lua_max_uri_args")
        end

        return params.queries[field:sub(PREFIX_LEN + 1)]
      end
    end
  end
  })

end -- is_http


local function fields_vistor(fields, params, ctx, cb)
  for _, field in ipairs(fields) do
    local func = FIELDS_FUNCS[field]

    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end -- if func

    local value = func(params, ctx)
    --print("f = ", field, ", v = ", value)

    local res, err = cb(field, value)
    if not res then
      return nil, err
    end
  end -- for fields

  return true
end


local function get_cache_key(fields, params, ctx)
  --print(table.concat(fields, "|"))

  local str_buf = buffer.new(64)

  fields_vistor(fields, params, ctx, function(field, value)
    -- these fields were not in cache key
    if field == "net.protocol" or field == "net.port" then
      return true
    end

    local prefix = field:sub(1, PREFIX_LEN)

    if prefix == HTTP_HEADERS_PREFIX or prefix == HTTP_QUERIES_PREFIX then
      if type(value) == "table" then
        tb_sort(value)
        value = tb_concat(value, ",")
      end

      str_buf:putf("%s=%s|", field, value or "")
      return true
    end

    str_buf:put(value or ""):put("|")
    return true
  end)

  return str_buf:get()
end


local function get_atc_context(schema, fields, params)
  local c = context.new(schema)

  local res, err = fields_vistor(fields, params, nil, function(field, value)
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
      return c:add_value(field, v_type == "boolean" and "" or value)
      --if v_type == "boolean" then
      --  value = ""
      --end
    end

    return c:add_value(field, value)
  end)

  if not res then
    return nil, err
  end

  return c
end


--[[
local SIMPLE_FIELDS_FUNCS = {
    -- http.*

    ["http.method"] =
    function(v, params, cb)
      return cb("http.method", params.method)
    end,

    ["http.path"] =
    function(v, params, cb)
      return cb("http.path", params.uri)
    end,

    ["http.host"] =
    function(v, params, cb)
      return cb("http.host", params.host)
    end,

    -- tls.*

    ["tls.sni"] =
    function(v, params, cb)
      return cb("tls.sni", params.sni)
    end,

    -- net.*

    ["net.src.ip"] =
    function(v, params, cb)
      return cb("net.src.ip", params.src_ip)
    end,

    ["net.src.port"] =
    function(v, params, cb)
      return cb("net.src.port", params.src_port)
    end,

    ["net.dst.ip"] =
    function(v, params, cb)
      return cb("net.dst.ip", params.dst_ip)
    end,

    ["net.dst.port"] =
    function(v, params, cb)
      return cb("net.dst.port", params.dst_port)
    end,

    -- below are atc context only

    ["net.protocol"] =
    function(v, params, cb)
      return cb("net.protocol", params.scheme)
    end,

    ["net.port"] =
    function(v, params, cb)
      return cb("net.port", params.port)
    end,
}


local COMPLEX_FIELDS_FUNCS = {
    ["http.headers."] =
    function(v, params, cb)
      local headers = params.headers
      if not headers then
        return true
      end

      for _, name in ipairs(v) do
        local value = headers[name]

        local res, err = cb("http.headers." .. name, value,
                            replace_dashes_lower) -- only for cache_key
        if not res then
          return nil, err
        end
      end -- for ipairs(v)

      return true
    end,

    ["http.queries."] =
    function(v, params, cb)
      local queries = params.queries
      if not queries then
        return true
      end

      for _, name in ipairs(v) do
        local value = queries[name]

        local res, err = cb("http.queries." .. name, value)
        if not res then
          return nil, err
        end
      end -- for ipairs(v)

      return true
    end,
}
--]]


--[[
-- cache key string
local str_buf = buffer.new(64)


local function get_cache_key(fields, params)
  str_buf:reset()

  -- NOTE: DO NOT yield until str_buf:get()
  for field, value in pairs(fields) do

    -- these fields were not in cache key
    if field == "net.protocol" or
       field == "net.port"
    then
      goto continue
    end

    local func = SIMPLE_FIELDS_FUNCS[field]

    if func then
      func(value, params, function(field, value)
        str_buf:put(value or ""):put("|")
        return true
      end)

      goto continue
    end -- if func

    func = COMPLEX_FIELDS_FUNCS[field]

    if func then  -- http.headers.* or http.queries.*
      func(value, params, function(field, value, lower_func)
        if lower_func then
          field = lower_func(field)
        end

        if type(value) == "table" then
          tb_sort(value)
          value = tb_concat(value, ",")
        end

        str_buf:putf("%s=%s|", field, value or "")

        return true
      end)

      goto continue
    end -- if func

    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end -- if func

    ::continue::
  end -- for fields

  return str_buf:get()
end
--]]

--[[
local function get_atc_context(schema, fields, params)
  local c = context.new(schema)

  for field, value in pairs(fields) do
    local func = SIMPLE_FIELDS_FUNCS[field]

    if func then
      local res, err = func(value, params, function(field, value)
        return c:add_value(field, value)
      end)

      if not res then
        return nil, err
      end

      goto continue
    end -- if func

    func = COMPLEX_FIELDS_FUNCS[field]

    if func then  -- http.headers.* or http.queries.*
      local res, err = func(value, params, function(field, value)
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
        return c:add_value(field, v_type == "boolean" and "" or value)
      end)

      if not res then
        return nil, err
      end

      goto continue
    end -- if func

    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end -- if func

    ::continue::
  end -- for fields

  return c
end
--]]


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
  get_cache_key = get_cache_key,
  get_atc_context = get_atc_context,

  _set_ngx = _set_ngx,
}
