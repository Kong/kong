-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local event_hooks = require "kong.enterprise_edition.event_hooks"
local uuid = require "kong.tools.uuid"
local sandbox = require "kong.tools.sandbox".sandbox
local pdk_private_rl = require "kong.pdk.private.rate_limiting"
local new_namespace = require "kong.plugins.ai-rate-limiting-advanced.namespaces".new
local ratelimiting = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".ratelimiting
local id_lookup = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".id_lookup
local human_window_size_lookup = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".human_window_size_lookup
local HEADERS = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".HEADERS
local ai_plugin_o11y = require "kong.llm.plugin.observability"

local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local rand = math.random
local time = ngx.time

local pdk_rl_store_response_header = pdk_private_rl.store_response_header
local pdk_rl_get_stored_response_header = pdk_private_rl.get_stored_response_header
local pdk_rl_apply_response_headers = pdk_private_rl.apply_response_headers


local _M = {
  NAME = "ai-rate-limiting-advanced-limit-request",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "determine if current request is above the rate limit",
}

local function create_timer(config, namespace)
  local rate = config.sync_rate
  local timer_id = uuid.uuid()
  local now = ngx.now()

  -- 0 <= when <= sync_rate, depends on timestamp
  local when = rate - (now - (floor(now / rate) * rate))
  kong.log.debug("creating timer for namespace ", namespace, ", timer_id: ",
                 timer_id, ", initial sync in ", when, " seconds")
  ngx.timer.at(when, ratelimiting.sync, namespace, timer_id)
  ratelimiting.config[namespace].timer_id = timer_id

  -- add a timeout to avoid situations where the lock can
  -- never be released when an exception happens
  ratelimiting.fetch(nil, namespace, now, min(rate - 0.001, 2), true)
end


function _M:run(conf)
  local now = time()
  local key = id_lookup[conf.identifier](conf)

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  local plugin_id = conf.__plugin_id
  local window_type = conf.window_type
  local shm = ngx.shared[conf.dictionary_name]
  local deny_providers = {}
  local ngx_ctx = ngx.ctx

  for _, provider_config in ipairs(conf.llm_providers) do

    local provider = provider_config.name
    local namespace_provider = provider .. ":" .. plugin_id
    local current_window = tonumber(provider_config.window_size)
    local current_limit = tonumber(provider_config.limit)

    if not ratelimiting.config[namespace_provider] then
      new_namespace(conf, nil , namespace_provider, current_window)
    end

    -- create the timer lazily so that no timers are created for zombie plugins.
    -- Let's say we have two RLA plugins. Plugin 1 is in workspace A and plugin 2
    -- is in workspace B. DP 1 serves workspace A and DP 2 serves workspace B.
    -- DP 1 and DP 2 are in different network enviorments. They each have their own
    -- redis service. DP 1 can never get access to the redis of DP 2, and vice versa.
    --
    -- If we don't create timers lazily, some timers will fail to connect to the
    -- redis forever which leads to error log flooding.
    --
    -- Even if there were no network isolation issues, it would be a waste to let
    -- the timers run empty there which will degrade the performance.
    -- https://konghq.atlassian.net/browse/FTI-5246
    if conf.sync_rate > 0 and not ratelimiting.config[namespace_provider].timer_id then
      create_timer(conf, namespace_provider)
    end

    local request_prompt_count_function_cost

    if conf.request_prompt_count_function and provider == "requestPrompt" then
      local success, request_prompt_cost = pcall(sandbox(conf.request_prompt_count_function))

      if success then
        if type(request_prompt_cost) ~= "number" then
            -- The code returned something unknown
            kong.log.err("Bad return value from function, expected number type, got ", type(request_prompt_cost))
            kong.response.exit(500, { message = "Bad return value from the request prompt count function" })
        end
        request_prompt_count_function_cost = request_prompt_cost
      else
        -- Handle errors from pcall
        kong.log.err("Error executing request prompt count function: ", request_prompt_cost)
        kong.response.exit(500, { message = "Error executing request prompt count function" })
      end
    end

    -- if we have exceeded any rate, we should not increment any other windows,
    -- but we should still show the rate to the client, maintaining a uniform
    -- set of response headers regardless of whether we block the request
    local rate = ratelimiting.sliding_window(key, current_window, nil, namespace_provider,
                                        window_type == "fixed" and 0 or nil)

    if provider == "requestPrompt" then
      -- update the adhoc rate if provider is requestPrompt (i.e. the only provider we can get cost during access phase)
      -- this also means when using other cost measurements (tokens, cost etc from response), the header sent will be
      -- bit "laggy" compared to the actual value
      rate = ratelimiting.increment(key, current_window, request_prompt_count_function_cost, namespace_provider,
                                      window_type == "fixed" and 0 or nil)
    end

    -- Ensure the window start time persists using shared memory
    -- This handles the thundering herd problem for the sliding window reset
    -- calculation to be extended longer than the actual window size
    local window_start = floor(now / current_window) * current_window
    local window_start_timstamp_key = "timestamp:" .. current_window .. ":window_start:" .. namespace_provider
    if rate > current_limit and window_type == "sliding" then
      shm:add(window_start_timstamp_key, window_start)
      window_start = shm:get(window_start_timstamp_key) or window_start
    else
      shm:delete(window_start_timstamp_key)
    end

    -- legacy logic of naming rate limiting headers. if we configured a window
    -- size that looks like a human friendly name, give that name
    local window_name = human_window_size_lookup[current_window] or tostring(current_window)
    window_name = window_name .. "-" .. provider

    local current_remaining
    if conf.tokens_count_strategy == "cost" then
      current_remaining = max(current_limit - rate, 0)
    else
      current_remaining = floor(max(current_limit - rate, 0))
    end

    if not conf.hide_client_headers then
      if provider == "requestPrompt" then
        pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_QUERY_COST .. "-" .. window_name, request_prompt_count_function_cost)
      end
      pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_LIMIT .. "-" .. window_name, current_limit)
      pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_REMAINING .. "-" .. window_name, current_remaining)
    end

    if rate > current_limit then
      -- Since we increment the counter unconditionally until a certain window
      -- has exceeded the limit, we need to record the index of the window
      -- which exceeds the limit in order to decrement the counter back if
      -- necessary, i.e. when the window_type is sliding and conf.disable_penalty
      -- is true.
      table.insert(deny_providers, provider)

      -- Ensure that the proper window reset value is set
      -- Calculate the fixed window reset value
      local reset = max(1.0, current_window - (now - window_start))

      -- Add some weight to the current reset value based on the window
      -- and the rate difference. Apply the adjustment to the current
      -- calculated reset value for a more accurate sliding window estimate.
      if window_type == "sliding" then
        local window_adjustment = max(0.0, (((rate - current_limit) / (rate + current_limit)) * current_window))
        reset = ceil(reset + window_adjustment)
      end

      -- Add draft headers for rate limiting RFC; FTI-1447
      local stored_reset = pdk_rl_get_stored_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RESET)
      if not stored_reset or stored_reset < reset then
        pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RESET, reset)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RESET .. "-" .. window_name, reset)
      end

      local retry_after = reset
      local jitter_max = conf.retry_after_jitter_max

      -- Add a random value (a jitter) to the Retry-After value
      -- to reduce a chance of retries spike occurrence.
      if retry_after and jitter_max > 0 then
        retry_after = retry_after + rand(jitter_max)
      end

      -- Add draft headers for rate limiting RFC; FTI-1447
      local stored_retry_after = pdk_rl_get_stored_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RETRY_AFTER)
      if not stored_retry_after or stored_retry_after < retry_after then
        pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RETRY_AFTER, retry_after)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, HEADERS.X_RATELIMIT_RETRY_AFTER .. "-" .. window_name, retry_after)
      end

      -- only gets emitted when kong.configuration.databus_enabled = true
      -- no need to if here
      -- XXX we are doing it on this flow of code because it's easier to
      -- get the rate and the limit that triggered it. Move it somewhere
      -- general later.
      event_hooks.emit("ai-rate-limiting-advanced", "rate-limit-exceeded-provider-".. provider, {
        consumer = kong.client.get_consumer() or {},
        ip = kong.client.get_forwarded_ip(),
        service = kong.router.get_service() or {},
        rate = rate,
        limit = current_limit,
        window = window_name,
      })
    end
  end

  pdk_rl_apply_response_headers(ngx_ctx)

  if next(deny_providers) ~= nil then
    local error_message = conf.error_message
    if not conf.error_hide_providers then
      error_message = error_message .. table.concat(deny_providers, ", ")
    end

    -- as we block the request from going upstream, clear any existing metrics if they are set before proxying
    ai_plugin_o11y.metrics_set("llm_prompt_tokens_count", 0)
    ai_plugin_o11y.metrics_set("llm_completion_tokens_count", 0)

    return kong.response.exit(conf.error_code, { message = error_message })
  end

  return true
end


return _M
