-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local dependency_tracker = require("kong.db.schema.plugin_dependency")
local ipairs = ipairs


--[[
topsort_plugins - Orders plugins based on their dependencies and the phase they run in.

@param plugins_hash {table} - A hash table containing plugin names as keys and their information as values.
@param plugins_array {table} - An array of plugin information tables.
@param phase {string} - (optional) The phase in which the plugins will run. Defaults to "access".

@returns {table} - The sorted plugins array based on the dependencies and phase specified.

@example

local plugins_hash = {
plugin1 = { plugin = { name = "plugin1" }, config = { ordering = { after = { access = {"plugin2"} } } } },
plugin2 = { plugin = { name = "plugin2" }, config = { ordering = { before = { access = {"plugin1"} } } } }
}

local plugins_array = {
{ plugin = { name = "plugin1" }, config = { ordering = { after = { access = {"plugin2"} } } } },
{ plugin = { name = "plugin2" }, config = { ordering = { before = { access = {"plugin1"} } } } }
}

local sorted_plugins = topsort_plugins(plugins_hash, plugins_array, "access")
-- sorted_plugins will be:
-- {
-- { plugin = { name = "plugin2" }, config = { ordering = { before = { access = {"plugin1"} } } } },
-- { plugin = { name = "plugin1" }, config = { ordering = { after = { access = {"plugin2"} } } } }
-- }
]]
   --
local function topsort_plugins(plugins_hash, plugins_array, phase)
  local has_ordering
  local dependencies = {}
  phase = phase or "access"

  -- Process each plugin and extract ordering information
  for _, plugin_information in ipairs(plugins_array) do
    local cfg = plugin_information.config
    local plugin_name = plugin_information.plugin.name
    local before, after
    local ordering = cfg.ordering

    if ordering then
      after = ordering.after and ordering.after[phase]
      before = ordering.before and ordering.before[phase]
    end

    -- Add dependencies for plugins that should run after this plugin
    if after then
      for _, after_plugin_name in ipairs(after) do
        local dependency = plugins_hash[after_plugin_name]
        if not dependency then
          kong.log.info("Plugin ", plugin_name, " has a dependency on a non-existing plugin. Cannot build graph")
        else
          if not has_ordering then has_ordering = true end
          dependency_tracker.add(dependencies, plugin_information, dependency)
        end
      end
    end

    -- Add dependencies for plugins that should run before this plugin
    if before then
      for _, before_plugin_name in ipairs(before) do
        local dependency = plugins_hash[before_plugin_name]
        if not dependency then
          kong.log.info("Plugin ", plugin_name, " is a dependency of a non-existing plugin. Cannot build graph")
        else
          if not has_ordering then has_ordering = true end
          dependency_tracker.add(dependencies, dependency, plugin_information)
        end
      end
    end
  end

  -- If there is an ordering, sort the plugins based on the dependencies
  if has_ordering then
    return dependency_tracker.sort(plugins_array, dependencies)
  end

  -- If there is no ordering, return the original plugins_array
  return plugins_array
end


return topsort_plugins
