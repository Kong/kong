local utils = require "kong.tools.utils"

return {
  table = "rbac_users",
  primary_key = { "id" },
  cache_key = { "user_token" },
  workspaceable = true,
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    name = {
      type = "string",
      required = true,
      unique = true,
    },
    user_token = {
      type = "string",
      required = true,
      unique = true,
      default = utils.random_string,
    },
    comment = {
      type = "string",
    },
    enabled = {
      type = "boolean",
      required = true,
      default = true,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  }
}
