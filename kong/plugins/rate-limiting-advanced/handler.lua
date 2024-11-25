-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ratelimiting = require("kong.tools.public.rate-limiting").new_instance("rate-limiting-advanced", { redis_config_version = "v2" })
local schema = require "kong.plugins.rate-limiting-advanced.schema"
local handler_helper = require "kong.enterprise_edition.rl_plugin_helpers"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local meta = require "kong.meta"

local kong = kong
local ipairs = ipairs
local PLUGIN_NAME = "rate-limiting-advanced"
local NewRLHandler = {
  PRIORITY = 910,
  VERSION = meta.core_version
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


local function get_key(conf)
  local key
  if type(conf.compound_identifier) == "table" and #conf.compound_identifier > 0 then
    local n = #conf.compound_identifier
    key = ""
    for i, item in ipairs(conf.compound_identifier) do
      local part_key = id_lookup[item](conf)
      if part_key then
        key = key .. part_key
        if i ~= n then
          key = key .. ":"
        end

      else
        -- fallback to conf.identifier
        goto fallback
      end
    end

    return key
  end

  ::fallback::
  local key = id_lookup[conf.identifier](conf)

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  return key
end


function NewRLHandler:init_worker()
  event_hooks.publish(PLUGIN_NAME, "rate-limit-exceeded", {
    fields = { "consumer", "ip", "service", "rate", "limit", "window" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when a rate limit has been exceeded",
  })
end


function NewRLHandler:configure(configs)
  handler_helper.configure_helper(configs, ratelimiting, schema, PLUGIN_NAME, false)
end


function NewRLHandler:access(conf)
  local key = get_key(conf)

  handler_helper.access_helper(conf, key, ratelimiting, schema, PLUGIN_NAME, false)
end

return NewRLHandler
