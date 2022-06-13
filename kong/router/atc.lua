local _M = {}
local schema = require("resty.router.schema")


local CACHED_SCHEMA


do
  CACHED_SCHEMA = schema.new()
  assert(CACHED_SCHEMA:add_field("net.protocol", "String"))
  assert(CACHED_SCHEMA:add_field("tls.sni", "String"))
  assert(CACHED_SCHEMA:add_field("http.method", "String"))
  assert(CACHED_SCHEMA:add_field("http.host", "String"))
  assert(CACHED_SCHEMA:add_field("http.path", "String"))
  assert(CACHED_SCHEMA:add_field("http.raw_path", "String"))
  assert(CACHED_SCHEMA:add_field("http.headers.*", "String"))
end


function _M.get_schema()
  return CACHED_SCHEMA
end


return _M
