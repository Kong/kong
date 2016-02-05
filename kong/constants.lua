local VERSION = "0.7.0"

return {
  NAME = "kong",
  VERSION = VERSION,
  ROCK_VERSION = VERSION.."-0",
  SYSLOG = {
    ADDRESS = "kong-hf.mashape.com",
    PORT = 61828,
    API = "api"
  },
  CLI = {
    GLOBAL_KONG_CONF = "/etc/kong/kong.yml",
    NGINX_CONFIG = "nginx.conf"
  },
  DATABASE_NULL_ID = "00000000-0000-0000-0000-000000000000",
  DB_ERROR_TYPES = setmetatable ({
    SCHEMA = "schema",
    INVALID_TYPE = "type",
    db = "db",
    UNIQUE = "unique",
    FOREIGN = "foreign"
  }, { __index = function(t, key)
                    local val = rawget(t, key)
                    if not val then
                       error("'"..tostring(key).."' is not a valid errortype", 2)
                    end
                    return val
                 end
              }),
  PLUGINS_AVAILABLE = {
    "ssl", "jwt", "acl", "cors", "oauth2", "tcp-log", "udp-log", "file-log",
    "http-log", "key-auth", "hmac-auth", "basic-auth", "ip-restriction",
    "mashape-analytics", "request-transformer", "response-transformer",
    "request-size-limiting", "rate-limiting", "response-ratelimiting", "syslog",
    "loggly", "datadog", "runscope"
  },
  -- Non standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_LATENCY = "X-Kong-Proxy-Latency",
    UPSTREAM_LATENCY = "X-Kong-Upstream-Latency",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
    CREDENTIAL_USERNAME = "X-Credential-Username",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining"
  },
  AUTHENTICATION = {
    QUERY = "query",
    BASIC = "basic",
    HEADER = "header"
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
  }
}
