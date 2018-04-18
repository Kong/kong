local ngx = ngx


local _CTX = {}
local _KONG_CORE_CTX_KEY = {}


function _CTX.get(k)
  local kctx = ngx.ctx[k]
  if not kctx then
    kctx = {}
  end

  return kctx
end


function _CTX.get_core_ctx()
  return _CTX.get[_KONG_CORE_CTX_KEY]
end


return _CTX
