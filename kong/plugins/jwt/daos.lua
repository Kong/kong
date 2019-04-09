local typedefs = require "kong.db.schema.typedefs"
local openssl_pkey = require "openssl.pkey"


local function validate_ssl_key(key)
  if not pcall(openssl_pkey.new, key) then
    return nil, "invalid key"
  end
  return true
end


return {
  jwt_secrets = {
    name = "jwt_secrets",
    primary_key = { "id" },
    cache_key = { "key" },
    endpoint_key = "key",
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", default = ngx.null, on_delete = "cascade", }, },
      { key = { type = "string", required = false, unique = true, auto = true }, },
      { secret = { type = "string", auto = true }, },
      { rsa_public_key = { type = "string" }, },
      { algorithm = {
          type    = "string",
          default = "HS256",
          one_of  = {
            "HS256",
            "HS384",
            "HS512",
            "RS256",
            "RS512",
            "ES256",
          },
      }, },
    },
    entity_checks = {
      { conditional = { if_field = "algorithm",
                        if_match = {
                          match_any = { patterns = { "^RS256$", "^RS512$" }, },
                        },
                        then_field = "rsa_public_key",
                        then_match = {
                          required = true,
                          custom_validator = validate_ssl_key,
                        },
                      },
      },
    },
  },
}
