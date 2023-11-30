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


return {
  HTTP_CACHE_KEY_FUNCS = HTTP_CACHE_KEY_FUNCS,
}
