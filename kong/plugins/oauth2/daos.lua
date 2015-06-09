local utils = require "kong.tools.utils"
local stringy = require "stringy"
local BaseDao = require "kong.dao.cassandra.base_dao"

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, { [column] = utils.random_string()}
  end
  return true
end

local OAuth2Credentials = BaseDao:extend()
function OAuth2Credentials:new(properties)
  self._schema = {
    id = { type = "id" },
    consumer_id = { type = "id", required = true, foreign = true, queryable = true },
    name = { type = "string", required = true },
    client_id = { type = "string", required = false, unique = true, queryable = true, func = generate_if_missing },
    client_secret = { type = "string", required = false, unique = true, func = generate_if_missing },
    redirect_uri = { type = "url", required = true },
    created_at = { type = "timestamp" }
  }

  self._queries = {
    insert = {
      args_keys = { "id", "consumer_id", "name", "client_id", "client_secret", "redirect_uri", "created_at" },
      query = [[
        INSERT INTO oauth2_credentials(id, consumer_id, name, client_id, client_secret, redirect_uri, created_at)
          VALUES(?, ?, ?, ?, ?, ?, ?);
      ]]
    },
    update = {
      args_keys = { "name", "created_at", "id" },
      query = [[ UPDATE oauth2_credentials SET name = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM oauth2_credentials %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM oauth2_credentials WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM oauth2_credentials WHERE id = ?; ]]
    },
    __foreign = {
      consumer_id = {
        args_keys = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      client_id = {
        args_keys = { "client_id" },
        query = [[ SELECT id FROM oauth2_credentials WHERE client_id = ?; ]]
      },
      client_secret = {
        args_keys = { "client_id" },
        query = [[ SELECT id FROM oauth2_credentials WHERE client_secret = ?; ]]
      }
    },
    drop = "TRUNCATE oauth2_credentials;"
  }

  OAuth2Credentials.super.new(self, properties)
end

local OAuth2AuthorizationCodes = BaseDao:extend()
function OAuth2AuthorizationCodes:new(properties)
  self._schema = {
    id = { type = "id" },
    code = { type = "string", required = false, unique = true, queryable = true, immutable = true, func = generate_if_missing },
    authenticated_username = { type = "string", required = false },
    authenticated_userid = { type = "string", required = false },
    scope = { type = "string" },
    created_at = { type = "timestamp" }
  }

  self._queries = {
    insert = {
      args_keys = { "id", "code", "authenticated_username", "authenticated_userid", "scope", "created_at" },
      query = [[
        INSERT INTO oauth2_authorization_codes(id, code, authenticated_username, authenticated_userid, scope, created_at)
          VALUES(?, ?, ?, ?, ?, ?);
      ]]
    },
    update = {
      -- Disable update
    },
    select = {
      query = [[ SELECT * FROM oauth2_authorization_codes %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM oauth2_authorization_codes WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM oauth2_authorization_codes WHERE id = ?; ]]
    },
    __foreign = {},
    __unique = {
      code = {
        args_keys = { "code" },
        query = [[ SELECT id FROM oauth2_authorization_codes WHERE code = ?; ]]
      }
    },
    drop = "TRUNCATE oauth2_authorization_codes;"
  }

  OAuth2AuthorizationCodes.super.new(self, properties)
end

local BEARER = "bearer"

local OAuth2Tokens = BaseDao:extend()
function OAuth2Tokens:new(properties)
  self._schema = {
    id = { type = "id" },
    credential_id = { type = "id", required = true, foreign = true, queryable = true },
    token_type = { type = "string", required = true, enum = { BEARER }, default = BEARER },
    access_token = { type = "string", required = false, unique = true, queryable = true, immutable = true, func = generate_if_missing },
    refresh_token = { type = "string", required = false, unique = true, queryable = true, immutable = true, func = generate_if_missing },
    expires_in = { type = "number", required = true },
    authenticated_username = { type = "string", required = false },
    authenticated_userid = { type = "string", required = false },
    scope = { type = "string" },
    created_at = { type = "timestamp" }
  }

  self._queries = {
    insert = {
      args_keys = { "id", "credential_id", "token_type", "access_token", "refresh_token", "expires_in", "authenticated_username", "authenticated_userid", "scope", "created_at" },
      query = [[
        INSERT INTO oauth2_tokens(id, credential_id, token_type, access_token, refresh_token, expires_in, authenticated_username, authenticated_userid, scope, created_at)
          VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ]]
    },
    update = { 
      -- Disable update
    },
    select = {
      query = [[ SELECT * FROM oauth2_tokens %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM oauth2_tokens WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM oauth2_tokens WHERE id = ?; ]]
    },
    __foreign = {
      credential_id = {
        args_keys = { "credential_id" },
        query = [[ SELECT id FROM oauth2_credentials WHERE id = ?; ]]
      }
    },
    __unique = {
      access_token = {
        args_keys = { "access_token" },
        query = [[ SELECT id FROM oauth2_tokens WHERE access_token = ?; ]]
      },
      refresh_token = {
        args_keys = { "access_token" },
        query = [[ SELECT id FROM oauth2_tokens WHERE refresh_token = ?; ]]
      }
    },
    drop = "TRUNCATE oauth2_tokens;"
  }

  OAuth2Tokens.super.new(self, properties)
end

return { oauth2_credentials = OAuth2Credentials, oauth2_authorization_codes = OAuth2AuthorizationCodes, oauth2_tokens = OAuth2Tokens }
