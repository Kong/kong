local ngx = ngx
local type = type
local assert = assert
local subsystem = ngx.config.subsystem
local math = math


local function is_nil(ctx, name)
  if ctx[name] ~= nil then
    return false, "[ctx-tests] " .. name .. " is not a nil"
  end

  return true
end


local function is_true(ctx, name)
  if ctx[name] ~= true then
    return false, "[ctx-tests] " .. name .. " is not true"
  end

  return true
end


local function is_positive_integer(ctx, name)
  local value = ctx[name]
  if type(value) ~= "number" then
    return false, "[ctx-tests] " .. name .. " is not a number"
  end

  if math.floor(value) ~= value then
    return false, "[ctx-tests] " .. name .. " is not an integer"
  end

  if value <= 0 then
    return false, "[ctx-tests] " .. name .. " is not a positive integer"
  end

  return true
end


local function is_non_negative_integer(ctx, name)
  local value = ctx[name]
  if value == 0 then
    return true
  end

  return is_positive_integer(ctx, name)
end


local function is_equal_to_start_time(ctx, name)
  local ok, err = is_positive_integer(ctx, name)
  if not ok then
    return ok, err
  end

  if ctx[name] < ctx.KONG_PROCESSING_START then
    return false, "[ctx-tests] " .. name .. " is less than the processing start"
  end

  if subsystem ~= "stream" then
    if ctx[name] ~= (ngx.req.start_time() * 1000) then
      return false, "[ctx-tests] " .. name .. " is less than the request start time"
    end
  end

  return true
end


local function is_greater_or_equal_to_start_time(ctx, name)
  local ok, err = is_positive_integer(ctx, name)
  if not ok then
    return ok, err
  end

  if ctx[name] < ctx.KONG_PROCESSING_START then
    return false, "[ctx-tests] " .. name .. " is less than the processing start"
  end

  if subsystem ~= "stream" then
    if ctx[name] < (ngx.req.start_time() * 1000) then
      return false, "[ctx-tests] " .. name .. " is less than the request start time"
    end
  end

  return true
end


local function is_greater_or_equal_to_ctx_value(ctx, name, greater_name)
  local ok, err = is_positive_integer(ctx, name)
  if not ok then
    return ok, err
  end

  local ok, err = is_positive_integer(ctx, greater_name)
  if not ok then
    return ok, err
  end

  if ctx[greater_name] < ctx[name] then
    return false, "[ctx-tests] " .. name .. " is greater than " .. greater_name
  end

  return true
end


local function has_correct_proxy_latency(ctx)
  local ok, err = is_positive_integer(ctx, "KONG_BALANCER_ENDED_AT")
  if not ok then
    return ok, err
  end

  local ok, err = is_non_negative_integer(ctx, "KONG_PROXY_LATENCY")
  if not ok then
    return ok, err
  end

  if ctx.KONG_BALANCER_ENDED_AT < ctx.KONG_PROCESSING_START then
    return false, "[ctx-tests] KONG_BALANCER_ENDED_AT is less than the processing start"
  end

  local latency = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START
  if ctx.KONG_PROXY_LATENCY ~= latency then
    return false, "[ctx-tests] KONG_PROXY_LATENCY is not calculated correctly"
  end

  if subsystem ~= "stream" then
    latency = ctx.KONG_BALANCER_ENDED_AT - ngx.req.start_time() * 1000
    if ctx.KONG_PROXY_LATENCY ~= latency then
      return false, "[ctx-tests] KONG_PROXY_LATENCY is not calculated correctly (request start time)"
    end
  end

  return true
end


local function has_correct_waiting_time(ctx)
  local ok, err = is_positive_integer(ctx, "KONG_HEADER_FILTER_START")
  if not ok then
    return ok, err
  end

  local ok, err = is_positive_integer(ctx, "KONG_BALANCER_ENDED_AT")
  if not ok then
    return ok, err
  end

  local waiting_time = ctx.KONG_HEADER_FILTER_START - ctx.KONG_BALANCER_ENDED_AT

  if ctx.KONG_WAITING_TIME ~= waiting_time then
    return false, "[ctx-tests] KONG_WAITING_TIME is not calculated correctly"
  end

  return true
end


local function has_correct_receive_time(ctx)
  local ok, err = is_positive_integer(ctx, "KONG_BODY_FILTER_ENDED_AT")
  if not ok then
    return ok, err
  end

  local ok, err = is_positive_integer(ctx, "KONG_HEADER_FILTER_START")
  if not ok then
    return ok, err
  end

  local receive_time = ctx.KONG_BODY_FILTER_ENDED_AT - ctx.KONG_HEADER_FILTER_START

  if ctx.KONG_RECEIVE_TIME ~= receive_time then
    return false, "[ctx-tests] KONG_RECEIVE_TIME is not calculated correctly"
  end

  return true
end



local CtxTests = {
  PRIORITY = -math.huge
}


function CtxTests:preread()
  local ctx = ngx.ctx
  assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_PREREAD_START"))
  assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_TIME"))
  assert(is_nil(ctx, "KONG_REWRITE_START"))
  assert(is_nil(ctx, "KONG_REWRITE_ENDED_AT"))
  assert(is_nil(ctx, "KONG_REWRITE_TIME"))
  assert(is_nil(ctx, "KONG_ACCESS_START"))
  assert(is_nil(ctx, "KONG_ACCESS_ENDED_AT"))
  assert(is_nil(ctx, "KONG_ACCESS_TIME"))
  assert(is_nil(ctx, "KONG_BALANCER_START"))
  assert(is_nil(ctx, "KONG_BALANCER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BALANCER_TIME"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_START"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_START"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_LOG_START"))
  assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
  assert(is_nil(ctx, "KONG_LOG_TIME"))
  assert(is_nil(ctx, "KONG_PROXIED"))
  assert(is_nil(ctx, "KONG_PROXY_LATENCY"))
  assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))
  assert(is_nil(ctx, "KONG_WAITING_TIME"))
  assert(is_nil(ctx, "KONG_RECEIVE_TIME"))
end


function CtxTests:rewrite()
  local ctx = ngx.ctx
  assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_start_time(ctx, "KONG_REWRITE_START", "KONG_REWRITE_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_START"))
  assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_TIME"))
  assert(is_nil(ctx, "KONG_REWRITE_ENDED_AT"))
  assert(is_nil(ctx, "KONG_REWRITE_TIME"))
  assert(is_nil(ctx, "KONG_ACCESS_START"))
  assert(is_nil(ctx, "KONG_ACCESS_ENDED_AT"))
  assert(is_nil(ctx, "KONG_ACCESS_TIME"))
  assert(is_nil(ctx, "KONG_BALANCER_START"))
  assert(is_nil(ctx, "KONG_BALANCER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BALANCER_TIME"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_START"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_START"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_LOG_START"))
  assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
  assert(is_nil(ctx, "KONG_LOG_TIME"))
  assert(is_nil(ctx, "KONG_PROXIED"))
  assert(is_nil(ctx, "KONG_PROXY_LATENCY"))
  assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))
  assert(is_nil(ctx, "KONG_WAITING_TIME"))
  assert(is_nil(ctx, "KONG_RECEIVE_TIME"))
end


function CtxTests:access()
  local ctx = ngx.ctx
  assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_start_time(ctx, "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_START", "KONG_REWRITE_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_REWRITE_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_ENDED_AT", "KONG_ACCESS_START"))
  assert(is_nil(ctx, "KONG_PREREAD_START"))
  assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_TIME"))
  assert(is_nil(ctx, "KONG_ACCESS_ENDED_AT"))
  assert(is_nil(ctx, "KONG_ACCESS_TIME"))
  assert(is_nil(ctx, "KONG_BALANCER_START"))
  assert(is_nil(ctx, "KONG_BALANCER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BALANCER_TIME"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_START"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_START"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_LOG_START"))
  assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
  assert(is_nil(ctx, "KONG_LOG_TIME"))
  assert(is_nil(ctx, "KONG_PROXIED"))
  assert(is_nil(ctx, "KONG_PROXY_LATENCY"))
  assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))
  assert(is_nil(ctx, "KONG_WAITING_TIME"))
  assert(is_nil(ctx, "KONG_RECEIVE_TIME"))
end


function CtxTests:header_filter()
  local ctx = ngx.ctx
  assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_start_time(ctx, "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_START", "KONG_REWRITE_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_REWRITE_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_ENDED_AT", "KONG_ACCESS_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_START", "KONG_ACCESS_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_ACCESS_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_ENDED_AT", "KONG_BALANCER_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_START", "KONG_BALANCER_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_BALANCER_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_ENDED_AT", "KONG_HEADER_FILTER_START"))
  assert(is_true(ctx, "KONG_PROXIED"))
  assert(has_correct_proxy_latency(ctx))
  assert(has_correct_waiting_time(ctx))
  assert(is_nil(ctx, "KONG_PREREAD_START"))
  assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_TIME"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_HEADER_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_START"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_LOG_START"))
  assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
  assert(is_nil(ctx, "KONG_LOG_TIME"))
  assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))
  assert(is_nil(ctx, "KONG_RECEIVE_TIME"))
end


function CtxTests:body_filter()
  if not ngx.arg[2] then
    return
  end

  local ctx = ngx.ctx
  assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_start_time(ctx, "KONG_REWRITE_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_START", "KONG_REWRITE_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_REWRITE_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_ENDED_AT", "KONG_ACCESS_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_START", "KONG_ACCESS_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_ACCESS_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_ENDED_AT", "KONG_BALANCER_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_START", "KONG_BALANCER_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_BALANCER_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_ENDED_AT", "KONG_HEADER_FILTER_START"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_HEADER_FILTER_START", "KONG_HEADER_FILTER_ENDED_AT"))
  assert(is_non_negative_integer(ctx, "KONG_HEADER_FILTER_TIME"))
  assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_HEADER_FILTER_ENDED_AT", "KONG_BODY_FILTER_START"))
  assert(is_true(ctx, "KONG_PROXIED"))
  assert(has_correct_proxy_latency(ctx))
  assert(has_correct_waiting_time(ctx))
  assert(is_nil(ctx, "KONG_PREREAD_START"))
  assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
  assert(is_nil(ctx, "KONG_PREREAD_TIME"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
  assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
  assert(is_nil(ctx, "KONG_LOG_START"))
  assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
  assert(is_nil(ctx, "KONG_LOG_TIME"))
  assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))
  assert(is_nil(ctx, "KONG_RECEIVE_TIME"))
end


function CtxTests:log()
  local ctx = ngx.ctx
  if subsystem == "stream" then
    assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_PREREAD_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PREREAD_START", "KONG_PREREAD_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_PREREAD_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PREREAD_ENDED_AT", "KONG_BALANCER_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_START", "KONG_BALANCER_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_BALANCER_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_ENDED_AT", "KONG_LOG_START"))
    assert(is_true(ctx, "KONG_PROXIED"))
    assert(has_correct_proxy_latency(ctx))
    assert(is_nil(ctx, "KONG_REWRITE_START"))
    assert(is_nil(ctx, "KONG_REWRITE_ENDED_AT"))
    assert(is_nil(ctx, "KONG_REWRITE_TIME"))
    assert(is_nil(ctx, "KONG_ACCESS_START"))
    assert(is_nil(ctx, "KONG_ACCESS_ENDED_AT"))
    assert(is_nil(ctx, "KONG_ACCESS_TIME"))
    assert(is_nil(ctx, "KONG_HEADER_FILTER_START"))
    assert(is_nil(ctx, "KONG_HEADER_FILTER_ENDED_AT"))
    assert(is_nil(ctx, "KONG_HEADER_FILTER_TIME"))
    assert(is_nil(ctx, "KONG_BODY_FILTER_START"))
    assert(is_nil(ctx, "KONG_BODY_FILTER_ENDED_AT"))
    assert(is_nil(ctx, "KONG_BODY_FILTER_TIME"))
    assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
    assert(is_nil(ctx, "KONG_LOG_TIME"))
    assert(is_nil(ctx, "KONG_RESPONSE_LATENCY"))

    -- TODO: ngx.var.upstream_first_byte_time?
    assert(is_nil(ctx, "KONG_WAITING_TIME"))


    -- TODO: ngx.ctx.KONG_LOG_START - (ngx.ctx.BALANCER_ENDED_AT + ngx.var.upstream_first_byte_time)?
    assert(is_nil(ctx, "KONG_RECEIVE_TIME"))

  else
    assert(is_equal_to_start_time(ctx, "KONG_PROCESSING_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_PROCESSING_START", "KONG_REWRITE_START"))
    assert(is_greater_or_equal_to_start_time(ctx, "KONG_REWRITE_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_START", "KONG_REWRITE_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_REWRITE_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_REWRITE_ENDED_AT", "KONG_ACCESS_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_START", "KONG_ACCESS_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_ACCESS_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_ACCESS_ENDED_AT", "KONG_BALANCER_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_START", "KONG_BALANCER_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_BALANCER_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BALANCER_ENDED_AT", "KONG_HEADER_FILTER_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_HEADER_FILTER_START", "KONG_HEADER_FILTER_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_HEADER_FILTER_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_HEADER_FILTER_ENDED_AT", "KONG_BODY_FILTER_START"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BODY_FILTER_START", "KONG_BODY_FILTER_ENDED_AT"))
    assert(is_non_negative_integer(ctx, "KONG_BODY_FILTER_TIME"))
    assert(is_greater_or_equal_to_ctx_value(ctx, "KONG_BODY_FILTER_ENDED_AT", "KONG_LOG_START"))
    assert(is_true(ctx, "KONG_PROXIED"))
    assert(has_correct_proxy_latency(ctx))
    assert(has_correct_waiting_time(ctx))
    assert(has_correct_receive_time(ctx))
    assert(is_nil(ctx, "KONG_PREREAD_START"))
    assert(is_nil(ctx, "KONG_PREREAD_ENDED_AT"))
    assert(is_nil(ctx, "KONG_PREREAD_TIME"))
    assert(is_nil(ctx, "KONG_LOG_ENDED_AT"))
    assert(is_nil(ctx, "KONG_LOG_TIME"))
  end
end


return CtxTests
