local VERSION = "0.3.0"

return {
  NAME = "kong",
  VERSION = VERSION,
  ROCK_VERSION = VERSION.."-1",
  SYSLOG = {
    ADDRESS = "kong-hf.mashape.com",
    PORT = 61828
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
  DATABASE_TYPES = {
    ID = "id",
    TIMESTAMP = "timestamp"
  },
  -- Non standard headers, specific to Kong
  HEADERS = {
    HOST_OVERRIDE = "X-Host-Override",
    PROXY_TIME = "X-Kong-Proxy-Time",
    API_TIME = "X-Kong-Api-Time",
    CONSUMER_ID = "X-Consumer-ID",
    RATELIMIT_LIMIT = "X-RateLimit-<duration>-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-<duration>-Remaining"
  },
  CACHE = {
    APIS = "apis",
    PLUGINS_CONFIGURATIONS = "plugins_configurations",
    BASICAUTH_CREDENTIAL = "basicauth_credentials",
    KEYAUTH_CREDENTIAL = "keyauth_credentials",
    SSL = "ssl"
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
