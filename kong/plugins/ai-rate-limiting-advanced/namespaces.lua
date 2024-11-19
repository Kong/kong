-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local pl_tablex = require "pl.tablex"
local schema = require "kong.plugins.ai-rate-limiting-advanced.schema"
local ratelimiting = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".ratelimiting


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

local function new_namespace(config, timer_id, namespace, window_size)
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
    if config.sync_rate ~= ngx.null and config.sync_rate ~= nil and config.sync_rate > -1 then
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
      window_sizes  = { window_size },
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
    if config.sync_rate ~= ngx.null and config.sync_rate ~= nil and config.sync_rate > -1 then
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

local function cleanup_by_configs(configs)
  local namespaces = {}

  for _, config in ipairs(configs or {}) do
    local plugin_id = config.__plugin_id
    local sync_rate = config.sync_rate
    if not sync_rate or
    sync_rate == ngx.null
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

  for namespace in pairs(ratelimiting.config) do
    if not namespaces[namespace] then
      kong.log.debug("clearing old namespace ", namespace)
      ratelimiting.config[namespace].kill = true
      ratelimiting.config[namespace].timer_id = nil
    end
  end
end


return {
  cleanup_by_configs = cleanup_by_configs,
  new = new_namespace,
}