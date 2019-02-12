return {
  name = "rbac_user_roles",
  primary_key = { "user_id", "role_id" },
  cache_key = { "user_id" },
  fields = {
    { user_id = {type = "id", required = true,} },
    { role_id = {type = "id", required = true,} },
  }
}
