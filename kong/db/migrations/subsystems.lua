return {
  { name = "core", namespace = "kong.db.migrations.core", },
  { name = "*plugins", namespace = "kong.plugins.*.migrations", name_pattern = "%s" },
  { name = "enterprise", namespace = "kong.enterprise_edition.db.migrations.enterprise", },
  { name = "*enterprise.plugins", namespace = "kong.plugins.*.migrations.enterprise", name_pattern = "enterprise.%s" },
}
