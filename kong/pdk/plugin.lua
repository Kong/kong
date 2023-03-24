--- Plugin related APIs
--
-- @module kong.plugin


local _plugin = {}


function _plugin.get_id(self)
  return ngx.ctx.plugin_id
end

local function new()
  return _plugin
end


return {
  new = new,
}
