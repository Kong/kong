local typedefs = require "kong.db.schema.typedefs"
local client = require("kong.plugins.letsencrypt.client")

local CERT_TYPES = { "rsa", "ecc" }

local STORAGE_TYPES = { "kong", "shm", "redis", "consul", "vault" }

local SHM_STORAGE_SCHEMA = {
  { shm_name = {
    type = "string",
    default = "kong",
    custom_validator = function(d) return ngx.shared[d] end,
  }, },
}

-- must be a table per schema definition
local KONG_STORAGE_SCHEMA = {
}

local REDIS_STORAGE_SCHEMA = {
  { host = typedefs.host, },
  { port = typedefs.port, },
  { database = { type = "number" }},
  { auth = { type = "string" }}
}

local CONSUL_VAULT_STORAGE_SCHEMA = {
  { https = { type = "boolean", default = true, }, },
  { host = typedefs.host, },
  { port = typedefs.port, },
  { kv_path = { type = "string", }, },
  { timeout = { type = "number", }, },
  { token = { type = "string", }, },
}

local function check_account(conf)
  -- hack: create an account if it doesn't exist, during plugin creation time
  -- TODO: remove from storage if schema check failed?
  local err = client.create_account(conf)
  return err == nil, err
end

return {
  name = "letsencrypt",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      custom_validator = check_account,
      fields = {
        { account_email = {
          type = "string",
          -- very loose validation for basic sanity test
          match = "%w*%p*@+%w*%.?%w*",
          required = true,
        }, },
        { staging = { type = "boolean", default = true, }, },
        -- kong doesn't support multiple certificate chains yet
        { cert_type = {
          type = "string",
          default = 'rsa',
          one_of = CERT_TYPES,
        }, },
        { renew_threshold_days = {
          type = "number",
          default = 14,
        }, },
        { storage = {
          type = "string",
          default = "kong",
          one_of = STORAGE_TYPES,
        }, },
        { storage_config = {
          type = "record",
          fields = {
            { shm = { type = "record", fields = SHM_STORAGE_SCHEMA, } },
            { kong = { type = "record", fields = KONG_STORAGE_SCHEMA, } },
            { redis = { type = "record", fields = REDIS_STORAGE_SCHEMA, } },
            { consul = { type = "record", fields = CONSUL_VAULT_STORAGE_SCHEMA, } },
            { vault = { type = "record", fields = CONSUL_VAULT_STORAGE_SCHEMA, } },
          },
        }, },
      },
    }, },
  },
}
