local cjson      = require "cjson.safe"
local constants  = require "kong.constants"
local Errors     = require "kong.db.errors"
local singletons = require "kong.singletons"
local auth       = require "kong.portal.auth"
local utils      = require "kong.tools.utils"
local responses  = require "kong.tools.responses"
local workspaces = require "kong.workspaces"
local enums      = require "kong.enterprise_edition.dao.enums"
local enterprise_utils = require "kong.enterprise_edition.utils"

local log = ngx.log
local ERR = ngx.ERR
local _log_prefix = "[developers] "
local helpers = { responses = responses }
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


local function set_portal_auth_conf(ws, entity)
  local ws_config = ws.config or {}
  local entity_config = entity.config or {}
  local auth_type = ws_config.portal_auth or entity_config.portal_auth
  local auth_empty = not auth_type or
                        auth_type == ngx.null or
                        auth_type == ""

  if auth_empty and
     entity_config.portal_auth_conf and
     entity_config.portal_auth_conf ~= ngx.null then

    return nil, "'config.portal_auth' must be set in order to configure 'config.portal_auth_type'"
  end

  if auth_type and
     entity_config.portal_auth_conf and
     entity_config.portal_auth_conf ~= ngx.null then

    local entity_auth_conf = entity_config.portal_auth_conf
    local ws_auth_conf = cjson.decode(ws_config.portal_auth_conf)

    if type(entity_auth_conf) ~= "table" then
      return nil, "'config.portal_auth_conf' must be type 'table'"
    end

    local auth_conf = utils.deep_merge(ws_auth_conf or {}, entity_auth_conf)
    local ok, err = singletons.invoke_plugin({
      name = auth_type,
      config = auth_conf,
      phases = { "access" },
      api_type = "portal",
      db = kong.db,
      validate_only = true,
    })

    if not ok then
      return nil, err
    end

    entity.config.portal_auth_conf = cjson.encode(auth_conf)
  end

  return entity
end


local function create_developer(self, entity, options)
  -- TODO: validate meta information

  -- local meta, err = cjson.decode(entity.meta)
  -- if err then
  --   return nil, nil, "cannot parse json"
  -- end

  -- local full_name = meta.full_name
  -- if not full_name or full_name == "" then
  --   local err_t = "meta param missing key: 'full_name'"
  --   return nil, nil, err_t
  -- end

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
  -- check if email is being updated
  if entity.email and entity.email ~= developer.email then
    local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}

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
}
