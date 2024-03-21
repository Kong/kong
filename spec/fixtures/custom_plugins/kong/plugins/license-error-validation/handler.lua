-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Plugin =  {
  VERSION = "1.0.0",
  PRIORITY = 1000,
}

local license_utils = require "kong.enterprise_edition.license_utils"
local saved_validate_kong_license = license_utils.validate_kong_license

-- monkey-patch license_utils so that we return custom license validation error
license_utils.validate_kong_license = function(...)
  local fh = io.open(kong.configuration.prefix .. "/license-error-validation")
  if fh then
    local content = fh:read("*a") or "oh no!"
    fh:close()
    ngx.log(ngx.WARN, "Using development (e.g. not a release) license validation: ", content)
    return content
  end

  return saved_validate_kong_license(...)
end

return Plugin
