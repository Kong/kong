-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local DebugSessionManager =  {
  VERSION = "9.9.9",
  PRIORITY = 1000,
}


function DebugSessionManager:access(conf)
  local session = kong.request.get_header("session")
  if session then
    session = cjson.decode(session)
    kong.debug_session:handle_action(session)
  end
end


return DebugSessionManager
