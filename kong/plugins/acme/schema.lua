local typedefs = require "kong.db.schema.typedefs"
local reserved_words = require "kong.plugins.acme.reserved_words"

local CERT_TYPES = { "rsa", "ecc" }

local RSA_KEY_SIZES = { 2048, 3072, 4096 }

local STORAGE_TYPES = { "kong", "shm", "redis", "consul", "vault" }

local function validate_namespace(namespace)
  if namespace ~= "" then
    for _, v in pairs(reserved_words) do
      if namespace:sub(1, #v) == v then
        return nil, "namespace can't be prefixed with reserved word: " .. v
      end
    end
  end

  return true
end

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
  { auth = { type = "string", referenceable = true, }},
  { ssl = { type = "boolean", required = true, default = false } },
  { ssl_verify = { type = "boolean", required = true, default = false } },
  { ssl_server_name = typedefs.sni { required = false } },
  { namespace = { type = "string", required = true, default = "", len_min = 0,
                  custom_validator = validate_namespace } },
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

local ACCOUNT_KEY_SCHEMA = {
  { key_id = { type = "string", required = true }},
  { key_set = { type = "string" }}
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
        { account_email = { description = "The account identifier. Can be reused in a different plugin instance.", type = "string",
          -- very loose validation for basic sanity test
          match = "%w*%p*@+%w*%.?%w*",
          required = true,
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        { account_key = {
          type = "record",
          required = false,
          fields = ACCOUNT_KEY_SCHEMA,
        }, },
        { api_uri = { description = "The ACMEv2 API endpoint to use. You can specify the [Let's Encrypt staging environment](https://letsencrypt.org/docs/staging-environment/) for testing. Kong doesn't automatically delete staging certificates. If you use the same domain in test and production environments, you need to manually delete those certificates after testing.", type = "string",
          format = "uri",
          default = "https://acme-v02.api.letsencrypt.org/directory",
        }, },
        { tos_accepted = { description = "If you are using Let's Encrypt, you must set this to `true` to agree the [Terms of Service](https://letsencrypt.org/repository/).", type = "boolean",
          default = false,
        }, },
        { eab_kid = { description = "External account binding (EAB) key id. You usually don't need to set this unless it is explicitly required by the CA.", type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        { eab_hmac_key = { description = "External account binding (EAB) base64-encoded URL string of the HMAC key. You usually don't need to set this unless it is explicitly required by the CA.", type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        }, },
        -- Kong doesn't support multiple certificate chains yet
        { cert_type = { description = "The certificate type to create. The possible values are `'rsa'` for RSA certificate or `'ecc'` for EC certificate.", type = "string",
          default = 'rsa',
          one_of = CERT_TYPES,
        }, },
        { rsa_key_size = { description = "RSA private key size for the certificate. The possible values are 2048, 3072, or 4096.", type = "number",
          default = 4096,
          one_of = RSA_KEY_SIZES,
        }, },
        { renew_threshold_days = { description = " Days remaining to renew the certificate before it expires.", type = "number",
          default = 14,
        }, },
        { domains = typedefs.hosts },
        { allow_any_domain = { description = "If set to `true`, the plugin allows all domains and ignores any values in the `domains` list.", type = "boolean",
          default = false,
        }, },
        { fail_backoff_minutes = { description = "Minutes to wait for each domain that fails to create a certificate. This applies to both a\nnew certificate and a renewal certificate.", type = "number",
          default = 5,
        }, },
        { storage = { description = "The backend storage type to use. The possible values are `'kong'`, `'shm'`, `'redis'`, `'consul'`, or `'vault'`. In DB-less mode, `'kong'` storage is unavailable. Note that `'shm'` storage does not persist during Kong restarts and does not work for Kong running on different machines, so consider using one of `'kong'`, `'redis'`, `'consul'`, or `'vault'` in production. Please refer to the Hybrid Mode sections below as well.", type = "string",
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
        { enable_ipv4_common_name = {
          type = "boolean",
          default = true,
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
