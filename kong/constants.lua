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
  "galileo",
  "request-transformer-advanced",
  "response-transformer",
  "request-size-limiting",
  "rate-limiting",
  "response-ratelimiting",
  "syslog",
  "loggly",
  "datadog",
  "runscope",
  "ldap-auth",
  "statsd",
  "bot-detection",
  "aws-lambda",
  "request-termination",
}

local core_models = {
  "apis",
  "consumers",
  "plugins",
  "ssl_certificates",
  "ssl_servers_names",
  "upstreams",
  "targets",
  "rbac_users",
  "rbac_user_roles",
  "rbac_roles",
  "rbac_role_perms",
  "rbac_perms",
  "rbac_resources",
  "workspaces",
  "workspace_entities",
  "role_entities",
  "role_endpoints",
}

local core_models_map = {}
for _, model in ipairs(core_models) do
  core_models_map[model] = true
end

local unique_ws_models = {
  "apis",
  "consumers",
  "ssl_certificates",
  "ssl_servers_names",
  "upstreams",
  "targets",
  "rbac_users",
  "rbac_user_roles",
  "rbac_roles",
  "rbac_role_perms",
  "rbac_perms",
  "rbac_resources",
  "workspaces",
  "workspace_entities",
  "role_entities",
  "role_endpoints",
}

local unique_ws_models_map = {}
for _, model in ipairs(unique_ws_models) do
  unique_ws_models_map[model] = true
end

local plugin_map = {}
for i = 1, #plugins do
  plugin_map[plugins[i]] = true
end

return {
  PLUGINS_AVAILABLE = plugin_map,
  CORE_MODELS = core_models_map,
  UNIQUE_WS_MODELS = unique_ws_models_map,

  -- non-standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_LATENCY = "X-Kong-Proxy-Latency",
    UPSTREAM_LATENCY = "X-Kong-Upstream-Latency",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
    CREDENTIAL_USERNAME = "X-Credential-Username",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining",
    CONSUMER_GROUPS = "X-Consumer-Groups",
    FORWARDED_HOST = "X-Forwarded-Host",
    FORWARDED_PREFIX = "X-Forwarded-Prefix",
    ANONYMOUS = "X-Anonymous-Consumer"
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
    ADDRESS = "kong-hf.mashape.com",
    SYSLOG_PORT = 61828,
    STATS_PORT = 61829
  },
  DICTS = {
    "kong",
    "kong_cache",
    "kong_process_events",
    "kong_cluster_events",
    "kong_vitals_requests_consumers",
    "kong_healthchecks",
  },
  DEFAULT_WORKSPACE = "default"
}
