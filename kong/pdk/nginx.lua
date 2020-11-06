-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
