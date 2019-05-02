local enums = require "kong.enterprise_edition.dao.enums"
local ee_api_helpers = require "kong.enterprise_edition.api_helpers"

local _M = {}

-- XXX EE: delete these unneeded find_*
-- function _M.find_consumer_by_username_or_id(self, dao_factory, helpers, filter)
--   filter = filter or {}
--   filter.type = enums.CONSUMERS.TYPE.PROXY

--   api_crud_helpers.find_consumer_by_username_or_id(self,
--                                                    dao_factory,
--                                                    helpers,
--                                                    filter)
-- end


-- function _M.find_developer_by_email_or_id(self, dao_factory, helpers, filter)
--   filter = filter or {}
--   filter.type = enums.CONSUMERS.TYPE.DEVELOPER

--   api_crud_helpers.find_consumer_by_email_or_id(self, dao_factory, helpers, filter)
-- end


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
  if consumer.type == enums.CONSUMERS.TYPE.ADMIN then
    return nil
  end

  return credential
end

return _M
