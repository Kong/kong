local typedefs = require "kong.db.schema.typedefs"
local rbac = require "kong.rbac"
local Errors = require "kong.db.errors"

local LOG_ROUNDS = 9

return {
  name = "rbac_users",
  generate_admin_api = false,
  primary_key = { "id" },
  endpoint_key = "name",
  cache_key = { "name" },
  workspaceable = true,
  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { name           = {type = "string", required = true, unique = true}},
    { user_token     = {type = "string", required = true, unique = true}},
    { user_token_ident = { type = "string"}},
    { comment = { type = "string"} },
    { enabled = { type = "boolean", required = true, default = true}}
  },

  check = function(user)
    local ident = rbac.get_token_ident(user.user_token)

    -- first make sure it's not a duplicate
    local token_users, err = rbac.retrieve_token_users(ident, "user_token_ident")
    if err then
      return nil, err
    end

    if rbac.validate_rbac_token(token_users, user.user_token) then
      return false, Errors:unique_violation({"user_token"})
    end

    -- if it doesnt look like a bcrypt digest, Do The Thing
    if user.user_token and not string.find(user.user_token, "^%$2b%$") then
      user.user_token_ident = ident

      local bcrypt = require "bcrypt"

      local digest = bcrypt.digest(user.user_token, LOG_ROUNDS)
      user.user_token = digest
    end

    return true
  end

}
