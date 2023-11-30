local buffer = require("string.buffer")


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


return {
  HTTP_CACHE_KEY_FUNCS = HTTP_CACHE_KEY_FUNCS,

  get_http_cache_key = get_http_cache_key,
}
