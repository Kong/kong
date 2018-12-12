local crud          = require "kong.api.crud_helpers"
local ee_crud       = require "kong.enterprise_edition.crud_helpers"
local enums         = require "kong.enterprise_edition.dao.enums"
local enterprise_utils = require "kong.enterprise_edition.utils"
local constants     = require "kong.constants"
local ws_helper     = require "kong.workspaces.helper"
local portal_smtp_client = require "kong.portal.emails"

local ws_constants  = constants.WORKSPACE_CONFIG

--- Allowed auth plugins
-- Table containing allowed auth plugins that the developer portal api
-- can create credentials for.
--
--["<route>"]:     {  name = "<name>",    dao = "<dao_collection>" }
local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", },
  ["acls"] =       { name = "acl",        dao = "acls" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials" },
}


local function check_portal_status(helpers)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal = ws_helper.retrieve_ws_config(ws_constants.PORTAL, workspace)
  if not portal then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end


local function find_developer(self, dao_factory, helpers)
  self.params.email_or_id = ngx.unescape_uri(self.params.email_or_id)
  if self.params.status then
    self.params.status = tonumber(self.params.status)
  end
  ee_crud.find_developer_by_email_or_id(self, dao_factory, helpers)
end


return {
  ["/files"] = {
    before = function(self, dao_factory, helpers)
      check_portal_status(helpers)
    end,

    -- List all files stored in the portal file system
    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.files)
    end,

    -- Create or Update a file in the portal file system
    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.files)
    end
  },

  ["/files/*"] = {
    -- Process request prior to handling the method
    before = function(self, dao_factory, helpers)
      local dao = dao_factory.files
      local identifier = self.params.splat

      -- Find a file by id or field "name"
      local rows, err = crud.find_by_id_or_field(dao, {}, identifier, "name")
      if err then
        return helpers.yield_error(err)
      end

      -- Since we know both the name and id of files are unique
      self.portal_file = rows[1]
      if not self.portal_file then
        return helpers.responses.send_HTTP_NOT_FOUND(
          "No file found by name or id '" .. identifier .. "'"
        )
      end
    end,

    -- Retrieve an individual file from the portal file system
    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.portal_file)
    end,

    PATCH = function(self, dao_factory)
      self.params.splat = nil
      crud.patch(self.params, dao_factory.files, self.portal_file)
    end,

    -- Delete a file in the portal file system that has
    -- been created outside of migrations
    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.portal_file, dao_factory.files)
    end
  },

  ["/portal/developers"] = {
    before = function(self, dao_factory, helpers)
      check_portal_status(helpers)
      -- you can only manage developers through this endpoint
      if self.params.type and tostring(self.params.type) ~= tostring(enums.CONSUMERS.TYPE.DEVELOPER) then
        helpers.responses.send_HTTP_BAD_REQUEST("type is invalid")
      end
    end,

    GET = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.DEVELOPER
      self.params.status = tonumber(self.params.status)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    POST = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.DEVELOPER
      self.params.status = tonumber(self.params.status)
      crud.post(self.params, dao_factory.consumers)
    end
  },

  ["/portal/developers/:email_or_id"] = {
    before = function(self, dao_factory, helpers)
      check_portal_status(helpers)
      -- you can only manage developers through this endpoint
      if self.params.type and tostring(self.params.type) ~= tostring(enums.CONSUMERS.TYPE.DEVELOPER) then
        helpers.responses.send_HTTP_BAD_REQUEST("type is invalid")
      end
    end,

    GET = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      -- If email is being updated, we need to sync it with the username
      -- and update the login credential
      if self.params.email then
        self.params.username = self.params.email

        local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}

        self.portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
        if not self.portal_auth or self.portal_auth == "" then
          return helpers.responses.send_HTTP_BAD_REQUEST("portal_auth must be enabled to change a developer's email")
        end

        local plugin = auth_plugins[self.portal_auth]
        if not plugin then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end

        self.collection = dao_factory[plugin.dao]

        local credentials, err = dao_factory.credentials:find_all({
          consumer_id = self.consumer.id,
          consumer_type = enums.CONSUMERS.TYPE.DEVELOPER,
          plugin = self.portal_auth,
        })

        if err then
          return helpers.yield_error(err)
        end

        if next(credentials) == nil then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end

        self.credential = credentials[1]

        local ok, err = enterprise_utils.validate_email(self.params.email)
        if not ok then
          return helpers.responses.send_HTTP_BAD_REQUEST("Invalid email: " .. err)
        end

        local cred_params = {
          username = self.params.email,
        }

        local filter = {
          consumer_id = self.consumer.id,
          id = self.credential.id,
        }

        local ok, err = crud.portal_crud.update_login_credential(cred_params, self.collection, filter)

        if err then
          return helpers.yield_error(err)
        end

        if not ok then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end
      end

      -- save the previous status to determine if we should send an approval email
      local previous_status = self.consumer.status

      crud.patch(self.params, dao_factory.consumers, self.consumer, function(consumer)
        local res = {consumer = consumer}

        if consumer.status == enums.CONSUMERS.STATUS.APPROVED and
           consumer.status ~= previous_status and previous_status ~= enums.CONSUMERS.STATUS.REVOKED then
          local portal_emails = portal_smtp_client.new()
          local email_res, err = portal_emails:approved(consumer.email)
          if err then
            if err.code then
              return helpers.responses.send(err.code, {message = err.message})
            end

            return helpers.yield_error(err)
          end

          res.email = email_res
        end

        return res
      end)
    end,

    DELETE = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      crud.delete(self.consumer, dao_factory.consumers)
    end
  },

  ["/portal/developers/:email_or_id/plugins/"] = {
    GET = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      crud.paginated_set(self, dao_factory.plugins)
    end,

    POST = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      crud.post(self.params, dao_factory.plugins)
    end,

    PUT = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      crud.put(self.params, dao_factory.plugins)
    end
  },

  ["/portal/developers/:email_or_id/plugins/:id"] = {
    GET = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      crud.find_plugin_by_filter(self, dao_factory, {
        consumer_id = self.consumer.id,
        id          = self.params.id,
      }, helpers)

      return helpers.responses.send_HTTP_OK(self.plugin)
    end,

    PATCH = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      crud.find_plugin_by_filter(self, dao_factory, {
        consumer_id = self.consumer.id,
        id          = self.params.id,
      }, helpers)

      crud.patch(self.params, dao_factory.plugins, self.plugin)
    end,

    DELETE = function(self, dao_factory, helpers)
      find_developer(self, dao_factory, helpers)

      crud.find_plugin_by_filter(self, dao_factory, {
        consumer_id = self.consumer.id,
        id          = self.params.id,
      }, helpers)

      crud.delete(self.plugin, dao_factory.plugins)
    end
  },

  ["/portal/invite"] = {
    before = function(self, dao_factory, helpers)
      check_portal_status(helpers)
    end,

    POST = function(self, dao_factory, helpers)
      if not self.params.emails or next(self.params.emails) == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("emails param required")
      end
      local portal_emails = portal_smtp_client.new()
      local res, err = portal_emails:invite(self.params.emails)
      if err then
        if err.code then
          return helpers.responses.send(err.code, {message = err.message})
        end

        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK(res)
    end
  },
}
