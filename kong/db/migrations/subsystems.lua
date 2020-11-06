-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  { name = "core", namespace = "kong.db.migrations.core", },
  { name = "*plugins", namespace = "kong.plugins.*.migrations", name_pattern = "%s" },
  { name = "enterprise", namespace = "kong.enterprise_edition.db.migrations.enterprise", },
  { name = "*enterprise.plugins", namespace = "kong.plugins.*.migrations.enterprise", name_pattern = "enterprise.%s" },
}
