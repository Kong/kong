local typedefs = require "kong.db.schema.typedefs"
local DEFAULT_TIMEOUT = 2000

return {
    config_schema = {
        type = "record",
        description = "Redis configuration",
        fields = {
            { host = typedefs.host },
            { port = typedefs.port({ default = 6379 }), },
            { timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
            { username = { description = "Username to use for Redis connections. If undefined, ACL authentication won't be performed. This requires Redis v6.0.0+. To be compatible with Redis v5.x.y, you can set it to `default`.", type = "string",
                referenceable = true
                } },
            { password = { description = "Password to use for Redis connections. If undefined, no AUTH commands are sent to Redis.", type = "string",
                encrypted = true,
                referenceable = true,
                len_min = 0
                } },
            { database = { description = "Database to use for the Redis connection when using the `redis` strategy", type = "integer",
                default = 0
                } },
            { ssl = { description = "If set to true, uses SSL to connect to Redis.",
                type = "boolean",
                required = false,
                default = false
                } },
            { ssl_verify = { description = "If set to true, verifies the validity of the server SSL certificate. If setting this parameter, also configure `lua_ssl_trusted_certificate` in `kong.conf` to specify the CA (or server) certificate used by your Redis server. You may also need to configure `lua_ssl_verify_depth` accordingly.",
                type = "boolean",
                required = false,
                default = false
                } },
            { server_name = typedefs.sni { required = false } }
        }
    }
}
