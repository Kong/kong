local typedefs = require "kong.db.schema.typedefs"


return {
  name = "audit_objects",
  primary_key = { "id" },
  generate_admin_api = false,
  workspaceable = false,
  ttl = true,

  fields = {
    { id = typedefs.uuid { required = true } },
    { request_id = {
      type = "string"
    }},
    { entity_key = {
      type = "string",
      uuid = true,
    }},
    { dao_name = {
      type = "string",
      required = true,
    }},
    { operation = {
      type = "string",
      one_of = { "create", "update", "delete" },
      required = true,
    }},
    { entity = {
      type = "string",
    }},
    { rbac_user_id = {
      type = "string",
      uuid = true,
    }},
    { signature = {
      type = "string",
    }},
  },
}
