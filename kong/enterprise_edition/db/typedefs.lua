local Schema = require "kong.db.schema"
local lpeg = require "lpeg"
local lp_email = require "lpeg_patterns.email"

local EOF = lpeg.P(-1)
local email_validator_pattern = lp_email.email_nocfws * EOF

local email = Schema.define { type = "string", custom_validator = function(s)
    local has_match = email_validator_pattern:match(s)
    if not has_match then
      return nil, "invalid email address " .. s
    end
    return true
  end
}

return {
  email = email,
}
