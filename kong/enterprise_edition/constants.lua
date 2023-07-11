-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  -- this list is joined into the DEPRECATED_PLUGINS map in kong.constants
  EE_DEPRECATED_PLUGIN_LIST = {
  },

  -- this list is joined into the ENTITIES list in kong.constants
  EE_ENTITIES = {
    "files",
    "legacy_files",
    "workspace_entity_counters",
    "consumer_reset_secrets",
    "credentials",
    "audit_requests",
    "audit_objects",
    "rbac_users",
    "rbac_roles",
    "rbac_user_roles",
    "rbac_role_entities",
    "rbac_role_endpoints",
    "admins",
    "developers",
    "document_objects",
    "applications",
    "application_instances",
    "groups",
    "group_rbac_roles",
    "login_attempts",
    "keyring_meta",
    "keyring_keys",
    "event_hooks",
    "licenses",
    "consumer_groups",
    "consumer_group_plugins",
    "consumer_group_consumers",
  },

  -- this list is joined into the DICTS list in kong.constants
  EE_DICTS = {
    "kong_counters",
    "kong_vitals_counters",
    "kong_vitals_lists",
  },

  -- the remaining entities are inserted as-in into the kong.constants table:
  ADMIN_CONSUMER_USERNAME_SUFFIX = "_ADMIN_",
  ADMIN_GUI_KCONFIG_CACHE_KEY = "admin:gui:kconfig",
  PORTAL_PREFIX = "__PORTAL-",
  WORKSPACE_CONFIG = {
    PORTAL = "portal",
    PORTAL_AUTH = "portal_auth",
    PORTAL_AUTH_CONF = "portal_auth_conf",
    PORTAL_AUTO_APPROVE = "portal_auto_approve",
    PORTAL_TOKEN_EXP = "portal_token_exp",
    PORTAL_INVITE_EMAIL = "portal_invite_email",
    PORTAL_ACCESS_REQUEST_EMAIL = "portal_access_request_email",
    PORTAL_APPROVED_EMAIL = "portal_approved_email",
    PORTAL_RESET_EMAIL = "portal_reset_email",
    PORTAL_APPLICATION_REQUEST_EMAIL = "portal_application_request_email",
    PORTAL_APPLICATION_STATUS_EMAIL = "portal_application_status_email",
    PORTAL_RESET_SUCCESS_EMAIL = "portal_reset_success_email",
    PORTAL_EMAILS_FROM = "portal_emails_from",
    PORTAL_EMAILS_REPLY_TO = "portal_emails_reply_to",
    PORTAL_SMTP_ADMIN_EMAILS = "portal_smtp_admin_emails",
    PORTAL_SESSION_CONF = "portal_session_conf",
    PORTAL_CORS_ORIGINS = "portal_cors_origins",
    PORTAL_DEVELOPER_META_FIELDS = "portal_developer_meta_fields",
    PORTAL_IS_LEGACY = "portal_is_legacy"
  },
  PORTAL_RENDERER = {
    EXTENSION_LIST = {
      "txt", "md", "html", "json", "yaml", "yml",
    },
    SPEC_EXT_LIST = {
      "json", "yaml", "yml",
    },
    ROUTE_TYPES = {
      EXPLICIT = "explicit", COLLECTION = "collection", DEFAULT = "defualt",
    },
    FALLBACK_404 = '<html><head><title>404 Not Found</title></head><body>' ..
      '<h1>404 Not Found</h1><p>The page you are requesting cannot be found.</p>' ..
      '</body></html>',
    FALLBACK_EMAIL = [[
      <!DOCTYPE html>
      <html>
        <head>
        </head>
        <body>
          <h4>{{page.heading}}</h4>
          <p>
            {*page.body*}
          </p>
        </body>
      </html>
    ]],
    SITEMAP = [[<?xml version="1.0" encoding="UTF-8"?>

      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        {% for idx, url_obj in ipairs(xml_urlset) do %}
          <url>
            {% for key, value in pairs(url_obj) do %}
              <{*key*}>{*value*}</{*key*}>
            {% end %}
          </url>
        {% end %}
      </urlset>
    ]],
    LAYOUTS = {
      UNSET = "__UNSET__",
      LOGIN = "login",
      UNAUTHORIZED = "unauthorized",
    },
    PRIORITY_INDEX_OFFSET = 6,
  },
  WEBSOCKET = {
    ---
    -- Well-known status codes and canned reasons
    --
    -- See:
    --   * https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.1
    --   * https://datatracker.ietf.org/doc/html/rfc6455#section-11.7
    STATUS = {
      NORMAL           = { CODE = 1000, REASON = "Normal Closure" },
      GOING_AWAY       = { CODE = 1001, REASON = "Going Away" },
      PROTOCOL_ERROR   = { CODE = 1002, REASON = "Protocol Error" },
      UNSUPPORTED_DATA = { CODE = 1003, REASON = "Unsupported Data" },
      NO_STATUS        = { CODE = 1005, REASON = "No Status" },
      ABNORMAL         = { CODE = 1006, REASON = "Abnormal Closure" },
      INVALID_DATA     = { CODE = 1007, REASON = "Invalid Frame Payload Data" },
      POLICY_VIOLATION = { CODE = 1008, REASON = "Policy Violation" },
      MESSAGE_TOO_BIG  = { CODE = 1009, REASON = "Message Too Big" },
      SERVER_ERROR     = { CODE = 1011, REASON = "Internal Server Error" },
    },

    ---
    -- Lookup tables for WebSocket opcodes and frame type names
    --
    -- See:
    --   * https://datatracker.ietf.org/doc/html/rfc6455#section-11.8
    OPCODE_BY_TYPE = {
      continuation = 0x0,
      text         = 0x1,
      binary       = 0x2,
      close        = 0x8,
      ping         = 0x9,
      pong         = 0xa,
    },
    TYPE_BY_OPCODE = {
      [0x0] = "continuation",
      [0x1] = "text",
      [0x2] = "binary",
      [0x8] = "close",
      [0x9] = "ping",
      [0xa] = "pong",
    },

    ---
    -- Registered WebSocket header names
    --
    -- See:
    --   * https://datatracker.ietf.org/doc/html/rfc6455#section-11.3
    HEADERS = {
      KEY        = "Sec-WebSocket-Key",
      EXTENSIONS = "Sec-WebSocket-Extensions",
      ACCEPT     = "Sec-WebSocket-Accept",
      PROTOCOL   = "Sec-WebSocket-Protocol",
      VERSION    = "Sec-WebSocket-Version",
    },

    ---
    -- Maximum allowed length for WebSocket payloads, in bytes.
    --
    -- Technically lua-resty-websocket supports all the way up to 2^31 bytes,
    -- but that is so large that there's probably no actual use case for it.
    --
    -- We'll go with 32 MiB
    MAX_PAYLOAD_SIZE = 1024 * 1024 * 32,

    -- Default maximum payload size for clients
    --
    -- Client frames are more expensive to handle because of masking, so their
    -- default limit is smaller.
    DEFAULT_CLIENT_MAX_PAYLOAD = 1024 * 1024,

    -- Default maximum payload size for upstreams
    --
    -- Upstream frames require no masking, so it's okay to have a higher limit
    -- on their size.
    DEFAULT_UPSTREAM_MAX_PAYLOAD = 1024 * 1024 * 16,
  },

  EE_CLUSTERING_SYNC_STATUS = {
    { PLUGIN_CONFIG_INCOMPATIBLE = "plugin_config_incompatible", },
  },

  RBAC = {
    -- Defines the cost factor, which is an exponent, that will be used in bcrypt.
    -- A cost factor of N is equivalent to 2^N iterations/rounds of computations.
    BCRYPT_COST_FACTOR = 9,
  },
}
