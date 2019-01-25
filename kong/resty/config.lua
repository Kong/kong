local ffi = require "ffi"
local openssl_ssl_context = require "openssl.ssl.context"
require "resty.core.base" -- defines ngx_str_t


local has_patch = false
local ngx_lua_get_server_block
local ngx_lua_server_block_server_name
local ngx_lua_get_SSL_CTX
if ngx.config.subsystem == "http" then
  ffi.cdef [[
    void* ngx_http_lua_get_server_block(uintptr_t);
    ngx_str_t* ngx_http_lua_server_block_server_name(void*);
    SSL_CTX* ngx_http_lua_ssl_get_SSL_CTX(void*);
  ]]

  has_patch = pcall(function()
    ngx_lua_get_server_block = ffi.C.ngx_http_lua_get_server_block
    ngx_lua_server_block_server_name = ffi.C.ngx_http_lua_server_block_server_name
    ngx_lua_get_SSL_CTX = ffi.C.ngx_http_lua_ssl_get_SSL_CTX
  end)
end
if not has_patch then
  ngx_lua_get_server_block = function()
    error("could not get server block (missing ffi interfaces from server_conf patch)")
  end
end


local function get_server_block(i)
  local srv_ptr = ngx_lua_get_server_block(i)
  if srv_ptr == nil then
    return nil
  end
  return {
    get_ssl_ctx = function()
      local ptr = ngx_lua_get_SSL_CTX(srv_ptr)
      if ptr == nil then
        return nil
      end
      return openssl_ssl_context.pushffi(ptr)
    end,
    get_server_name = function()
      local str = ngx_lua_server_block_server_name(srv_ptr)
      return ffi.string(str.data, str.len)
    end,
  }
end


local function each_server_block()
  local i = 0
  return function()
    local srv = get_server_block(i)
    if srv == nil then
      return nil
    end
    i = i + 1
    return srv
  end
end


return {
  can_get_server_block = has_patch,
  get_server_block = get_server_block,
  each_server_block = each_server_block,
}
