local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local crypto = require "crypto"

local SCHEMA = {
  primary_key = {"id"},
  table = "jwt_secrets",
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = {type = "id", required = true, foreign = "consumers:id"},
    key = {type = "string", unique = true, default = utils.random_string},
    secret = {type = "string", unique = true, default = utils.random_string},
    rsa_public_key = {type = "string"},
    algorithm = {type = "string", enum = {"HS256", "RS256", "ES256"}, default = 'HS256'}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if plugin_t.algorithm == "RS256" and plugin_t.rsa_public_key == nil then
      return false, Errors.schema "no mandatory 'rsa_public_key'"
    end
    if plugin_t.algorithm == "RS256" and crypto.pkey.from_pem(plugin_t.rsa_public_key) == nil then
      return false, Errors.schema "'rsa_public_key' format is invalid"
    end
    return true
  end,
  marshall_event = function(self, t)
    return {id = t.id, consumer_id = t.consumer_id, key = t.key}
  end
}

return {jwt_secrets = SCHEMA}
