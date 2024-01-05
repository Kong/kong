--- Plugin related APIs
--
-- @module kong.plugin


local _plugin = {}


---
-- Returns the instance ID of the plugin.
--
-- @function kong.plugin.get_id
-- @phases rewrite, access, header_filter, response, body_filter, log
-- @treturn string The ID of the running plugin
-- @usage
--
-- kong.plugin.get_id() -- "123e4567-e89b-12d3-a456-426614174000"
function _plugin.get_id(self)
  return ngx.ctx.plugin_id
end

local function new()
  return _plugin
end


return {
  new = new,
}
