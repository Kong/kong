-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local dist_constants = require "kong.enterprise_edition.distributions_constants"
local ee_constants = require "kong.enterprise_edition.constants"

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
  "prometheus",
  "proxy-cache",
  "session",
  "acme",
  "grpc-gateway",
  "grpc-web",
  "pre-function",
  "post-function",
  "azure-functions",
  "zipkin",
  "opentelemetry",
}

-- XXX EE
local ce_plugin_map = {}
for i = 1, #plugins do
  ce_plugin_map[plugins[i]] = true
end

for _, plugin in ipairs(dist_constants.plugins) do
  table.insert(plugins, plugin)
end

local plugin_map = {}
for i = 1, #plugins do
  plugin_map[plugins[i]] = true
end

local ee_plugin_map = {}
for i = 1, #dist_constants.plugins do
  ee_plugin_map[dist_constants.plugins[i]] = true
end

local deprecated_plugins = {} -- no currently deprecated plugin

for _, plugin in ipairs(ee_constants.EE_DEPRECATED_PLUGIN_LIST) do
  table.insert(deprecated_plugins, plugin)
end

local deprecated_plugin_map = {}
for _, plugin in ipairs(deprecated_plugins) do
  deprecated_plugin_map[plugin] = true
end

local vaults = {
  "env",
  -- Vault EE [[
  "aws",
  "gcp",
  "hcv",
  -- ]]
}

local vault_map = {}
for i = 1, #vaults do
  vault_map[vaults[i]] = true
end

local deprecated_vaults = {} -- no currently deprecated vaults

local deprecated_vault_map = {}
for _, vault in ipairs(deprecated_vaults) do
  deprecated_vault_map[vault] = true
end

local protocols_with_subsystem = {
  http = "http",
  https = "http",
  tcp = "stream",
  tls = "stream",
  udp = "stream",
  tls_passthrough = "stream",
  grpc = "http",
  grpcs = "http",
  -- EE websockets [[
  ws = "http",
  wss = "http",
  -- ]]
}
local protocols = {}
for p,_ in pairs(protocols_with_subsystem) do
  protocols[#protocols + 1] = p
end
table.sort(protocols)

local key_formats_map = {
  ["jwk"] = true,
  ["pem"] = true,
}
local key_formats = {}
for k in pairs(key_formats_map) do
  key_formats[#key_formats + 1] = k
end

local constants = {
  BUNDLED_PLUGINS = plugin_map,
  EE_PLUGINS = dist_constants.plugins,
  EE_PLUGINS_MAP = ee_plugin_map,
  CE_PLUGINS_MAP = ce_plugin_map,
  DEPRECATED_PLUGINS = deprecated_plugin_map,
  BUNDLED_VAULTS = vault_map,
  DEPRECATED_VAULTS = deprecated_vault_map,
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
    CREDENTIAL_IDENTIFIER = "X-Credential-Identifier",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining",
    CONSUMER_GROUPS = "X-Consumer-Groups",
    AUTHENTICATED_GROUPS = "X-Authenticated-Groups",
    FORWARDED_HOST = "X-Forwarded-Host",
    FORWARDED_PATH = "X-Forwarded-Path",
    FORWARDED_PREFIX = "X-Forwarded-Prefix",
    ANONYMOUS = "X-Anonymous-Consumer",
    VIA = "Via",
    SERVER = "Server"
  },
  -- Notice that the order in which they are listed is important:
  -- schemas of dependencies need to be loaded first.
  --
  -- This table doubles as a set (e.g. CORE_ENTITIES["routes"] = true)
  -- (see below where the set entries are populated)
  CORE_ENTITIES = {
    "workspaces",
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
    "clustering_data_planes",
    "parameters",
    "vaults",
    "key_sets",
    "keys",
    "filter_chains",
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
    vaults = "core_cache",
    key_sets = "core_cache",
    keys = "core_cache",
    consumers_groups = "core_cache",
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
    STATS_TLS_PORT = 61833,
  },
  DICTS = {
    "kong",
    "kong_locks",
    "kong_db_cache",
    "kong_db_cache_miss",
    "kong_cluster_events",
    "kong_healthchecks",
    "kong_rate_limiting_counters",
    "kong_vitals",
  },
  DATABASE = {
    POSTGRES = {
      MIN = "9.5",
    },
    -- a bit over three years maximum to make it more safe against
    -- integer overflow (time() + ttl)
    DAO_MAX_TTL = 1e8,
  },
  PROTOCOLS = protocols,
  PROTOCOLS_WITH_SUBSYSTEM = protocols_with_subsystem,

  DECLARATIVE_LOAD_KEY = "declarative_config:loaded",
  DECLARATIVE_HASH_KEY = "declarative_config:hash",
  PLUGINS_REBUILD_COUNTER_KEY = "readiness_probe_config:plugins_rebuild_counter",
  ROUTERS_REBUILD_COUNTER_KEY = "readiness_probe_config:routers_rebuild_counter",
  DECLARATIVE_EMPTY_CONFIG_HASH = string.rep("0", 32),

  CLUSTER_ID_PARAM_KEY = "cluster_id",

  CLUSTERING_SYNC_STATUS = {
    { UNKNOWN                     = "unknown", },
    { NORMAL                      = "normal", },
    { KONG_VERSION_INCOMPATIBLE   = "kong_version_incompatible", },
    { PLUGIN_SET_INCOMPATIBLE     = "plugin_set_incompatible", },
    { PLUGIN_VERSION_INCOMPATIBLE = "plugin_version_incompatible", },
    { FILTER_SET_INCOMPATIBLE     = "filter_set_incompatible", },
  },
  CLUSTERING_TIMEOUT = 5000, -- 5 seconds
  CLUSTERING_PING_INTERVAL = 30, -- 30 seconds
  CLUSTERING_OCSP_TIMEOUT = 5000, -- 5 seconds

  CLEAR_HEALTH_STATUS_DELAY = 300, -- 300 seconds

  KEY_FORMATS_MAP = key_formats_map,
  KEY_FORMATS = key_formats,

  LOG_LEVELS = {
    debug = ngx.DEBUG,
    info = ngx.INFO,
    notice = ngx.NOTICE,
    warn = ngx.WARN,
    error = ngx.ERR,
    crit = ngx.CRIT,
    alert = ngx.ALERT,
    emerg = ngx.EMERG,
    [ngx.DEBUG] = "debug",
    [ngx.INFO] = "info",
    [ngx.NOTICE] = "notice",
    [ngx.WARN] = "warn",
    [ngx.ERR] = "error",
    [ngx.CRIT] = "crit",
    [ngx.ALERT] = "alert",
    [ngx.EMERG] = "emerg",
  },

  DYN_LOG_LEVEL_KEY = "kong:dyn_log_level",
  DYN_LOG_LEVEL_TIMEOUT_AT_KEY = "kong:dyn_log_level_timeout_at",
}

-- XXX EE: add enterprise-specific CLUSTERING_SYNC_STATUS enum values before
-- indexing the table by status name
for _, v in ipairs(ee_constants.EE_CLUSTERING_SYNC_STATUS) do
  table.insert(constants.CLUSTERING_SYNC_STATUS, v)
end

for _, v in ipairs(constants.CLUSTERING_SYNC_STATUS) do
  local k, v = next(v)
  constants.CLUSTERING_SYNC_STATUS[k] = v
end

-- Make the CORE_ENTITIES table usable both as an ordered array and as a set
-- This sets whether entity uses kong.core_cache (true) or kong.cache
for _, v in ipairs(constants.CORE_ENTITIES) do
  constants.CORE_ENTITIES[v] = true
end

-- EE [[

-- Add all top-level ee_constants into constants (replaces existing ones)
for k, v in pairs(ee_constants) do
  constants[k] = v
end

-- Add EE_ENTITIES to the CORE_ENTITIES list
for _, v in ipairs(ee_constants.EE_ENTITIES) do
  if type(v) == "table" then
    for i, e in ipairs(constants.CORE_ENTITIES) do
      if e == v.ahead_of then
        table.insert(constants.CORE_ENTITIES, i, v[1])
        break
      end
    end
  else
    table.insert(constants.CORE_ENTITIES, v)
  end
end

-- Add EE_DICTS to DICTS list
for _, v in ipairs(ee_constants.EE_DICTS) do
  table.insert(constants.DICTS, v)
end

-- XXX EE: we need consumers to use kong.cache for portal auth to work
constants.CORE_ENTITIES["consumers"] = nil

-- XXX EE: For now do not set kong.core_cache on enterprise entities.
-- Let's see what happens
-- for _, v in ipairs(ee_constants.EE_ENTITIES) do
--   constants.CORE_ENTITIES[v] = true
-- end

-- EE ]]


return constants
