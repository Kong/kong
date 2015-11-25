local _M = {}

local function increment(api_id, identifier, current_timestamp, value, name)
  -- Increment metrics for all periods if the request goes through
  local _, stmt_err = dao.response_ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value, name)
  if stmt_err then
    ngx.log(ngx.ERR, tostring(stmt_err))
  end
end

local function log(premature, api_id, identifier, current_timestamp, increments, usage)
  -- Increment metrics for all periods if the request goes through
  for k, v in pairs(usage) do
    if increments[k] and increments[k] ~= 0 then
      increment(api_id, identifier, current_timestamp, increments[k], k)
    end
  end
end

function _M.execute(api_id, identifier, current_timestamp, increments, usage)
  local ok, err = ngx.timer.at(0, log, api_id, identifier, current_timestamp, increments, usage)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M