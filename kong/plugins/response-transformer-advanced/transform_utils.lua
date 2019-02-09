local utils = require "kong.tools.utils"

local table_contains = utils.table_contains

local REGEX_SPLIT_RANGE  = "(%d%d%d)%-(%d%d%d)"
local REGEX_SINGLE_STATUS_CODE  = "^%d%d%d$"
local REGEX_STATUS_CODE_RANGE   = "^%d%d%d%-%d%d%d$"

local match = string.match

local _M = {}

-- Extracts status codes from the given list by types (singles and ranges)
local function extract_status_codes(status_codes)
  local singles = {}
  local ranges = {}

  if status_codes then
    for _, item in pairs(status_codes) do
      if match(item, REGEX_STATUS_CODE_RANGE) then
        table.insert(ranges, item)
      elseif match(item, REGEX_SINGLE_STATUS_CODE) then
        table.insert(singles, item)
      end
    end
  end
  return singles, ranges
end

-- check if the status code is in given status code ranges
local function is_in_range(ranges, status_code)
  for _, range in pairs(ranges) do
      status_code = tonumber(status_code)
      local start_r, end_r = match(range, REGEX_SPLIT_RANGE)

      if status_code >= tonumber(start_r)
              and status_code <= tonumber(end_r) then
        return true
      end
   end
   return false
end

-- true iff resp_code is in allowed_codes
function _M.skip_transform(resp_code, allowed_codes)
  local singles, ranges = extract_status_codes(allowed_codes)

  resp_code = tostring(resp_code)
  return resp_code and allowed_codes and #allowed_codes > 0
    and not table_contains(singles, resp_code)
    and not is_in_range(ranges, resp_code)
end

return _M