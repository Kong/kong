return {
    table = "label_mappings",
    primary_key = {"id"},
    cache_key = { "api_id", "consumer_id"},
    fields = {
      id = {
        type = "id", 
        dao_insert_value = true, 
        required = true
      },
      label_id = {
        type = "id",
        foreign = "labels:id"
      },
      api_id = {
        type = "id",
        foreign = "apis:id"
      },
      consumer_id = {
        type = "id",
        foreign = "consumers:id"
      },
      created_at = {
        type = "timestamp", 
        immutable = true, 
        dao_insert_value = true, 
        required = true
      },
    },
  }  