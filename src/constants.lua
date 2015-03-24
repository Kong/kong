return {
  NAME = "kong",
  VERSION = "0.0.1beta-1",
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
    PROXY_TIME = "X-Kong-Proxy-Time",
    API_TIME = "X-Kong-Api-Time",
    ACCOUNT_ID = "X-Account-ID",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining"
  },
  CACHE = {
    APIS = "apis",
    PLUGINS = "plugins",
    APPLICATIONS = "applications"
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
