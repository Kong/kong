local getters = require "kong.portal.render_toolset.getters"


local Kong = {}


function Kong:config()
  local ctx = getters.select_kong_config()

  return self
          :set_ctx(ctx)
          :next()
end


return Kong
