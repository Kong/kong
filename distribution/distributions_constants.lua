-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local c = {}

c.plugins = {
  "application-registration", -- built-in in kong-ee
  "oauth2-introspection", -- built-in in kong-ee
  "proxy-cache-advanced", -- built-in in kong-ee
  "openid-connect",  -- built-in in kong-ee
  "forward-proxy", -- built-in in kong-ee
  "canary", -- built-in in kong-ee
  "request-transformer-advanced",  -- built-in in kong-ee
  "response-transformer-advanced",  -- built-in in kong-ee
  "rate-limiting-advanced",  -- built-in in kong-ee
  "ldap-auth-advanced",  -- built-in in kong-ee
  "statsd-advanced", -- built-in in kong-ee
  "route-by-header", -- built-in in kong-ee
  "jwt-signer",  -- built-in in kong-ee
  "vault-auth",  -- built-in in kong-ee
  "request-validator",  -- built-in in kong-ee
  "mtls-auth",  -- built-in in kong-ee
  "graphql-proxy-cache-advanced",  -- built-in in kong-ee
  "graphql-rate-limiting-advanced",  -- built-in in kong-ee
  "degraphql",  -- built-in in kong-ee
  "route-transformer-advanced",  -- built-in in kong-ee
  "kafka-log",  -- built-in in kong-ee
  "kafka-upstream",  -- built-in in kong-ee
  "exit-transformer",  -- built-in in kong-ee
  "key-auth-enc",  -- built-in in kong-ee
  "upstream-timeout",  -- built-in in kong-ee
  "mocking",  -- built-in in kong-ee
  "opa",  -- built-in in kong-ee
  "jq",  -- built-in in kong-ee
  "websocket-size-limit",  -- built-in in kong-ee
  "websocket-validator",  -- built-in in kong-ee
  "konnect-application-auth",  -- built-in in kong-ee
  "tls-handshake-modifier", -- built-in in kong-ee
  "tls-metadata-headers", -- built-in in kong-ee
  -- "app-dynamics",  -- built-in in kong-ee, not part of the 'bundled' set due to system-level configuration requirements
  "saml", -- built-in in kong-ee
  "xml-threat-protection", -- built-in in kong-ee
  "jwe-decrypt", -- built-in in kong-ee
  "oas-validation", -- built-in in kong-ee
}

c.featureset = {
  full = {
    conf = {},
  },
  full_expired = {
    conf = {},
    allow_admin_api = {
      ["/licenses"] = { ["*"] = true },
      ["/licenses/:licenses"] = { ["*"] = true },
    },
    allow_ee_entity = { READ = true, WRITE = false },
    disabled_ee_entities = {
      ["workspaces"] = true,
      ["event_hooks"] = true,
      ["consumer_groups"] = true,
      ["consumer_group_plugins"] = true,
      ["rbac_role_endpoints"] = true,
      ["rbac_role_entities"] = true,
      ["rbac_roles"] = true,
      ["rbac_user_roles"] = true,
      ["rbac_users"] = true,
    },
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
    },
    -- deny a particular entity (and related api methods)
    -- deny_entity = { ["some_entity_name"] = true },
    -- disable running of enterprise plugins
    allow_ee_entity = { READ = false, WRITE = false },
    disabled_ee_entities = {
      ["workspaces"] = false,
      ["event_hooks"] = true,
      ["consumer_groups"] = true,
      ["consumer_group_plugins"] = true,
      ["rbac_role_endpoints"] = true,
      ["rbac_role_entities"] = true,
      ["rbac_roles"] = true,
      ["rbac_user_roles"] = true,
      ["rbac_users"] = true,
    },
  }
}

-- This is a flag is being used to indicate a generated release
c.release = true

return setmetatable(c, {__index = function() return {} end })
