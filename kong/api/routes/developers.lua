local constants    = require "kong.constants"
local utils        = require "kong.tools.utils"
local endpoints    = require "kong.api.endpoints"
local workspaces   = require "kong.workspaces"
local portal_smtp_client = require "kong.portal.emails"
local crud_helpers = require "kong.portal.crud_helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local cjson = require "cjson"

local kong = kong

local unescape_uri = ngx.unescape_uri
local ws_constants = constants.WORKSPACE_CONFIG

local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}

local function validate_credential_plugin(self, db, helpers)
  local plugin_name = ngx.unescape_uri(self.params.plugin)

  self.credential_plugin = auth_plugins[plugin_name]
  if not self.credential_plugin then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.credential_collection = db.daos[self.credential_plugin.dao]
end


local function find_developer(db, developer_pk)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:select({ id = developer_pk })
  end

  return db.developers:select_by_email(developer_pk)
end


local function update_developer(db, developer_pk, params)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:update({ id = developer_pk }, params)
  end

  return db.developers:update_by_email(developer_pk, params)
end


local function get_developer_status()
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local auto_approve = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTO_APPROVE, workspace)

  if auto_approve then
    return enums.CONSUMERS.STATUS.APPROVED
  end

  return enums.CONSUMERS.STATUS.PENDING
end


return {
  ["/developers"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers, parent)
      local size = self.params.size or 100
      local offset = self.params.offset

      self.params.offset = nil
      self.params.size = nil
      self.params.status = tonumber(self.params.status)

      local developers, err, err_t = db.developers:select_all(self.params)
      if err then
        return endpoints.handle_error(err_t)
      end

      local paginated_results, _, err_t = crud_helpers.paginate(
        self, '/developers', developers, size, offset
      )

      if not paginated_results then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, paginated_results)
    end,

    POST = function(self, db, helpers)
      if not self.params.status then
        self.params.status = get_developer_status()
      end

      local developer, _, err_t = db.developers:insert(self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, developer)
    end,
  },

  ["/developers/:developers"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    PATCH = function(self, db, helpers)
      local developer_pk = self.params.developers
      self.params.developers = nil

      -- save previous status
      local developer = find_developer(db, developer_pk)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local previous_status = developer.status

      local developer, _, err_t = update_developer(db, developer_pk, self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      local res = { developer = developer }
      if developer.status == enums.CONSUMERS.STATUS.APPROVED and
         developer.status ~= previous_status and
         previous_status ~= enums.CONSUMERS.STATUS.REVOKED then

        local portal_emails = portal_smtp_client.new()
        local email_res, err = portal_emails:approved(developer.email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end

        res.email = email_res
      end

      return kong.response.exit(200, res)
    end,
  },


  ["/developers/:email_or_id/plugins/"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local consumer = developer.consumer
      local plugins = setmetatable({}, cjson.empty_array_mt)

      for row, err in db.plugins:each_for_consumer({id = consumer.id}) do
        if err then
          return endpoints.handle_error(err)
        end

        table.insert(plugins, row)
      end

      return kong.response.exit(200, plugins)
    end,

    POST = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.params.email_or_id = nil
      self.params.consumer = developer.consumer

      local ok, _, err_t = db.plugins:insert(self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(201, ok)
    end,
  },

  ["/developers/:email_or_id/plugins/:id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local consumer = developer.consumer
      local plugin, err, err_t = db.plugins:select({id = self.params.id})
      if err then
        return endpoints.handle_error(err_t)
      end

      if not plugin or plugin.consumer and plugin.consumer.id ~= consumer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200, plugin)
    end,

    PATCH = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.params.email_or_id = nil

      local consumer = developer.consumer
      local plugin, err, err_t = db.plugins:select({id = self.params.id})
      if err then
        return endpoints.handle_error(err_t)
      end

      if not plugin or plugin.consumer and plugin.consumer.id ~= consumer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.params.id = nil

      local ok, _, err_t = db.plugins:update({ id = plugin.id }, self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, ok)
    end,

    DELETE = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local consumer = developer.consumer
      local plugin, err, err_t = db.plugins:select({id = self.params.id})
      if err then
        return endpoints.handle_error(err_t)
      end

      if not plugin or plugin.consumer and plugin.consumer.id ~= consumer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.params.id = nil

      local ok, _, err_t = db.plugins:delete({ id = plugin.id })
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end
  },

  ["/developers/:developers/credentials/:plugin"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      validate_credential_plugin(self, db, helpers)

      local developer_pk = self.params.developers
      local developer = find_developer(db, developer_pk)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.developer = developer
      self.params.developers = nil
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_credential(self, db, helpers)
    end,
  },

  ["/developers/:developers/credentials/:plugin/:credential_id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      validate_credential_plugin(self, db, helpers)

      local developer_pk = self.params.developers
      local developer = find_developer(db, developer_pk)
      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.developer = developer
      self.params.developers = nil
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_credential(self, db, helpers)
    end,

    PATCH = function(self, db, helpers)
      return crud_helpers.update_credential(self, db, helpers)
    end,

    DELETE = function(self, db, helpers)
      return crud_helpers.delete_credential(self, db, helpers)
    end,
  },

  ["/developers/invite"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    POST = function(self, db, helpers)
      if not self.params.emails or next(self.params.emails) == nil then
        return kong.response.exit(400, { message = "emails param required" })
      end
      local portal_emails = portal_smtp_client.new()
      local res, err = portal_emails:invite(self.params.emails)
      if err then
        if err.code then
          return kong.response.exit(err.code, { message = err.message })
        end

        return endpoints.handle_error(err)
      end

      return kong.response.exit(200, res)
    end
  },
}
