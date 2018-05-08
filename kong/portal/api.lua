local responses   = require "kong.tools.responses"
local singletons  = require "kong.singletons"
local app_helpers = require "lapis.application"
local crud        = require "kong.api.crud_helpers"
local enums       = require "kong.portal.enums"
local utils       = require "kong.portal.utils"
local constants   = require "kong.constants"


local plugin_route_dao_dict = {
  ["basic-auth"] = "basicauth_credentials",
  ["acls"] = "acls",
  ["oauth2"] = "oauth2_credentials",
  ["hmac-auth"] = "hmacauth_credentials",
  ["jwt"] = "jwt_secrets",
  ["key-auth"] = "keyauth_credentials",
}


return {
  ["/files"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]
      local portal_auth = singletons.configuration.portal_auth

      if portal_auth and not consumer_id then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      if portal_auth then
        self.params.email_or_id = consumer_id
        crud.find_consumer_by_email_or_id(self, dao_factory, helpers)

        if self.consumer
           and self.consumer.status ~= enums.CONSUMERS.STATUS.APPROVED then
          local status = self.consumer.status
          local label = enums.get_key_from_value(enums.CONSUMERS.STATUS, status)
          return helpers.responses.send_HTTP_UNAUTHORIZED({
              ["status"] = status,
              ["label"]  = label
            })
        end
      end
    end,

    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.portal_files)
    end,
  },

  ["/files/unauthenticated"] = {
    -- List all unauthenticated files stored in the portal file system
    GET = function(self, dao_factory, helpers)
      self.params = {
        auth = false
      }

      crud.paginated_set(self, dao_factory.portal_files)
    end,
  },

  ["/files/*"] = {
    before = function(self, dao_factory, helpers)
      local dao = dao_factory.portal_files
      local identifier = self.params.splat

      -- Find a file by id or field "name"
      local rows, err = crud.find_by_id_or_field(dao, {}, identifier, "name")
      if err then
        return helpers.yield_error(err)
      end

      -- Since we know both the name and id of portal_files are unique
      self.params.file_name_or_id = nil
      self.portal_file = rows[1]
      if not self.portal_file then
        return helpers.responses.send_HTTP_NOT_FOUND(
          "No file found by name or id '" .. identifier .. "'"
        )
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.portal_file)
    end,
  },

  ["/portal/register"] = {
    before = function(self, dao_factory, helpers)
      self.portal_auth = singletons.configuration.portal_auth
      self.auto_approve = singletons.configuration.portal_auto_approve
    end,

    POST = function(self, dao_factory, helpers)
      if utils.validate_email(self.params.email) == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("Invalid email")
      end

      self.params.type = enums.CONSUMERS.TYPE.DEVELOPER
      self.params.status = enums.CONSUMERS.STATUS.PENDING
      self.params.username = self.params.email

      if self.auto_approve then
        self.params.status = enums.CONSUMERS.STATUS.APPROVED
      end

      local password = self.params.password
      self.params.password = nil

      local consumer, err = dao_factory.consumers:insert(self.params)
      if err then
        return app_helpers.yield_error(err)
      end

      -- omit credential post for oidc
      if self.portal_auth == 'openid-connect' then
        return responses.send_HTTP_CREATED({
          consumer = consumer,
          credential = {}
        })
      end

      local collection = dao_factory[plugin_route_dao_dict[self.portal_auth]]
      local credential_data

      if self.portal_auth == "basic-auth" then
        credential_data = {
          consumer_id = consumer.id,
          username = self.params.username,
          password = password,
        }
      end

      if self.portal_auth == "key-auth" then
        credential_data = {
          consumer_id = consumer.id,
          key = self.params.key
        }
      end

      if credential_data == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
          "Cannot create credential with portal_auth = " ..
            self.portal_auth)
      end

      crud.post(credential_data, collection, function(credential)
          crud.portal_crud.insert_credential(credential,
                                            self.portal_auth,
                                            enums.CONSUMERS.TYPE.DEVELOPER)
          return {
            credential = credential,
            consumer = consumer,
          }
        end)
    end,
  },

  ["/config"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]

      if singletons.configuration.portal_auth and not consumer_id then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      self.params.email_or_id = consumer_id
      crud.find_consumer_by_email_or_id(self, dao_factory, helpers)

      if self.consumer
         and self.consumer.status ~= enums.CONSUMERS.STATUS.APPROVED then
        return helpers.responses.send_HTTP_UNAUTHORIZED(
          "Developer " .. consumer_id .. " not approved"
        )
      end
    end,

    GET = function(self, dao_factory, helpers)
      local distinct_plugins = {}

      do
        local rows, err = dao_factory.plugins:find_all()
        if err then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end

        local map = {}
        for _, row in ipairs(rows) do
          if not map[row.name] then
            distinct_plugins[#distinct_plugins+1] = row.name
          end
          map[row.name] = true
        end

        singletons.internal_proxies:add_internal_plugins(distinct_plugins, map)
      end

      self.config = {
        plugins = {
          enabled_in_cluster = distinct_plugins,
        }
      }

      return helpers.responses.send_HTTP_OK(self.config)
    end,
  },

  ["/developer"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]

      if singletons.configuration.portal_auth and not consumer_id then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      self.params.email_or_id = consumer_id
      crud.find_consumer_by_email_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end,
  },

  ["/credentials"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]

      if singletons.configuration.portal_auth and not consumer_id then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      self.portal_auth = singletons.configuration.portal_auth
      self.collection = dao_factory[plugin_route_dao_dict[self.portal_auth]]

      self.params.consumer_id = consumer_id
      self.params.email_or_id = self.params.consumer_id

      crud.find_consumer_by_email_or_id(self, dao_factory, helpers)

      if not self.consumer.status == enums.CONSUMERS.STATUS.APPROVED then
        return helpers.responses.send_HTTP_UNAUTHORIZED(
          "Developer " .. consumer_id .. " not approved"
        )
      end
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.id == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                                  "credential id is required")
      end

      crud.patch(self.params, self.collection, {
        id = self.params.id
      })
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, self.collection, function(credential)
        crud.portal_crud.insert_credential(credential, self.portal_auth)
      end)
    end,
  },

  ["/credentials/:plugin"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]

      if singletons.configuration.portal_auth and not consumer_id then
        helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      self.plugin = ngx.unescape_uri(self.params.plugin)
      self.collection = dao_factory[plugin_route_dao_dict[self.plugin]]

      self.params.plugin = nil
      self.params.consumer_id = consumer_id
      self.params.email_or_id = consumer_id

      crud.find_consumer_by_email_or_id(self, dao_factory, helpers)

      if not self.consumer.status == enums.CONSUMERS.STATUS.APPROVED then
        return helpers.responses.send_HTTP_UNAUTHORIZED(
          "Developer " .. consumer_id .. " not approved"
        )
      end
    end,

    GET = function(self, dao_factory, helpers)
      self.params.consumer_type = enums.CONSUMERS.TYPE.PROXY
      self.params.plugin = self.plugin
      crud.paginated_set(self, dao_factory.credentials)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, self.collection, function(credential)
        crud.portal_crud.insert_credential(credential, self.plugin)
      end)
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.id == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                                  "credential id is required")
      end

      crud.patch(self.params, self.collection, { id = self.params.id },
        function(credential)
          crud.portal_crud.update_credential(credential)
      end)
    end,
  },

  ["/credentials/:plugin/:credential_id"] = {
    before = function(self, dao_factory, helpers)
      local consumer_id = ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]

      if singletons.configuration.portal_auth and not consumer_id then
        helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      self.plugin = ngx.unescape_uri(self.params.plugin)
      self.collection = dao_factory[plugin_route_dao_dict[self.plugin]]

      self.params.consumer_id = consumer_id
      self.params.email_or_id = self.params.consumer_id
      self.params.plugin = nil

      crud.find_consumer_by_email_or_id(self, dao_factory, helpers)

      if not self.consumer.status == enums.CONSUMERS.STATUS.APPROVED then
        return helpers.responses.send_HTTP_UNAUTHORIZED(
          "Developer " .. consumer_id .. " not approved"
        )
      end

      local credentials, err = self.collection:find_all({
        consumer_id = consumer_id,
        id = self.params.credential_id
      })

      if err then
        return app_helpers.yield_error(err)
      end

      if next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.credential_id = nil
      self.credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, self.collection, self.credential, function(credential)
        crud.portal_crud.update_credential(credential)
      end)
    end,

    DELETE = function(self, dao_factory)
      crud.portal_crud.delete_credential(self.credential.id)
      crud.delete(self.credential, self.collection)
    end,
  },
}
