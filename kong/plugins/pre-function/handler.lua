local BasePlugin = require "kong.plugins.base_plugin"
local PreFunction = BasePlugin:extend()

local config_cache = setmetatable({}, { __mode = "k" })


function PreFunction:new()
  PreFunction.super.new(self, "pre-function")
end


function PreFunction:access(config)
  PreFunction.super.access(self)

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


PreFunction.VERSION = "0.1.0"
PreFunction.PRIORITY = math.huge


return PreFunction
