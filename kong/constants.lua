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
  "proxy-cache",
  "session",
  "acme",
}

local plugin_map = {}
for i = 1, #plugins do
  plugin_map[plugins[i]] = true
end

local deprecated_plugins = {} -- no currently deprecated plugin

local deprecated_plugin_map = {}
for _, plugin in ipairs(deprecated_plugins) do
  deprecated_plugin_map[plugin] = true
end

local protocols_with_subsystem = {
  http = "http",
  https = "http",
  tcp = "stream",
  tls = "stream",
  grpc = "http",
  grpcs = "http",
}
local protocols = {}
for p,_ in pairs(protocols_with_subsystem) do
  protocols[#protocols + 1] = p
end
table.sort(protocols)

return {
  BUNDLED_PLUGINS = plugin_map,
  DEPRECATED_PLUGINS = deprecated_plugin_map,
  -- non-standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_LATENCY = "X-Kong-Proxy-Latency",
    RESPONSE_LATENCY = "X-Kong-Response-Latency",
    ADMIN_LATENCY = "X-Kong-Admin-Latency",
    UPSTREAM_LATENCY = "X-Kong-Upstream-Latency",
    UPSTREAM_STATUS = "X-Kong-Upstream-Status",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
    CREDENTIAL_USERNAME = "X-Credential-Username",
    CREDENTIAL_IDENTIFIER = "X-Credential-Identifier",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining",
    CONSUMER_GROUPS = "X-Consumer-Groups",
    AUTHENTICATED_GROUPS = "X-Authenticated-Groups",
    FORWARDED_HOST = "X-Forwarded-Host",
    FORWARDED_PREFIX = "X-Forwarded-Prefix",
    ANONYMOUS = "X-Anonymous-Consumer",
    VIA = "Via",
    SERVER = "Server"
  },
  -- Notice that the order in which they are listed is important:
  -- schemas of dependencies need to be loaded first.
  CORE_ENTITIES = {
    "consumers",
    "certificates",
    "services",
    "routes",
    "snis",
    "upstreams",
    "targets",
    "plugins",
    "tags",
    "ca_certificates",
    consumers = true,
    certificates = true,
    services = true,
    routes = true,
    snis = true,
    upstreams = true,
    targets = true,
    plugins = true,
    tags = true,
    ca_certificates = true,
  },
  ENTITY_CACHE_STORE = setmetatable({
    consumers = "cache",
    certificates = "core_cache",
    services = "core_cache",
    routes = "core_cache",
    snis = "core_cache",
    upstreams = "core_cache",
    targets = "core_cache",
    plugins = "core_cache",
    tags = "cache",
    ca_certificates = "core_cache",
  }, {
    __index = function()
      return "cache"
    end
  }),
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
    STATS_PORT = 61830
  },
  DICTS = {
    "kong",
    "kong_locks",
    "kong_db_cache",
    "kong_db_cache_miss",
    "kong_process_events",
    "kong_cluster_events",
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
  PROTOCOLS = protocols,
  PROTOCOLS_WITH_SUBSYSTEM = protocols_with_subsystem,
}
