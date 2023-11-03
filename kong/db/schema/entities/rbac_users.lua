-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local bcrypt = require "bcrypt"
local typedefs = require "kong.db.schema.typedefs"
local rbac = require "kong.rbac"
local secret = require "kong.plugins.oauth2.secret"
local Errors = require "kong.db.errors"
local constants = require "kong.constants"

local BCRYPT_COST_FACTOR = constants.RBAC.BCRYPT_COST_FACTOR

return {
  name = "rbac_users",
  dao = "kong.db.dao.rbac_users",
  generate_admin_api = false,
  admin_api_name = "rbac/users",
  primary_key = { "id" },
  endpoint_key = "name",
  workspaceable = true,
  db_export = false,
  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { name = { description = "The name of the user.", type = "string", required = true, unique = true } },
    { user_token = typedefs.rbac_user_token },
    { user_token_ident = { description = " The user token.", type = "string" } },
    { comment = { description = "Any comments associated with the user.", type = "string" } },
    { enabled = { description = "Wether or not the user has RBAC enabled.", type = "boolean", required = true, default = true } }
  },
  entity_checks = { {
    custom_entity_check = {
      field_sources = { "id", "user_token", },
      fn = function(entity)
        -- make sure the token doesn't start or end with a whitespace
        local token = entity.user_token:gsub("%s+", "")
        local token_ident = rbac.get_token_ident(token)

        -- first make sure it's not a duplicate
        local token_users, err = rbac.retrieve_token_users(token_ident, "user_token_ident")
        if err then
          return false, err
        end

        -- find the user associated with the token
        local user = rbac.validate_rbac_token(token_users, token)
        if user and entity.id ~= user.id then
          -- throw a unique violation error only if it is used by another user
          return false, Errors:unique_violation({ "user_token" })
        end

        return true
      end,
    }
  } },
  transformations = { {
    input = { "user_token" },
    on_write = function(user_token)
      -- make sure the token doesn't start or end with a whitespace
      local token = user_token:gsub("%s+", "")
      local token_ident = rbac.get_token_ident(token)

      if kong.configuration and kong.configuration.fips then
        if token and secret.needs_rehash(token) then
          local digest, hash_error = secret.hash(token)
          if hash_error then
            return nil, "error attempting to hash user token: " .. hash_error
          end

          return { user_token = digest, user_token_ident = token_ident }
        end
      else
        -- if it doesnt look like a bcrypt digest, rehash it
        if token and not string.find(token, "^%$2b%$") then
          local digest = bcrypt.digest(token, BCRYPT_COST_FACTOR)

          return { user_token = digest, user_token_ident = token_ident }
        end
      end

      return {}
    end,
  } }
}
