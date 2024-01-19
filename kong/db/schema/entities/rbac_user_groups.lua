-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  name = "rbac_user_groups",
  generate_admin_api = false,
  primary_key = { "user", "group" },
  db_export = false,
  fields = {
    { user = { description = "The RBAC user associated with the group.", type = "foreign", required = true, reference = "rbac_users", on_delete = "cascade" } },
    { group = { description = "The group assigned to the user.", type = "foreign", required = true, reference = "groups", on_delete = "cascade" } },
  }
}
