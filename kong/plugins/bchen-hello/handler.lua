-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local get_header = require("kong.tools.http").get_header

local MyPluginHandler = {
    PRIORITY = 1000,
    VERSION = "0.0.1",
}

function MyPluginHandler:access()
  -- ngx.ctx.get_headers_patch = 0
  local start = os.clock()
  for i=1,10 do
    local headers = ngx.req.get_headers()
    -- ngx.req.set_header("foo", tostring(i))
    -- ngx.log(ngx.WARN, "bchen access", ngx.req.get_headers()["Content-Type"])
    -- local v = headers["Content-Type"]
  end
  local elapsed = (os.clock() - start)

  ngx.log(ngx.WARN, "bchen access", string.format(" elapsed time: %.10f, %d\n", elapsed, 1))
  
  -- ngx.request.set_header("foo", "bar")
end

function MyPluginHandler:response(conf)
  
  -- local content_type = kong.response.get_header("Content-Type")
  kong.response.set_header("X-BChen-Plugin", "response")
  local headers = kong.response.get_headers()
  local headers2 = kong.service.response.get_headers()
  local fmt = string.format
  local string_tools = require "kong.tools.string"
  local replace_dashes_lower = string_tools.replace_dashes_lower
--   ngx.log(ngx.WARN, "single: ", "multi-foo-r".." : "..tostring(kong.response.get_header("multi-foo-r")))

--   for k, v in pairs(headers) do
--     ngx.log(ngx.WARN, "resp header: ", k.." : "..tostring(v))
--     local var = fmt("upstream_http_%s", replace_dashes_lower(k))
--     if ngx.var[var] then
--       ngx.log(ngx.WARN, "upstream header: ", k)
--     end
--   end
--   for k, v in pairs(headers2) do
--     ngx.log(ngx.WARN, "service header: ", k.." : "..tostring(v))
--   end
end


return MyPluginHandler
