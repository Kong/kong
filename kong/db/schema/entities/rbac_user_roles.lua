-- local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_user_roles",
  generate_admin_api = false,
  primary_key = { "user", "role" },
  -- cache_key = { "user", "role" }, -- XXX EE How was this supposed to work?
  fields = {
    { user = { type = "foreign", required = true, reference = "rbac_users", on_delete = "cascade" } },
    { role = { type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade" } },
  }
}
