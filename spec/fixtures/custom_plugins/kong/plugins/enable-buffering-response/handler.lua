-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx = ngx
local kong = kong


local EnableBuffering = {
  PRIORITY = math.huge
}


function EnableBuffering:access()
  kong.service.request.enable_buffering()
end


function EnableBuffering:response(conf)
  if conf.phase == "response" then
    if conf.mode == "modify-json" then
      local body = assert(kong.service.response.get_body())
      body.modified = true
      return kong.response.exit(kong.service.response.get_status(), body, {
        Modified = "yes",
      })
    end

    if conf.mode == "md5-header" then
      local body = kong.service.response.get_raw_body()
      kong.response.set_header("MD5", ngx.md5(body))
    end
  end
end


return EnableBuffering
