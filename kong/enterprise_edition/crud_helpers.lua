local responses   = require "kong.tools.responses"
local app_helpers = require "lapis.application"
local api_crud_helpers = require "kong.api.crud_helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local singletons = require "kong.singletons"
local ee_api_helpers = require "kong.enterprise_edition.api_helpers"

local _M = {}


function _M.delete_without_sending_response(primary_keys, dao_collection)
  local ok, err = dao_collection:delete(primary_keys)

  if not ok then
    if err then
      return app_helpers.yield_error(err)
    else
      return responses.send_HTTP_NOT_FOUND()
    end
  else
    return nil
  end
end


function _M.find_consumer_by_username_or_id(self, dao_factory, helpers, filter)
  filter = filter or {}
  filter.type = enums.CONSUMERS.TYPE.PROXY

  api_crud_helpers.find_consumer_by_username_or_id(self,
                                                   dao_factory,
                                                   helpers,
                                                   filter)
end


function _M.post_process_credential(credential)
  local consumer_cache_key = singletons.dao.consumers:cache_key(credential.consumer_id)
  local consumer, err = singletons.cache:get(consumer_cache_key,
                                             nil,
                                             ee_api_helpers.retrieve_consumer,
                                             credential.consumer_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(
        "error finding consumer: ", credential.consumer_id)
  end

  -- don't return credentials for non-proxy consumers
  if consumer.type ~= enums.CONSUMERS.TYPE.PROXY then
    return nil
  end

  return credential
end

return _M
