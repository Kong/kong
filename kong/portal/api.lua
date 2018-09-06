local singletons   = require "kong.singletons"
local crud         = require "kong.api.crud_helpers"
local enums        = require "kong.enterprise_edition.dao.enums"
local portal_utils = require "kong.portal.utils"
local cjson        = require "cjson.safe"
local ee_jwt       = require "kong.enterprise_edition.jwt"
local utils        = require "kong.tools.utils"
local time         = ngx.time


--- Allowed auth plugins
-- Table containing allowed auth plugins that the developer portal api
-- can create credentials for.
--
--["<route>"]:     {  name = "<name>",    dao = "<dao_collection>" }
local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["acls"] =       { name = "acl",        dao = "acls" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}


local function validate_auth_plugin(self, dao_factory, helpers, plugin_name)
  plugin_name = plugin_name or singletons.configuration.portal_auth
  self.plugin = auth_plugins[plugin_name]
  if not self.plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.collection = dao_factory[self.plugin.dao]
end


local function validate_email(self, dao_factory, helpers)
  local ok, err = portal_utils.validate_email(self.params.email)
  if not ok then
    return helpers.responses.send_HTTP_BAD_REQUEST("Invalid email: " .. err)
  end
end


local function find_login_credential(self, dao_factory, helpers)
  local credentials, err = dao_factory.credentials:find_all({
    consumer_id = self.consumer.id,
    consumer_type = enums.CONSUMERS.TYPE.DEVELOPER,
    plugin = self.plugin.name,
  })

  if err then
    return helpers.yield_error(err)
  end

  if next(credentials) == nil then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.credential = credentials[1]
end


local function authenticate(self, dao_factory, helpers)
  validate_auth_plugin(self, dao_factory, helpers)

  -- apply auth plugin
  local auth_conf = utils.deep_copy(singletons.configuration.portal_auth_conf or {})
  local prepared_plugin = portal_utils.prepare_plugin(self.plugin.name, auth_conf)
  portal_utils.apply_plugin(prepared_plugin, "access")

  -- Validate status if we have a developer type consumer
  self.consumer = ngx.ctx.authenticated_consumer
  if self.consumer.status ~= 0 then
    local msg = portal_utils.get_developer_status(self.consumer)
    return helpers.responses.send_HTTP_UNAUTHORIZED(msg)
  end
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


local function validate_jwt(self, dao_factory, helpers)
  -- Verify params
  if not self.params.token or self.params.token == "" then
    return helpers.responses.send_HTTP_BAD_REQUEST("token is required")
  end

  -- Parse and ensure that jwt contains the correct claims/headers.
  -- Signature NOT verified yet
  local jwt, err = portal_utils.validate_reset_jwt(self.params.token)
  if err then
    return helpers.responses.send_HTTP_UNAUTHORIZED(err)
  end

  -- Look up the secret by consumer id and pending status
  local rows = singletons.dao.portal_reset_secrets:find_all({
    consumer_id = jwt.claims.id,
    status = enums.TOKENS.STATUS.PENDING,
  })

  if not rows or next(rows) == nil then
    return helpers.responses.send_HTTP_UNAUTHORIZED()
  end

  local reset_secret = rows[1]

  -- Generate a new signature and compare it to passed token
  local ok, _ = ee_jwt.verify_signature(jwt, reset_secret.secret)
  if not ok then
    return helpers.responses.send_HTTP_UNAUTHORIZED()
  end

  self.params.email_or_id = jwt.claims.id
  self.reset_secret_id = reset_secret.id
end


return {
  ["/auth"] = {
    GET = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/files"] = {
    before = function(self, dao_factory, helpers)
      -- If auth is enabled, we need to validate consumer/developer
      if singletons.configuration.portal_auth then
        authenticate(self, dao_factory, helpers)
      end
    end,

    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.portal_files, nil, {__skip_rbac = true})
    end,
  },

  ["/files/unauthenticated"] = {
    -- List all unauthenticated files stored in the portal file system
    GET = function(self, dao_factory, helpers)
      self.params = {
        auth = false,
      }

      crud.paginated_set(self, dao_factory.portal_files, nil, {__skip_rbac = true})
    end,
  },

  ["/files/*"] = {
    before = function(self, dao_factory, helpers)
      local dao = dao_factory.portal_files
      local identifier = self.params.splat

      -- Find a file by id or field "name"
      local rows, err = crud.find_by_id_or_field(dao, {__skip_rbac = true}, identifier, "name")
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

  ["/register"] = {
    before = function(self, dao_factory, helpers)
      self.auto_approve = singletons.configuration.portal_auto_approve
      validate_email(self, dao_factory, helpers)
    end,

    POST = function(self, dao_factory, helpers)
      if not self.params.meta then
        return helpers.responses.send_HTTP_BAD_REQUEST("meta param is missing")
      end

      local meta, err = cjson.decode(self.params.meta)
      if err then
        return helpers.responses.send_HTTP_BAD_REQUEST("meta param is invalid")
      end

      local full_name = meta.full_name
      if not full_name or full_name == "" then
        return helpers.responses.send_HTTP_BAD_REQUEST("meta param missing key: 'full_name'")
      end

      self.params.type = enums.CONSUMERS.TYPE.DEVELOPER
      self.params.status = enums.CONSUMERS.STATUS.PENDING
      self.params.username = self.params.email

      if self.auto_approve then
        self.params.status = enums.CONSUMERS.STATUS.APPROVED
      end

      local password = self.params.password
      local key = self.params.key

      self.params.password = nil
      self.params.key = nil

      local consumer, err = dao_factory.consumers:insert(self.params)
      if err then
        return helpers.yield_error(err)
      end

      -- omit credential post for oidc
      if singletons.configuration.portal_auth == "openid-connect" then
        return helpers.responses.send_HTTP_CREATED({
          consumer = consumer,
          credential = {},
        })
      end

      validate_auth_plugin(self, dao_factory, helpers)
      local credential_data

      if self.plugin.name == "basic-auth" then
        credential_data = {
          consumer_id = consumer.id,
          username = self.params.username,
          password = password,
        }
      end

      if self.plugin.name == "key-auth" then
        credential_data = {
          consumer_id = consumer.id,
          key = key,
        }
      end

      if credential_data == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
          "Cannot create credential with portal_auth = " ..
          self.plugin.name)
      end

      crud.post(credential_data, self.collection, function(credential)
          crud.portal_crud.insert_credential(self.plugin.name,
                                             enums.CONSUMERS.TYPE.DEVELOPER
                                            )(credential)
        local res = {
          consumer = consumer,
          credential = credential,
        }

        if consumer.status == enums.CONSUMERS.STATUS.PENDING then
          local email, err = singletons.portal_emails:access_request(consumer.email, full_name)
          if err then
            if err.code then
              return helpers.responses.send(err.code, {message = err.message})
            end

            return helpers.yield_error(err)
          end

          res.email = email
        end

        return res
      end)
    end,
  },

  ["/validate-reset"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)
      validate_jwt(self, dao_factory, helpers)
    end,

    POST = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/reset-password"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)
      validate_jwt(self, dao_factory, helpers)
    end,

    POST = function(self, dao_factory, helpers)
      -- If we made it this far, the jwt is valid format and properly signed.
      -- Now we will lookup the consumer and credentials we need to update
      -- Lookup consumer by id contained in jwt, if not found, this will 404
      crud.find_consumer_by_email_or_id(self, dao_factory, helpers, {__skip_rbac = true})

      local credentials, err = dao_factory.credentials:find_all({
        consumer_id = self.consumer.id,
        consumer_type = enums.CONSUMERS.TYPE.DEVELOPER,
        plugin = self.plugin.name,
      })

      if err then
        return helpers.yield_error(err)
      end

      local credential = credentials[1]
      if not credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- key or password
      local new_password = self.params[self.plugin.credential_key]
      if not new_password or new_password == "" then
        return helpers.responses.send_HTTP_BAD_REQUEST(self.plugin.credential_key .. " is required")
      end

      local filter = {consumer_id = self.consumer.id, id = credential.id}
      local cred_params = {[self.plugin.credential_key] = new_password}
      local ok, err = crud.portal_crud.update_login_credential(cred_params,
                                                      self.collection, filter)
      if err then
        return helpers.yield_error(err)
      end

      if not ok then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- Mark the token secret as consumed
      local _, err = singletons.dao.portal_reset_secrets:update({
        status = enums.TOKENS.STATUS.CONSUMED,
        updated_at = time() * 1000,
      }, {
        id = self.reset_secret_id,
      })

      if err then
        return helpers.yield_error(err)
      end

      local _, err = singletons.portal_emails:password_reset_success(self.consumer.email)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/forgot-password"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)
      validate_email(self, dao_factory, helpers)
    end,

    POST = function(self, dao_factory, helpers)
      local token_ttl = singletons.configuration.portal_token_exp
      local filter = {__skip_rbac = true}
      local rows, err = crud.find_by_id_or_field(dao_factory.consumers, filter,
                                                    self.params.email, "email")
      if err then
        return helpers.yield_error(err)
      end

      -- If we do not have a consumer, return 200 ok
      self.consumer = rows[1]
      if not self.consumer then
        return helpers.responses.send_HTTP_OK()
      end

      local rows, err = singletons.dao.portal_reset_secrets:find_all({
        consumer_id = self.consumer.id
      })

      if err then
        return helpers.yield_error(err)
      end

      -- Invalidate any pending resets for this consumer
      for _, row in ipairs(rows) do
        if row.status == enums.TOKENS.STATUS.PENDING then
          local _, err = singletons.dao.portal_reset_secrets:update({
            status = enums.TOKENS.STATUS.INVALIDATED,
            updated_at = time() * 1000,
          }, {
            id = row.id
          })
          if err then
            return helpers.yield_error(err)
          end
        end
      end

      -- Generate new reset
      local row, err = singletons.dao.portal_reset_secrets:insert({
        consumer_id = self.consumer.id,
        client_addr = ngx.var.remote_addr,
      })

      if err then
        return helpers.yield_error(err)
      end

      local claims = {id = self.consumer.id, exp = time() + token_ttl}
      local jwt, err = ee_jwt.generate_JWT(claims, row.secret)
      if err then
        return helpers.yield_error(err)
      end

      local _, err = singletons.portal_emails:password_reset(self.consumer.email, jwt)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK()
    end,
  },

  ["/config"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
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

        -- singletons.internal_proxies:add_internal_plugins(distinct_plugins, map)
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
      authenticate(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.consumer, dao_factory.consumers)
    end
  },

  ["/developer/password"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
      find_login_credential(self, dao_factory, helpers)
    end,

    PATCH = function(self, dao_factory, helpers)
      local cred_params = {}

      if self.params.password then
        cred_params.password = self.params.password
        self.params.password = nil
      elseif self.params.key then
        cred_params.key = self.params.key
        self.params.key = nil
      else
        return helpers.responses.send_HTTP_BAD_REQUEST("key or password is required")
      end

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

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/developer/email"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
      find_login_credential(self, dao_factory, helpers)
      validate_email(self, dao_factory, helpers)
    end,

    PATCH = function(self, dao_factory, helpers)
      if singletons.configuration.portal_auth == "basic-auth" then
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

      local dev_params = {
        username = self.params.email,
        email = self.params.email,
      }

      local ok, err = singletons.dao.consumers:update(dev_params, {
        id = self.consumer.id,
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

  ["/developer/meta"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
    end,

    PATCH = function(self, dao_factory, helpers)
      local meta_params = self.params.meta and cjson.decode(self.params.meta)

      if not meta_params then
        return helpers.responses.send_HTTP_BAD_REQUEST("meta required")
      end

      local current_dev_meta = self.consumer.meta and cjson.decode(self.consumer.meta)

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

      -- Encode full meta (current and new) and assign it to update params
      local dev_params = {
        meta = cjson.encode(current_dev_meta)
      }

      local ok, err = singletons.dao.consumers:update(dev_params, {
        id = self.consumer.id,
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

  ["/credentials"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.id == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                                  "credential id is required")
      end

      crud.patch(self.params, self.collection, {id = self.params.id}, nil,
                                                         {__skip_rbac = true})
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, self.collection,
                crud.portal_crud.insert_credential(self.plugin.name))
    end,
  },

  ["/credentials/:plugin"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)

      local plugin_name = ngx.unescape_uri(self.params.plugin)
      validate_auth_plugin(self, dao_factory, helpers, plugin_name)

      self.params.consumer_id = self.consumer.id
      self.params.plugin = nil
    end,

    GET = function(self, dao_factory, helpers)
      self.params.consumer_type = enums.CONSUMERS.TYPE.PROXY
      self.params.plugin = self.plugin.name
      crud.paginated_set(self, dao_factory.credentials, nil,
                                                         {__skip_rbac = true})
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, self.collection,
                crud.portal_crud.insert_credential(self.plugin.name))
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.id == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
                                                  "credential id is required")
      end

      crud.patch(self.params, self.collection, { id = self.params.id },
                 crud.portal_crud.update_credential, {__skip_rbac = true})
    end,
  },

  ["/credentials/:plugin/:credential_id"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)

      local plugin_name = ngx.unescape_uri(self.params.plugin)
      validate_auth_plugin(self, dao_factory, helpers, plugin_name)

      self.params.plugin = nil

      local credentials, err = self.collection:find_all({
        __skip_rbac = true,
        consumer_id = self.consumer.id,
        id = self.params.credential_id,
      })

      if err then
        return helpers.yield_error(err)
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
      crud.patch(self.params, self.collection, self.credential,
                 crud.portal_crud.update_credential, {__skip_rbac = true})
    end,

    DELETE = function(self, dao_factory)
      crud.portal_crud.delete_credential(self.credential)
      crud.delete(self.credential, self.collection, {__skip_rbac = true})
    end,
  },

  ["/vitals/status_codes/by_consumer"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)

      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      local opts = {
        entity_type = "consumer",
        duration    = self.params.interval,
        entity_id   = self.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = singletons.vitals:get_status_codes(opts)
      return handle_vitals_response(res, err, helpers)
    end,
  },

  ["/vitals/status_codes/by_consumer_and_route"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)

      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      local key_by = "route_id"
      local opts = {
        entity_type = "consumer_route",
        duration    = self.params.interval,
        consumer_id = self.consumer.id,
        entity_id   = self.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = singletons.vitals:get_status_codes(opts, key_by)
      return handle_vitals_response(res, err, helpers)
    end
  },

  ["/vitals/consumers/cluster"] = {
    before = function(self, dao_factory, helpers)
      authenticate(self, dao_factory, helpers)

      if not singletons.configuration.vitals then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      local opts = {
        consumer_id = self.consumer.id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = singletons.vitals:get_consumer_stats(opts)
      return handle_vitals_response(res, err, helpers)
    end
  },
}
