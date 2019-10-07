local enums = require "kong.enterprise_edition.dao.enums"
local ee_api_helpers = require "kong.enterprise_edition.api_helpers"

local ADMIN = enums.CONSUMERS.TYPE.ADMIN
local DEVELOPER = enums.CONSUMERS.TYPE.DEVELOPER

local kong = kong
local _M = {}

function _M.post_process_credential(credential)
  local consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                      ee_api_helpers.retrieve_consumer,
                                      credential.consumer.id)
  if err then
    return kong.response.exit(500, {message =
      "error finding consumer: ", credential.consumer_id})
  end

  -- don't return credentials for non-proxy consumers
  if consumer.type == ADMIN or consumer.type == DEVELOPER then
    return nil
  end

  return credential
end

return _M
