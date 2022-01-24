--- Nginx information module.
--
-- A set of functions for retrieving Nginx-specific implementation
-- details and meta information.
-- @module kong.nginx


local ngx = ngx


local function new(self)
  local _NGINX = {}


  ---
  -- Returns the current Nginx subsystem this function is called from. Can be
  -- one of `"http"` or `"stream"`.
  --
  -- @function kong.nginx.get_subsystem
  -- @phases any
  -- @treturn string Subsystem, either `"http"` or `"stream"`.
  -- @usage
  -- kong.nginx.get_subsystem() -- "http"
  function _NGINX.get_subsystem()
    return ngx.config.subsystem
  end


  return _NGINX
end


return {
  new = new,
}
