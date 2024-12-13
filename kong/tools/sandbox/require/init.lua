-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


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
