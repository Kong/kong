local utils = require "kong.tools.utils"
local stringy = require "stringy"
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
    scopes = { required = false, type = "array" },
    mandatory_scope = { required = true, type = "boolean", default = false, func = check_mandatory_scope },
    provision_key = { required = false, unique = true, type = "string", func = generate_if_missing },
    provision_key_hash = { required = false, unique = false, type = "string" },
    token_expiration = { required = true, type = "number", default = 7200 },
    enable_authorization_code = { required = true, type = "boolean", default = true },
    enable_implicit_grant = { required = true, type = "boolean", default = false },
    enable_client_credentials = { required = true, type = "boolean", default = false },
    enable_password_grant = { required = true, type = "boolean", default = false },
    hide_credentials = { type = "boolean", default = false },
    accept_http_if_already_terminated = { required = false, type = "boolean", default = false }
  },
  self_check = function (self, config, dao, is_update)
    if not is_update and config.provision_key then
      config.provision_key_hash = bcrypt.digest(config.provision_key, BCRYPT_ROUNDS)
      config.provision_key = nil
    end
    return true
  end
}
