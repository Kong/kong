local plugins = {
  "jwt",
  "acl",
  "correlation-id",
  "cors",
  "oauth2",
  "tcp-log",
  "udp-log",
  "file-log",
  "http-log",
  "key-auth",
  "hmac-auth",
  "basic-auth",
  "ip-restriction",
  "request-transformer",
  "response-transformer",
  "request-size-limiting",
  "rate-limiting",
  "response-ratelimiting",
  "syslog",
  "loggly",
  "datadog",
  "ldap-auth",
  "statsd",
  "bot-detection",
  "aws-lambda",
  "request-termination",
  -- external plugins
  "azure-functions",
  "zipkin",
  "pre-function",
  "post-function",
  "prometheus",
  -- XXX disabled for now; needs to have its schema updated
  --"session",
}

local plugin_map = {}
for i = 1, #plugins do
  plugin_map[plugins[i]] = true
end

local deprecated_plugins = {
  "galileo",
}

local deprecated_plugin_map = {}
for _, plugin in ipairs(deprecated_plugins) do
  deprecated_plugin_map[plugin] = true
end

return {
  BUNDLED_PLUGINS = plugin_map,
  DEPRECATED_PLUGINS = deprecated_plugin_map,
  -- non-standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_LATENCY = "X-Kong-Proxy-Latency",
    UPSTREAM_LATENCY = "X-Kong-Upstream-Latency",
    UPSTREAM_STATUS = "X-Kong-Upstream-Status",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
    CREDENTIAL_USERNAME = "X-Credential-Username",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining",
    CONSUMER_GROUPS = "X-Consumer-Groups",
    FORWARDED_HOST = "X-Forwarded-Host",
    FORWARDED_PREFIX = "X-Forwarded-Prefix",
    ANONYMOUS = "X-Anonymous-Consumer",
    VIA = "Via",
    SERVER = "Server"
  },
  RATELIMIT = {
    PERIODS = {
      "second",
      "minute",
      "hour",
      "day",
      "month",
      "year"
    }
  },
  REPORTS = {
    ADDRESS = "kong-hf.konghq.com",
    SYSLOG_PORT = 61828,
    STATS_PORT = 61829
  },
  DICTS = {
    "kong",
    "kong_locks",
    "kong_db_cache",
    "kong_db_cache_miss",
    "kong_process_events",
    "kong_cluster_events",
    "kong_vitals_counters",
    "kong_vitals_lists",
    "kong_healthchecks",
    "kong_rate_limiting_counters",
  },
  DATABASE = {
    POSTGRES = {
      MIN = "9.5",
      -- also accepts a DEPRECATED key, i.e. DEPRECATED = "9.4"
    },
    CASSANDRA = {
      MIN = "2.2",
      -- also accepts a DEPRECATED key
    }
  },
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
  }
}
