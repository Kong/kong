local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local openssl_pkey = require "openssl.pkey"

local SCHEMA = {
  primary_key = {"id"},
  table = "jwt_secrets",
  cache_key = { "key" },
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    consumer_id = { type = "id", required = true,
                    -- foreign = "consumers:id" -- manually tested in self_check
                  },
    key = {type = "string", unique = true, default = utils.random_string},
    secret = {type = "string", default = utils.random_string},
    rsa_public_key = {type = "string"},
    algorithm = {type = "string", enum = {"HS256", "RS256", "RS512", "ES256"}, default = 'HS256'}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if plugin_t.algorithm == "RS256" then
      if plugin_t.rsa_public_key == nil then
        return false, Errors.schema "no mandatory 'rsa_public_key'"
      elseif not pcall(openssl_pkey.new, plugin_t.rsa_public_key) then
        return false, Errors.schema "'rsa_public_key' format is invalid"
      end
    elseif plugin_t.algorithm == "RS512" then
      if plugin_t.rsa_public_key == nil then
        return false, Errors.schema "no mandatory 'rsa_public_key'"
      elseif not pcall(openssl_pkey.new, plugin_t.rsa_public_key) then
        return false, Errors.schema "'rsa_public_key' format is invalid"
      end
    end

    local consumer_id = plugin_t.consumer_id
    if consumer_id ~= nil then
      local ok, err = dao.db.new_db.consumers:check_foreign_key({ id = consumer_id },
                                                                "Consumer")
      if not ok then
        return false, err
      end
    end

    return true
  end,
}

return {jwt_secrets = SCHEMA}
