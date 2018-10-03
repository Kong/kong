return {
  table = "audit_objects",
  primary_key = { "id" },
  workspaceable = false,
  fields = {
    id = {
      type = "id",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    request_id = {
      type = "string",
      immutable = true,
    },
    entity_key = {
      type = "id",
      immutable = true,
    },
    dao_name = {
      type = "string",
      required = true,
      immutable = true,
    },
    operation = {
      type = "string",
      enum = { "create", "update", "delete" },
      immutable = true,
      required = true,
    },
    entity = {
      type = "string",
      immutable = true,
    },
    rbac_user_id = {
      type = "id",
      immutable = true,
    },
    signature = {
      type = "string",
      immutable = true,
    },
    expire = {
      type = "timestamp",
      immutable = true,
    },
  },
}
