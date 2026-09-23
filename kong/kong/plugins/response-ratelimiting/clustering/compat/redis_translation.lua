local function adapter(config_to_update)
    if config_to_update.policy == "redis" then
        config_to_update.redis_host = config_to_update.redis.host
        config_to_update.redis_port = config_to_update.redis.port
        config_to_update.redis_username = config_to_update.redis.username
        config_to_update.redis_password = config_to_update.redis.password
        config_to_update.redis_database = config_to_update.redis.database
        config_to_update.redis_timeout = config_to_update.redis.timeout
        config_to_update.redis_ssl = config_to_update.redis.ssl
        config_to_update.redis_ssl_verify = config_to_update.redis.ssl_verify
        config_to_update.redis_server_name = config_to_update.redis.server_name

        config_to_update.redis = nil

        return true
    end

    return false
end

return {
    adapter = adapter
}
