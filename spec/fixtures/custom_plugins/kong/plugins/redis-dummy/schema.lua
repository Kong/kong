local redis_schema = require "kong.tools.redis.schema"

return {
  name = "redis-dummy",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { redis = redis_schema.config_schema },
        },
      },
    },
  },
}
