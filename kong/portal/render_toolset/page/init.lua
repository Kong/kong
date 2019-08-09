local getters = require "kong.portal.render_toolset.getters"

local Page = {}

function Page:setup(arg)
  local ctx = getters.get_page_content()

  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next()
end

return Page
