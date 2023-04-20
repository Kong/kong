-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local c = {}

c.plugins = {
}

c.featureset = {
  full = {
    conf = {},
  },
  full_expired = {
    conf = {},
    write_admin_api = false,
    allow_admin_api = {
      ["/licenses"] = { ["*"] = true },
    }
  },
  free = {
    conf = {
      enforce_rbac = "off",
      -- XXX need to keep this alias to enforce_rbac
      rbac = "off",
      vitals = false,
      anonymous_reports = true,
      portal = false,
      event_hooks_enabled = false,
      -- NOOP (unset it)
      admin_gui_auth = function() end,
    },
    allow_admin_api = {
      -- Allow these granularly
      ["/workspaces"] = { GET = true, OPTIONS = true },
      ["/workspaces/:workspaces"] = { GET = true, OPTIONS = true },
    },
    deny_admin_api = {
      -- Deny any other
      ["/workspaces"] = { ["*"] = true },
      ["/workspaces/:workspaces"] = { ["*"] = true },
      ["/event-hooks"] = { ["*"] = true },
      ["/event-hooks/:event_hooks"] = { ["*"] = true },
      ["/event-hooks/:event_hooks/test"] = { ["*"] = true },
      ["/event-hooks/:event_hooks/ping"] = { ["*"] = true },
      ["/event-hooks/sources"] = { ["*"] = true },
      ["/event-hooks/sources/:source"] = { ["*"] = true },
      ["/event-hooks/sources/:source/:event"] = { ["*"] = true },
      ["/consumer_groups"] = { ["*"] = true },
      ["/consumer_groups/:consumer_groups"] = { ["*"] = true },
      ["/consumer_groups/:consumer_groups/consumers"] = { ["*"] = true },
      ["/consumer_groups/:consumer_groups/consumers/:consumers"] = { ["*"] = true },
      ["/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced"] = { ["*"] = true },
      ["/consumers/:consumers/consumer_groups"] = { ["*"] = true },
      ["/consumers/:consumers/consumer_groups/:consumer_groups"] = { ["*"] = true },

    },
    -- deny a particular entity (and related api methods)
    -- deny_entity = { ["some_entity_name"] = true },
    -- disable running of enterprise plugins
    ee_plugins = false,
  }
}

-- This is a flag is being used to indicate a generated release
c.release = false

return setmetatable(c, {__index = function() return {} end })
