local singletons = require "kong.singletons"
local ee_jwt = require "kong.enterprise_edition.jwt"
local enums = require "kong.enterprise_edition.dao.enums"

local INVALIDATED = enums.TOKENS.STATUS.INVALIDATED
local PENDING = enums.TOKENS.STATUS.PENDING
local CONSUMED = enums.TOKENS.STATUS.CONSUMED

local _M = {}


function _M.create(consumer, client_addr, expiry)
  local reset_secrets = singletons.db.consumer_reset_secrets

  -- Invalidate pending resets
  local ok, err = _M.invalidate_pending_resets(consumer)
  if not ok then
    return nil, err
  end

  -- Generate new reset
  local row, err = reset_secrets:insert({
    consumer = { id = consumer.id },
    client_addr = client_addr,
  })

  if err then
    return nil, err
  end

  -- Generate a JWT the user can use to complete a reset
  local claims = {
    id = consumer.id,
    exp = ngx.time() + expiry,
  }

  local jwt, err = ee_jwt.generate_JWT(claims, row.secret)
  if err then
    return nil, err
  end

  return jwt
end


function _M.invalidate_pending_resets(consumer)
  local reset_secrets = singletons.db.consumer_reset_secrets

  for secret, err in reset_secrets:each_for_consumer({ id = consumer.id }) do
    if err then
      return nil, err
    end

    if secret.status == PENDING then
      local _, err = reset_secrets:update({
        id = secret.id,
      }, {
        status = INVALIDATED,
      })
      if err then
        return nil, err
      end
    end
  end

  return true
end


function _M.consume_secret(secret_id)
  return singletons.db.consumer_reset_secrets:update({
    id = secret_id,
  }, {
    status = CONSUMED,
  })
end


return _M
