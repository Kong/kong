return {
  table = "audit_requests",
  primary_key = { "request_id" },
  workspaceable = false,
  fields = {
    request_id = {
      type = "string",
      required = true,
      immutable = true,
    },
    request_timestamp = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    client_ip = {
      type = "string",
      required = true,
      immutable = true,
    },
    path = {
      type = "string",
      required = true,
      immutable = true,
    },
    method = {
      type = "string",
      required = true,
      immutable = true,
    },
    payload = {
      type = "string",
      immutable = true,
    },
    status = {
      type = "number",
      required = true,
      immutable = true,
    },
    rbac_user_id = {
      type = "id",
      immutable = true,
    },
    workspace = {
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
