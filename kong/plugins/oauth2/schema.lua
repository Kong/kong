local typedefs = require "kong.db.schema.typedefs"

local function validate_flows(config)
  if config.enable_authorization_code
  or config.enable_implicit_grant
  or config.enable_client_credentials
  or config.enable_password_grant
  then
    return true
  end

  return nil, "at least one of these fields must be true: enable_authorization_code, enable_implicit_grant, enable_client_credentials, enable_password_grant"
end

return {
  name = "oauth2",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { scopes = { type = "array", elements = { type = "string" }, }, },
          { mandatory_scope = { type = "boolean", default = false, required = true }, },
          { provision_key = { type = "string", unique = true, auto = true, required = true }, },
          { token_expiration = { type = "number", default = 7200, required = true }, },
          { enable_authorization_code = { type = "boolean", default = false, required = true }, },
          { enable_implicit_grant = { type = "boolean", default = false, required = true }, },
          { enable_client_credentials = { type = "boolean", default = false, required = true }, },
          { enable_password_grant = { type = "boolean", default = false, required = true }, },
          { hide_credentials = { type = "boolean", default = false, required = true }, },
          { accept_http_if_already_terminated = { type = "boolean", default = false }, },
          { anonymous = { type = "string" }, },
          { global_credentials = { type = "boolean", default = false }, },
          { auth_header_name = { type = "string", default = "authorization" }, },
          { refresh_token_ttl = { type = "number", default = 1209600, required = true }, },
        },
        custom_validator = validate_flows,
        entity_checks = {
          { conditional = {
              if_field = "mandatory_scope",
              if_match = { eq = true },
              then_field = "scopes",
              then_match = { required = true },
          }, },
        },
      },
    },
  },
}


