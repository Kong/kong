return {
  { name = "core", namespace = "kong.db.migrations.core", },
  { name = "*plugins", namespace = "kong.plugins.*.migrations", name_pattern = "%s" },
}
