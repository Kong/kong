local buffer = require("string.buffer")
local context = require("resty.router.context")


local type = type
local pairs = pairs
local ipairs = ipairs
local assert = assert
local tb_sort = table.sort
local tb_concat = table.concat
local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


-- cache key string
local str_buf = buffer.new(64)


local function _get_atc_context(funcs, schema, fields, params)
  local c = context.new(schema)

  for field, value in pairs(fields) do
    local func = funcs[field]
    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end

    assert(value)

    local res, err = func(value, c, params)
    if not res then
      return nil, err
    end
  end -- for fields

  return c
end


local get_cache_key, get_atc_context


local is_http = ngx.config.subsystem == "http"


if is_http then


local HTTP_CACHE_KEY_FUNCS = {
    ["http.method"] =
    function(v, params, buf)
      buf:put(params.method or ""):put("|")
    end,

    ["http.path"] =
    function(v, params, buf)
      buf:put(params.uri or ""):put("|")
    end,

    ["http.host"] =
    function(v, params, buf)
      buf:put(params.host or ""):put("|")
    end,

    ["tls.sni"] =
    function(v, params, buf)
      buf:put(params.sni or ""):put("|")
    end,

    ["http.headers."] =
    function(v, params, buf)
      local headers = params.headers
      if not headers then
        return
      end

      for _, name in ipairs(v) do
        local name = replace_dashes_lower(name)
        local value = headers[name]

        if type(value) == "table" then
          tb_sort(value)
          value = tb_concat(value, ",")
        end

        buf:putf("%s=%s|", name, value)
      end
    end,

    ["http.queries."] =
    function(v, params, buf)
      local queries = params.queries
      if not queries then
        return
      end

      for _, name in ipairs(v) do
        local value = queries[name]

        if type(value) == "table" then
          tb_sort(value)
          value = tb_concat(value, ",")
        end

        buf:putf("%s=%s|", name, value)
      end
    end,
}


local HTTP_MATCH_CTX_FUNCS = {
    ["http.method"] =
    function(v, c, params)
      return c:add_value("http.method", params.method)
    end,

    ["http.path"] =
    function(v, c, params)
      return c:add_value("http.path", params.uri)
    end,

    ["http.host"] =
    function(v, c, params)
      return c:add_value("http.host", params.host)
    end,

    ["tls.sni"] =
    function(v, c, params)
      return c:add_value("tls.sni", params.sni)
    end,

    ["net.protocol"] =
    function(v, c, params)
      return c:add_value("net.protocol", params.scheme)
    end,

    ["net.port"] =
    function(v, c, params)
      return c:add_value("net.port", params.port)
    end,

    ["http.headers."] =
    function(v, c, params)
      local headers = params.headers
      if not headers then
        return true
      end

      for _, h in ipairs(v) do
        local v = headers[h]
        local f = "http.headers." .. h

        if type(v) == "string" then
          local res, err = c:add_value(f, v)
          if not res then
            return nil, err
          end

        elseif type(v) == "table" then
          for _, v in ipairs(v) do
            local res, err = c:add_value(f, v)
            if not res then
              return nil, err
            end
          end
        end -- if type(v)
      end

      return true
    end,

    ["http.queries."] =
    function(v, c, params)
      local queries = params.queries
      if not queries then
        return true
      end

      for _, n in ipairs(v) do
        local v = queries[n]
        local f = "http.queries." .. n

        -- the query parameter has only one value, like /?foo=bar
        if type(v) == "string" then
          local res, err = c:add_value(f, v)
          if not res then
            return nil, err
          end

        -- the query parameter has no value, like /?foo,
        -- get_uri_arg will get a boolean `true`
        -- we think it is equivalent to /?foo=
        elseif type(v) == "boolean" then
          local res, err = c:add_value(f, "")
          if not res then
            return nil, err
          end

        -- multiple values for a single query parameter, like /?foo=bar&foo=baz
        elseif type(v) == "table" then
          for _, v in ipairs(v) do
            local res, err = c:add_value(f, v)
            if not res then
              return nil, err
            end
          end
        end -- if type(v)
      end

      return true
    end,
}


function get_cache_key(fields, params)
  for field, func in pairs(HTTP_CACHE_KEY_FUNCS) do
    local value = fields[field]

    if value or                 -- true or table
       field == "http.host" or  -- preserve_host
       field == "http.path"     -- 05-proxy/02-router_spec.lua:1329
    then
      func(value, params, str_buf)
    end
  end

  return str_buf:get()
end


function get_atc_context(schema, fields, params)
  return _get_atc_context(HTTP_MATCH_CTX_FUNCS, schema, fields, params)
end


else -- stream subsystem


local STREAM_CACHE_KEY_FUNCS = {
    ["net.src.ip"] =
    function(v, params, buf)
      buf:put(params.src_ip or ""):put("|")
    end,

    ["net.src.port"] =
    function(v, params, buf)
      buf:put(params.src_port or ""):put("|")
    end,

    ["net.dst.ip"] =
    function(v, params, buf)
      buf:put(params.dst_ip or ""):put("|")
    end,

    ["net.dst.port"] =
    function(v, params, buf)
      buf:put(params.dst_port or ""):put("|")
    end,

    ["tls.sni"] =
    function(v, params, buf)
      buf:put(params.sni or ""):put("|")
    end,
}


local STREAM_MATCH_CTX_FUNCS = {
    ["net.src.ip"] =
    function(v, c, params)
      return c:add_value("net.src.ip", params.src_ip)
    end,

    ["net.src.port"] =
    function(v, c, params)
      return c:add_value("net.src.port", params.src_port)
    end,

    ["net.dst.ip"] =
    function(v, c, params)
      return c:add_value("net.dst.ip", params.dst_ip)
    end,

    ["net.dst.port"] =
    function(v, c, params)
      return c:add_value("net.dst.port", params.dst_port)
    end,

    ["tls.sni"] =
    function(v, c, params)
      return c:add_value("tls.sni", params.sni)
    end,

    ["net.protocol"] =
    function(v, c, params)
      return c:add_value("net.protocol", params.scheme)
    end,
}


function get_cache_key(fields, params)
  for field, func in pairs(STREAM_CACHE_KEY_FUNCS) do
    local value = fields[field]

    if value then
      func(value, params, str_buf)
    end
  end

  return str_buf:get()
end


function get_atc_context(schema, fields, params)
  return _get_atc_context(STREAM_MATCH_CTX_FUNCS, schema, fields, params)
end


end -- is_http


return {
  get_cache_key = get_cache_key,
  get_atc_context = get_atc_context,
}
