-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local proc_mgmt = require "kong.runloop.plugin_servers.process"
local plugin = require "kong.runloop.plugin_servers.plugin"

local pairs = pairs
local kong = kong

-- module cache of loaded external plugins
-- XXX historically, this list of plugins has not been invalidated;
-- however, as plugin servers can be managed externally, users may also
-- change and restart the plugin server, potentially with new configurations
-- this needs to be improved -- docs and code hardening
local loaded_plugins

local function load_external_plugins()
  if loaded_plugins then
    return true
  end

  loaded_plugins = {}

  local kong_config = kong.configuration

  local plugins_info, err = proc_mgmt.load_external_plugins_info(kong_config)
  if not plugins_info then
    return nil, "failed loading external plugins: " .. err
  end

  for plugin_name, plugin_info in pairs(plugins_info) do
    local plugin = plugin.new(plugin_info)
    loaded_plugins[plugin_name] = plugin
  end

  return loaded_plugins
end

local function get_plugin(plugin_name)
  assert(load_external_plugins())

  return loaded_plugins[plugin_name]
end

local function load_plugin(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin
  end

  return false, "no plugin found"
end

local function load_schema(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin.schema
  end

  return false, "no plugin found"
end

local function start()
  -- in case plugin server restarts, all workers need to update their defs
  kong.worker_events.register(function (data)
    plugin.reset_instances_for_plugin(data.plugin_name)
  end, "plugin_server", "reset_instances")

  return proc_mgmt.start_pluginservers()
end

local function stop()
  return proc_mgmt.stop_pluginservers()
end


--
-- This modules sole responsibility is to
-- manage external plugins: starting/stopping plugins servers,
-- and return plugins info (such as schema and their loaded representations)
--
-- The general initialization flow is:
-- - kong.init: calls start and stop to start/stop external plugins servers
-- - kong.db.schema.plugin_loader: calls load_schema to get an external plugin schema
-- - kong.db.dao.plugins: calls load_plugin to get the expected representation of a plugin
--                        (phase handlers, priority, etc)
--
-- Internal flow:
-- .plugin_servers.init: loads all external plugins, by calling .plugin_servers.process and .plugin_servers.plugin
--   .plugin_servers.process: queries external plugins info with the command specified in _query_cmd properties
--   .plugin_servers.plugin: with info obtained as described above, .plugin:new returns a kong-compatible representation
--                           of an external plugin, with phase handlers, PRIORITY, and wrappers to the PDK. Calls
--                           .plugin_servers.rpc to create an RPC through which Kong communicates with the plugin process
--     .plugin_servers.rpc: based on info contained in the plugin (protocol field), creates the correct RPC for the
--                           given external plugin
--       .plugin_servers.rpc.pb_rpc: protobuf rpc implementation - used by Golang
--       .plugin_servers.rpc.mp.rpc: messagepack rpc implementation - used by JS and Python
-- .plugin_servers.init: calls .plugin_servers.process to start external plugin servers
--   .plugin_servers.process: optionally starts all external plugin servers (if a _start_cmd is found)
--      uses the resty pipe API to manage the external plugin process
--

return {
  start = start,
  stop = stop,
  load_schema = load_schema,
  load_plugin = load_plugin,
}
