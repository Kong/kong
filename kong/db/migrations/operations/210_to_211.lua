-- Helper module for 210_to_211 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.


local core_entities_to_clean = {
  { name = "upstreams", unique_keys = { "name" } },
  { name = "consumers", unique_keys = { "username", "custom_id" } },
  { name = "services",  unique_keys = { "name" }, partitioned = true, },
  { name = "routes",    unique_keys = { "name" }, partitioned = true, },
}


return {
  entities = core_entities_to_clean,
}
