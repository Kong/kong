local enums = require "kong.portal.enums"
local cjson = require "cjson"
local app_helpers   = require "lapis.application"
local singletons = require "kong.singletons"


local _M = {}


function _M.insert_credential(credential, plugin, consumer_type)
  local cred, err = singletons.dao.credentials:insert({
    id = cred.id,
    consumer_id = cred.consumer_id,
    consumer_type = consumer_type or enums.CONSUMERS.TYPE.PROXY,
    plugin = plugin,
    credential_data = tostring(cjson.encode(credential)),
  })

  if err then
    return app_helpers.yield_error(err)
  end

  return cred
end


function _M.update_credential(credential)
  local params = {
    credential_data = cjson.encode(credential),
  }

  local cred, err = singletons.dao.credentials:update(params, {
      id = credential.id,
      consumer_id = credential.consumer_id
  })

  if err then
    return app_helpers.yield_error(err)
  end

  return cred
end


function _M.delete_credential(credential_id)
  local ok, err = singletons.dao.credentials:delete({ id = credential_id })
    if err then
      return app_helpers.yield_error(err)
  end
end


return _M
