local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_user_roles",
  primary_key = { "user_id", "role_id" },
  -- cache_key = { "user_id" }, -- How was this supposed to work?
  fields = {
    {user_id = typedefs.uuid},
    {role_id = typedefs.uuid},
    -- { user_id = {type = "foreign", required = true, reference = "rbac_users", on_delete = "cascade"} },
    -- { role_id = {type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade"} },
  }
}
