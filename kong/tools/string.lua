-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local find          = string.find
local gsub          = string.gsub


local _M = {}


local replace_dashes
local replace_dashes_lower
do
  local str_replace_char

  if ngx and ngx.config.subsystem == "http" then

    -- 1,000,000 iterations with input of "my-header":
    -- string.gsub:        81ms
    -- ngx.re.gsub:        74ms
    -- loop/string.buffer: 28ms
    -- str_replace_char:   14ms
    str_replace_char = require("resty.core.utils").str_replace_char

  else    -- stream subsystem
    str_replace_char = function(str, ch, replace)
      if not find(str, ch, nil, true) then
        return str
      end

      return gsub(str, ch, replace)
    end
  end

  replace_dashes = function(str)
    return str_replace_char(str, "-", "_")
  end

  replace_dashes_lower = function(str)
    return str_replace_char(str:lower(), "-", "_")
  end
end
_M.replace_dashes = replace_dashes
_M.replace_dashes_lower = replace_dashes_lower


return _M

