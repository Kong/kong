local cjson      = require "cjson.safe"
local constants  = require "kong.constants"
local Errors     = require "kong.db.errors"
local Schema     = require "kong.db.schema"
local singletons = require "kong.singletons"
local auth       = require "kong.portal.auth"
local workspaces = require "kong.workspaces"
local enums      = require "kong.enterprise_edition.dao.enums"

local enterprise_utils = require "kong.enterprise_edition.utils"
local MetaSchema   = require "kong.db.schema.metaschema"
local log = ngx.log
local ERR = ngx.ERR
local null = ngx.null
local _log_prefix = "[developers] "
local helpers = {} -- XXX EE remove this
local ws_constants = constants.WORKSPACE_CONFIG

local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", },
  ["acls"] =       { name = "acl",        dao = "acls" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials" },
}


local function rollback_on_create(entities)
  local _, err

  if entities.consumer then
    _, err = singletons.db.consumers:delete({ id = entities.consumer.id })
    if err then
      log(ERR, _log_prefix, err)
    end
  end
end


local function build_cred_plugin_data(self, entity, consumer)
  local data

  if self.portal_auth == "basic-auth" then
    data = {
      consumer = consumer,
      username = entity.email,
      password = self.password,
    }
  end

  if self.portal_auth == "key-auth" then
    data = {
      consumer = consumer,
      key = self.key,
    }
  end

  return data
end


local function build_cred_data(self, plugin_cred, consumer)
  return {
    id = plugin_cred.id,
    consumer = { id = consumer.id },
    consumer_type = enums.CONSUMERS.TYPE.DEVELOPER,
    plugin = self.portal_auth,
    credential_data = tostring(cjson.encode(plugin_cred)),
  }
end


local function build_developer_data(entity, consumer)
  local data = entity

  data.password = nil
  data.key = nil
  data.consumer = { id = consumer.id }

  return data
end


local function create_consumer(entity)
  return singletons.db.consumers:insert({
    username = entity.email,
    type = enums.CONSUMERS.TYPE.DEVELOPER,
  })
end


local function build_temp_record (input_fields)
  if type(input_fields) ~= "table" then
    return nil, 'config.portal_developer_meta_fields must be arrays'
  end

  local fields = {}
  for _, v in ipairs(input_fields) do
    if not v.title or type(v.title) ~= "string" then
      return nil, 'portal_developer_meta_fields titles are required and must be strings'
    end

    if not v.validator or type(v.validator) ~= "table" or not v.validator.type then
      return nil, 'portal_developer_meta_fields validator is required'
    end

    table.insert(fields, { [v.title] = v.validator })
  end

  return {
    type = "record",
    fields = fields,
  }
end


local function validate_developer_meta_fields(input_fields)
  input_fields = cjson.decode(input_fields)
  if input_fields == nil then
    return nil, 'error decoding developer meta fields'
  end

  local schema, err = build_temp_record(input_fields)
  if not schema then
    return nil, err
  end

  local temp = {
    name          = "temp developer meta fields",
    primary_key   = { "name" },
    fields = {{ meta_field = schema }},
  }

  local ok, err_t = MetaSchema:validate(temp)
  if not ok then
    return nil, err_t
  end

  return ok
end


local function set_portal_developer_meta_fields(ws, entity_config)
  if entity_config.portal_developer_meta_fields and
     entity_config.portal_developer_meta_fields ~= null then
    local meta_fields = entity_config.portal_developer_meta_fields
    local ok, err = validate_developer_meta_fields(meta_fields)
    if not ok then
      return nil, err
    end

    entity_config.portal_developer_meta_fields = meta_fields
  end

  return true
end


local function validate_incoming_developer_meta(ws, entity)
  local ws_config = ws.config or {}
  if ws_config.portal_developer_meta_fields and
     ws_config.portal_developer_meta_fields ~= null then

    -- build temp schema to validate developer meta
    -- against developer meta fields(json)
    local meta_fields = cjson.decode(ws_config.portal_developer_meta_fields)
    local temp_schema = build_temp_record(meta_fields)

    local meta_fields_schema, err = Schema.new(temp_schema)
    if not meta_fields_schema then
      return nil, err
    end

    local meta = cjson.decode(entity.meta)
    if not meta then
      meta = {}
    end

    -- we need to strip empty strings for valiidation
    for k, v in pairs(meta) do
      if v == "" then
        meta[k] = nil
      end
    end

    for _, v in ipairs(meta_fields) do
      -- frontend send will always send us numbers, so if a field is a number
      -- convert it to a number for validation
      if v.validator.type == "number" and meta[v.title] ~= nil then
        -- tonumber will return nil if argument will not convert to number
        -- however because this is being saved to a table,
        -- if the field is optional the validator will approve this
        -- to prevent this we only save the result if it is not nil
        local meta_number = tonumber(meta[v.title])
        if meta_number ~= nil then
          meta[v.title] = meta_number
        end
      end
      -- validate email
      if v.is_email and meta[v.title] then
        local ok, err = enterprise_utils.validate_email(meta[v.title])
        if not ok then
          return nil, meta[v.title] .. " is not a valid email " .. err
        end
      end
    end

    local ok, err = meta_fields_schema:validate_field(meta_fields_schema, meta)

    if not ok then
      return nil, err
    end

  elseif entity.meta then
    return nil, "'config.portal_extra_fields' must be set to validate developer meta"
  end

  return entity
end


-- For a given conf key and value, returns the required value for validation
-- * if value is ngx.null, meaning "set to default", returns value from kong.conf
-- * if value is nil, meaning it was not sent in the req, returns result of retrieve_ws_config
-- * if type is invalid, returns err
-- * if encode flag and type is table, will re assign and return encoded value
-- * otherwise, value will pass through
local function get_conf_value(key, entity_config, req_type, ws, encode)
  local value = entity_config[key]
  if value == null then
    -- incoming_value sent as null, return default from kong.conf
    return kong.configuration[key]
  elseif value == nil then
     -- return with either ws or kong.conf
    return workspaces.retrieve_ws_config(key, ws)
  elseif type(value) ~= req_type then
    return nil, "'config." .. key .. "' must be type '" .. req_type .. "'"
  elseif encode and type(value) == "table" then
    local encoded, err = cjson.encode(value)
    if err then
      return nil, err
    end

    entity_config[key] = encoded
  end

  return value
end


local function set_portal_auth_conf(ws, entity_config, portal_auth)
  local key = ws_constants.PORTAL_AUTH_CONF
  local req_type = "table"
  local encode = true

  local portal_auth_conf, err = get_conf_value(key, entity_config, req_type, ws, encode)
  if err then
    return nil, err
  end

  -- we have no auth type, return early
  -- cannot validate auth conf, but still allow it to be saved
  if portal_auth == nil or portal_auth == "" then
    return true
  end

  -- validate auth type and conf via invoke_plugin with `validate_only` flag
  return singletons.invoke_plugin({
    name = portal_auth,
    config = portal_auth_conf,
    phases = { "access" },
    api_type = "portal",
    db = kong.db,
    validate_only = true,
  })
end


local function set_portal_session_conf(ws, entity_config, portal_auth)
  local incoming_session_conf = entity_config.portal_session_conf
  if type(incoming_session_conf) == "table" and type(incoming_session_conf.secret) ~= "string" then
    return nil, "'config.portal_session_conf.secret' must be type 'string'"
  end

  local key = ws_constants.PORTAL_SESSION_CONF
  local req_type = "table"
  local encode = true

  local portal_session_conf, err = get_conf_value(key, entity_config, req_type, ws, encode)
  if err then
    return nil, err
  end

  local requires_session_conf = portal_auth ~= nil and
                                portal_auth ~= "" and
                                portal_auth ~= "openid-connect"

  if requires_session_conf and portal_session_conf == nil or portal_session_conf == "" then
    return nil, "'portal_session_conf' is required when 'portal_auth' is set to " .. portal_auth
  end

  -- validate portal_session_conf via invoke_plugin with `validate_only` flag
  return singletons.invoke_plugin({
    name = "session",
    config = portal_session_conf,
    phases = { "access" },
    api_type = "portal",
    db = kong.db,
    validate_only = true,
  })
end


local function set_portal_conf(ws, entity)
  local entity_config = entity.config
  if entity_config == nil then
    return entity
  end

  if type(entity_config) ~= "table" then
    return nil, "'config' must be type 'table'"
  end

  local key = ws_constants.PORTAL_AUTH
  local req_type = "string"

  local portal_auth, err = get_conf_value(key, entity_config, req_type, ws)
  if err then
    return nil, err
  end

  local ok, err = set_portal_auth_conf(ws, entity_config, portal_auth)
  if not ok then
    return nil, err
  end

  local ok, err = set_portal_session_conf(ws, entity_config, portal_auth)
  if not ok then
    return nil, err
  end

  local ok, err = set_portal_developer_meta_fields(ws, entity_config)
  if not ok then
    return nil, err
  end

  return entity
end


local function create_developer(self, entity, options)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}

  if entity.email then
    -- validate email
    local ok, err = enterprise_utils.validate_email(entity.email)
    if not ok then
      local code = Errors.codes.SCHEMA_VIOLATION
      local err_t = { code = code, fields = { email = err, }, }
      return nil, err, err_t
    end
  end

  -- validate develoer meta field against portal extra fields
  local ok, err = validate_incoming_developer_meta(workspace, entity)
  if not ok then
   local code = Errors.codes.SCHEMA_VIOLATION
   local err_t = { code = code, fields = { meta = err,}, }
   local err = "developer update: error in validating developer meta fields "
   return nil, err, err_t
  end

  -- create developers consumer
  local consumer = create_consumer(entity)
  if not consumer then
    local code = Errors.codes.UNIQUE_VIOLATION
    local err = "developer insert: could not create consumer mapping for " .. entity.email
    local err_t = { code = code, fields = { email = "developer already exists with email: " .. entity.email }, }
    return nil, err, err_t
  end

  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal_auth = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)

  if portal_auth ~= "openid-connect" then
    -- validate auth plugin
    local collection = auth.validate_auth_plugin(self, self.db, helpers, portal_auth)
    if not collection then
      rollback_on_create({ consumer = consumer })
      local err = "developer insert: could not create developer, invalid portal_auth plugin set"
      local err_t = { code = Errors.codes.DATABASE_ERROR }
      return nil, err, err_t
    end

    -- generate credential data
    local credential_plugin_data = build_cred_plugin_data(self, entity, consumer)
    if credential_plugin_data == nil then
      rollback_on_create({ consumer = consumer })
      local err = "developer insert: could not set credential plugin data for " .. entity.email
      local err_t = { code = Errors.codes.DATABASE_ERROR }
      return nil, err, err_t
    end

    -- create plugin credential
    local plugin_cred = collection:insert(credential_plugin_data)
    if not plugin_cred then
      rollback_on_create({ consumer = consumer })
      local err = "developer insert: could not create plugin credential for " .. entity.email
      local err_t = { code = Errors.codes.DATABASE_ERROR }
      return nil, err, err_t
    end

    -- create credential reference
    local cred_data = build_cred_data(self, plugin_cred, consumer)
    local cred = self.db.credentials:insert(cred_data)
    if not cred then
      rollback_on_create({ consumer = consumer })
      local err = "developer insert: could not create credential for " .. entity.email
      local err_t = { code = Errors.codes.DATABASE_ERROR }
      return nil, err, err_t
    end
  end

  -- create developer
  local developer_data = build_developer_data(entity, consumer)
  local developer, err, err_t = self.super.insert(self, developer_data, options)
  if not developer then
    rollback_on_create({ consumer = consumer })
    local err = "developer insert: could not create developer " .. entity.email
    local err_t = { code = Errors.codes.DATABASE_ERROR }
    return nil, err, err_t
  end

  return developer, err, err_t
end


local function update_developer(self, developer, entity, options)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  -- validate developer meta field against portal extra fields
  if entity.meta then
    local ok, err = validate_incoming_developer_meta(workspace, entity)
    if not ok then
      local code = Errors.codes.SCHEMA_VIOLATION
      local err_t = { code = code, fields = { meta = err,}, }
      local err = "developer update: error in validating developer meta fields "
      return nil, err, err_t
    end
  end

  -- check if email is being updated
  if entity.email and entity.email ~= developer.email then

    -- validate email
    local ok, err = enterprise_utils.validate_email(entity.email)
    if not ok then
      local code = Errors.codes.SCHEMA_VIOLATION
      local err_t = { code = code, fields = { email = err, }, }
      local err = "developer update: " .. err
      return nil, err, err_t
    end

    -- retrieve portal auth plugin type
    self.portal_auth = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
    if not self.portal_auth or self.portal_auth == "" then
      local code = Errors.codes.DATABASE_ERROR
      local err = "developer update: portal auth must be turned on to update developer fields"
      local err_t = { code = code }
      return nil, err, err_t
    end

    if self.portal_auth ~= "openid-connect" then
      -- retrieve auth plugin
      local plugin = auth_plugins[self.portal_auth]
      if not plugin then
        local code = Errors.codes.DATABASE_ERROR
        local err = "developer update: invalid authentication applied to portal in workspace" .. workspace.name
        local err_t = { code = code }
        return nil, err, err_t
      end

      -- find developers consumer
      local consumer = self.db.consumers:select({ id = developer.consumer.id })
      if not consumer then
        local code = Errors.codes.DATABASE_ERROR
        local err = "developer update: could not find consumer mapping for " .. developer.email
        local err_t = { code = code }
        return nil, err, err_t
      end

      -- update consumer username
      -- XXX DEVX: look into expanding this error state to include more generic 500 error
      local ok = self.db.consumers:update(
        { id = consumer.id },
        { username = entity.email }
      )
      if not ok then
        local code = Errors.codes.UNIQUE_VIOLATION
        local err = "developer update: could not update consumer mapping for " .. developer.email
        local err_t = { code = code, fields = { ["email"] = "already exists with value '" .. entity.email .. "'" }, }
        return nil, err, err_t
      end

      -- find all consumers credentails
      local credential
      for row, err in self.db.credentials:each_for_consumer({ id = consumer.id }) do
        if err then
          local code = Errors.codes.DATABASE_ERROR
          local err = "developer update: could not find login credentials for " .. developer.email
          local err_t = { code = code }
          return nil, err, err_t
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER and
          row.plugin == self.portal_auth then
          credential = row
        end
      end

      if not credential then
        local code = Errors.codes.DATABASE_ERROR
        local err = "developer update: primary login credentials not found for " .. developer.email
        local err_t = { code = code }
        return nil, err, err_t
      end

      -- update plugin credential
      local collection = auth.validate_auth_plugin(self, self.db, helpers)
      local credential, _, _ = collection:update(
        { id = credential.id },
        { username = entity.email }
      )

      -- if credential update successful, update credential reference
      if credential then

        local ok = self.db.credentials:update(
          { id = credential.id },
          { credential_data = cjson.encode(credential), },
          { skip_rbac = true }
        )

        if not ok then
          local code = Errors.codes.DATABASE_ERROR
          local err = "developer update: " .. "could not update login credential for: " .. developer.email
          local err_t = { code = code }
          return nil, err, err_t
        end
      end
    end
  end

  return self.super.update(self, { id = developer.id }, entity, options)
end


return {
  create_developer = create_developer,
  update_developer = update_developer,
  set_portal_auth_conf = set_portal_auth_conf,
  set_portal_developer_meta_fields = set_portal_developer_meta_fields,
  set_portal_session_conf = set_portal_session_conf,
  set_portal_conf = set_portal_conf,
}
