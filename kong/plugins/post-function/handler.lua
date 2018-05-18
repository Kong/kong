local BasePlugin = require "kong.plugins.base_plugin"
local PostFunction = BasePlugin:extend()

local config_cache = setmetatable({}, { __mode = "k" })


function PostFunction:new()
  PostFunction.super.new(self, "post-function")
end


function PostFunction:access(config)
  PostFunction.super.access(self)

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


PostFunction.PRIORITY = -1000
PostFunction.VERSION = "0.1.0"


return PostFunction
