local plugins = {
  "ssl", "jwt", "acl", "correlation-id", "cors", "oauth2", "tcp-log", "udp-log",
  "file-log", "http-log", "key-auth", "hmac-auth", "basic-auth", "ip-restriction",
  "galileo", "request-transformer", "response-transformer",
  "request-size-limiting", "rate-limiting", "response-ratelimiting", "syslog",
  "loggly", "datadog", "runscope", "ldap-auth", "statsd", "bot-detection"
}

local plugin_map = {}
for i = 1, #plugins do
  plugin_map[plugins[i]] = true
end

return {
  PLUGINS_AVAILABLE = plugin_map,
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
    FORWARDED_PREFIX = "X-Forwarded-Prefix"
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
  SYSLOG = {
    ADDRESS = "kong-hf.mashape.com",
    PORT = 61828
  }
}
