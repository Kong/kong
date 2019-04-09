local Schema = require "kong.db.schema"
local lpeg = require "lpeg"
local lp_email = require "lpeg_patterns.email"
local enums = require "kong.enterprise_edition.dao.enums"

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

local function one_of_ee_user_status(status)
  if enums.CONSUMERS.STATUS_LABELS[status] then
    return true
  end

  return nil, "invalid ee_user_status value: " .. status
end

local function one_of_consumer_type(type)
  if enums.CONSUMERS.TYPE_LABELS[type] then
    return true
  end

  return nil, "invalid consumer_type value: " .. type
end

local ee_user_status = Schema.define {
  type = "integer",
  default = enums.CONSUMERS.STATUS.INVITED,
  custom_validator = one_of_ee_user_status,
}

local consumer_type = Schema.define {
  type = "integer",
  default = enums.CONSUMERS.TYPE.PROXY,
  custom_validator = one_of_consumer_type,
}

return {
  email = email,
  admin_status = ee_user_status,
  developer_status = ee_user_status,
  consumer_type = consumer_type,
}
