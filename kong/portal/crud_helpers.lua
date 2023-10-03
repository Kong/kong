-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson       = require "cjson"
local inspect     = require "inspect"
local Errors      = require "kong.db.errors"
local workspaces  = require "kong.workspaces"
local utils       = require "kong.tools.utils"
local endpoints   = require "kong.api.endpoints"
local enums       = require "kong.enterprise_edition.dao.enums"
local files       = require "kong.portal.migrations.01_initial_files"
local constants   = require "kong.constants"
local workspace_config = require "kong.portal.workspace_config"
local arguments   = require "kong.api.arguments"
local permissions = require "kong.portal.permissions"
local file_helpers = require "kong.portal.file_helpers"
local app_auth_strategies = require "kong.portal.app_auth_strategies"
local portal_smtp_client  = require "kong.portal.emails"
local dao_helpers         = require "kong.portal.dao_helpers"


local kong = kong
local type = type
local next = next
local sort = table.sort


local PORTAL = constants.WORKSPACE_CONFIG.PORTAL
local PAGE_SIZE_DEFAULT = 100
local PAGE_SIZE_MIN = 1
local PAGE_SIZE_MAX = 1000


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
  local new_offset, offset, sort_by
  local size = PAGE_SIZE_DEFAULT
  local sort_desc = false
  local data = setmetatable({}, cjson.empty_array_mt)
  local should_post_process = type(post_process) == "function"

  local params_get = self.req.params_get
  if params_get then
    offset = params_get.offset
    size = tonumber(params_get.size) or PAGE_SIZE_DEFAULT
    sort_by = type(params_get.sort_by) == "string" and params_get.sort_by
    sort_desc = not not params_get.sort_desc
  end

  if type(size) ~= "number" or size > PAGE_SIZE_MAX or size < PAGE_SIZE_MIN then
    return nil, "invalid size", {
      code = Errors.codes.INVALID_SIZE,
      message = "invalid size"
    }
  end

  -- default to id if no sort_by
  sort_by = sort_by or "id"

  sort(set, function (a, b)
    -- if sort_by values are equal
    -- sort by id instead
    local key
    if a[sort_by] ~= b[sort_by] then
      key = sort_by
    else
      key = "id"
    end

    -- sort nil as "less"
    -- avoid comparing them, this throws an error
    if a[key] == nil then
      return not sort_desc
    end

    if b[key] == nil then
      return sort_desc
    end

    if sort_desc then
      return a[key] > b[key]
    end

    return a[key] < b[key]
  end)

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


local function send_application_service_requested_email(developer, application_instance, application)
  -- if name does not exist, we use the email for email template
  local name_or_email = dao_helpers.get_name_or_email(developer)
  local portal_emails = portal_smtp_client.new()
  local _, err = portal_emails:application_service_requested(name_or_email, developer.email,
                                                       application.name, application.id)
  if err then
    ngx.log(ngx.ERR, "failed sending service request email: ", inspect(err))
  end
end


local function send_application_service_status_change_email(developer, application_instance, application)
  -- if name does not exist, we use the email for email template
  local name_or_email = dao_helpers.get_name_or_email(developer)
  local portal_emails = portal_smtp_client.new()
  local _, err

  if application_instance.status == enums.CONSUMERS.STATUS.APPROVED then
    _, err = portal_emails:application_service_approved(developer.email,
                        name_or_email,
                        application.name)
  elseif application_instance.status == enums.CONSUMERS.STATUS.PENDING then
    _, err = portal_emails:application_service_pending(developer.email,
                        name_or_email,
                        application.name)
  elseif application_instance.status == enums.CONSUMERS.STATUS.REJECTED then
    _, err = portal_emails:application_service_rejected(developer.email,
                        name_or_email,
                        application.name)
  elseif application_instance.status == enums.CONSUMERS.STATUS.REVOKED then
    _, err = portal_emails:application_service_revoked(developer.email,
                        name_or_email,
                        application.name)
  end

  if err then
    ngx.log(ngx.ERR, "failed sending status change email: ", err)
  end
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
  local search_fields = {}

  local client_id_filter = self.req.params_get.client_id
  if client_id_filter then
    search_fields.client_id = { value = client_id_filter, field = { type = "string" }}
  end

  local username_filter = self.req.params_get.username
  if username_filter then
    search_fields.username = { value = username_filter, field = { type = "string" }}
  end

  local key_filter = self.req.params_get.key
  if key_filter then
    search_fields.key = { value = key_filter, field = { type = "string" }}
  end

  local matches_search_fields = function(row)
    for k, search in pairs(search_fields) do
      if row[k] and not _M.contains_substring(row[k], search.value) then
        return false
      end
    end
    return true
  end

  local login_credentials, err = find_login_credentials(db, self.consumer.id)
  if err then
    return endpoints.handle_error(err)
  end

  for row, err in self.credential_collection:each_for_consumer({ id = self.consumer.id }, opts) do
    if err then
      return endpoints.handle_error(err)
    end

    if not is_login_credential(login_credentials, row) and matches_search_fields(row) then
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
  if self.params.id and self.params.id ~= self.params.credential_id then
    return kong.response.exit(400, { message = "Bad request" })
  end

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

  self.params.consumer = self.consumer

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


function _M.create_app_reg_credentials(self, db, helpers, opts)
  self.params.name = self.application.name
  self.params.consumer = self.application.consumer
  self.params.redirect_uris = { self.application.redirect_uri }
  self.params.plugin = nil

  local oauth2_credential, _, err_t = db.daos["oauth2_credentials"]:insert(self.params, opts)
  if not oauth2_credential then
    return endpoints.handle_error(err_t)
  end

  local keyauth_credential, _, err_t = db.daos["keyauth_credentials"]:insert({
    consumer = self.params.consumer,
    key = oauth2_credential.client_id
  }, opts)

  if not keyauth_credential then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(201, oauth2_credential)
end


function _M.delete_app_reg_credentials(self, db, helpers, opts)
  local cred_id = self.params.credential_id

  local credential, _, err_t = db.daos["oauth2_credentials"]:select({ id = cred_id })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not credential then
    return kong.response.exit(204)
  end

  if self.consumer.id ~= credential.consumer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  local _, _, err_t = db.daos["oauth2_credentials"]:delete({ id = cred_id })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  for row, err in db.daos["keyauth_credentials"]:each_for_consumer({ id = self.consumer.id }, opts) do
    if err then
      return endpoints.handle_error(err)
    end

    if row.key == credential.client_id then
      db.daos["keyauth_credentials"]:delete({ id = row.id })
    end
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

  local _, err, err_t = kong.db.credentials:update(
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
    return kong.response.exit(404, { message = "Not found" })
  end

  local document_object, _, err_t = db.document_objects:insert({
    service = { id = service_id },
    path = path,
  })

  if err_t then
    return endpoints.handle_error(err_t)
  end

  -- Currently not supporting multiple documents per service
  -- Deleting previously created ones to replace it with the new one (TDX-1620)
  for row, err in db.document_objects:each_for_service({ id = service_id }) do
    if row and row.id ~= document_object.id then
      db.document_objects:delete({ id = row.id })
    end
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

  send_application_service_requested_email(developer, application_instance, self.application)
  send_application_service_status_change_email(developer, application_instance, self.application)

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
  local previous_instance

  -- get the previous instance if updating the status
  if type(self.params.status) == "number" then
    previous_instance = db.application_instances:select(application_instance_pk)
  end

  local application_instance, _, err_t = db.application_instances:update(application_instance_pk, self.params)
  if not application_instance then
    return endpoints.handle_error(err_t)
  end

  -- send an email to the application's developer if the status changed
  if previous_instance and previous_instance.status ~= self.params.status then
    send_application_service_status_change_email(developer, application_instance, self.application)
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

local function build_developer(db, application, row)
  if not application then
    return row
  end
  local developer, err = db.developers:select({ id = application.developer.id })
  if err then
    ngx.log(ngx.DEBUG, err)
  end

  if developer then
    application.developer = developer
    row.application = application
  end

  return row
end

local function build_service_display_name(db, row)
  local plugin_name = "application-registration"
  for plugin, err in db.plugins:each_for_service({ id = row.service.id }, nil, { search_fields = { name = plugin_name } }) do
    if err then
      ngx.log(ngx.DEBUG, err)
    end
    if plugin and plugin.enabled then
      row.service.display_name = plugin.config.display_name
      break
    end
  end

  return row
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

  local post_process = {
    ["application"] = function(row)
      local application = self.entity
      row.application = application
      if application.developer then
        build_developer(db, application, row)
      end
      build_service_display_name(db, row)
     
      return row
    end,
    ["service"] = function(row)
      row.service = self.entity
      local application, err = db.applications:select({ id = row.application.id })
      if err then
        ngx.log(ngx.DEBUG, err)
      end

      if application.developer then
        build_developer(db, application, row)
      end
      return row
    end
  }

  setmetatable(application_instances, cjson.empty_array_mt)

  local res, _, err_t = _M.paginate(self, application_instances, post_process[opts.search_entity])
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
  local any_file = db.files:each(nil, { workspace = workspace.id })()

  -- if we already have files, return
  if any_file then
    return workspace
  end

  -- if no files for this workspace, create them!
  for _, file in ipairs(files) do
    local entity = { path = file.path, contents = file.contents }
    local ok, err = db.files:insert(entity, { workspace = workspace.id })

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
  local ws = workspaces.get_workspace()
  local opts = { explicitly_ws = true }
  local enabled_in_ws = workspace_config.retrieve(PORTAL, ws, opts)
  local enabled_in_conf = kong.configuration.portal
  if not enabled_in_conf or not enabled_in_ws then
    return kong.response.exit(404, { message = "Not Found" })
  end
end

function _M.exit_if_external_oauth2()
  if kong.configuration.portal_app_auth == "external-oauth2" then
    return kong.response.exit(404, { message = "Not Found" })
  end
end

function _M.get_application_services(self, db, helpers)
  local name_filter = self.req.params_get.name
  local app_id = self.req.params_get.app_id
  local status_filter = self.req.params_get.status

  local application_services = setmetatable({}, cjson.empty_array_mt)
  local application

  local matches_plugin_filters = function(row)
    if name_filter and not _M.contains_substring(row.config.display_name, name_filter) then
      return false
    end

    return true
  end

  local matches_instance_filters = function(instance)
    if status_filter == nil then return true end

    local status = tonumber(status_filter)

    if status == nil then
      return false
    elseif status == -1 then
      return instance == nil
    elseif instance then
      return instance.status == status
    end

    return false
  end

  -- If query params contain an app_id, join with any
  -- application_instances for each application_service.
  -- In this case, also filter the joined instances by
  -- their status if specified
  if app_id then
    local app, _, err_t = db.applications:select({ id = app_id })
    if err_t or not app or app.developer.id ~= self.developer.id then
      return kong.response.exit(404, { message = "Application not found" })
    end

    application = app
  end

  local app_reg_plugins = {}
  for plugin, err in db.plugins:each(nil, { search_fields = { name = "application-registration" } }) do
    if err then
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    if matches_plugin_filters(plugin) then
      table.insert(app_reg_plugins, plugin)
    end
  end

  -- get all instances for the given application
  local app_instances = {}
  if application then
    
    for instance, err in db.application_instances:each_for_application({ id = application.id }) do
      if err then
        return endpoints.handle_error(err)
      end

      if instance then
        app_instances[instance.service.id] = instance
      end
    end
  end

  local app_auth_type = kong.configuration.portal_app_auth
  local app_auth_strategy = app_auth_strategies[app_auth_type]
  local auth_config
  for i, v in ipairs(app_reg_plugins) do
    local instance = app_instances[v.service.id]
    if not matches_instance_filters(instance) then
      goto continue
    end
    local service, _, err_t = db.services:select(v.service)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    auth_config = app_auth_strategy.build_service_auth_config(service, v)

    local document_object
    for row, err in db.document_objects:each_for_service({ id = v.service.id }) do
      if err then
        return endpoints.handle_error(err)
      end

      document_object = row
    end

    local route

    if document_object then
      local file = db.files:select_by_path(document_object.path)
      if file then
        local file_meta = file_helpers.parse_content(file)
        if file_meta then
          local headmatter = file_meta.headmatter or {}
          local readable_by = headmatter.readable_by
          if type(readable_by) == "table" and #readable_by > 0 then
            local ws = workspaces.get_workspace()
            if not permissions.can_read(self.developer, ws.name, document_object.path) then
              goto continue
            end
          end

          route = file_meta.route
        end
      end
    end

    local application_service = {
      id = service.id,
      name = v.config.display_name,
      document_route = route,
      app_registration_config = v.config,
      auth_plugin_config = auth_config,
    }

    if instance then
      application_service.instance = instance
    end

    table.insert(application_services, application_service)

    ::continue::
  end

  local res, _, err_t = _M.paginate(self, application_services)
  if not res then
    return endpoints.handle_error(err_t)
  end

  return kong.response.exit(200, res)
end

function _M.get_applications(self, db, helpers, include_instances)
  local post_process_actions = include_instances and function (row)
    if include_instances then
      row.application_instances = setmetatable({}, cjson.empty_array_mt)
      for instance, err in db.application_instances:each_for_application({ id = row.id }) do
        if err then
          return endpoints.handle_error(err)
        end

        if instance then
          table.insert(row.application_instances, instance)
        end
      end
    end
    return row
  end or nil

  local endpoint = _M.page_by_foreign_key_endpoint(
    db.applications.schema,
    db.developers.schema,
    "developer"
  )

  return endpoint(self, db, helpers, self.developer.id, post_process_actions)
end

function _M.page_by_foreign_key_endpoint(schema, foreign_schema, foreign_field_name)
  return function (self, db, helpers, foreign_key, post_process)
    local rows = setmetatable({}, cjson.empty_array_mt)
    local search_fields = _M.get_search_fields(self.req, schema)

    local dao = db[schema.name]

    self.params[foreign_schema.name] =  { id = foreign_key }

    for row, err in dao["each_for_" .. foreign_field_name](dao, { id = self.developer.id }) do
      if err then
        return endpoints.handle_error(err)
      end
      if _M.row_matches_search_fields(row, search_fields) then
        local p_row = type(post_process) == "function" and post_process(row) or row
        table.insert(rows, p_row)
      end
    end

    local res, _, err_t = _M.paginate(self, rows)
    if not res then
      return endpoints.handle_error(err_t)
    end
    return kong.response.exit(200, res)
  end
end

function _M.get_search_fields(req, schema)
  local args = arguments.load({
    schema  = schema,
    request = req,
  })

  local search_fields = {}
  for k, v in pairs(args.uri) do
    if type(k) ~= "string" then
      goto continue
    end

    v = type(v) == "table" and v[1] or v

    -- date range params will come in as, e.g., created_at_from / created_at_to
    for _, suffix in ipairs({"_from", "_to"}) do
      if string.sub(k, #k - #suffix + 1, #k) == suffix then
        local field_name = string.sub(k, 1, #k - #suffix)
        local field = schema.fields[field_name]
        if field and field.type and field.type == "integer" and field.timestamp then
          search_fields[k] = { field = field, value = v, suffix = suffix, name = field_name }
          goto continue
        end
      end
    end

    local field = schema.fields[k]
    if field and field.type then
        search_fields[k] = { field = field, value = v }
    end

    ::continue::
  end

  return search_fields
end

function _M.contains_substring(target, value)
  if type(target) ~= "string" or type(value) ~= "string" then
    return false
  end

  return not not string.find(
    string.lower(target),
    string.lower(value),
    1, true
  )
end

function _M.row_matches_search_fields(row, search_fields)
  if not search_fields then
    return true
  end

  -- simulates ANDing all the filters together (if 1 fails they all fail)
  for k, search in pairs(search_fields) do
    if search.field.type == "string" or search.field.type == "foreign" then
      if not _M.contains_substring(row[k], search.value) then
        return false
      end
    elseif search.field.type == 'integer' and
      search.field.timestamp and search.suffix and search.name then

      local valid = string.find(search.value, "^%d%d%d%d%-%d%d%-%d%d$")
      if not valid then
        return false
      end

      local row_date = os.date("!%Y-%m-%d", row[search.name])

      if search.suffix == "_from" and row_date < search.value then
        return false
      elseif search.suffix == "_to" and row_date > search.value then
        return false
      end
    end
  end

  return true
end


return _M
