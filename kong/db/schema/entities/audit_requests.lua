local typedefs = require "kong.db.schema.typedefs"


return {
  name = "audit_requests",
  primary_key = { "request_id" },
  generate_admin_api = false,
  workspaceable = false,
  ttl = true,

  fields = {
    { request_id = {
      type = "string",
    }},
    { request_timestamp = typedefs.auto_timestamp_s },
    { client_ip = {
      type = "string",
      required = true,
    }},
    { path = {
      type = "string",
      required = true,
    }},
    { method = {
      type = "string",
      required = true,
    }},
    { payload = {
      type = "string",
    }},
    { status = {
      type = "integer",
      required = true,
    }},
    { rbac_user_id = {
      type = "string",
      uuid = true,
    }},
    { workspace = {
      type = "string",
      uuid = true
    }},
    { signature = {
      type = "string",
    }},
  },
}
