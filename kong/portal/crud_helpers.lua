local enums       = require "kong.enterprise_edition.dao.enums"
local cjson       = require "cjson"
local app_helpers = require "lapis.application"
local singletons  = require "kong.singletons"
local files       = require "kong.portal.migrations.01_initial_files"
local workspaces  = require "kong.workspaces"


local _M = {}


function _M.insert_credential(plugin, consumer_type)
  return function(credential)
    local _, err = singletons.db.credentials:insert({
      id = credential.id,
      consumer = { id = credential.consumer.id },
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
  local _, err = singletons.db.credentials:update(
    { id = credential.id },
    { credential_data = cjson.encode(credential), },
    { skip_rbac = true }
  )

  if err then
    return app_helpers.yield_error(err)
  end

  return credential
end


function _M.delete_credential(credential)
  if not credential or not credential.id then
    ngx.log(ngx.DEBUG, "Failed to delete credential from credentials")
  end

  local _, err = singletons.db.credentials:delete({ id = credential.id }, { skip_rbac = true })
  if err then
    return app_helpers.yield_error(err)
  end
end

function _M.update_login_credential(credential_params, dao_collection, filter_keys)
  local credential, err = dao_collection:update(credential_params, filter_keys, { skip_rbac = true })

  if err then
    return nil, err
  end

  if credential == nil then
    return nil
  end

  return _M.update_credential(credential)
end

function _M.check_initialized(workspace, dao)
  -- if portal is not enabled, return early
  local config = workspace.config
  if not config.portal then
    return workspace
  end

  local count, err = workspaces.run_with_ws_scope({workspace}, dao.files.count, dao.files)
  if not count then
    return nil, err
  end

  -- if we already have files, return
  if count > 0 then
    return workspace
  end

  -- if no files for this workspace, create them!
  for _, file in ipairs(files) do
    local ok, err = workspaces.run_with_ws_scope({workspace}, dao.files.insert, dao.files, {
      auth = file.auth,
      name = file.name,
      type = file.type,
      contents = file.contents,
    })

    if not ok then
      return nil, err
    end
  end

  return workspace
end

return _M
