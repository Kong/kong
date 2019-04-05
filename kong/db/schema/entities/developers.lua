local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local lpeg = require "lpeg"
local lp_email = require "lpeg_patterns.email"

local EOF = lpeg.P(-1)
local email_validator_pattern = lp_email.email_nocfws * EOF


local email = Schema.define {
  type = "string",
  required = true,
  unique = true,
  custom_validator = function(s)
    local has_match = email_validator_pattern:match(s)
    if not has_match then
      return nil, "invalid email address " .. s
    end
    return true
  end
}


local developer_status = Schema.define { type = "integer", between = { 0, 4 }, default = 4 }


return {
  name         = "developers",
  primary_key  = { "id" },
  endpoint_key = "email",
  workspaceable = true,
  dao          = "kong.db.dao.developers",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { email          = email },
    { status         = developer_status },
    { consumer       = { type = "foreign", reference = "consumers", }, },
    { meta           = { type = "string" }, },
  },
} 

