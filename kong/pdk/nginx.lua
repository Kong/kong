--- Nginx information module.
--
-- A set of functions for retrieving Nginx-specific implementation
-- details and meta information.
-- @module kong.nginx

local ffi = require "ffi"


local C    = ffi.C
local arch = ffi.arch
local ngx  = ngx
local tonumber = tonumber

if arch == "x64" or arch == "arm64" then
  ffi.cdef[[
    uint64_t *ngx_stat_active;
    uint64_t *ngx_stat_reading;
    uint64_t *ngx_stat_writing;
    uint64_t *ngx_stat_waiting;
    uint64_t *ngx_stat_requests;
    uint64_t *ngx_stat_accepted;
    uint64_t *ngx_stat_handled;
  ]]

elseif arch == "x86" or arch == "arm" then
  ffi.cdef[[
    uint32_t *ngx_stat_active;
    uint32_t *ngx_stat_reading;
    uint32_t *ngx_stat_writing;
    uint32_t *ngx_stat_waiting;
    uint32_t *ngx_stat_requests;
    uint32_t *ngx_stat_accepted;
    uint32_t *ngx_stat_handled;
  ]]

else
  kong.log.err("Unsupported arch: " .. arch)
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
  -- Returns various connection and request metrics exposed by
  -- Nginx, similar to those reported by the
  -- [ngx_http_stub_status_module](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html#data).
  --
  -- The following fields are included in the returned table:
  -- * `connections_active` - the current number of active client connections including `connections_waiting`.
  -- * `connections_reading` - the current number of connections where nginx is reading the request header.
  -- * `connections_writing` - the current number of connections where nginx is writing the response back to the client.
  -- * `connections_waiting` - the current number of idle client connections waiting for a request.
  -- * `connections_accepted` - the total number of accepted client connections.
  -- * `connections_handled` - the total number of handled connections. Same as `connections_accepted` unless some resource limits have been reached
  --   (for example, the [`worker_connections`](https://nginx.org/en/docs/ngx_core_module.html#worker_connections) limit).
  -- * `total_requests` - the total number of client requests.
  --
  -- @function kong.nginx.get_statistics
  -- @treturn table Nginx connections and requests statistics
  -- @usage
  -- local nginx_statistics = kong.nginx.get_statistics()
  function _NGINX.get_statistics()
    return {
      connections_active = tonumber(C.ngx_stat_active[0]),
      connections_reading = tonumber(C.ngx_stat_reading[0]),
      connections_writing = tonumber(C.ngx_stat_writing[0]),
      connections_waiting = tonumber(C.ngx_stat_waiting[0]),
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
