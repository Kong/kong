local enums = require "kong.enterprise_edition.dao.enums"
local cjson = require "cjson"
local app_helpers   = require "lapis.application"
local singletons = require "kong.singletons"


local _M = {}


function _M.insert_credential(plugin, consumer_type)
  return function(credential)
    local _, err = singletons.dao.credentials:insert({
      id = credential.id,
      consumer_id = credential.consumer_id,
      consumer_type = consumer_type or enums.CONSUMERS.TYPE.PROXY,
      plugin = plugin,
      credential_data = tostring(cjson.encode(credential)),
    })

    if err then
      return app_helpers.yield_error(err)
    end

    return credential
  end
end


function _M.update_credential(credential)
  local params = {
    credential_data = cjson.encode(credential),
  }

  local _, err = singletons.dao.credentials:update(params, {
      id = credential.id,
      consumer_id = credential.consumer_id
  }, {__skip_rbac = true})

  if err then
    return app_helpers.yield_error(err)
  end

  return credential
end


function _M.delete_credential(credential)
  if not credential or not credential.id then
    ngx.log(ngx.DEBUG, "Failed to delete credential from credentials")
  end

  local _, err = singletons.dao.credentials:delete({ id = credential.id }, {__skip_rbac = true})
  if err then
    return app_helpers.yield_error(err)
  end
end

function _M.update_login_credential(credential_params, dao_collection, filter_keys)
  local credential, err = dao_collection:update(credential_params, filter_keys, {__skip_rbac = true})

  if err then
    return nil, err
  end

  if credential == nil then
    return nil
  end

  return _M.update_credential(credential)
end


return _M
