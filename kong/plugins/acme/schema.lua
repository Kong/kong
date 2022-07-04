local typedefs = require "kong.db.schema.typedefs"

local CERT_TYPES = { "rsa", "ecc" }

local RSA_KEY_SIZES = { 2048, 3072, 4096 }

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
  { auth = { type = "string", referenceable = true, }}
}

local CONSUL_STORAGE_SCHEMA = {
  { https = { type = "boolean", default = false, }, },
  { host = typedefs.host, },
  { port = typedefs.port, },
  { kv_path = { type = "string", }, },
  { timeout = { type = "number", }, },
  { token = { type = "string", referenceable = true, }, },
}

local VAULT_STORAGE_SCHEMA = {
  { https = { type = "boolean", default = false, }, },
  { host = typedefs.host, },
  { port = typedefs.port, },
  { kv_path = { type = "string", }, },
  { timeout = { type = "number", }, },
  { token = { type = "string", referenceable = true, }, },
  { tls_verify = { type = "boolean", default = true, }, },
  { tls_server_name = { type = "string" }, },
  { auth_method = { type = "string", default = "token", one_of = { "token", "kubernetes" } } },
  { auth_path =  { type = "string" }, },
  { auth_role =  { type = "string" }, },
  { jwt_path =  { type = "string" }, },
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
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        { api_uri = typedefs.url({ default = "https://acme-v02.api.letsencrypt.org/directory" }),
        },
        { tos_accepted = {
          type = "boolean",
          default = false,
        }, },
        { eab_kid = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        { eab_hmac_key = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        -- Kong doesn't support multiple certificate chains yet
        { cert_type = {
          type = "string",
          default = 'rsa',
          one_of = CERT_TYPES,
        }, },
        { rsa_key_size = {
          type = "number",
          default = 4096,
          one_of = RSA_KEY_SIZES,
        }, },
        { renew_threshold_days = {
          type = "number",
          default = 14,
        }, },
        { domains = typedefs.hosts },
        { allow_any_domain = {
          type = "boolean",
          default = false,
        }, },
        { fail_backoff_minutes = {
          type = "number",
          default = 5,
        }, },
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
            { consul = { type = "record", fields = CONSUL_STORAGE_SCHEMA, } },
            { vault = { type = "record", fields = VAULT_STORAGE_SCHEMA, } },
          },
        }, },
        { preferred_chain = {
          type = "string",
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
        local field = entity.config.storage
        if _G.kong and kong.configuration.database == "off" and
            kong.configuration.role ~= "data_plane" and field == "kong" then
          return nil, "\"kong\" storage can't be used with dbless mode"
        end
        if _G.kong and kong.configuration.role == "control_plane" and field == "shm" then
          return nil, "\"shm\" storage can't be used in Hybrid mode"
        end
        return true
      end
    } },
  },
}

return schema
