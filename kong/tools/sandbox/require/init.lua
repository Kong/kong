local REQUIRES do
  local require = require
  local package = package
  local ipairs = ipairs
  local error = error

  local function denied_require(modname)
    return error(("require '%s' not allowed within sandbox"):format(modname))
  end

  REQUIRES = setmetatable({}, {
    __index = function()
      return denied_require
    end
  })

  local function generate_require(packages)
    return function(modname)
      if not packages[modname] then
        return denied_require(modname)
      end
      return require(modname)
    end
  end

  -- the order is from the biggest to the smallest so that package
  -- unloading works properly (just to not leave garbage around)
  for _, t in ipairs({ "handler", "schema", "lua" }) do
    local packages = {}
    local package_name = "kong.tools.sandbox.require." .. t
    require(package_name):gsub("%S+", function(modname)
      packages[modname] = true
    end)
    package.loaded[package_name] = nil
    REQUIRES[t] = generate_require(packages)
  end
end


return REQUIRES
