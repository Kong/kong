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
      description = "The ID of the audit request.",
      type = "string",
    }},
    { request_source = {
      description = "The source of the audit request.",
      type = "string"
    }},
    { request_timestamp = typedefs.auto_timestamp_s { indexed = true } },
    { client_ip = {
      description = "The IP address of the client making the request.",
      type = "string",
      required = true,
    }},
    { path = {
      description = "The path of the requested resource.",
      type = "string",
      required = true,
    }},
    { method = {
      description = "The HTTP method of the request.",
      type = "string",
      required = true,
    }},
    { payload = {
      description = "The payload of the request.",
      type = "string",
    }},
    { removed_from_payload = {
      description = "The removed data from the payload.",
      type = "string",
    }},
    { status = {
      description = "The status code of the request.",
      type = "integer",
      required = true,
    }},
    { rbac_user_id = {
      description = "The ID of the RBAC (Role-Based Access Control) user associated with the request.",
      type = "string",
      uuid = true,
    }},
    { rbac_user_name = {
      description = "The name of the RBAC user associated with the request.",
      type = "string"
    }},
    { workspace = {
      description = "The ID of the workspace associated with the request.",
      type = "string",
      uuid = true
    }},
    { signature = {
      description = "The signature associated with the request.",
      type = "string",
    }},
  },
}
