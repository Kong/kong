-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local event_hooks = require "kong.enterprise_edition.event_hooks"
local helpers = require "kong.enterprise_edition.consumer_groups_helpers"
local uuid = require "kong.tools.uuid"
local pl_tablex = require "pl.tablex"
local pdk_private_rl = require "kong.pdk.private.rate_limiting"
local concurrency = require "kong.concurrency"

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
local pdk_rl_apply_response_headers = pdk_private_rl.apply_response_headers


local X_RATELIMIT_LIMIT = "X-RateLimit-Limit"
local X_RATELIMIT_REMAINING = "X-RateLimit-Remaining"


-- Add draft headers for rate limiting RFC
-- https://tools.ietf.org/html/draft-polli-ratelimit-headers-02
local RATELIMIT_LIMIT = "RateLimit-Limit"
local RATELIMIT_REMAINING = "RateLimit-Remaining"
local RATELIMIT_RESET = "RateLimit-Reset"
local RATELIMIT_RETRY_AFTER = "Retry-After"


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}

local function merge_size_table(merged_sizes, window_size)
  -- The reason why we use two tables to store the array part and the map part
  -- is because size is also a number type, which will conflict with index.
  for _, size in ipairs(window_size) do
    if not merged_sizes.map[size] then
      merged_sizes.map[size] = true
      local count = merged_sizes.count + 1
      merged_sizes.count = count
      merged_sizes.array[count] = size
    end
  end

  return merged_sizes
end


-- merge the window sizes (including the base window sizes and consumer group window sizes)
-- into the table `merged_sizes`
-- returns a table including the array part and the map part
local function merge_window_size(config, merged_sizes, plugin_name)
  merged_sizes = merged_sizes or { array = {}, map = {}, count = 0 }
  local ws_id = config.__ws_id

  -- merge the base window_size
  merged_sizes = merge_size_table(merged_sizes, config.window_size)

  if config.enforce_consumer_groups and config.consumer_groups then
    for _, group_name in ipairs(config.consumer_groups) do
      local consumer_group = helpers.get_consumer_group(group_name, ws_id)
      if consumer_group then
        local consumer_group_config = helpers.get_consumer_group_config(consumer_group.id, plugin_name, ws_id)
        local consumer_group_window_size = consumer_group_config and consumer_group_config.config
                                           and consumer_group_config.config.window_size
        if consumer_group_window_size then
          -- merge the window_size in the overriding config of the consumer group
          merged_sizes = merge_size_table(merged_sizes, consumer_group_window_size)
        end
      end
    end
  end

  return merged_sizes
end


local function create_timer(config, ratelimiting)
  local rate = config.sync_rate
  local namespace = config.namespace
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


local function new_namespace(config, timer_id, merged_window_size, ratelimiting, schema, plugin_name, is_bare_window_size)
  if not config then
    kong.log.warn("[", plugin_name, "] no config was specified.",
                  " Skipping the namespace creation.")
    return false
  end

  kong.log.debug("attempting to add namespace ", config.namespace)

  local strategy = config.strategy == "cluster" and
                   kong.configuration.database or
                   "redis"

  local strategy_opts = strategy == "redis" and config.redis

  if config.strategy == "local" then
    config.sync_rate = -1
  end

  -- no shm was specified, try the default value specified in the schema
  local dict_name = config.dictionary_name
  if dict_name == nil then
    dict_name = schema.fields.dictionary_name.default
    if dict_name then
      kong.log.warn("[", plugin_name, "] no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    else
      kong.log.warn("[", plugin_name, "] no schema default was specified.",
        " Skipping the namespace creation.")
      return false
    end
  end

  local lock_dict_name = config.lock_dictionary_name
  if type(lock_dict_name) ~= "string" or lock_dict_name == "" then
    lock_dict_name = "kong_locks"
  end
  kong.log.notice("[", plugin_name, "] using independent lock dict ", lock_dict_name,
    " when new namespace")

  -- if dictionary name was passed but doesn't exist, fallback to kong
  if ngx.shared[dict_name] == nil then
    kong.log.notice("[", plugin_name, "] specified shared dictionary '", dict_name,
      "' doesn't exist. Falling back to the 'kong' shared dictionary")
    dict_name = "kong"
  end
  kong.log.notice("[", plugin_name, "] using shared dictionary '"
                         .. dict_name .. "'")

  local ok, err = pcall(function()
    ratelimiting.new({
      namespace     = config.namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      lock_dict     = lock_dict_name,
      window_sizes  = is_bare_window_size and config.window_size or merged_window_size,
      db            = kong.db,
      timer_id      = timer_id,
    })
  end)

  if not ok then
    kong.log.err("err in creating new ratelimit namespace ", config.namespace, " :", err)
    return false
  end

  return true
end


local function update_namespace(config, timer_id, merged_window_size, ratelimiting, schema, plugin_name, is_bare_window_size)
  if not config then
    kong.log.warn("[", plugin_name, "] no config was specified.",
                  " Skipping the namespace creation.")
    return false
  end

  kong.log.debug("attempting to update namespace ", config.namespace)

  local strategy = config.strategy == "cluster" and
                   kong.configuration.database or
                   "redis"

  local strategy_opts = strategy == "redis" and config.redis

  if config.strategy == "local" then
    config.sync_rate = -1
  end

  -- no shm was specified, try the default value specified in the schema
  local dict_name = config.dictionary_name
  if dict_name == nil then
    dict_name = schema.fields.dictionary_name.default
    if dict_name then
      kong.log.warn("[", plugin_name, "] no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    else
      kong.log.warn("[", plugin_name, "] no schema default was specified.",
        " Skipping the namespace creation.")
      return false
    end
  end

  -- if dictionary name was passed but doesn't exist, fallback to kong
  if ngx.shared[dict_name] == nil then
    kong.log.notice("[", plugin_name, "] specified shared dictionary '", dict_name,
      "' doesn't exist. Falling back to the 'kong' shared dictionary")
    dict_name = "kong"
  end
  kong.log.notice("[", plugin_name, "] using shared dictionary '"
                         .. dict_name .. "'")

  local lock_dict_name = config.lock_dictionary_name
  if type(lock_dict_name) ~= "string" or lock_dict_name == "" then
    lock_dict_name = "kong_locks"
  end
  kong.log.notice("[", plugin_name, "] using independent lock dict ", lock_dict_name,
    " when update namespace")

  local ok, err = pcall(function()
    ratelimiting.update({
      namespace     = config.namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      lock_dict     = lock_dict_name,
      window_sizes  = is_bare_window_size and config.window_size or merged_window_size,
      db            = kong.db,
      timer_id      = timer_id,
    })
  end)

  if not ok then
    kong.log.err("err in updating ratelimit namespace ", config.namespace, " :", err)
    return false
  end

  return true
end


-- fields that are required for synchronizing counters for a namespace
local sync_fields = {
  "sync_rate", "strategy", "dictionary_name", "redis",
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

local function configure_helper(configs, ratelimiting, schema, plugin_name, is_bare_window_size)
  local namespaces = {}
  local merged_window_sizes = {}
  if configs then
    for _, config in ipairs(configs) do
      local namespace = config.namespace
      if namespaces[namespace] then
        if not are_same_config(namespaces[namespace], get_sync_conf(config)) then
          kong.log.err("multiple ", plugin_name, " plugins with the namespace '", namespace,
            "' have different counter syncing configurations. Please correct them to use the same configuration.")
        end
      else

        namespaces[namespace] = get_sync_conf(config)
      end

      merged_window_sizes[namespace] = merge_window_size(config, merged_window_sizes[namespace], plugin_name)
    end

    for namespace, config in pairs(namespaces) do
      -- if nil, do not sync with DB or Redis
      local sync_rate = config.sync_rate
      if not sync_rate or sync_rate == null then
        sync_rate = -1
      end

      kong.log.debug("clear and reset ", namespace)

      config.namespace = namespace
      -- previous config doesn't exist for this worker
      -- create a namespace for the new config and return, similar to "rl:create"
      if not ratelimiting.config[namespace] then
        local ok, err = concurrency.with_coroutine_mutex({ name = namespace }, function()
          -- double check
          if ratelimiting.config[namespace] then
            local timer_id
            -- if the previous config has a timer_id, i.e., a background timer already exists,
            -- and the current config still needs a timer, we pass the timer_id to reuse the
            -- existing timer
            if sync_rate > 0 then
              timer_id = ratelimiting.config[namespace].timer_id
            end

            update_namespace(config, timer_id, merged_window_sizes[namespace].array, ratelimiting, schema, plugin_name, is_bare_window_size)

          else

            new_namespace(config, nil, merged_window_sizes[namespace].array, ratelimiting, schema, plugin_name, is_bare_window_size)
          end

          return true
        end)

        if not ok then
          kong.log.err(err)
        end

      else
        local timer_id

        -- if the previous config has a timer_id, i.e., a background timer already exists,
        -- and the current config still needs a timer, we pass the timer_id to reuse the
        -- existing timer
        if sync_rate > 0 then
          timer_id = ratelimiting.config[namespace].timer_id
        end

        update_namespace(config, timer_id, merged_window_sizes[namespace].array, ratelimiting, schema, plugin_name, is_bare_window_size)
      end

      -- recommendation have changed with FT-928
      if sync_rate > 0 and sync_rate < 1 then
        kong.log.warn("Config option 'sync_rate' " .. sync_rate .. " is between 0 and 1; a config update is recommended")
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


local function access_helper(conf, key_id, ratelimiting, schema, plugin_name, is_bare_window_size)
  local namespace = conf.namespace
  local now = time()
  local key = key_id

  local deny_window_index

  -- if this worker has not yet seen the "rl:create" event propagated by the
  -- instatiation of a new plugin, create the namespace. in this case, the call
  -- to new_namespace in the registered rl handler will never be called on this
  -- worker
  --
  -- this workaround will not be necessary when real IPC is implemented for
  -- inter-worker communications
  --
  -- changes in https://github.com/Kong/kong-plugin-enterprise-rate-limiting/pull/35
  -- currently rely on this in scenarios where workers initialize without database availability
  if not ratelimiting.config[namespace] then
    -- because `new_namespace` may yield, to avoid the namespace is created in the configure()
    -- first and then overridden here, a mutex is added to protect the namespace creation
    local ok, err = concurrency.with_coroutine_mutex({ name = namespace }, function()
      -- double check
      if ratelimiting.config[namespace] then
        return true
      end

      local ret = new_namespace(conf, nil, merge_window_size(conf).array, ratelimiting, schema, plugin_name, is_bare_window_size)
      if not ret then
        return nil
      end

      return true
    end)

    -- maybe the namespace has been created by another coroutine
    if not ok and not ratelimiting.config[namespace] then
      kong.log.err("failed to new namespace ", namespace, ": ", err)
      kong.response.error(500, "An unexpected error occurred")
    end
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
  if conf.sync_rate > 0 and not ratelimiting.config[namespace].timer_id then
    create_timer(conf, ratelimiting)
  end

  local config
  -- check to apply consumer groups
  if conf.enforce_consumer_groups then
    if kong.client.get_consumer() and conf.consumer_groups then
      local consumer = kong.client.get_consumer()
      for i = 1, #conf.consumer_groups do
        -- if found a match, overrides the configuration value
        local consumer_group = helpers.get_consumer_group(conf.consumer_groups[i])
        if consumer_group and helpers.is_consumer_in_group(consumer.id, consumer_group.id) then
          local config_raw = helpers.get_consumer_group_config(consumer_group.id, plugin_name)
          if config_raw then
            config = config_raw.config
          else
            kong.log.warn("Consumer group " .. consumer_group.name ..
            " enforced but no consumer group configurations provided. Original plugin configurations will apply.")
          end
          break --exit on the first matching group found
        end
      end
    end
  end

  -- fall back to the original plugin configurations
  if not config then
    config = conf
  end

  local limit
  local window
  local remaining
  local reset
  local window_type = config.window_type
  local shm = ngx.shared[conf.dictionary_name]
  local ngx_ctx= ngx.ctx
  for i = 1, #config.window_size do
    local current_window = tonumber(config.window_size[i])
    local current_limit = tonumber(config.limit[i])

    -- if we have exceeded any rate, we should not increment any other windows,
    -- butwe should still show the rate to the client, maintaining a uniform
    -- set of response headers regardless of whether we block the request
    local rate
    if deny_window_index then
      rate = ratelimiting.sliding_window(key, current_window, nil, namespace)
    else
      rate = ratelimiting.increment(key, current_window, 1, namespace,
                                    config.window_type == "fixed" and 0 or nil)
    end

    -- Ensure the window start time persists using shared memory
    -- This handles the thundering herd problem for the sliding window reset
    -- calculation to be extended longer than the actual window size
    local window_start = floor(now / current_window) * current_window
    local window_start_timstamp_key = "timestamp:" .. current_window .. ":window_start"
    if rate > current_limit and window_type == "sliding" then
      shm:add(window_start_timstamp_key, window_start)
      window_start = shm:get(window_start_timstamp_key) or window_start
    else
      shm:delete(window_start_timstamp_key)
    end

    -- legacy logic of naming rate limiting headers. if we configured a window
    -- size that looks like a human friendly name, give that name
    local window_name = human_window_size_lookup[current_window] or current_window

    local current_remaining = floor(max(current_limit - rate, 0))
    if not conf.hide_client_headers then
      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_LIMIT .. "-" .. window_name, current_limit)
      pdk_rl_store_response_header(ngx_ctx, X_RATELIMIT_REMAINING .. "-" .. window_name, current_remaining)

      -- calculate the reset value based on the window type (if applicable)
      if not limit or (current_remaining < remaining)
                   or (current_remaining == remaining and
                       current_window > window) then
        -- Ensure that the proper window reset value is set
        limit = current_limit
        window = current_window
        remaining = current_remaining

        -- Calculate the fixed window reset value
        reset = max(1.0, window - (now - window_start))

        -- Add some weight to the current reset value based on the window
        -- and the rate difference. Apply the adjustment to the current
        -- calculated reset value for a more accurate sliding window estimate.
        if window_type == "sliding" then
          local window_adjustment = max(0.0, (((rate - limit) / limit) * window))
          reset = ceil(reset + window_adjustment)
        end
      end
    end

    if rate > current_limit then
      -- Since we increment the counter unconditionally until a certain window
      -- has exceeded the limit, we need to record the index of the window
      -- which exceeds the limit in order to decrement the counter back if
      -- necessary, i.e. when the window_type is sliding and conf.disable_penalty
      -- is true.
      deny_window_index = i
      -- only gets emitted when kong.configuration.databus_enabled = true
      -- no need to if here
      -- XXX we are doing it on this flow of code because it's easier to
      -- get the rate and the limit that triggered it. Move it somewhere
      -- general later.
      local ok, err = event_hooks.emit(plugin_name, "rate-limit-exceeded", {
        consumer = kong.client.get_consumer() or {},
        ip = kong.client.get_forwarded_ip(),
        service = kong.router.get_service() or {},
        rate = rate,
        limit = current_limit,
        window = window_name,
      })

      if not ok and err then
        kong.log.warn("failed to emit event: ", err)
      end
    end
  end

  -- Add draft headers for rate limiting RFC; FTI-1447
  if limit then
    pdk_rl_store_response_header(ngx_ctx, RATELIMIT_LIMIT, limit)
    pdk_rl_store_response_header(ngx_ctx, RATELIMIT_REMAINING, remaining)
    pdk_rl_store_response_header(ngx_ctx, RATELIMIT_RESET, reset)
  end

  if deny_window_index then
    local retry_after = reset
    local jitter_max = config.retry_after_jitter_max

    -- Add a random value (a jitter) to the Retry-After value
    -- to reduce a chance of retries spike occurrence.
    if retry_after then
      if jitter_max > 0 then
        retry_after = retry_after + rand(jitter_max)
      end

      -- Only added for denied requests (if hide_client_headers == false)
      pdk_rl_store_response_header(ngx_ctx, RATELIMIT_RETRY_AFTER, retry_after)
    end

    -- don't count requests which are rejected with 429
    if conf.disable_penalty and window_type == "sliding" then
      for i = 1, deny_window_index do
        local current_window = tonumber(config.window_size[i])
        -- we don't care about the return value here
        -- so set weight as 0 to speedup the function call
        ratelimiting.increment(key, current_window, -1, namespace, 0)
      end
    end

    pdk_rl_apply_response_headers(ngx_ctx)

    return kong.response.exit(conf.error_code, { message = conf.error_message })
  end

  pdk_rl_apply_response_headers(ngx_ctx)
end

return {
    configure_helper = configure_helper,
    access_helper = access_helper
}