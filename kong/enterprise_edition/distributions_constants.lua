-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- This file is meant to be overwritten during the kong-distributions
-- process. Returning an empty 2 level dictionary to comply with the
-- interface.

local constants = {
  featureset = {
    full = {
      conf = {},
      abilities = {
      },
    },
    full_expired = {
      conf = {},
      abilities = {
        -- write_admin_api = false,
      },
    },
    free = {
      conf = {
        -- enforce_rbac = false,
        -- vitals = false,
        -- anonymous_reports = true,
      },
      abilities = {
        -- Granular allow.
        allow_admin_api = {
          -- -- ie: this only allows GET /workspaces
          -- ["/workspaces"] = { GET = true },
          -- -- and GET /workspaces/:workspaces
          -- ["/workspaces/:workspaces"] = { GET = true },
          -- -- A route not specified here is left untouched
        },
        deny_admin_api = {
          -- -- deny any method. We could just deny here any "write" method
          -- -- instead, but using allow + deny seems more explicit
          -- ["/workspaces"] = { ["*"] = true },
          -- ["/workspaces/:workspaces"] = { ["*"] = true },
        },
        ee_plugins = false
      }
    },
  },

  --[[
    This is only being used for local development and uses the real FFI
    function call when built with kong-distributions. It can be used to
    simulate different errors during testing by naming the variable name being
    passed in the appropriate key. If there is not match, then the returned
    value is always ERROR_VALIDATION_PASS.
  ]]
  validate_kong_license = function(license)
    local invalid_errors = {
      ["no_error"] = "ERROR_NO_ERROR", -- 0
      ["license_path_not_set"] = "ERROR_LICENSE_PATH_NOT_SET", -- 1
      ["internal_error"] = "ERROR_INTERNAL_ERROR", -- 2
      ["open_license_file"] = "ERROR_OPEN_LICENSE_FILE", -- 3
      ["read_license_file"] = "ERROR_READ_LICENSE_FILE", -- 4
      ["invalid_license_json"] = "ERROR_INVALID_LICENSE_JSON", -- 5
      ["invalid_license_format"] = "ERROR_INVALID_LICENSE_FORMAT", -- 6
      ["validation_fail"] = "ERROR_VALIDATION_FAIL", -- 8
      ["license_expired"] = "ERROR_LICENSE_EXPIRED", -- 9
      ["invalid_expiration_date"] = "ERROR_INVALID_EXPIRATION_DATE", -- 10
      ["grace_period"] = "ERROR_GRACE_PERIOD", -- 11
    }

    local passed_in_variable_name = debug.getlocal(2, 1)
    for key, value in pairs(invalid_errors) do
      if key == passed_in_variable_name then
        return value
      end
    end

    return "ERROR_VALIDATION_PASS" -- 7
  end
}
return setmetatable(constants, {__index = function() return {} end })
