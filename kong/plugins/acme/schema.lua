local typedefs = require "kong.db.schema.typedefs"
local reserved_words = require "kong.plugins.acme.reserved_words"
local redis_schema = require "kong.tools.redis.schema"
local deprecation = require("kong.deprecation")

local tablex = require "pl.tablex"

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
  {
    shm_name = {
      description = "Name of shared memory zone used for Kong API gateway storage",
      type = "string",
      default = "kong",
      custom_validator = function(d) return ngx.shared[d] end,
    },
  },
}

-- must be a table per schema definition
local KONG_STORAGE_SCHEMA = {
}

local LEGACY_SCHEMA_TRANSLATIONS = {
  { auth = {
    type = "string",
    len_min = 0,
    translate_backwards = {'password'},
    func = function(value)
      deprecation("acme: config.storage_config.redis.auth is deprecated, please use config.storage_config.redis.password instead",
        { after = "4.0", })
      return { password = value }
    end
  }},
  { ssl_server_name = {
    type = "string",
    translate_backwards = {'server_name'},
    func = function(value)
      deprecation("acme: config.storage_config.redis.ssl_server_name is deprecated, please use config.storage_config.redis.server_name instead",
        { after = "4.0", })
      return { server_name = value }
    end
  }},
  { namespace = {
    type = "string",
    len_min = 0,
    translate_backwards = {'extra_options', 'namespace'},
    func = function(value)
      deprecation("acme: config.storage_config.redis.namespace is deprecated, please use config.storage_config.redis.extra_options.namespace instead",
        { after = "4.0", })
      return { extra_options = { namespace = value } }
    end
  }},
  { scan_count = {
    type = "integer",
    translate_backwards = {'extra_options', 'scan_count'},
    func = function(value)
      deprecation("acme: config.storage_config.redis.scan_count is deprecated, please use config.storage_config.redis.extra_options.scan_count instead",
        { after = "4.0", })
      return { extra_options = { scan_count = value } }
    end
  }},
}

local REDIS_STORAGE_SCHEMA = tablex.copy(redis_schema.config_schema.fields)
table.insert(REDIS_STORAGE_SCHEMA, { extra_options = {
  description = "Custom ACME Redis options",
  type = "record",
  fields = {
    {
      namespace = {
        type = "string",
        description = "A namespace to prepend to all keys stored in Redis.",
        required = true,
        default = "",
        len_min = 0,
        custom_validator = validate_namespace
      }
    },
    { scan_count = { type = "number", required = false, default = 10, description = "The number of keys to return in Redis SCAN calls." } },
  }
} })

local CONSUL_STORAGE_SCHEMA = {
  { https = { type = "boolean", default = false, description = "Boolean representation of https."}, },
  { host = typedefs.host},
  { port = typedefs.port},
  { kv_path = { type = "string", description = "KV prefix path."}, },
  { timeout = { type = "number", description = "Timeout in milliseconds."}, },
  { token = { type = "string", referenceable = true, description = "Consul ACL token."}, },
}

local VAULT_STORAGE_SCHEMA = {
  { https = { type = "boolean", default = false, description = "Boolean representation of https." }, },
  { host = typedefs.host, },
  { port = typedefs.port, },
  { kv_path = { type = "string", description = "KV prefix path." }, },
  { timeout = { type = "number", description = "Timeout in milliseconds."}, },
  { token = { type = "string", referenceable = true, description = "Consul ACL token." }, },
  { tls_verify = { type = "boolean", default = true, description = "Turn on TLS verification." }, },
  { tls_server_name = { type = "string", description = "SNI used in request, default to host if omitted."  }, },
  { auth_method = { type = "string", default = "token", one_of = { "token", "kubernetes" }, description = "Auth Method, default to token, can be 'token' or 'kubernetes'." } },
  { auth_path = { type = "string", description = "Vault's authentication path to use." }, },
  { auth_role = { type = "string", description = "The role to try and assign." }, },
  { jwt_path = { type = "string", description = "The path to the JWT." }, },
}

local ACCOUNT_KEY_SCHEMA = {
  { key_id = { type = "string", required = true, description = "The Key ID." } },
  { key_set = { type = "string", description = "The ID of the key set to associate the Key ID with." } }
}

local schema = {
  name = "acme",
  fields = {
    -- global plugin only
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { route = typedefs.no_route },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            account_email = {
              description = "The account identifier. Can be reused in a different plugin instance.",
              type = "string",
              -- very loose validation for basic sanity test
              match = "%w*%p*@+%w*%.?%w*",
              required = true,
              encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
              referenceable = true,
            },
          },
          {
            account_key = {
              description = "The private key associated with the account.",
              type = "record",
              required = false,
              fields = ACCOUNT_KEY_SCHEMA,
            },
          },
          {
            api_uri = typedefs.url({ default = "https://acme-v02.api.letsencrypt.org/directory" }),
          },
          {
            tos_accepted = {
              type = "boolean",
              description = "If you are using Let's Encrypt, you must set this to `true` to agree the terms of service.",
              default = false,
            },
          },
          {
            eab_kid = {
              description = "External account binding (EAB) key id. You usually don't need to set this unless it is explicitly required by the CA.",
              type = "string",
              encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
              referenceable = true,
            },
          },
          {
            eab_hmac_key = {
              description = "External account binding (EAB) base64-encoded URL string of the HMAC key. You usually don't need to set this unless it is explicitly required by the CA.",
              type = "string",
              encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
              referenceable = true,
            },
          },
          -- Kong doesn't support multiple certificate chains yet
          {
            cert_type = {
              description = "The certificate type to create. The possible values are `'rsa'` for RSA certificate or `'ecc'` for EC certificate.",
              type = "string",
              default = 'rsa',
              one_of = CERT_TYPES,
            },
          },
          {
            rsa_key_size = {
              description = "RSA private key size for the certificate. The possible values are 2048, 3072, or 4096.",
              type = "number",
              default = 4096,
              one_of = RSA_KEY_SIZES,
            },
          },
          {
            renew_threshold_days = {
              description = "Days remaining to renew the certificate before it expires.",
              type = "number",
              default = 14,
            },
          },
          { domains = typedefs.hosts },
          {
            allow_any_domain = {
              description = "If set to `true`, the plugin allows all domains and ignores any values in the `domains` list.",
              type = "boolean",
              default = false,
            },
          },
          {
            fail_backoff_minutes = {
              description = "Minutes to wait for each domain that fails to create a certificate. This applies to both a\nnew certificate and a renewal certificate.",
              type = "number",
              default = 5,
            },
          },
          {
            storage = {
              description = "The backend storage type to use. The possible values are `'kong'`, `'shm'`, `'redis'`, `'consul'`, or `'vault'`. In DB-less mode, `'kong'` storage is unavailable. Note that `'shm'` storage does not persist during Kong restarts and does not work for Kong running on different machines, so consider using one of `'kong'`, `'redis'`, `'consul'`, or `'vault'` in production. Please refer to the Hybrid Mode sections below as well.",
              type = "string",
              default = "shm",
              one_of = STORAGE_TYPES,
            },
          },
          {
            storage_config = {
              type = "record",
              fields = {
                { shm = { type = "record", fields = SHM_STORAGE_SCHEMA, } },
                { kong = { type = "record", fields = KONG_STORAGE_SCHEMA, } },
                { redis = { type = "record", fields = REDIS_STORAGE_SCHEMA, shorthand_fields = LEGACY_SCHEMA_TRANSLATIONS } },
                { consul = { type = "record", fields = CONSUL_STORAGE_SCHEMA, } },
                { vault = { type = "record", fields = VAULT_STORAGE_SCHEMA, } },
              },
            },
          },
          {
            preferred_chain = {
              description = "A string value that specifies the preferred certificate chain to use when generating certificates.",
              type = "string",
            },
          },
          {
            enable_ipv4_common_name = {
              description = "A boolean value that controls whether to include the IPv4 address in the common name field of generated certificates.",
              type = "boolean",
              default = true,
            },
          },
        },
      },
    },
  },
  entity_checks = {
    {
      conditional = {
        if_field = "config.api_uri",
        if_match = {
          one_of = {
            "https://acme-v02.api.letsencrypt.org",
            "https://acme-staging-v02.api.letsencrypt.org",
          }
        },
        then_field = "config.tos_accepted",
        then_match = { eq = true },
        then_err = "terms of service must be accepted, see https://letsencrypt.org/repository/",
      }
    },
    { conditional = {
      if_field = "config.storage", if_match = { eq = "redis" },
      then_field = "config.storage_config.redis.host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.storage", if_match = { eq = "redis" },
      then_field = "config.storage_config.redis.port", then_match = { required = true },
    } },
    {
      custom_entity_check = {
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
      }
    },
  },
}

return schema
