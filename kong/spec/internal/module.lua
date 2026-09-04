
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
