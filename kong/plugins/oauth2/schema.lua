local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local stringy = require "stringy"
local utils = require "kong.tools.utils"
local bcrypt = require "bcrypt"

local BCRYPT_ROUNDS = 12

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, { [column] = utils.random_string()}
  end
  return true
end

local function check_mandatory_scope(v, t)
  if v and not t.scopes then
    return false, "To set a mandatory scope you also need to create available scopes"
  end
  return true
end

local function marshall_event(conf)
end

return {
  no_consumer = true,
  fields = {
    -- Don't 401 someone without authentication, just don't fill out the user headers
    allow_unauthenticated = { required = false, type = "boolean", default = false },
    -- pass_authenticated means that if another auth plugin has already filled
    -- out the context, we won't bother to re-auth
    pass_authenticated = { required = false, type = "boolean", default = false },
    scopes = { required = false, type = "array" },
    mandatory_scope = { required = true, type = "boolean", default = false, func = check_mandatory_scope },
    provision_key = { required = false, unique = true, type = "string", func = generate_if_missing },
    provision_key_hash = { required = false, unique = false, type = "string" },
    token_expiration = { required = true, type = "number", default = 7200 },
    enable_authorization_code = { required = true, type = "boolean", default = false },
    enable_implicit_grant = { required = true, type = "boolean", default = false },
    enable_client_credentials = { required = true, type = "boolean", default = false },
    enable_password_grant = { required = true, type = "boolean", default = false },
    hide_credentials = { type = "boolean", default = false },
    accept_http_if_already_terminated = { required = false, type = "boolean", default = false }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if not plugin_t.enable_authorization_code and not plugin_t.enable_implicit_grant
       and not plugin_t.enable_client_credentials and not plugin_t.enable_password_grant then
       return false, Errors.schema "You need to enable at least one OAuth flow"
    end
    return true
  end,
  to_dao_transform = function (schema, dao, plugin_t, is_update)
    if not is_update and plugin_t.config.provision_key then
      local plugin_copy = utils.shallow_copy(plugin_t)
      local config = utils.shallow_copy(plugin_t.config)
      plugin_copy.config = config
      config.provision_key_hash = bcrypt.digest(config.provision_key, BCRYPT_ROUNDS)
      config.provision_key = nil
      return plugin_copy
    end
    return plugin_t
  end,
  from_dao_transform = function (schema, dao, original_plugin_t, transformed_plugin_t, dao_result, is_update)
    if original_plugin_t.config.provision_key then
      dao_result.provision_key = original_plugin_t.config.provision_key
    end
    dao.provision_key_hash = nil
    return dao_result
  end
}
