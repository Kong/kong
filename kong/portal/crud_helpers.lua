local cjson       = require "cjson"
local Errors      = require "kong.db.errors"
local singletons  = require "kong.singletons"
local app_helpers = require "lapis.application"
local workspaces  = require "kong.workspaces"
local files       = require "kong.portal.migrations.01_initial_files"

local _M = {}


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

function _M.update_login_credential(collection, cred_pk, entity)
  local credential, err = collection:update(cred_pk, entity, {skip_rbac = true})

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
