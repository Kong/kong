return {
  table = "consumers_rbac_users_map",
  primary_key = { "consumer_id", "user_id" },
  cache_key = { "user_id" },
  fields = {
    consumer_id = { type = "id", foreign = "consumers:id" },
    user_id = { type = "id", foreign = "rbac_users:id" },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  },
}
