-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "audit_objects",
  primary_key = { "id" },
  generate_admin_api = false,
  admin_api_name = "audit/objects",
  workspaceable = false,
  ttl = true,
  db_export = false,

  fields = {
    { id = typedefs.uuid { required = true } },
    { request_id = {
      description = "The ID of the request associated with the audit object.",
      type = "string"
    }},
    { entity_key = {
      description = "The key of the entity associated with the audit object.",
      type = "string",
      uuid = true,
    }},
    { dao_name = {
      description = "The name of the DAO (Data Access Object) associated with the audit object.",
      type = "string",
      required = true,
    }},
    { operation = {
      description = "The operation performed on the entity ('create', 'update', or 'delete').",
      type = "string",
      one_of = { "create", "update", "delete" },
      required = true,
    }},
    { entity = {
      description = "The entity associated with the audit object.",
      type = "string",
    }},
    { removed_from_entity = {
      description = "The data that was removed from the entity.",
      type = "string",
    }},
    { rbac_user_id = {
      description = "The ID of the RBAC (Role-Based Access Control) user associated with the audit object.",
      type = "string",
      uuid = true,
    }},
    { signature = {
      description = "The signature associated with the audit object.",
      type = "string",
    }},
  },
}
