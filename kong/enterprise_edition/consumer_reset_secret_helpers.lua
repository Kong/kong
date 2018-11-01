local singletons = require "kong.singletons"
local ee_jwt = require "kong.enterprise_edition.jwt"
local enums = require "kong.enterprise_edition.dao.enums"
local now = ngx.now


local _M = {}

local function create(consumer, client_addr, expiry)
  local rows, err = singletons.dao.consumer_reset_secrets:find_all({
    consumer_id = consumer.id
  })

  if err then
    return nil, err
  end

  -- Invalidate any pending resets for this consumer
  for _, row in ipairs(rows) do
    if row.status == enums.TOKENS.STATUS.PENDING then
      local _, err = singletons.dao.consumer_reset_secrets:update({
            status = enums.TOKENS.STATUS.INVALIDATED,
            updated_at = now() * 1000,
          }, {
            id = row.id
          })

      if err then
        -- bail on first error. There's probably something else more wrong.
        return nil, err
      end
    end
  end

  -- Generate new reset
  local row, err = singletons.dao.consumer_reset_secrets:insert({
    consumer_id = consumer.id,
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
_M.create = create

return _M
