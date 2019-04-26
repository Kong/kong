local cjson       = require "cjson"
local Errors      = require "kong.db.errors"
local workspaces  = require "kong.workspaces"
local singletons  = require "kong.singletons"
local app_helpers = require "lapis.application"
local endpoints   = require "kong.api.endpoints"
local enums       = require "kong.enterprise_edition.dao.enums"
local files       = require "kong.portal.migrations.01_initial_files"

local _M = {}


local function count_entities(arr)
  return {
    total = #arr,
    data = arr
  }
end


function _M.find_and_filter(self, entity, validator)
  local filtered_items = {}
  local all_items, err = entity:page()
  if err then
    return nil, err
  end

  if not validator then
    return all_items
  end

  for i, v in ipairs(all_items) do
    if validator(self, v) then
      table.insert(filtered_items, v)
    end
  end

  return filtered_items
end


local function rebuild_params(params)
  local param_str = ""
  for k, v in pairs(params) do
    param_str = param_str .. tostring(k) .. '=' .. tostring(v)
  end

  return param_str
end


local function get_paginated_table(self, route, set, size, idx)
  local offset
  local data = {}
  local next = ngx.null
  local offset_idx = size + idx
  local final_idx = size + idx - 1

  local data = setmetatable(data, cjson.empty_array_mt)

  for i = idx, final_idx do
    if set[i] then
      table.insert(data, set[i])
    end
  end

  if set[offset_idx] then
    offset = set[offset_idx].id
    next = route .. '?' .. rebuild_params(self.params) .. '&offset=' .. offset
  end

  return  {
    data = data,
    offset = offset,
    next = next,
  }
end


function _M.paginate(self, route, set, size, offset)
  if not offset then
    return get_paginated_table(self, route, set, size, 1)
  end

  for i, v in ipairs(set) do
    if v.id == offset then
      return get_paginated_table(self, route, set, size, i)
    end
  end

  return nil, nil, {
    code = Errors.codes.INVALID_OFFSET,
    message = "invalid offset"
  }
end


local function find_login_credentials(db, consumer_pk)
  local creds = {}
  local login_creds = db.credentials:select_all({ consumer = { id = consumer_pk } })
  for i, v in ipairs(login_creds) do
    if v.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER then
      table.insert(creds, v.credential_data)
    end
  end

  return creds
end


local function is_login_credential(login_credentials, credential)
  for i, v in ipairs(login_credentials) do
    if v.id == credential.id then
      return true
    end
  end

  return false
end


function _M.get_credential(self, db, helpers, opts)
  local login_credentials = find_login_credentials(db, self.developer.consumer.id)
  local credential, _, err_t = self.credential_collection:select({ id = self.params.credential_id })
  if err_t then
    return helpers.handle_error(err_t)
  end

  if not credential then
    helpers.responses.send_HTTP_NOT_FOUND()
  end

  if is_login_credential(login_credentials, credential) then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  return helpers.responses.send_HTTP_OK(credential)
end


function _M.create_credential(self, db, helpers, opts)
  self.params.consumer = { id = self.developer.consumer.id }
  self.params.plugin = nil

  local credential, _, err_t = self.credential_collection:insert(self.params, opts)
  if not credential then
    return endpoints.handle_error(err_t)
  end

  return helpers.responses.send_HTTP_OK(credential)
end


function _M.update_credential(self, db, helpers, opts)
  local cred_id = self.params.credential_id
  self.params.plugin = nil
  self.params.credential_id = nil

  local login_credentials = find_login_credentials(db, self.developer.consumer.id)
  local credential, _, err_t = self.credential_collection:select({ id = cred_id })
  if not credential then
    return endpoints.handle_error(err_t)
  end

  if is_login_credential(login_credentials, credential) then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  credential, _, err_t = self.credential_collection:update({ id = cred_id }, self.params)
  if not credential then
    return endpoints.handle_error(err_t)
  end

  return helpers.responses.send_HTTP_OK(credential)
end


function _M.delete_credential(self, db, helpers, opts)
  local cred_id = self.params.credential_id
  self.params.plugin = nil
  self.params.credential_id = nil

  local login_credentials = find_login_credentials(db, self.developer.consumer.id)
  local credential, _, err_t = self.credential_collection:select({ id = cred_id })
  if not credential then
    return endpoints.handle_error(err_t)
  end

  if is_login_credential(login_credentials, credential) then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  local ok, _, err_t = self.credential_collection:delete({id = cred_id })
  if not ok then
    return endpoints.handle_error(err_t)
  end

  return helpers.responses.send_HTTP_NO_CONTENT()
end


function _M.get_credentials(self, db, helpers, opts)
  local credentials = setmetatable({}, cjson.empty_array_mt)
  local login_credentials = find_login_credentials(db, self.developer.consumer.id)

  for row, err in self.credential_collection:each_for_consumer({ id = self.developer.consumer.id }, opts) do
    if err then
      return endpoints.handle_error(err)
    end

    if not is_login_credential(login_credentials, row) then
      credentials[#credentials + 1] = row
    end
  end

  return helpers.responses.send_HTTP_OK(count_entities(credentials))
end


function _M.update_login_credential(collection, cred_pk, entity)
  local credential, err = collection:update(cred_pk, entity, {skip_rbac = true})

  if err then
    return nil, err
  end

  if credential == nil then
    return nil
  end

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


function _M.check_initialized(workspace, db)
  -- if portal is not enabled, return early
  local config = workspace.config
  if not config.portal then
    return workspace
  end

  -- Check if any files exist
  local any_file = workspaces.run_with_ws_scope(
    { workspace },
    db.files.each,
    db.files )()

  -- if we already have files, return
  if any_file then
    return workspace
  end

  -- if no files for this workspace, create them!
  for _, file in ipairs(files) do
    local ok, err = workspaces.run_with_ws_scope(
      { workspace },
      db.files.insert,
      db.files,
      {
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
