-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_meta = require("kong.meta")
local proxy_handler = require("kong.llm.proxy.handler")
local deep_copy = require "kong.tools.table".deep_copy
local uuid = require "kong.tools.uuid".uuid

local set_tried_target = require "kong.plugins.ai-proxy-advanced.balancer.state".set_tried_target

local _M = {
  PRIORITY = 770, -- same as ai-proxy
  VERSION = kong_meta.core_version
}

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

-- crud event handler for traditional mode
function _M:init_worker()
  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  local worker_events = kong.worker_events
  local cluster_events = kong.configuration.role == "traditional" and kong.cluster_events

  worker_events.register(function(data)
    local conf = data.entity.config

    local operation = data.operation
    if operation == "create" or operation == "update" then
      conf.__plugin_id = assert(data.entity.id, "missing plugin conf key __plugin_id")
      assert(get_balancer_instance(conf, BYPASS_CACHE))

    elseif operation == "delete" then
      local conf_key = data.entity.id
      assert(conf_key, "missing plugin conf key data.entity.id")
      balancers_by_plugin_key[conf_key] = nil
    end
  end, "ai-proxy-advanced", "balancers")

  -- event handlers to update balancer instances
  worker_events.register(function(data)
    if data.entity.name == "ai-proxy-advanced" then
      -- remove metatables from data
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }

      -- broadcast this to all workers becasue dao events are sent using post_local
      worker_events.post("ai-proxy-advanced", "balancers", post_data)

      if cluster_events then
        cluster_events:broadcast("ai-proxy-advanced:balancers", post_data)
      end
    end
  end, "crud", "plugins")

  if cluster_events then
    cluster_events:subscribe("ai-proxy-advanced:balancers", function(data)
      -- remove metatables from data
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }
      worker_events.post("ai-proxy-advanced", "balancers", post_data)
    end)
  end

end

-- crud event handler for hybrid mode
function _M:configure(configs)
  if not configs then
    return
  end

  local current_config_ids = {}

  for _, conf in ipairs(configs) do
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
    balancers_by_plugin_key[k] = nil
    kong.log.debug("plugin instance is delete: ", k)
  end
end

function _M:access(conf)
  local balancer_instance, err = get_balancer_instance(conf)
  if not balancer_instance then
    kong.log.err("failed to get balancer: ", err)
    return kong.response.exit(500, { message = "failed to get balancer" })
  end

  local selected, err = balancer_instance:getPeer()
  if err then
    kong.log.err("failed to get peer: ", err)
    return kong.response.exit(500, { message = "failed to get peer" })
  end

  kong.ctx.plugin.selected_target = selected

  kong.service.set_retries(conf.balancer.retries)
  kong.service.set_timeouts(conf.balancer.connect_timeout, conf.balancer.write_timeout, conf.balancer.read_timeout)

  -- pass along the top level magic keys to selected target/conf
  selected.__key__ = conf.__key__
  selected.__plugin_id = conf.__plugin_id
  selected.max_request_body_size = conf.balancer.max_request_body_size

  -- no return value, short circuit the request on error
  proxy_handler:access(selected)

  set_tried_target(selected)

  kong.service.set_target_retry_callback(function()
    local selected_retry, err_retry = balancer_instance:getPeer()
    if err_retry then
      return false, "failed to get peer " .. err_retry
    end
    -- pass along the top level magic keys to selected target/conf
    selected_retry.__key__ = conf.__key__
    selected_retry.__plugin_id = conf.__plugin_id

    proxy_handler:access(selected_retry)

    set_tried_target(selected)

    return true
  end)
end

function _M:header_filter(conf)
  local target = kong.ctx.plugin.selected_target
  if not target then
    return
  end

  target.model_name_header = conf.model_name_header

  return proxy_handler:header_filter(target)
end

function _M:body_filter()
  local target = kong.ctx.plugin.selected_target
  if not target then
    return
  end

  return proxy_handler:body_filter(target)
end

function _M:log(conf)
  local target = kong.ctx.plugin.selected_target
  if not target then
    return
  end

  local balancer_instance, err = get_balancer_instance(conf)
  if not balancer_instance then
    return kong.log.err("failed to get balancer: ", err)
  end

  local _, err = balancer_instance:afterBalance(conf, kong.ctx.plugin.selected_target)

  if err then
    return kong.log.warn("failed to perform afterBalance operation: ", err)
  end
end


return _M
