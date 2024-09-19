
-- totally clean the module then load it
local function reload(name)
  package.loaded[name] = nil
  return require(name)
end


local reload_helpers
do
  local misc = require("spec.internal.misc")

  -- flavor could be "traditional","traditional_compatible" or "expressions"
  -- changing flavor will change db's schema
  reload_helpers= function(flavor)
    _G.kong = {
      configuration = {
        router_flavor = flavor,
      },
    }

    misc.setenv("KONG_ROUTER_FLAVOR", flavor)

    reload("kong.global")
    reload("kong.cache")
    reload("kong.db")
    reload("kong.db.schema.entities.routes_subschemas")

    local helpers = reload("spec.helpers")

    misc.unsetenv("KONG_ROUTER_FLAVOR")

    return helpers
  end
end


return {
  reload = reload,
  reload_helpers = reload_helpers,
}
