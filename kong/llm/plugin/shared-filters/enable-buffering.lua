-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {
  NAME = "enable-buffering",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "set the response to buffering mode",
}

function _M:run(_)
  if ngx.get_phase() == "access" then
    kong.service.request.enable_buffering()
  end

  return true
end

return _M