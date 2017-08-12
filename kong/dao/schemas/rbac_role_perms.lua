return {
  table = "rbac_role_perms",
  primary_key = { "role_id", "perm_id" },
  cache_key = { "role_id" },
  fields = {
    role_id = {
      type = "id",
      required = true,
    },
    perm_id = {
      type = "id",
      required = true,
    },
  }
}
