local VERSION = "0.3.2"

return {
  NAME = "kong",
  VERSION = VERSION,
  ROCK_VERSION = VERSION.."-1",
  SYSLOG = {
    ADDRESS = "kong-hf.mashape.com",
    PORT = 61828,
    API = "api"
  },
  CLI = {
    GLOBAL_KONG_CONF = "/etc/kong/kong.yml",
    NGINX_CONFIG = "nginx.conf",
    NGINX_PID = "kong.pid",
    DNSMASQ_PID = "dnsmasq.pid",
  },
  DATABASE_NULL_ID = "00000000-0000-0000-0000-000000000000",
  DATABASE_ERROR_TYPES = {
    SCHEMA = "schema",
    INVALID_TYPE = "invalid_type",
    DATABASE = "database",
    UNIQUE = "unique",
    FOREIGN = "foreign"
  },
  -- Non standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_TIME = "X-Kong-Proxy-Time",
    API_TIME = "X-Kong-Api-Time",
    CONSUMER_ID = "X-Consumer-ID",
    CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
    CONSUMER_USERNAME = "X-Consumer-Username",
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
