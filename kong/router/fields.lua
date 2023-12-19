local buffer = require("string.buffer")
local context = require("resty.router.context")


local type = type
local pairs = pairs
local ipairs = ipairs
local tb_sort = table.sort
local tb_concat = table.concat
local replace_dashes_lower = require("kong.tools.string").replace_dashes_lower


-- 13 bytes, same len for "http.queries."
local PREFIX_LEN = 13 -- #"http.headers."


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

        local res, err = cb("http.headers." .. name, value)
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


-- cache key string
local str_buf = buffer.new(64)


local function get_cache_key(fields, params)
  str_buf:reset()

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
      func(value, params, function(field, value)
        local headers_or_queries = field:sub(1, PREFIX_LEN)

        if headers_or_queries == "http.headers." then
          field = replace_dashes_lower(field)
        end

        if type(value) == "table" then
          tb_sort(value)
          value = tb_concat(value, ",")
        end

        str_buf:putf("%s=%s|", field, value or "")

        return true
      end)
    end -- if func

    -- ignore unknown fields

    ::continue::
  end -- for fields

  return str_buf:get()
end


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


return {
  get_cache_key = get_cache_key,
  get_atc_context = get_atc_context,
}
