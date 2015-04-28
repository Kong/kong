return {
  NAME = "kong",
  VERSION = "0.2.1-1",
  SYSLOG = {
    ADDRESS = "kong-hf.mashape.com",
    PORT = 61828
  },
  CLI = {
    GLOBAL_KONG_CONF = "/etc/kong/kong.yml",
    NGINX_CONFIG = "nginx.conf",
    NGINX_PID = "kong.pid"
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
  HEADERS = {
    SERVER = "Server",
    VIA = "Via",
    PROXY_TIME = "X-Kong-Proxy-Time",
    API_TIME = "X-Kong-Api-Time",
    CONSUMER_ID = "X-Consumer-ID",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining"
  },
  CACHE = {
    APIS = "apis",
    PLUGINS_CONFIGURATIONS = "plugins_configurations",
    BASICAUTH_CREDENTIAL = "basicauth_credentials",
    KEYAUTH_CREDENTIAL = "keyauth_credentials"
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
