local url = require "socket.url"
local typedefs = require "kong.db.schema.typedefs"


local function validate_uri(uri)
  local parsed_uri = url.parse(uri)
  if not (parsed_uri and parsed_uri.host and parsed_uri.scheme) then
    return nil, "cannot parse '" .. uri .. "'"
  end
  if parsed_uri.fragment ~= nil then
    return nil, "fragment not allowed in '" .. uri .. "'"
  end

  return true
end


local oauth2_credentials = {
  primary_key = { "id" },
  name = "oauth2_credentials",
  cache_key = { "client_id" },
  endpoint_key = "client_id",
  admin_api_name = "oauth2",
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade", }, },
    { name = { type = "string", required = true }, },
    { client_id = { type = "string", required = false, unique = true, auto = true }, },
    { client_secret = { type = "string", required = false, auto = true }, },
    { redirect_uris = {
      type = "array",
      required = false,
      elements = {
        type = "string",
        custom_validator = validate_uri,
    }, }, },
    { tags = typedefs.tags },
  },
}


local oauth2_authorization_codes = {
  primary_key = { "id" },
  name = "oauth2_authorization_codes",
  ttl = true,
  generate_admin_api = false,
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { service = { type = "foreign", reference = "services", default = ngx.null, on_delete = "cascade", }, },
    { credential = { type = "foreign", reference = "oauth2_credentials", required = true, on_delete = "cascade", }, },
    { code = { type = "string", required = false, unique = true, auto = true }, }, -- FIXME immutable
    { authenticated_userid = { type = "string", required = false }, },
    { scope = { type = "string" }, },
  },
}


local BEARER = "bearer"
local oauth2_tokens = {
  primary_key = { "id" },
  name = "oauth2_tokens",
  endpoint_key = "access_token",
  cache_key = { "access_token" },
  dao = "kong.plugins.oauth2.daos.oauth2_tokens",
  ttl = true,
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { service = { type = "foreign", reference = "services", default = ngx.null, on_delete = "cascade", }, },
    { credential = { type = "foreign", reference = "oauth2_credentials", required = true, on_delete = "cascade", }, },
    { token_type = { type = "string", required = true, one_of = { BEARER }, default = BEARER }, },
    { expires_in = { type = "integer", required = true }, },
    { access_token = { type = "string", required = false, unique = true, auto = true }, },
    { refresh_token = { type = "string", required = false, unique = true }, },
    { authenticated_userid = { type = "string", required = false }, },
    { scope = { type = "string" }, },
  },
}

return {
  oauth2_credentials,
  oauth2_authorization_codes,
  oauth2_tokens,
}
