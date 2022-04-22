--- Nginx information module.
--
-- A set of functions for retrieving Nginx-specific implementation
-- details and meta information.
-- @module kong.nginx

local ffi = require "ffi"


local C   = ffi.C
local ngx = ngx
local var = ngx.var

if ffi.arch == "x64" or ffi.arch == "arm64" then
  ffi.cdef[[
    uint64_t *ngx_stat_requests;
    uint64_t *ngx_stat_accepted;
    uint64_t *ngx_stat_handled;
  ]]

elseif ffi.arch == "x86" or ffi.arch == "arm" then
  ffi.cdef[[
    uint32_t *ngx_stat_requests;
    uint32_t *ngx_stat_accepted;
    uint32_t *ngx_stat_handled;
  ]]

else
  kong.log.err("Unsupported arch: " .. ffi.arch)
end


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


  ---
  -- @function kong.nginx.get_statistics
  --
  -- @treturn table Nginx connections and requests statistics
  -- @usage
  -- local nginx_statistics = kong.nginx.get_statistics()
  function _NGINX.get_statistics()
    return {
      connections_active = tonumber(var.connections_active),
      connections_reading = tonumber(var.connections_reading),
      connections_writing = tonumber(var.connections_writing),
      connections_waiting = tonumber(var.connections_waiting),
      connections_accepted = tonumber(C.ngx_stat_accepted[0]),
      connections_handled = tonumber(C.ngx_stat_handled[0]),
      total_requests = tonumber(C.ngx_stat_requests[0])
    }
  end


  return _NGINX
end


return {
  new = new,
}
