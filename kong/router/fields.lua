local buffer = require("string.buffer")
local context = require("resty.router.context")


local type = type
local pairs = pairs
local ipairs = ipairs
local tb_sort = table.sort
local tb_concat = table.concat
local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


local HTTP_CACHE_KEY_FUNCS = {
  {
    "http.method",
    function(v, ctx, buf)
      buf:put(ctx.req_method or ""):put("|")
    end,
  },
  {
    "http.path",
    function(v, ctx, buf)
      buf:put(ctx.req_uri or ""):put("|")
    end,
  },
  {
    "http.host",
    function(v, ctx, buf)
      buf:put(ctx.req_host or ""):put("|")
    end,
  },
  {
    "tls.sni",
    function(v, ctx, buf)
      buf:put(ctx.sni or ""):put("|")
    end,
  },
  {
    "http.headers.",
    function(v, ctx, buf)
      local headers = ctx.headers
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
  },
  {
    "http.queries.",
    function(v, ctx, buf)
      local queries = ctx.queries
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
  },
}


local HTTP_MATCH_CTX_FUNCS = {
    ["http.method"] =
    function(v, c, ctx)
      return c:add_value("http.method", ctx.req_method)
    end,

    ["http.path"] =
    function(v, c, ctx)
      return c:add_value("http.path", ctx.req_uri)
    end,

    ["http.host"] =
    function(v, c, ctx)
      return c:add_value("http.host", ctx.host)
    end,

    ["tls.sni"] =
    function(v, c, ctx)
      return c:add_value("tls.sni", ctx.sni)
    end,

    ["net.protocol"] =
    function(v, c, ctx)
      return c:add_value("net.protocol", ctx.req_scheme)
    end,

    ["net.port"] =
    function(v, c, ctx)
      return c:add_value("net.port", ctx.port)
    end,

    ["http.headers."] =
    function(v, c, ctx)
      local headers = ctx.headers
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
    function(v, c, ctx)
      local queries = ctx.queries
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


local function get_http_cache_key(fields, ctx)
  local str_buf = buffer.new(64)

  for _, m in ipairs(HTTP_CACHE_KEY_FUNCS) do
    local field = m[1]
    local value = fields[field]

    if value or                 -- true or table
       field == "http.host" or  -- preserve_host
       field == "http.path"     -- 05-proxy/02-router_spec.lua:1329
    then
      local func = m[2]
      func(value, ctx, str_buf)
    end
  end

  return str_buf:get()
end


local function get_http_atc_context(schema, fields, ctx)
  local c = context.new(schema)

  for field, value in pairs(fields) do
    local func = HTTP_MATCH_CTX_FUNCS[field]
    if not func then  -- unknown field
      error("unknown router matching schema field: " .. field)
    end

    assert(value)

    local res, err = func(value, c, ctx)
    if not res then
      return nil, err
    end
  end -- for fields

  return c
end


return {
  get_http_cache_key = get_http_cache_key,
  get_http_atc_context = get_http_atc_context,
}
