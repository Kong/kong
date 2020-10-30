-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "audit_requests",
  primary_key = { "request_id" },
  generate_admin_api = false,
  admin_api_name = "audit/requests",
  workspaceable = false,
  ttl = true,
  db_export = false,

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
    { removed_from_payload = {
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
