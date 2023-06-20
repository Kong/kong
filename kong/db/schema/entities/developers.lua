-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local lpeg = require "lpeg"
local lp_email = require "lpeg_patterns.email"

local EOF = lpeg.P(-1)
local email_validator_pattern = lp_email.email_nocfws * EOF


local email = Schema.define {
  type = "string",
  required = true,
  description = "The email address of the developer.",
  unique = true,
  custom_validator = function(s)
    local has_match = email_validator_pattern:match(s)
    if not has_match then
      return nil, "invalid email address " .. s
    end
    return true
  end
}


local developer_status = Schema.define { description = "The status of the developer.", type = "integer", between = { 0, 5 }, default = 5 }


return {
  name          = "developers",
  primary_key   = { "id" },
  cache_key     = { "email" },
  endpoint_key  = "email",
  dao           = "kong.db.dao.developers",
  workspaceable = true,
  db_export = true,

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { email          = email },
    { status         = developer_status },
    { custom_id = { description = "A custom identifier for the developer.", type = "string", unique = true } },
    { consumer = { description = "The consumer associated with the developer.", type = "foreign", reference = "consumers" } },
    { meta = { description = "Additional metadata for the developer.", type = "string" } },
    { rbac_user = { description = "The RBAC user associated with the developer.", type = "foreign", reference = "rbac_users" } },
  },
}
