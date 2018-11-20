local utils = require "kong.tools.utils"

local table_contains = utils.table_contains

local _M = {}

-- true iff resp_code is in allowed_codes
function _M.skip_transform(resp_code, allowed_codes)
  resp_code = tostring(resp_code)
  return resp_code and allowed_codes and #allowed_codes > 0
    and not table_contains(allowed_codes, resp_code)
end

return _M
