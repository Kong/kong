-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local debug

do
  local os   = os
  local ngx  = ngx
  local type = type
  if type(ngx) == "table" then
    if ngx.get_phase() == "timer" and ngx.exit == os.exit and arg then
      local log = ngx.say
      if log then
        debug = function(message)
          log(message)
        end
      end

    else
      local log = ngx.log
      if log then
        local DEBUG = ngx.DEBUG
        debug = function(message)
          log(DEBUG, message)
        end
      end
    end
  end

  if not debug then
    debug = function() end
  end
end

return debug

