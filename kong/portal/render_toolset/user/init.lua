local getters = require "kong.portal.render_toolset.getters"

local User = {}

function User:info(arg)
  local ctx = getters.select_authenticated_developer()

  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next()
end


function User:is_authenticated()
  local user = getters.select_authenticated_developer()
  local ctx = user ~= nil and user ~= {}

  return self
          :set_ctx(ctx)
          :next()
end


return User
