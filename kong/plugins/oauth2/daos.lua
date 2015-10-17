local utils = require "kong.tools.utils"
local stringy = require "stringy"
local BaseDao = require "kong.dao.cassandra.base_dao"

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, { [column] = utils.random_string()}
  end
  return true
end

local function generate_refresh_token(v, t, column)
  if t.expires_in and t.expires_in > 0 then
    return generate_if_missing(v, t, column)
  end
  return true
end

local OAUTH2_CREDENTIALS_SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    consumer_id = { type = "id", required = true, queryable = true, foreign = "consumers:id" },
    name = { type = "string", required = true },
    client_id = { type = "string", required = false, unique = true, queryable = true, func = generate_if_missing },
    client_secret = { type = "string", required = false, unique = true, func = generate_if_missing },
    redirect_uri = { type = "url", required = true },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  },
  marshall_event = function(self, t)
    return { id = t.id, consumer_id = t.consumer_id, client_id = t.client_id }
  end
}

local OAUTH2_AUTHORIZATION_CODES_SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    code = { type = "string", required = false, unique = true, queryable = true, immutable = true, func = generate_if_missing },
    authenticated_userid = { type = "string", required = false, queryable = true },
    scope = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  }
}

local BEARER = "bearer"
local OAUTH2_TOKENS_SCHEMA = {
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    credential_id = { type = "id", required = true, queryable = true, foreign = "oauth2_credentials:id" },
    token_type = { type = "string", required = true, enum = { BEARER }, default = BEARER },
    expires_in = { type = "number", required = true },
    access_token = { type = "string", required = false, unique = true, queryable = true, func = generate_if_missing },
    refresh_token = { type = "string", required = false, unique = true, queryable = true, func = generate_refresh_token },
    authenticated_userid = { type = "string", required = false, queryable = true },
    scope = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true }
  },
  marshall_event = function(self, t)
    return { id = t.id, credential_id = t.credential_id, access_token = t.access_token }
  end
}

local OAuth2Credentials = BaseDao:extend()
function OAuth2Credentials:new(properties, events_handler)
  self._table = "oauth2_credentials"
  self._schema = OAUTH2_CREDENTIALS_SCHEMA

  OAuth2Credentials.super.new(self, properties, events_handler)
end

local OAuth2AuthorizationCodes = BaseDao:extend()
function OAuth2AuthorizationCodes:new(properties, events_handler)
  self._table = "oauth2_authorization_codes"
  self._schema = OAUTH2_AUTHORIZATION_CODES_SCHEMA

  OAuth2AuthorizationCodes.super.new(self, properties, events_handler)
end

local OAuth2Tokens = BaseDao:extend()
function OAuth2Tokens:new(properties, events_handler)
  self._table = "oauth2_tokens"
  self._schema = OAUTH2_TOKENS_SCHEMA

  OAuth2Tokens.super.new(self, properties, events_handler)
end

return { oauth2_credentials = OAuth2Credentials, oauth2_authorization_codes = OAuth2AuthorizationCodes, oauth2_tokens = OAuth2Tokens }
