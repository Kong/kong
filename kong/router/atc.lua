-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
