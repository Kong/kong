-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- totally clean the module then load it
local function reload(name)
  package.loaded[name] = nil
  return require(name)
end


local reload_helpers
do
  local sys = require("spec.internal.sys")

  -- flavor could be "traditional","traditional_compatible" or "expressions"
  -- changing flavor will change db's schema
  reload_helpers = function(flavor)
    _G.kong = {
      configuration = {
        router_flavor = flavor,
      },
    }

    sys.setenv("KONG_ROUTER_FLAVOR", flavor)

    -- reload db and global module
    reload("kong.db.schema.entities.routes_subschemas")
    reload("kong.db.schema.entities.routes")
    reload("kong.cache")
    reload("kong.global")

    -- reload helpers module
    local helpers = reload("spec.helpers")

    sys.unsetenv("KONG_ROUTER_FLAVOR")

    return helpers
  end
end


return {
  reload = reload,
  reload_helpers = reload_helpers,
}
