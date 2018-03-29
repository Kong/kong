local utils = require "kong.tools.utils"
local url = require "socket.url"
local Errors = require "kong.dao.errors"
local db_errors = require "kong.db.errors"


local function validate_uris(v, t, column)
  if v then
    if #v < 1 then
      return false, "at least one URI is required"
    end
    for _, uri in ipairs(v) do
      local parsed_uri = url.parse(uri)
      if not (parsed_uri and parsed_uri.host and parsed_uri.scheme) then
        return false, "cannot parse '" .. uri .. "'"
      end
      if parsed_uri.fragment ~= nil then
        return false, "fragment not allowed in '" .. uri .. "'"
      end
    end
  end
  return true, nil
end


local function validate_service_id(service_id, db)

  if service_id ~= nil then
    local service, err, err_t = db.services:select({
      id = service_id,
    })
    if err then
      if err_t.code == db_errors.codes.DATABASE_ERROR then
        return false, Errors.db(err)
      end

      return false, Errors.schema(err_t)
    end

    if not service then
      return false, Errors.foreign("no such Service (id=" .. service_id .. ")")
    end
  end
end


local OAUTH2_CREDENTIALS_SCHEMA = {
  primary_key = {"id"},
  table = "oauth2_credentials",
  cache_key = { "client_id" },
  fields = {
    id = { type = "id", dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    name = { type = "string", required = true },
    client_id = { type = "string", required = false, unique = true, default = utils.random_string },
    client_secret = { type = "string", required = false, default = utils.random_string },
    redirect_uri = { type = "array", required = true, func = validate_uris },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  },
}

local OAUTH2_AUTHORIZATION_CODES_SCHEMA = {
  primary_key = {"id"},
  table = "oauth2_authorization_codes",
  fields = {
    id = { type = "id", dao_insert_value = true },
    service_id = { type = "id" }, --foreign = "services:id" -- manually tested in self_check
    api_id = { type = "id", required = false, foreign = "apis:id" },
    credential_id = { type = "id", required = true, foreign = "oauth2_credentials:id" },
    code = { type = "string", required = false, unique = true, immutable = true, default = utils.random_string },
    authenticated_userid = { type = "string", required = false },
    scope = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  },
  self_check = function(self, auth_t, dao, is_update)
    return validate_service_id(auth_t.service_id, dao.db.new_db)
  end,
}

local BEARER = "bearer"
local OAUTH2_TOKENS_SCHEMA = {
  primary_key = {"id"},
  table = "oauth2_tokens",
  cache_key = { "access_token" },
  fields = {
    id = { type = "id", dao_insert_value = true },
    service_id = { type = "id" }, --foreign = "services:id" -- manually tested in self_check
    api_id = { type = "id", required = false, foreign = "apis:id" },
    credential_id = { type = "id", required = true, foreign = "oauth2_credentials:id" },
    token_type = { type = "string", required = true, enum = { BEARER }, default = BEARER },
    expires_in = { type = "number", required = true },
    access_token = { type = "string", required = false, unique = true, default = utils.random_string },
    refresh_token = { type = "string", required = false, unique = true },
    authenticated_userid = { type = "string", required = false },
    scope = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  },
  self_check = function(self, token_t, dao, is_update)
    return validate_service_id(token_t.service_id, dao.db.new_db)
  end,
}

return {
  oauth2_credentials = OAUTH2_CREDENTIALS_SCHEMA,
  oauth2_authorization_codes = OAUTH2_AUTHORIZATION_CODES_SCHEMA,
  oauth2_tokens = OAUTH2_TOKENS_SCHEMA
}
