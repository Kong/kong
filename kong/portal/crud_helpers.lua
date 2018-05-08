local enums = require "kong.portal.enums"
local cjson = require "cjson"
local app_helpers   = require "lapis.application"
local singletons = require "kong.singletons"

local _M = {}


function _M.insert_credential(credential, plugin, consumer_type)
  local _credential, err = singletons.dao.credentials:insert({
    id = credential.id,
    consumer_id = credential.consumer_id,
    consumer_type = consumer_type or enums.CONSUMERS.TYPE.PROXY,
    plugin = plugin,
    blob = tostring(cjson.encode(credential)),
  })

  if err then
    return app_helpers.yield_error(err)
  end

  return _credential
end


function _M.patch_credential(credential)
  local params = {
    blob = cjson.encode(credential)
  }

  credential.created_at = nil
  print(require("pl.pretty").write(singletons.dao.credentials))
  local _credential, err = singletons.dao.credentials:update(params, {
      id = credential.id,
      consumer_id = credential.consumer_id
  })

  if err then
    return app_helpers.yield_error(err)
  end

  return _credential
end


function _M.delete_credential(credential_id)
  local ok, err = singletons.dao.credentials:delete({ id = credential_id })

  if not ok then
    if err then
      return app_helpers.yield_error(err)
    end
  end
end


return _M
