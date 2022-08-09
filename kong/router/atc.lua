local _M = {}
local schema = require("resty.router.schema")


local CACHED_SCHEMA


do
  local fields = {"net.protocol", "tls.sni",
                  "http.method", "http.host", "http.path",
                  "http.raw_path", "http.headers.*",
  }

  CACHED_SCHEMA = schema.new()

  for _, v in ipairs(fields) do
    assert(CACHED_SCHEMA:add_field(v, "String"))
  end
end


function _M.get_schema()
  return CACHED_SCHEMA
end


return _M
