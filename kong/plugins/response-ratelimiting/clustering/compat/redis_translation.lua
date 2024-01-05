local function adapter(config_to_update)
    if config_to_update.policy == "redis" then
        config_to_update.redis_host = config_to_update.redis.base.host
        config_to_update.redis_port = config_to_update.redis.base.port
        config_to_update.redis_username = config_to_update.redis.base.username
        config_to_update.redis_password = config_to_update.redis.base.password
        config_to_update.redis_database = config_to_update.redis.base.database
        config_to_update.redis_timeout = 1100
        config_to_update.redis_ssl = config_to_update.redis.base.ssl
        config_to_update.redis_ssl_verify = config_to_update.redis.base.ssl_verify
        config_to_update.redis_server_name = config_to_update.redis.base.server_name

        config_to_update.redis = nil

        return true
    end

    return false
end

return {
    adapter = adapter
}
