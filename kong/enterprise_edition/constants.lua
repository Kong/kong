return {
  -- this list is joined into the DEPRECATED_PLUGINS map in kong.constants
  EE_DEPRECATED_PLUGIN_LIST = {
    "route-by-header",
    "upstream-tls",
  },

  -- this list is joined into the ENTITIES list in kong.constants
  EE_ENTITIES = {
    "files",
    "legacy_files",
    "workspace_entities",
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
    "event_hooks",
  },

  -- this list is joined into the DICTS list in kong.constants
  EE_DICTS = {
    "kong_counters",
    "kong_vitals_counters",
    "kong_vitals_lists",
  },

  -- the remaining entities are inserted as-in into the kong.constants table:

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
    PORTAL_RESET_SUCCESS_EMAIL = "portal_reset_success_email",
    PORTAL_EMAILS_FROM = "portal_emails_from",
    PORTAL_EMAILS_REPLY_TO = "portal_emails_reply_to",
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
}
