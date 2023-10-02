-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- This file is meant to be overwritten during the kong-distributions
-- process. Returning an empty 2 level dictionary to comply with the
-- interface.

-- Commented out. Check kong-distributions / dist_constants
local constants = {
  featureset = {
    full = {
      conf = {},
    },
    full_expired = {
      conf = {},
    },
    free = {
      conf = {
        -- enforce_rbac = "off",
        -- rbac = "off",
        -- vitals = false,
        -- anonymous_reports = true,
      },
      -- -- Granular allow.
      -- allow_admin_api = {
      --   -- ie: this only allows GET /workspaces
      --   ["/workspaces"] = { GET = true },
      --   -- and GET /workspaces/:workspaces
      --   ["/workspaces/:workspaces"] = { GET = true },
      --   -- A route not specified here is left untouched
      -- },
      -- deny_admin_api = {
      --   -- deny any method. We could just deny here any "write" method
      --   -- instead, but using allow + deny seems more explicit
      --   ["/workspaces"] = { ["*"] = true },
      --   ["/workspaces/:workspaces"] = { ["*"] = true },
      -- },
      -- -- deny a particular entity (and related api methods)
      -- deny_entity = { ["some_entity_name"] = true },
      -- -- disable EE plugins, does not apply on data_plane
      -- allow_ee_entity = { READ = false, WRITE = false },
      -- disabled_ee_entities = {},
    },
  },

  plugins = {
    "application-registration"
  },

  release = false,
}

return setmetatable(constants, {__index = function() return {} end })
