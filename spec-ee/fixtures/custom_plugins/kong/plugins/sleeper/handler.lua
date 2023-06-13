-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Sleeper =  {
  VERSION = "1.0.0",
  PRIORITY = 1,
}

local HEADERS = {
  read_body_sleep = "NGX-Req-Get-Body-Data-Sleep",
}

do
  local orig_get_body_data = ngx.req.get_body_data
  ngx.req.get_body_data = function() -- luacheck: ignore
    local delay = kong.request.get_header(HEADERS.read_body_sleep)
    if delay then
      ngx.sleep(tonumber(delay))
    end
    return orig_get_body_data()
  end
end


return Sleeper
