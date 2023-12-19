local buffer = require("string.buffer")
local context = require("resty.router.context")


local type = type
local pairs = pairs
local ipairs = ipairs
local assert = assert
local fmt = string.format
local tb_sort = table.sort
local tb_concat = table.concat
local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


local is_http = ngx.config.subsystem == "http"


local MATCH_CTX_FUNCS
--local CACHE_KEY_FUNCS


local FIELDS_FUNCS = {
    ["http.method"] =
    function(v, params, func)
      func("http.method", params.method)
    end,

    ["http.path"] =
    function(v, params, func)
      func("http.path", params.uri)
    end,

    ["http.host"] =
    function(v, params, func)
      func("http.host", params.host)
    end,

    ["tls.sni"] =
    function(v, params, func)
      func("tls.sni", params.sni)
    end,

    ["http.headers."] =
    function(v, params, func)
      local headers = params.headers
      if not headers then
        return
      end

      for _, name in ipairs(v) do
        --local name = replace_dashes_lower(name)
        local value = headers[name]

        --if type(value) == "table" then
        --  tb_sort(value)
        --  value = tb_concat(value, ",")
        --end

        func("http.headers." .. name, value)
      end -- for ipairs(v)
    end,

    ["http.queries."] =
    function(v, params, func)
      local queries = params.queries
      if not queries then
        return
      end

      for _, name in ipairs(v) do
        local value = queries[name]

        --if type(value) == "table" then
        --  tb_sort(value)
        --  value = tb_concat(value, ",")
        --end

        func("http.queries." .. name, value)
      end -- for ipairs(v)
    end,

    ["net.src.ip"] =
    function(v, params, func)
      func("net.src.ip", params.src_ip)
    end,

    ["net.src.port"] =
    function(v, params, func)
      func("net.src.port", params.src_port)
    end,

    ["net.dst.ip"] =
    function(v, params, func)
      func("net.dst.ip", params.dst_ip)
    end,

    ["net.dst.port"] =
    function(v, params, func)
      func("net.dst.port", params.dst_port)
    end,
}


if is_http then

--[[
CACHE_KEY_FUNCS = {
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
      end -- for ipairs(v)
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
      end -- for ipairs(v)
    end,
}
--]]


MATCH_CTX_FUNCS = {
    ["http.method"] =
    function(v, params, c)
      return c:add_value("http.method", params.method)
    end,

    ["http.path"] =
    function(v, params, c)
      return c:add_value("http.path", params.uri)
    end,

    ["http.host"] =
    function(v, params, c)
      return c:add_value("http.host", params.host)
    end,

    ["tls.sni"] =
    function(v, params, c)
      return c:add_value("tls.sni", params.sni)
    end,

    ["net.protocol"] =
    function(v, params, c)
      return c:add_value("net.protocol", params.scheme)
    end,

    ["net.port"] =
    function(v, params, c)
      return c:add_value("net.port", params.port)
    end,

    ["http.headers."] =
    function(v, params, c)
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
      end   -- for ipairs(v)

      return true
    end,

    ["http.queries."] =
    function(v, params, c)
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
      end   -- for ipairs(v)

      return true
    end,
}


else -- stream subsystem

--[[
CACHE_KEY_FUNCS = {
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
--]]

MATCH_CTX_FUNCS = {
    ["net.src.ip"] =
    function(v, params, c)
      return c:add_value("net.src.ip", params.src_ip)
    end,

    ["net.src.port"] =
    function(v, params, c)
      return c:add_value("net.src.port", params.src_port)
    end,

    ["net.dst.ip"] =
    function(v, params, c)
      return c:add_value("net.dst.ip", params.dst_ip)
    end,

    ["net.dst.port"] =
    function(v, params, c)
      return c:add_value("net.dst.port", params.dst_port)
    end,

    ["tls.sni"] =
    function(v, params, c)
      return c:add_value("tls.sni", params.sni)
    end,

    ["net.protocol"] =
    function(v, params, c)
      return c:add_value("net.protocol", params.scheme)
    end,
}


end -- is_http


-- cache key string
local str_buf = buffer.new(64)


local function get_cache_key(fields, params)
  for field, value in pairs(fields) do

    -- these fields were not in cache key
    if field == "http.scheme"  or
       field == "net.protocol" or
       field == "net.port"
    then
      goto continue
    end

    local func = FIELDS_FUNCS[field]

    if not func then
      goto continue
    end

    func(value, params, function(field, value)
      local prefix = field:sub(1, 13)

      if prefix == "http.headers." or prefix == "http.queries." then
        if type(value) == "table" then

          if prefix == "http.headers." then
            field = replace_dashes_lower(field)
          end

          tb_sort(value)
          value = tb_concat(value, ",")
        end

        value = fmt("%s=%s", field, value)
      end

      str_buf:put(value or ""):put("|")
    end)

    ::continue::
  end

  return str_buf:get()
end


local function get_atc_context(schema, fields, params)
  local c = context.new(schema)

  for field, value in pairs(fields) do
    local func = MATCH_CTX_FUNCS[field]
    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end

    assert(value)

    local res, err = func(value, params, c)
    if not res then
      return nil, err
    end
  end -- for fields

  return c
end


return {
  get_cache_key = get_cache_key,
  get_atc_context = get_atc_context,
}
