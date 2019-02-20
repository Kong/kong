local constants = require "kong.plugins.statsd-advanced.constants"

-- Constants
local ngx_log = ngx.log
local DEBUG   = ngx.DEBUG
local ERR     = ngx.ERR
local match   = ngx.re.match

local START_RANGE_IDX = 1
local END_RANGE_IDX   = 2

local result_cache = setmetatable({}, { __mode = "k" })
local range_cache  = setmetatable({}, { __mode = "k" })

local function log(lvl, ...)
  ngx_log(lvl, "[statsd-advanced loghelper] ", ...)
end

local _M = {}

local function get_cache_value(cache, cache_key)
  local cache_value = cache[cache_key]
  if not cache_value then
    cache_value = {}
    cache[cache_key] = cache_value
  end
  return cache_value
end

local function extract_range(status_code_list, range)
  local start_code, end_code
  local ranges = get_cache_value(range_cache, status_code_list)

  -- If range isn't in the cache, extract and put it in
  if not ranges[range] then
    local range_result, err = match(range, constants.REGEX_SPLIT_STATUS_CODES_BY_DASH, "oj")

    if err then
      log(ERR, err)
      return
    end
    ranges[range] = { range_result[START_RANGE_IDX], range_result[END_RANGE_IDX] }
  end

  start_code = ranges[range][START_RANGE_IDX]
  end_code = ranges[range][END_RANGE_IDX]

  return start_code, end_code
end

-- Returns true if a given status code is within status code ranges
local function is_in_range(status_code_list, status_code)
  -- If there is no configuration then pass all response codes
  if not status_code_list then
    return true
  end

  local result_list = get_cache_value(result_cache, status_code_list)
  local result = result_list[status_code]

  -- If result is found in a cache then return results instantly
  if result ~= nil then
    return result
  end

  for _, range in ipairs(status_code_list) do
    -- Get status code range splitting by "-" character
    local start_code, end_code = extract_range(status_code_list, range)

    -- Checks if there is both interval numbers
    if start_code and end_code then
      -- If HTTP response code is in the range return true
      if status_code >= tonumber(start_code) and status_code <= tonumber(end_code) then
        -- Storing results in a cache
        result_list[status_code] = true
        return true
      end
    end
  end

  -- Return false if there are no match for a given status code ranges and store it in cache
  result_list[status_code] = false
  return false
end

--
-- Sends log data to statsd server if it pass the rules
--
-- @param conf        - Plugin configuration object
-- @param status code - HTTP response status code
function _M:log(logger, conf, status_code)
  if not logger then
    return
  end

  if is_in_range(conf.allow_status_codes, status_code) then
    log(DEBUG, "Status code is within given status code ranges")
    logger:log(conf)
  end
end

return _M