-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local deep_copy = require "kong.tools.table".deep_copy
local uuid = require "kong.tools.uuid".uuid


local balancers_by_plugin_key = {}
local BYPASS_CACHE = true

local function get_balancer_instance(conf, bypass_cache)
  local conf_key = conf.__plugin_id
  assert(conf_key, "missing plugin conf key __plugin_id")

  local err
  local balancer_instance = balancers_by_plugin_key[conf_key]

  if not balancer_instance or bypass_cache then
    if balancer_instance and balancer_instance.cleanup then
      local ok, err = balancer_instance:cleanup()
      if not ok then
        kong.log.warn("error occured during cleaning up the staled balancer: ", err)
      end
    end

    local mod = require("kong.plugins.ai-proxy-advanced.balancer." .. conf.balancer.algorithm)
    -- copy the table, ignore metatables
    local targets = deep_copy(conf.targets, false)
    for _, target in ipairs(targets) do
      target.id = target.id or uuid()
    end

    balancer_instance, err = mod.new(targets, conf)
    if err then
      return nil, err
    end

    balancers_by_plugin_key[conf_key] = balancer_instance
  end

  return balancer_instance
end

local function delete_balancer_instance(conf_key)
  balancers_by_plugin_key[conf_key] = nil
end

local function cleanup_by_configs(configs)
  local current_config_ids = {}

  for _, conf in ipairs(configs or {}) do
    local k = conf.__plugin_id
    if balancers_by_plugin_key[k] then
      kong.log.warn("plugin instance is recreated: ", k, ", all previous balancing state is reset")
    end
    assert(get_balancer_instance(conf, BYPASS_CACHE))
    current_config_ids[k] = true
  end

  -- purge non existent balancers
  local keys_to_delete = {}
  for k, _ in pairs(balancers_by_plugin_key) do
    if not current_config_ids[k] then
      keys_to_delete[k] = true
    end
  end
  for _, k in ipairs(keys_to_delete) do
    delete_balancer_instance(k)
    kong.log.debug("plugin instance is delete: ", k)
  end
end

return {
  get_balancer_instance = get_balancer_instance,
  delete_balancer_instance = delete_balancer_instance,
  cleanup_by_configs = cleanup_by_configs,
}
