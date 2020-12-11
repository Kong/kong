-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- This file is ment to be overwritten during the kong-distributions
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
        -- enforce_rbac = "off",
        -- vitals = "off",
        -- anonymous_reports = "on",
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
  }
}
return setmetatable(constants, {__index = function() return {} end })
