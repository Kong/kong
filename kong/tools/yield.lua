local _M = {}


---
-- Check if the phase is yieldable.
-- @tparam string phase the phase to check, if not specified then
-- the default value will be the current phase
-- @treturn boolean true if the phase is yieldable, false otherwise
local in_yieldable_phase
do
  local get_phase = ngx.get_phase

  -- https://github.com/openresty/lua-nginx-module/blob/c89469e920713d17d703a5f3736c9335edac22bf/src/ngx_http_lua_util.h#L35C10-L35C10
  local LUA_CONTEXT_YIELDABLE_PHASE = {
    rewrite = true,
    server_rewrite = true,
    access = true,
    content = true,
    timer = true,
    ssl_client_hello = true,
    ssl_certificate = true,
    ssl_session_fetch = true,
    preread = true,
  }

  in_yieldable_phase = function(phase)
    return LUA_CONTEXT_YIELDABLE_PHASE[phase or get_phase()]
  end
end
_M.in_yieldable_phase = in_yieldable_phase


local yield
do
  local ngx_sleep = _G.native_ngx_sleep or ngx.sleep

  local YIELD_ITERATIONS = 1000
  local counter = YIELD_ITERATIONS

  yield = function(in_loop, phase)
    if ngx.IS_CLI or not in_yieldable_phase(phase) then
      return
    end

    if in_loop then
      counter = counter - 1
      if counter > 0 then
        return
      end
      counter = YIELD_ITERATIONS
    end

    ngx_sleep(0)  -- yield
  end
end
_M.yield = yield


return _M
