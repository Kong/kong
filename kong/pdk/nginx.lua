--- Nginx information module
-- A set of functions allowing to retrieve Nginx-specific implementation
-- details and meta information.
-- @module kong.nginx


local ngx = ngx


local function new(self)
  local _NGINX = {}


  ---
  -- Returns the current Nginx subsystem this function is called from: "http"
  -- or "stream".
  --
  -- @function kong.nginx.get_subsystem
  -- @phases any
  -- @treturn string subsystem Either `"http"` or `"stream"`
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
