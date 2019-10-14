-- handler file for both the pre-function and post-function plugin
return function(plugin_name, priority)
  local loadstring = loadstring
  local insert = table.insert
  local ipairs = ipairs

  local config_cache = setmetatable({}, { __mode = "k" })

  local ServerlessFunction = {
    PRIORITY = priority,
    VERSION = "0.3.1",
  }

  function ServerlessFunction:access(config)

    local functions = config_cache[config]

    if not functions then
      -- first call, go compile the functions
      functions = {}
      for _, fn_str in ipairs(config.functions) do
        local func1 = loadstring(fn_str)    -- load it
        local _, func2 = pcall(func1)       -- run it
        if type(func2) ~= "function" then
          -- old style (0.1.0), without upvalues
          insert(functions, func1)
        else
          -- this is a new function (0.2.0+), with upvalues
          insert(functions, func2)

          -- the first call to func1 above only initialized it, so run again
          func2()
        end
      end

      config_cache[config] = functions
      return  -- must return since we allready executed them
    end

    for _, fn in ipairs(functions) do
      fn()
    end
  end


  return ServerlessFunction
end
