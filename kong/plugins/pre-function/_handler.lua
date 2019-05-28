-- handler file for both the pre-function and post-function plugin
return function(plugin_name, priority)

  local BasePlugin = require "kong.plugins.base_plugin"
  local ServerlessFunction = BasePlugin:extend()

  local config_cache = setmetatable({}, { __mode = "k" })

  function ServerlessFunction:new()
    ServerlessFunction.super.new(self, plugin_name)
  end


  function ServerlessFunction:access(config)
    ServerlessFunction.super.access(self)

    local functions = config_cache[config]
    if not functions then
      functions = {}
      for _, fn_str in ipairs(config.functions) do
        table.insert(functions, loadstring(fn_str))
      end
      config_cache[config] = functions
    end

    for _, fn in ipairs(functions) do
      fn()
    end
  end


  ServerlessFunction.PRIORITY = priority
  ServerlessFunction.VERSION = "0.1.0"


  return ServerlessFunction
end
