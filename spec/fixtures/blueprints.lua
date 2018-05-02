local ssl_fixtures = require "spec.fixtures.ssl"
local utils = require "kong.tools.utils"

local deep_merge = utils.deep_merge
local fmt = string.format


local Blueprint   = {}
Blueprint.__index = Blueprint


function Blueprint:build(overrides)
  overrides = overrides or {}
  return deep_merge(self.build_function(overrides), overrides)
end


function Blueprint:insert(overrides)
  local entity, err = self.dao:insert(self:build(overrides))
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:insert_n(n, overrides)
  local res = {}
  for i=1,n do
    res[i] = self:insert(overrides)
  end
  return res
end


local function new_blueprint(dao, build_function)
  return setmetatable({
    dao            = dao,
    build_function = build_function,
  }, Blueprint)
end


local Sequence = {}
Sequence.__index = Sequence


function Sequence:next()
  self.count = self.count + 1
  return fmt(self.sequence_string, self.count)
end


local function new_sequence(sequence_string)
  return setmetatable({
    count           = 0,
    sequence_string = sequence_string,
  }, Sequence)
end


local _M = {}


function _M.new(dao, db)
  local res = {}

  local sni_seq = new_sequence("server-name-%d")
  res.snis = new_blueprint(db.snis, function(overrides)
    return {
      name        = sni_seq:next(),
      certificate = overrides.certificate or res.certificates:insert(),
    }
  end)

  res.certificates = new_blueprint(db.certificates, function()
    return {
      cert = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    }
  end)

  local upstream_name_seq = new_sequence("upstream-%d")
  res.upstreams = new_blueprint(dao.upstreams, function(overrides)
    local slots = overrides.slots or 100

    return {
      name      = upstream_name_seq:next(),
      slots     = slots,
    }
  end)

  local consumer_custom_id_seq = new_sequence("consumer-id-%d")
  local consumer_username_seq = new_sequence("consumer-username-%d")
  res.consumers = new_blueprint(dao.consumers, function()
    return {
      custom_id = consumer_custom_id_seq:next(),
      username  = consumer_username_seq:next(),
    }
  end)

  res.targets = new_blueprint(dao.targets, function()
    return {
      weight = 10,
    }
  end)

  res.plugins = new_blueprint(dao.plugins, function()
    return {}
  end)

  res.routes = new_blueprint(db.routes, function(overrides)
    return {
      service = overrides.service or res.services:insert(),
    }
  end)

  res.services = new_blueprint(db.services, function()
    return {
      protocol = "http",
      host = "127.0.0.1",
      port = 15555,
    }
  end)

  res.acl_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "acl",
      config = {},
    }
  end)

  res.acls = new_blueprint(dao.acls, function()
    return {}
  end)

  res.cors_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "cors",
      config = {
        origins         = { "example.com" },
        methods         = { "GET" },
        headers         = { "origin", "type", "accepts"},
        exposed_headers = { "x-auth-token" },
        max_age         = 23,
        credentials     = true,
      }
    }
  end)

  res.loggly_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "loggly",
      config = {}, -- all fields have default values already
    }
  end)

  res.tcp_log_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "tcp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  res.udp_log_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  res.galileo_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "galileo",
      config = {
        environment = "test",
      },
    }
  end)

  res.jwt_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "jwt",
      config = {},
    }
  end)

  local jwt_key_seq = new_sequence("jwt-key-%d")
  res.jwt_secrets = new_blueprint(dao.jwt_secrets, function()
    return {
      key       = jwt_key_seq:next(),
      secret    = "secret",
      algorithm = "HS256",
    }
  end)

  res.oauth2_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "oauth2",
      config = {
        scopes                    = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope           = true,
        provision_key             = "provision123",
        token_expiration          = 5,
        enable_implicit_grant     = true,
      }
    }
  end)

  res.oauth2_credentials = new_blueprint(dao.oauth2_credentials, function()
    return {
      name          = "oauth2 credential",
      client_secret = "secret",
    }
  end)

  local oauth_code_seq = new_sequence("oauth-code-%d")
  res.oauth2_authorization_codes = new_blueprint(dao.oauth2_authorization_codes, function()
    return {
      code  = oauth_code_seq:next(),
      scope = "default",
    }
  end)

  res.oauth2_tokens = new_blueprint(dao.oauth2_tokens, function()
    return {
      token_type = "bearer",
      expires_in = 1000000000,
      scope      = "default",
    }
  end)

  res.key_auth_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "key-auth",
      config = {},
    }
  end)

  local keyauth_key_seq = new_sequence("keyauth-key-%d")
  res.keyauth_credentials = new_blueprint(dao.keyauth_credentials, function()
    return {
      key = keyauth_key_seq:next(),
    }
  end)

  res.basicauth_credentials = new_blueprint(dao.basicauth_credentials, function()
    return {}
  end)

  res.hmac_auth_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "hmac-auth",
      config = {},
    }
  end)

  local hmac_username_seq = new_sequence("hmac-username-%d")
  res.hmacauth_credentials = new_blueprint(dao.hmacauth_credentials, function()
    return {
      username = hmac_username_seq:next(),
      secret   = "secret",
    }
  end)

  res.rate_limiting_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "rate-limiting",
      config = {},
    }
  end)

  res.response_ratelimiting_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "response-ratelimiting",
      config = {},
    }
  end)

  res.datadog_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "datadog",
      config = {},
    }
  end)

  res.statsd_plugins = new_blueprint(dao.plugins, function()
    return {
      name   = "statsd",
      config = {},
    }
  end)

  return res
end

return _M
