-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ratelimiting = require("kong.tools.public.rate-limiting").new_instance("ai-rate-limiting-advanced", { redis_config_version = "v2" })
local ai_shared = require("kong.llm.drivers.shared")
local schema = require "kong.plugins.ai-rate-limiting-advanced.schema"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local sandbox = require "kong.tools.sandbox".sandbox
local meta = require "kong.meta"
local uuid = require "kong.tools.uuid"
local pl_tablex = require "pl.tablex"
local pdk_private_rl = require "kong.pdk.private.rate_limiting"
local llm_state = require "kong.llm.state"

local ngx = ngx
local null = ngx.null
local kong = kong
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local rand = math.random
local time = ngx.time
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local pdk_rl_store_response_header = pdk_private_rl.store_response_header
local pdk_rl_get_stored_response_header = pdk_private_rl.get_stored_response_header
local pdk_rl_apply_response_headers = pdk_private_rl.apply_response_headers

local sandbox_opts = { env = { kong = kong, ngx = ngx } }

local NewRLHandler = {
  PRIORITY = 905,
  VERSION = meta.core_version
}

-- Add draft headers for rate limiting RFC
-- https://tools.ietf.org/html/draft-polli-ratelimit-headers-02
local X_RATELIMIT_LIMIT = "X-AI-RateLimit-Limit"
local X_RATELIMIT_REMAINING = "X-AI-RateLimit-Remaining"
local X_RATELIMIT_RESET = "X-AI-RateLimit-Reset"
local X_RATELIMIT_RETRY_AFTER = "X-AI-RateLimit-Retry-After"
local X_RATELIMIT_QUERY_COST = "X-AI-RateLimit-Query-Cost"


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}


local id_lookup = {
  ip = function()
    return kong.client.get_forwarded_ip()
  end,
  credential = function()
    return kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  consumer = function()
    -- try the consumer, fall back to credential
    return kong.client.get_consumer() and
           kong.client.get_consumer().id or
           kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  service = function()
    return kong.router.get_service() and
           kong.router.get_service().id
  end,
  header = function(conf)
    return kong.request.get_header(conf.header_name)
  end,
  path = function(conf)
    return kong.request.get_path() == conf.path and conf.path
  end,
  ["consumer-group"] = function (conf)
    local scoped_to_cg_id = conf.consumer_group_id
    if not scoped_to_cg_id then
      return nil
    end
    for _, cg in ipairs(kong.client.get_consumer_groups()) do
      if cg.id == scoped_to_cg_id then
        return cg.id
      end
    end
    return nil
  end
}

local function send_stats_error()
  local aip_conf = llm_state.get_ai_proxy_conf()
  if not aip_conf then
    return
  end

  local response_stats = {
    usage = {
      prompt_tokens = 0,
      completion_tokens = 0,
      total_tokens = 0,
    }
  }
  ai_shared.post_request(aip_conf, response_stats)
end

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

local function new_namespace(config, timer_id, namespace, window_sizes)
  if not config then
    kong.log.warn("no config was specified.",
                  " Skipping the namespace creation.")
    return false
  end

  kong.log.debug("attempting to add namespace ", namespace)

  local strategy = config.strategy == "cluster" and
                   kong.configuration.database or
                   "redis"

  local strategy_opts = strategy == "redis" and config.redis

  if config.strategy == "local" then
    if config.sync_rate ~= null and config.sync_rate ~= nil and config.sync_rate > -1 then
      kong.log.warn("sync_rate cannot be configured when using a local strategy, default sync_rate to -1")
    end
    config.sync_rate = -1
  end


  -- no shm was specified, try the default value specified in the schema
  local dict_name = config.dictionary_name
  if dict_name == nil then
    dict_name = schema.fields.dictionary_name.default
    if dict_name then
      kong.log.warn("no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    else
      kong.log.warn("no schema default was specified.",
        " Skipping the namespace creation.")
      return false
    end
  end

  -- if dictionary name was passed but doesn't exist, fallback to kong
  if ngx.shared[dict_name] == nil then
    kong.log.notice("specified shared dictionary '", dict_name,
      "' doesn't exist. Falling back to the 'kong' shared dictionary")
    dict_name = "kong"
  end
  kong.log.notice("using shared dictionary '"
                       .. dict_name .. "'")

  local ok, err = pcall(function()
    ratelimiting.new({
      namespace     = namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      window_sizes  = window_sizes,
      db            = kong.db,
      timer_id      = timer_id,
    })
  end)

  if not ok then
    kong.log.err("err in creating new ratelimit namespace ", namespace, " :", err)
    return false
  end

  return true
end


local function update_namespace(config, timer_id, namespace, window_sizes)
  if not config then
    kong.log.warn("no config was specified.",
                  " Skipping the namespace creation.")
    return false
  end

  kong.log.debug("attempting to update namespace ", namespace)

  local strategy = config.strategy == "cluster" and
                   kong.configuration.database or
                   "redis"

  local strategy_opts = strategy == "redis" and config.redis

  if config.strategy == "local" then
    if config.sync_rate ~= null and config.sync_rate ~= nil and config.sync_rate > -1 then
      kong.log.warn("sync_rate cannot be configured when using a local strategy, default sync_rate to -1")
    end
    config.sync_rate = -1
  end


  -- no shm was specified, try the default value specified in the schema
  local dict_name = config.dictionary_name
  if dict_name == nil then
    dict_name = schema.fields.dictionary_name.default
    if dict_name then
      kong.log.warn("no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    else
      kong.log.warn("no schema default was specified.",
        " Skipping the namespace creation.")
      return false
    end
  end

  -- if dictionary name was passed but doesn't exist, fallback to kong
  if ngx.shared[dict_name] == nil then
    kong.log.notice("specified shared dictionary '", dict_name,
      "' doesn't exist. Falling back to the 'kong' shared dictionary")
    dict_name = "kong"
  end
  kong.log.notice("using shared dictionary '"
                       .. dict_name .. "'")

  local ok, err = pcall(function()
    ratelimiting.update({
      namespace     = namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      window_sizes  = window_sizes,
      db            = kong.db,
      timer_id      = timer_id,
    })
  end)

  if not ok then
    kong.log.err("err in updating ratelimit namespace ", namespace, " :", err)
    return false
  end

  return true
end


-- fields that are required for synchronizing counters for a namespace
local sync_fields = {
  "window_size", "sync_rate", "strategy", "dictionary_name", "redis",
}

local function get_sync_conf(conf)
  local sync_conf = {}
  for _, k in ipairs(sync_fields) do
    sync_conf[k] = conf[k]
  end

  return sync_conf
end

local function are_same_config(conf1, conf2)
  return pl_tablex.deepcompare(conf1, conf2)
end


function NewRLHandler:init_worker()
  event_hooks.publish("ai-rate-limiting-advanced", "rate-limit-exceeded", {
    fields = { "consumer", "ip", "service", "rate", "limit", "window" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when a rate limit has been exceeded",
  })
end


function NewRLHandler:configure(configs)
  local namespaces = {}

  if configs then
    for _, config in ipairs(configs) do
      local plugin_id = config.__plugin_id
      local sync_rate = config.sync_rate
      if not sync_rate or
      sync_rate == null
      then
        sync_rate = -1
      end

      for _, provider_config in ipairs(config.llm_providers) do
        config.window_size = provider_config.window_size
        local namespace_provider = provider_config.name .. ":" .. plugin_id

        if namespaces[namespace_provider] then
          if not are_same_config(namespaces[namespace_provider], get_sync_conf(config)) then
            kong.log.err("multiple ai-rate-limiting-advanced plugins with the namespace '", namespace_provider,
              "' have different counter syncing configurations. Please correct them to use the same configuration.")
          end
        else

          namespaces[namespace_provider] = get_sync_conf(config)
        end

        kong.log.debug("clear and reset ", namespace_provider)

        -- previous config doesn't exist for this worker
        -- create a namespace for the new config and return, similar to "rl:create"
        if not ratelimiting.config[namespace_provider] then
          new_namespace(config, nil, namespace_provider, provider_config.window_size)

        else
          local timer_id

          -- if the previous config has a timer_id, i.e., a background timer already exists,
          -- and the current config still needs a timer, we pass the timer_id to reuse the
          -- existing timer
          if sync_rate > 0 then
            timer_id = ratelimiting.config[namespace_provider].timer_id
          end

          update_namespace(config, timer_id, namespace_provider, provider_config.window_size)

          -- recommendation have changed with FT-928
          if sync_rate > 0 and sync_rate < 1 then
            kong.log.warn("Config option 'sync_rate' " .. sync_rate .. " is between 0 and 1; a config update is recommended")
          end
        end
      end
    end
  end

  for namespace in pairs(ratelimiting.config) do
    if not namespaces[namespace] then
      kong.log.debug("clearing old namespace ", namespace)
      ratelimiting.config[namespace].kill = true
      ratelimiting.config[namespace].timer_id = nil
    end
  end
end


function NewRLHandler:access(conf)
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
    local query_cost = 0

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

    if conf.request_prompt_count_function and provider == "requestPrompt" then
      local success, request_prompt_cost = pcall(sandbox(conf.request_prompt_count_function, sandbox_opts))

      if success then
          if type(request_prompt_cost) ~= "number" then
              -- The code returned something unknown
              kong.log.err("Bad return value from function, expected number type, got ", type(request_prompt_cost))
              kong.response.exit(500, { message = "Bad return value from the request prompt count function" })
          end
          query_cost = request_prompt_cost
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
      if rate < current_limit or not conf.disable_penalty then
        rate = ratelimiting.increment(key, current_window, query_cost, namespace_provider,
                                      window_type == "fixed" and 0 or nil)
      end
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
    local window_name = human_window_size_lookup[current_window] or current_window
    window_name = window_name .. "-" .. provider

    local current_remaining
    if conf.tokens_count_strategy == "cost" then
      current_remaining = max(current_limit - rate, 0)
    else
      current_remaining = floor(max(current_limit - rate, 0))
    end

    if not conf.hide_client_headers then
      if provider == "requestPrompt" then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_QUERY_COST .. "-" .. window_name, query_cost)
      end

      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_LIMIT .. "-" .. window_name, current_limit)
      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_REMAINING .. "-" .. window_name, current_remaining)
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
      local stored_reset = pdk_rl_get_stored_response_header(ngx_ctx, X_RATELIMIT_RESET)
      if not stored_reset or stored_reset < reset then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RESET, reset)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RESET .. "-" .. window_name, reset)
      end

      local retry_after = reset
      local jitter_max = conf.retry_after_jitter_max

      -- Add a random value (a jitter) to the Retry-After value
      -- to reduce a chance of retries spike occurrence.
      if retry_after and jitter_max > 0 then
        retry_after = retry_after + rand(jitter_max)
      end

      -- Add draft headers for rate limiting RFC; FTI-1447
      local stored_retry_after = pdk_rl_get_stored_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER)
      if not stored_retry_after or stored_retry_after < retry_after then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER, retry_after)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER .. "-" .. window_name, retry_after)
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

    send_stats_error()
    return kong.response.exit(conf.error_code, { message = error_message })
  end
end


function NewRLHandler:header_filter(conf)
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

  local request_analytics = llm_state.get_request_analytics() or {}
  kong.ctx.plugin.ai_query_cost = {}

  for _, plugin_data in pairs(request_analytics) do
    local provider = plugin_data.meta.provider_name
    kong.ctx.plugin.ai_query_cost[provider] = (kong.ctx.plugin.ai_query_cost[provider] or 0) + plugin_data.usage[conf.tokens_count_strategy]
  end

  for _, provider_config in ipairs(conf.llm_providers) do

    local provider = provider_config.name
    local namespace_provider = provider .. ":" .. plugin_id
    local current_window = tonumber(provider_config.window_size)
    local current_limit = tonumber(provider_config.limit)
    kong.ctx.plugin.ai_query_cost[provider] = kong.ctx.plugin.ai_query_cost[provider] or 0

    local query_cost = kong.ctx.plugin.ai_query_cost[provider]

    -- we increment all window even if we have exceeded any rate,
    -- as the ai requests has already been sent in body filter phase
    -- this part won't be called if we block the request in access phase
    local rate = ratelimiting.increment(key, current_window, query_cost, namespace_provider,
                                    window_type == "fixed" and 0 or nil)
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
    local window_name = human_window_size_lookup[current_window] or current_window
    window_name = window_name .. "-" .. provider

    local current_remaining
    if conf.tokens_count_strategy == "cost" then
      current_remaining = max(current_limit - rate, 0)
    else
      current_remaining = floor(max(current_limit - rate, 0))
    end

    if not conf.hide_client_headers then
      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_LIMIT .. "-" .. window_name, current_limit)
      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_REMAINING .. "-" .. window_name, current_remaining)
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
      local stored_reset = pdk_rl_get_stored_response_header(ngx_ctx, X_RATELIMIT_RESET)
      if not stored_reset or stored_reset < reset then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RESET, reset)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RESET .. "-" .. window_name, reset)
      end

      local retry_after = reset
      local jitter_max = conf.retry_after_jitter_max

      -- Add a random value (a jitter) to the Retry-After value
      -- to reduce a chance of retries spike occurrence.
      if retry_after and jitter_max > 0 then
        retry_after = retry_after + rand(jitter_max)
      end

      -- Add draft headers for rate limiting RFC; FTI-1447
      local stored_retry_after = pdk_rl_get_stored_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER)
      if not stored_retry_after or stored_retry_after < retry_after then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER, retry_after)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      if not conf.hide_client_headers then
        pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_RETRY_AFTER .. "-" .. window_name, retry_after)
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

    send_stats_error()
    return kong.response.exit(conf.error_code, { message = error_message })
  end
end


function NewRLHandler:log(conf)
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
  local request_analytics = llm_state.get_request_analytics() or {}
  local request_analytics_log = {}

  for _, plugin_data in pairs(request_analytics) do
    local provider = plugin_data.meta.provider_name
    request_analytics_log[provider] = (request_analytics_log[provider] or 0) + (plugin_data.usage[conf.tokens_count_strategy] or 0)
  end

  for _, provider_config in ipairs(conf.llm_providers) do

    local provider = provider_config.name
    local namespace_provider = provider .. ":" .. plugin_id
    local current_window = tonumber(provider_config.window_size)
    local current_limit = tonumber(provider_config.limit)
    local query_cost = request_analytics_log[provider]

    if not query_cost then
      kong.log.debug("No " .. conf.tokens_count_strategy .. " data for the provider " .. provider .. " in the request")
    end

    -- we increment all window even if we have exceeded any rate,
    -- as the ai requests has already been sent in body filter phase
    -- this part won't be called if we add the query cost in header filter phase
    if query_cost and query_cost > kong.ctx.plugin.ai_query_cost[provider] then
      query_cost = query_cost - kong.ctx.plugin.ai_query_cost[provider]

      local rate = ratelimiting.increment(key, current_window, query_cost, namespace_provider,
                                      conf.window_type == "fixed" and 0 or nil)
      -- Ensure the window start time persists using shared memory
      -- This handles the thundering herd problem for the sliding window reset
      -- calculation to be extended longer than the actual window size
      local window_start = floor(now / current_window) * current_window
      local window_start_timstamp_key = "timestamp:" .. current_window .. ":window_start:" .. namespace_provider
      if rate > current_limit and window_type == "sliding" then
        shm:add(window_start_timstamp_key, window_start)
      else
        shm:delete(window_start_timstamp_key)
      end
    end
  end
end

return NewRLHandler
