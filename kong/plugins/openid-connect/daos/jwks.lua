-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local jwks = require "kong.openid-connect.jwks"


local kong = kong
local remove = table.remove
local ipairs = ipairs


local cache_opts = {
  ttl     = 0,
  neg_ttl = 0.001,
}


local cache_key
local pk_default = {
  id = "c3cfba2d-1617-453f-a416-52e6edb5f9a0",
}


local JWKS = {
  id = pk_default.id,
  jwks = {
    keys = {}
  }
}

local _M = {
}


local function load_jwks(dao)
  local ok
  local keys, err = dao.super.select(dao, pk_default)
  if keys then
    return keys
  end

  if err then
    return nil, err
  end

  local dbless = kong.configuration.database == "off"

  if dbless and #JWKS.jwks.keys > 0 then
    keys = JWKS
    return keys
  end

  keys, err = dao.super.select(dao, pk_default)
  if keys then
    return keys
  end

  if dbless then
    ok, err = kong.worker_events.poll()
    if not ok then
      return nil, err
    end

    if #JWKS.jwks.keys > 0 then
      keys = JWKS
      return keys
    end
  end

  local generated_jwks
  generated_jwks, err = jwks.new()
  if not generated_jwks then
    return nil, err
  end

  if dbless then
    for i, key in ipairs(generated_jwks.keys) do
      JWKS.jwks.keys[i] = key
    end

    keys = JWKS

    ok, err = kong.worker_events.post("openid-connect", "reset-jwks", JWKS.jwks.keys)
    if not ok then
      return nil, err
    end

  else
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

  if not keys and dbless then
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


function _M:rem()
  if not cache_key then
    cache_key = self.super.cache_key(self, pk_default)
  end

  local ok, err = self.super.delete(self, pk_default)
  if not ok then
    return nil, err
  end

  if kong.configuration.database == "off" then
    kong.cache:invalidate_local(cache_key)
  else
    kong.cache:invalidate(cache_key)
  end

  for i = #JWKS.jwks.keys, 1, -1 do
    remove(JWKS.jwks.keys, i)
  end

  ok, err = self:get()
  if not ok then
    return nil, err
  end

  return true
end


function _M.init_worker()
  kong.worker_events.register(function(keys)
    for i = #JWKS.jwks.keys, 1, -1 do
      remove(JWKS.jwks.keys, i)
    end

    for i = 1, #keys do
      JWKS.jwks.keys[i] = keys[i]
    end
  end, "openid-connect", "reset-jwks")
end


return _M
