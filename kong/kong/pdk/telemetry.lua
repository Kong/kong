---
-- The telemetry module provides capabilities for telemetry operations.
--
-- @module kong.telemetry.log


local dynamic_hook = require("kong.dynamic_hook")

local dyn_hook_run_hook = dynamic_hook.run_hook
local dyn_hook_is_group_enabled = dynamic_hook.is_group_enabled

local function new()
  local telemetry = {}


  ---
  -- Records a structured log entry, to be reported via the OpenTelemetry plugin.
  --
  -- This function has a dependency on the OpenTelemetry plugin, which must be
  -- configured to report OpenTelemetry logs.
  --
  -- @function kong.telemetry.log
  -- @phases `rewrite`, `access`, `balancer`, `timer`, `header_filter`,
  --         `response`, `body_filter`, `log`
  -- @tparam string plugin_name the name of the plugin
  -- @tparam table plugin_config the plugin configuration
  -- @tparam string message_type the type of the log message, useful to categorize
  --         the log entry
  -- @tparam string message the log message
  -- @tparam table attributes structured information to be included in the
  --         `attributes` field of the log entry
  -- @usage
  -- local attributes = {
  --   http_method = kong.request.get_method()
  --   ["node.id"] = kong.node.get_id(),
  --   hostname = kong.node.get_hostname(),
  -- }
  --
  -- local ok, err = kong.telemetry.log("my_plugin", conf, "result", "successful operation", attributes)
  telemetry.log = function(plugin_name, plugin_config, message_type, message, attributes)
    if type(plugin_name) ~= "string" then
      return nil, "plugin_name must be a string"
    end

    if type(plugin_config) ~= "table" then
      return nil, "plugin_config must be a table"
    end

    if type(message_type) ~= "string" then
      return nil, "message_type must be a string"
    end

    if message and type(message) ~= "string" then
      return nil, "message must be a string"
    end

    if attributes and type(attributes) ~= "table" then
      return nil, "attributes must be a table"
    end

    local hook_group = "observability_logs"
    if not dyn_hook_is_group_enabled(hook_group) then
      return nil, "Telemetry logging is disabled: log entry will not be recorded. " ..
                  "Ensure the OpenTelemetry plugin is correctly configured to "     ..
                  "report logs in order to use this feature."
    end

    attributes = attributes or {}
    attributes["message.type"] = message_type
    attributes["plugin.name"] = plugin_name
    attributes["plugin.id"] = plugin_config.__plugin_id
    attributes["plugin.instance.name"] = plugin_config.plugin_instance_name

    -- stack level = 5:
    -- 1: maybe_push
    -- 2: dynamic_hook.pcall
    -- 3: dynamic_hook.run_hook
    -- 4: kong.telemetry.log
    -- 5: caller
    dyn_hook_run_hook(hook_group, "push", 5, attributes, nil, message)
    return true
  end


  return telemetry
end


return {
  new = new,
}
