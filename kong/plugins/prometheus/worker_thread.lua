local ngx_re_match = ngx.re.match
local table_sort = table.sort
local METRICS_KEY_REGEX = [[(.*[,{]le=")(.*)(".*)]]

local function fix_histogram_bucket_labels(key)
  local match, err = ngx_re_match(key, METRICS_KEY_REGEX, "jo")
  if err then
    return nil, "failed to match regex: " .. err
  end

  if not match then
    return key
  end

  if match[2] == "Inf" then
    return match[1] .. "+Inf" .. match[3]
  else
    return match[1] .. tostring(tonumber(match[2])) .. match[3]
  end
end

local function shared_metrics_data(local_keys, shared_dict)
  local dict = ngx.shared[shared_dict]
  local res_table = {}
  local keys = dict:get_keys(0)
  
  local count = #keys
  for k, v in pairs(local_keys) do
    keys[count+1] = k
    count = count + 1
  end
  -- Prometheus server expects buckets of a histogram to appear in increasing
  -- numerical order of their label values.
  table_sort(keys)

  for _, key in ipairs(keys) do
    local value, err
    local is_local_metrics = true
    value = local_keys[key]
    if (not value) then
      value = dict:get(key)
      is_local_metrics = false
    end

    if value then
      if not is_local_metrics then -- local metrics is always a gauge
        key, err = fix_histogram_bucket_labels(key)
        if err then
          goto continue
        end
      end
      res_table[key] = value
    end
    ::continue::
  end

  return res_table
end

return {
  shared_metrics_data = shared_metrics_data
}