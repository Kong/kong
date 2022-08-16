local _M = {}
local schema = require("resty.router.schema")


local CACHED_SCHEMA


do
  local str_fields = {"net.protocol", "tls.sni",
                      "http.method", "http.host",
                      "http.path", "http.raw_path",
                      "http.headers.*",
  }

  local int_fields = {"net.port",
  }

  CACHED_SCHEMA = schema.new()

  for _, v in ipairs(str_fields) do
    assert(CACHED_SCHEMA:add_field(v, "String"))
  end

  for _, v in ipairs(int_fields) do
    assert(CACHED_SCHEMA:add_field(v, "Int"))
  end
end


function _M.get_schema()
  return CACHED_SCHEMA
end


return _M
