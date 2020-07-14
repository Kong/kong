local jwks = require "kong.openid-connect.jwks"


local kong = kong


local cache_opts = {
  ttl     = 0,
  neg_ttl = 0.001,
}


local cache_key
local pk_default = {
  id = "c3cfba2d-1617-453f-a416-52e6edb5f9a0",
}


local _M = {
}


local function load_jwks(dao)
  local keys, err = dao.super.select(dao, pk_default)
  if not keys then
    if err then
      return nil, err
    end

    if kong.configuration.database ~= "off" then
      local generated_jwks
      generated_jwks, err = jwks.new()
      if not generated_jwks then
        return nil, err
      end

      keys, err = dao.super.insert(dao, {
        id   = pk_default.id,
        jwks = generated_jwks,
      })

      if not keys then
        local err2
        keys, err2 = dao.super.select(dao, pk_default)
        if not keys then
          if err then
            return nil, err
          end

          if err2 then
            return nil, err2
          end

          return nil, "unable to load default jwks"
        end
      end
    end
  end

  if not keys and kong.configuration.database ~= "off" then
    return nil, "unable to load default jwks"
  end

  return keys
end


function _M:get()
  if not cache_key then
    cache_key = self.super.cache_key(self, pk_default)
  end

  local keys, err = kong.cache:get(cache_key, cache_opts, load_jwks, self)
  if not keys then
    return nil, err
  end

  return keys
end


return _M
