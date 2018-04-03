local base = require "kong.sdk.utils.base"


local function new(sdk)
  sdk.new_tab = base.new_tab
  sdk.clear_tab = base.clear_tab
end


return {
  new = new,
}
