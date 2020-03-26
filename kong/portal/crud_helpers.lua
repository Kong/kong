local cjson       = require "cjson"
local Errors      = require "kong.db.errors"
local workspaces  = require "kong.workspaces"
local singletons  = require "kong.singletons"
local utils       = require "kong.tools.utils"
local endpoints   = require "kong.api.endpoints"
local enums       = require "kong.enterprise_edition.dao.enums"
local files       = require "kong.portal.migrations.01_initial_files"
local constants    = require "kong.constants"

local kong = kong
local type = type
local next = next


local PORTAL = constants.WORKSPACE_CONFIG.PORTAL


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


local function add_param(key, value, param_str)
  local param = tostring(key) .. "=" .. tostring(value)
  if param_str == "" then
    return "?" .. param
  else
    return param_str .. "&" .. param
  end
end


local function get_next_page(self, offset)
  if not offset then
    return ngx.null
  end

  -- rebuild query params from the request,
  -- minus the offset param if there was one
  local param_str = ""
  for k, v in pairs(self.req.params_get) do
    if k ~= "offset" then
      param_str = add_param(k, v, param_str)
    end
  end

  -- finally add the new offset
  param_str = add_param("offset", offset, param_str)

  return self.req.parsed_url.path .. param_str
end


function _M.paginate(self, set, post_process)
  local new_offset
  local data = setmetatable({}, cjson.empty_array_mt)
  local should_post_process = type(post_process) == "function"

  local size = self.req.params_get and tonumber(self.req.params_get.size) or 100
  local offset = self.req.params_get and self.req.params_get.offset

  -- find the index of the first element that matches our offset
  local i = 1
  if offset then
    while set[i] do
      if set[i].id == offset then break end
      i = i + 1
    end

    -- offset did not match any ids in the set, return error
    if not set[i] then
      return nil, "invalid offset", {
        code = Errors.codes.INVALID_OFFSET,
        message = "invalid offset"
      }
    end
  end

  -- search for n+1 records, or until set is exhausted
  -- after n rows are found, we search for next valid row
  -- to serve as our pagination offset.
  while set[i] and not new_offset do
    local row = set[i]
    if should_post_process then
      row = post_process(row)
    end

    if row and next(row) then
      -- our data set is full, save this id as the offset for the next page
      if #data == size then
        new_offset = row.id
      else
        -- otherwise add row to return data
        table.insert(data, row)
      end
    end

    i = i + 1
  end

  return  {
    data = data,
    total = #data,
    offset = new_offset,
    next = get_next_page(self, new_offset),
  }
end


local function find_login_credentials(db, consumer_pk)
  local creds = setmetatable({}, cjson.empty_array_mt)

  for row, err in db.credentials:each_for_consumer({id = consumer_pk}) do
    if err then
      return nil, err
    end

    if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER then
      local cred_data = row.credential_data
      if type(cred_data) == "string" then
        cred_data, err = cjson.decode(cred_data)
        if err then
          return nil, err
        end
      end

      table.insert(creds, cred_data)
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


function _M.get_credential(self, db, helpers)
  local login_credentials, err = find_login_credentials(db, self.consumer.id)
  if err then
    return endpoints.handle_error(err)
  end

  local credential, _, err_t = self.credential_collection:select({ id = self.params.credential_id })
  if err_t then
    return endpoints.handle_error(err_t)
  end
  if not credential then
    return kong.response.exit(404, { message = "Not found" })
  end

  if self.consumer.id ~= credential.consumer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  if is_login_credential(login_credentials, credential) then
    return kong.response.exit(404, { message = "Not found" })
  end

  return kong.response.exit(200, credential)
end


function _M.get_credentials(self, db, helpers, opts)
  local credentials = setmetatable({}, cjson.empty_array_mt)
  local login_credentials, err = find_login_credentials(db, self.consumer.id)
  if err then
    return endpoints.handle_error(err)
  end

  for row, err in self.credential_collection:each_for_consumer({ id = self.consumer.id }, opts) do
    if err then
      return endpoints.handle_error(err)
    end

    if not is_login_credential(login_credentials, row) then
      credentials[#credentials + 1] = row
    end
  end

  local res, _, err_t = _M.paginate(self, credentials)
  if not res then
    return endpoints.handle_error(err_t)
  end

  kong.response.exit(200, res)
end


function _M.create_credential(self, db, helpers, opts)
  self.params.plugin = nil

  local credential, _, err_t = self.credential_collection:insert(self.params, opts)
  if not credential then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(201, credential)
end


function _M.update_credential(self, db, helpers, opts)
  local cred_id = self.params.credential_id
  self.params.plugin = nil
  self.params.credential_id = nil

  local login_credentials, err = find_login_credentials(db, self.consumer.id)
  if err then
    return endpoints.handle_error(err)
  end

  local credential, _, err_t = self.credential_collection:select({ id = cred_id })
  if not credential then
    return endpoints.handle_error(err_t)
  end

  if self.consumer.id ~= credential.consumer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  if is_login_credential(login_credentials, credential) then
    return kong.response.exit(404, { message = "Not found" })
  end

  credential, _, err_t = self.credential_collection:update({ id = cred_id }, self.params)
  if not credential then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(200, credential)
end


function _M.delete_credential(self, db, helpers, opts)
  local cred_id = self.params.credential_id
  self.params.plugin = nil
  self.params.credential_id = nil

  local login_credentials, err = find_login_credentials(db, self.consumer.id)
  if err then
    return endpoints.handle_error(err)
  end

  local credential, _, err_t = self.credential_collection:select({ id = cred_id })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not credential then
    return kong.response.exit(204)
  end

  if self.consumer.id ~= credential.consumer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  if is_login_credential(login_credentials, credential) then
    return kong.response.exit(204)
  end

  local _, _, err_t = self.credential_collection:delete({id = cred_id })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(204)
end


function _M.update_login_credential(collection, cred_pk, entity)
  local credential, err = collection:update(cred_pk, entity, {skip_rbac = true})

  if err then
    return nil, err
  end

  if credential == nil then
    return nil
  end

  local _, err, err_t = singletons.db.credentials:update(
    { id = credential.id },
    { credential_data = cjson.encode(credential), },
    { skip_rbac = true }
  )

  if err then
    return endpoints.handle_error(err_t)
  end

  return credential
end


function _M.get_document_objects_by_service(self, db, helpers)
  local service_id = self.params.services
  local document_object
  for row, err in db.document_objects:each_for_service({ id = service_id }) do
    document_object = row
  end

  return kong.response.exit(200, {
    data = setmetatable({ document_object }, cjson.empty_array_mt),
    next = ngx.null,
  })
end


function _M.create_document_object_by_service(self, db, helpers)
  local service_id = self.params.services
  local path = self.params.path
  local document = db.files:select_by_path(path)
  if not document then
    return kong.response.exit(404, {message = "Not found" })
  end

  local document_object, _, err_t = db.document_objects:insert({
    service = { id = service_id },
    path = path,
  })

  if err_t then
    return endpoints.handle_error(err_t)
  end

  kong.response.exit(200, {
    data = { document_object },
    next = ngx.null,
  })
end


function _M.create_application_instance(self, db, helpers)
  local developer, _, err_t = kong.db.developers:select({ id = self.application.developer.id })
  if not developer then
    return endpoints.handle_error(err_t)
  end

  self.params.suspended = developer.status ~= enums.CONSUMERS.STATUS.APPROVED
  self.params.application = { id = self.application.id }

  local application_instance, _, err_t = db.application_instances:insert(self.params)
  if not application_instance then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(201, application_instance)
end


function _M.get_application_instance(self, db, helpers)
  local application_instance_pk = { id = self.application_instance.id }
  local application_instance, _, err_t =
    db.application_instances:select(application_instance_pk)

  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not application_instance then
    return kong.response.exit(404, {message = "Not found" })
  end

  if not self.application then
    self.application = db.applications:select({ id = application_instance.application.id })
    if not self.application then
      return kong.response.exit(404, {message = "Not found" })
    end
  end

  if not self.developer then
    self.developer = db.developers:select({ id = self.application.developer.id })
    if not self.developer then
      return kong.response.exit(404, {message = "Not found" })
    end
  end

  application_instance.application = self.application
  application_instance.application.developer = self.developer

  kong.response.exit(200, application_instance)
end


function _M.update_application_instance(self, db, helpers)
  if not self.application then
    self.application = db.applications:select({ id = self.application_instance.application.id })
    if not self.application then
      return kong.response.exit(404, {message = "Not found" })
    end
  end

  local developer, _, err_t = kong.db.developers:select({ id = self.application.developer.id })
  if not developer then
    return endpoints.handle_error(err_t)
  end

  self.params.suspended = developer.status ~= enums.CONSUMERS.STATUS.APPROVED

  local application_instance_pk = { id = self.application_instance.id }
  local application_instance, _, err_t = db.application_instances:update(application_instance_pk, self.params)
  if not application_instance then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(200, application_instance)
end


function _M.delete_application_instance(self, db, helpers)
  local application_instance_pk = { id = self.application_instance.id }
  local _, _, err_t = db.application_instances:delete(application_instance_pk, self.params)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(204)
end


local function get_application_instances(self, db, helpers, opts)
  local status = tonumber(self.params.status)

  local application_instances = {}
  local dao = db.application_instances
  local entity_method = "each_for_" .. opts.search_entity

  for row, err in dao[entity_method](dao, { id = self.entity.id }) do
    if row and row.status == status or status == nil then
      table.insert(application_instances, row)
    end
  end

  local post_process = function(row)
    local application, err = db.applications:select({ id = row.application.id })
    if err then
      ngx.log(ngx.DEBUG, err)
    end

    if application then
      local developer, err = db.developers:select({ id = application.developer.id })
      if err then
        ngx.log(ngx.DEBUG, err)
      end

      if developer then
        application.developer = developer
        row.application = application
      end
    end

    return row
  end

  setmetatable(application_instances, cjson.empty_array_mt)

  local res, _, err_t = _M.paginate(self, application_instances, post_process)
  if not res then
    return endpoints.handle_error(err_t)
  end

  kong.response.exit(200, res)
end


function _M.get_application_instances_by_application(self, db, helpers)
  self.entity = self.application
  return get_application_instances(self, db, helpers, {
    search_entity = "application"
  })
end


function _M.get_application_instances_by_service(self, db, helpers)
  -- currently "/services/:services/application_instances" sets self.entity to service instance
  -- if changed update here
  self.entity = self.service
  return get_application_instances(self, db, helpers, {
    search_entity = "service",
  })
end


function _M.service_applications_before(self, db, helpers)
  local id = self.params.services
  self.params.services = nil

  local entity, _, err_t
  if not utils.is_valid_uuid(id) then
    entity, _, err_t = db.services:select_by_name(id)
  else
    entity, _, err_t = db.services:select({ id = id })
  end

  if not entity or err_t then
    return kong.response.exit(404, {message = "Not found" })
  end

  self.entity = entity
end


function _M.service_application_instances_before(self, db, helpers)
  local id = self.params.services
  self.params.services = nil

  local entity, _, err_t
  if not utils.is_valid_uuid(id) then
    entity, _, err_t = db.services:select_by_name(id)
  else
    entity, _, err_t = db.services:select({ id = id })
  end

  if not entity or err_t then
    return kong.response.exit(404, {message = "Not found" })
  end

  local application_instance, _, err_t = db.application_instances:select({ id = self.params.application_instances })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not application_instance then
    return kong.response.exit(404, {message = "Not found" })
  end

  if application_instance.service.id ~= entity.id then
    return kong.response.exit(404, {message = "Not found" })
  end

  self.application_instance = application_instance
  self.entity = entity
end


local function initialize_portal_files(premature, workspace, db)
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
        path = file.path,
        contents = file.contents,
      })

    if not ok then
      return nil, err
    end
  end

  return workspace
end


function _M.check_initialized(workspace, db)
  -- if portal is not enabled, return early
  local config = workspace.config
  if not config.portal then
    return workspace
  end

  -- run database insertions in the background to avoid partial insertion on
  -- request terminations from the browser
  local ok, err = ngx.timer.at(0, initialize_portal_files, workspace, db)
  if not ok then
    return nil, err
  end

  return workspace
end


function _M.exit_if_portal_disabled()
  local ws = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local opts = { explicitly_ws = true }
  local enabled_in_ws = workspaces.retrieve_ws_config(PORTAL, ws, opts)
  local enabled_in_conf = kong.configuration.portal
  if not enabled_in_conf or not enabled_in_ws then
    return kong.response.exit(404, { message = "Not Found" })
  end
end


return _M
