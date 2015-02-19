return {
  VERSION = "0.1-preview",
  DATABASE_ERROR_TYPES = {
    SCHEMA = "schema",
    INVALID_TYPE = "invalid_type",
    DATABASE = "database",
    UNIQUE = "unique",
    FOREIGN = "foreign"
  },
  HEADERS = {
    VERSION = "X-Kong-Version",
    PROXY_TIME = "X-Kong-Proxy-Time",
    API_TIME = "X-Kong-Api-Time",
    ACCOUNT_ID = "X-Account-ID",
    RATELIMIT_LIMIT = "X-RateLimit-Limit",
    RATELIMIT_REMAINING = "X-RateLimit-Remaining"
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
