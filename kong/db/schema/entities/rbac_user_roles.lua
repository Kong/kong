local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_user_roles",
  generate_admin_api = false,
  primary_key = { "user_id", "role_id" },
  -- cache_key = { "user_id" }, -- XXX EE How was this supposed to work?
  fields = {
    {user_id = typedefs.uuid },
    {role_id = typedefs.uuid },
    -- { user_id = {type = "foreign", required = true, reference = "rbac_users", on_delete = "cascade"} }, -- XXX EE
    -- { role_id = {type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade"} }, -- XXX EE
  }
}
