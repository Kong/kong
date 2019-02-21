local utils = require "kong.tools.utils"
local constants = require "kong.plugins.response-transformer-advanced.constants"


local table_contains = utils.table_contains
local match = ngx.re.match


local STATUS_CODE_SINGLES = 'single'
local STATUS_CODE_RANGES = 'range'


local status_codes_cache  = setmetatable({}, { __mode = "k" })
local result_cache = setmetatable({}, { __mode = "k" })

local _M = {}


-- Retrieve a cached value by a given cache key
local function get_cache_value(cache, cache_key)
  local cache_value = cache[cache_key]

  if not cache_value then
    cache_value = {}
    cache[cache_key] = cache_value
  end

  return cache_value
end


-- Extracts status codes from the given list by types (singles and ranges)
local function extract_status_codes(status_codes)
  local scodes_cache = get_cache_value(status_codes_cache, status_codes)

  -- Retrieving results from the cache
  local singles = scodes_cache[STATUS_CODE_SINGLES] or {}
  local ranges = scodes_cache[STATUS_CODE_RANGES] or {}

  if #singles > 0 or #ranges > 0 then
    return singles, ranges
  end

  if status_codes then
    -- Iterating over status codes, extracting using regex and grouping by type (singles, ranges)
    for _, item in ipairs(status_codes) do
      local range_res = match(item, constants.REGEX_SPLIT_RANGE, "oj")

      if range_res then
        local range = {
          range_res[1],
          range_res[2]
        }

        table.insert(ranges, range)
      elseif match(item, constants.REGEX_SINGLE_STATUS_CODE, "oj") then
        table.insert(singles, item)
      end
    end

    -- Storing results in a cache
    scodes_cache[STATUS_CODE_SINGLES] = singles
    scodes_cache[STATUS_CODE_RANGES] = ranges
  end

  return singles, ranges
end


-- check if the status code is in given status code ranges
local function is_in_range(ranges, status_code)
  status_code = tonumber(status_code)

  for _, range in ipairs(ranges) do
      local start_range = range[1]
      local end_range = range[2]

      if status_code >= tonumber(start_range)
              and status_code <= tonumber(end_range) then
        return true
      end
  end

  return false
end


-- true iff resp_code is in allowed_codes
function _M.skip_transform(resp_code, allowed_codes)
  if not allowed_codes then
    return false
  end

  resp_code = tostring(resp_code)
  local result_list = get_cache_value(result_cache, allowed_codes)
  local result = result_list[resp_code]

  -- If result is found in a cache then return result instantly
  if result ~= nil then
    return result
  end

  -- Retrieving single status codes and status code ranges
  local singles, ranges = extract_status_codes(allowed_codes)

  result = resp_code
          and allowed_codes
          and #allowed_codes > 0
          and not table_contains(singles, resp_code)
          and not is_in_range(ranges, resp_code)

  -- Storing results in a cache
  result_list[resp_code] = result

  return result
end


return _M
