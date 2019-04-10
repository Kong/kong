local singletons    = require "kong.singletons"
local crud          = require "kong.api.crud_helpers"
local ws_helper     = require "kong.workspaces.helper"
local enums         = require "kong.enterprise_edition.dao.enums"
local cjson         = require "cjson.safe"
local ee_api        = require "kong.enterprise_edition.api_helpers"
local constants     = require "kong.constants"
local auth          = require "kong.portal.auth"
local portal_smtp_client = require "kong.portal.emails"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local endpoints = require "kong.api.endpoints"



local kong = kong
local ws_constants = constants.WORKSPACE_CONFIG

--- Allowed auth plugins
-- Table containing allowed auth plugins that the developer portal api
-- can create credentials for.
--
--["<route>"]:     {  name = "<name>",    dao = "<dao_collection>" }
local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}

local function get_developer_status()
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local auto_approve = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTO_APPROVE, workspace)

  if auto_approve then
    return enums.CONSUMERS.STATUS.APPROVED
  end

  return enums.CONSUMERS.STATUS.PENDING
end

local function get_workspace()
  return ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
end


local function count_entities(arr)
  arr = arr or setmetatable({}, cjson.empty_array_mt)
  return {
    total = #arr,
    data = arr
  }
end


local function validate_credential_plugin(self, db, helpers)
  local plugin_name = ngx.unescape_uri(self.params.plugin)

  self.credential_plugin = auth_plugins[plugin_name]
  if not self.credential_plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.credential_collection = db.daos[self.credential_plugin.dao]
end


local function handle_vitals_response(res, err, helpers)
  if err then
    if err:find("Invalid query params", nil, true) then
      return helpers.responses.send_HTTP_BAD_REQUEST(err)
    end

    return helpers.yield_error(err)
  end

  return helpers.responses.send_HTTP_OK(res)
end


return {
  ["/auth"] = {
    GET = function(self, db, helpers)
      auth.login(self, db, helpers)
      return helpers.responses.send_HTTP_OK()
    end,

    DELETE = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/files/unauthenticated"] = {
    -- List all unauthenticated files stored in the portal file system
    GET = function(self, db, helpers)
      local files, err, err_t = db.files:select_all({
        auth = false,
        type = self.params.type,
      }, {
        skip_rbac = true,
      })

      if err then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(count_entities(files))
    end,
  },

  ["/files"] = {
    GET = function(self, db, helpers)
      local files, err, err_t = db.files:select_all({
        type = self.params.type,
      }, {
        skip_rbac = true ,
      })

      if err then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(count_entities(files))
    end,
  },

  ["/files/*"] = {
    GET = function(self, db, helpers)
      local identifier = self.params.splat

      local file, err, err_t = db.files:select_by_name(identifier, { skip_rbac = true })
      if err then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK({data = file})
    end,
  },

  ["/register"] = {
    POST = function(self, db, helpers)
      self.params.status = get_developer_status()

      local developer, _, err_t = db.developers:insert(self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      local res = {
        developer = developer,
      }

      if developer.status == enums.CONSUMERS.STATUS.PENDING then
        local portal_emails = portal_smtp_client.new()
        local email, err = portal_emails:access_request(developer.email,
                                                      developer.meta.full_name)
        if err then
          if err.code then
            return helpers.responses.send(err.code, { message = err.message })
          end

          return helpers.yield_error(err)
        end

        res.email = email
      end

      return helpers.responses.send_HTTP_OK(res)
    end,
  },

  ["/validate-reset"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)
      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/reset-password"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)

      -- If we made it this far, the jwt is valid format and properly signed.
      -- Now we will lookup the consumer and credentials we need to update
      -- Lookup consumer by id contained in jwt, if not found, this will 404
      local consumer, _, err_t = db.consumers:select({ id = self.consumer_id },
                                                          { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not consumer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local credential
      for row, err in db.credentials:each_for_consumer({ id = consumer.id }) do
        if err then
          return helpers.yield_error(err)
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER and
           row.plugin == self.plugin.name then
           credential = row
        end
      end

      if not credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- key or password
      local new_password = self.params[self.plugin.credential_key]
      if not new_password or new_password == "" then
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                  self.plugin.credential_key .. " is required")
      end

      local cred_pk = { id = credential.id }
      local entity = { [self.plugin.credential_key] = new_password }
      local ok, err = crud.portal_crud.update_login_credential(
                                              self.collection, cred_pk, entity)
      if err then
        return helpers.yield_error(err)
      end

      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- Mark the token secret as consumed
      local ok, err = secrets.consume_secret(self.reset_secret_id)
      if not ok then
        return helpers.yield_error(err)
      end

      -- Email user with reset success confirmation
      local portal_emails = portal_smtp_client.new()
      local _, err = portal_emails:password_reset_success(consumer.username)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/forgot-password"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)

      local workspace = get_workspace()
      local token_ttl = ws_helper.retrieve_ws_config(
                                      ws_constants.PORTAL_TOKEN_EXP, workspace)

      local developer, _, err_t = db.developers:select_by_email(self.params.email,
                                                          { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      -- If we do not have a developer, return 200 ok
      if not developer then
        return helpers.responses.send_HTTP_OK()
      end

      -- Generate a reset secret and jwt
      local jwt, err = secrets.create(developer.consumer, ngx.var.remote_addr,
                                                                     token_ttl)
      if not jwt then
        return helpers.yield_error(err)
      end

      -- Email user with reset jwt included
      local portal_emails = portal_smtp_client.new()
      local _, err = portal_emails:password_reset(developer.email, jwt)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/config"] = {
    GET = function(self, db, helpers)
      local distinct_plugins = {}

      do
        local rows, err = db.plugins:select_all()
        if err then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end

        local map = {}
        for _, row in ipairs(rows) do
          if not map[row.name] and auth_plugins[row.name] and auth_plugins[row.name].dao then
            distinct_plugins[#distinct_plugins+1] = row.name
          end
          map[row.name] = true
        end
      end

      return helpers.responses.send_HTTP_OK({
        plugins = {
          enabled_in_cluster = distinct_plugins,
        }
      })
    end,
  },

  ["/developer"] = {
    GET = function(self, db, helpers)
      return helpers.responses.send_HTTP_OK(self.developer)
    end,

    DELETE = function(self, db, helpers)
      local ok, err = db.developers:delete({id = self.developer.id})
      if not ok then
        if err then
          return helpers.yield_error(err)
        else
          return helpers.responses.send_HTTP_NOT_FOUND()
        end
      end

       return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },

  ["/developer/password"] = {
    PATCH = function(self, db, helpers)
      local credential
      for row, err in db.credentials:each_for_consumer({ id = self.developer.consumer.id}) do
        if err then
          return helpers.yield_error(err)
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER and
           row.plugin == self.plugin.name then
           credential = row
        end
      end

      if not credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local cred_params = {}

      if self.params.password then
        cred_params.password = self.params.password
        self.params.password = nil
      elseif self.params.key then
        cred_params.key = self.params.key
        self.params.key = nil
      else
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                                 "key or password is required")
      end

      local cred_pk = { id = credential.id }
      local ok, err = crud.portal_crud.update_login_credential(self.collection,
                                                          cred_pk, cred_params)
      if err then
        return helpers.yield_error(err)
      end

      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/developer/email"] = {
    PATCH = function(self, db, helpers)
      local developer, _, err_t = db.developers:update({
        id = self.developer.id
      }, {
        email = self.params.email
      })

      if not developer then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(developer)
    end,
  },

  ["/developer/meta"] = {
    PATCH = function(self, db, helpers)
      local meta_params = self.params.meta and cjson.decode(self.params.meta)

      if not meta_params then
        return helpers.responses.send_HTTP_BAD_REQUEST("meta required")
      end

      local current_dev_meta = self.developer.meta and
                                               cjson.decode(self.developer.meta)

      if not current_dev_meta then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- Iterate over meta update params and assign them to current meta
      for k, v in pairs(meta_params) do
        -- Only assign values that are already in the current meta
        if current_dev_meta[k] then
          current_dev_meta[k] = v
        end
      end

      local ok, err = db.developers:update({
        id = self.developer.id
      }, {
        meta = cjson.encode(current_dev_meta)
      })

      if err then
        return helpers.yield_error(err)
      end

      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/credentials/:plugin"] = {
    GET = function(self, db, helpers)
      validate_credential_plugin(self, db, helpers)

      local credentials = {}
      for row, err in db.credentials:each_for_consumer({ id = self.developer.consumer.id}) do
        if err then
          return helpers.yield_error(err)
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.PROXY and
           row.plugin == self.credential_plugin.name then
           credentials[#credentials + 1] = row
        end
      end

      return helpers.responses.send_HTTP_OK(count_entities(credentials))
    end,

    POST = function(self, db, helpers)
      validate_credential_plugin(self, db, helpers)
      self.params.consumer = { id = self.developer.consumer.id }
      self.params.plugin = nil

      local credential, _, err_t = self.credential_collection:insert(self.params, {skip_rbac = true})
      if not credential then
        return endpoints.handle_error(err_t)
      end

      local _, err = db.credentials:insert({
        id = credential.id,
        consumer = { id = credential.consumer.id },
        consumer_type = enums.CONSUMERS.TYPE.PROXY,
        plugin = self.credential_plugin.name,
        credential_data = tostring(cjson.encode(credential)),
      })

      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK(credential)
    end,
  },

  ["/credentials/:plugin/:credential_id"] = {
    GET = function(self, db, helpers)
      validate_credential_plugin(self, db, helpers)

      local credential, _, err_t = self.credential_collection:select({
        id = self.params.credential_id
      }, {
        skip_rbac = true,
      })

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      if credential.consumer.id ~= self.developer.consumer.id then
        return helpers.responses.send_HTTP_BAD_REQUEST()
      end

      return helpers.responses.send_HTTP_OK(credential)
    end,

    PATCH = function(self, db, helpers)
      validate_credential_plugin(self, db, helpers)

      local cred_id = self.params.credential_id
      self.params.plugin = nil
      self.params.credential_id = nil

      local credential, err = crud.portal_crud.update_login_credential(
                     self.credential_collection, { id = cred_id }, self.params)
      if err then
        return helpers.yield_error(err)
      end

      if not credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_OK(credential)
    end,

    DELETE = function(self, db, helpers)
      validate_credential_plugin(self, db, helpers)

      local credential, _, err_t = self.credential_collection:select({
        id = self.params.credential_id
      }, {
        skip_rbac = true,
      })

      if not credential then
        return endpoints.handle_error(err_t)
      end

      if credential.consumer.id ~= self.developer.consumer.id then
        return helpers.responses.send_HTTP_BAD_REQUEST()
      end

      crud.portal_crud.delete_credential(credential)

      local ok, _, err_t = self.credential_collection:delete({id = credential.id})
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/vitals/status_codes/by_consumer"] = {
    GET = function(self, db, helpers)
      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        entity_type = "consumer",
        duration    = self.params.interval,
        entity_id   = self.developer.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_status_codes(opts)
      return handle_vitals_response(res, err, helpers)
    end,
  },

  ["/vitals/status_codes/by_consumer_and_route"] = {
    GET = function(self, db, helpers)
      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local key_by = "route_id"
      local opts = {
        entity_type = "consumer_route",
        duration    = self.params.interval,
        entity_id   = self.developer.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_status_codes(opts, key_by)
      return handle_vitals_response(res, err, helpers)
    end
  },

  ["/vitals/consumers/cluster"] = {
    GET = function(self, db, helpers)
      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local opts = {
        consumer_id = self.developer.consumer.id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_consumer_stats(opts)
      return handle_vitals_response(res, err, helpers)
    end
  },
}
