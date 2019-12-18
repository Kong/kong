local typedefs = require "kong.db.schema.typedefs"

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

local schema = {
  name = "acme",
  fields = {
    -- global plugin only
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { account_email = {
          type = "string",
          -- very loose validation for basic sanity test
          match = "%w*%p*@+%w*%.?%w*",
          required = true,
        }, },
        { api_uri = typedefs.url({ default = "https://acme-v02.api.letsencrypt.org" }),
        },
        { tos_accepted = {
          type = "boolean",
          default = false,
        }, },
        -- Kong doesn't support multiple certificate chains yet
        { cert_type = {
          type = "string",
          default = 'rsa',
          one_of = CERT_TYPES,
        }, },
        { renew_threshold_days = {
          type = "number",
          default = 14,
        }, },
        { domains = typedefs.hosts },
        { storage = {
          type = "string",
          default = "shm",
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
  entity_checks = {
    { conditional = {
      if_field = "config.api_uri", if_match = { one_of = {
        "https://acme-v02.api.letsencrypt.org",
        "https://acme-staging-v02.api.letsencrypt.org",
      } },
      then_field = "config.tos_accepted", then_match = { eq = true },
      then_err = "terms of service must be accepted, see https://letsencrypt.org/repository/",
    } },
    { custom_entity_check = {
      field_sources = { "config.storage", },
      fn = function(entity)
        if _G.kong and kong.configuration.database == "off" and entity == "kong" then
          return nil, "\"kong\" storage can't be used with dbless mode"
        end
        return true
      end
    } },
  },
}

return schema
