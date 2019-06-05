-- handler file for both the pre-function and post-function plugin
return function(plugin_name, priority)
  local loadstring = loadstring
  local insert = table.insert
  local ipairs = ipairs

  local config_cache = setmetatable({}, { __mode = "k" })

  local ServerlessFunction = {
    PRIORITY = priority,
    VERSION = "0.1.0",
  }

  function ServerlessFunction:access(config)

    local functions = config_cache[config]
    if not functions then
      functions = {}
      for _, fn_str in ipairs(config.functions) do
        local func1 = loadstring(fn_str)
        local _, func2 = pcall(func1)
        insert(functions, type(func2) == "function" and func2 or func1)
      end
      config_cache[config] = functions
    end

    for _, fn in ipairs(functions) do
      fn()
    end
  end


  return ServerlessFunction
end
