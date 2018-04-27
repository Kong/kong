local ngx = ngx


-- shared between all global instances
local _CTX_SHARED_KEY = {}


local function new(self)
  local _CTX = {
    -- those would be visible on the *.ctx namespace for now
    -- TODO: hide them in a private table shared between this
    -- module and the global.lua one
    shared_ctx_key = _CTX_SHARED_KEY,
    keys = setmetatable({}, { __mode = "k" }),
  }


  local _ctx_mt = {}


  function _ctx_mt.__index(t, k)
    local nctx = ngx.ctx
    local key

    if k == "shared" then
      key = t.shared_ctx_key
    else
      key = t.keys[k]
    end

    if key then
      local ctx = nctx[key]
      if not ctx then
        ctx = {}
        nctx[key] = ctx
      end

      return ctx
    end
  end


  return setmetatable(_CTX, _ctx_mt)
end


return {
  new = new,
}
