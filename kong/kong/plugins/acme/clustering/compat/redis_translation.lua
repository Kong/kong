local function adapter(config_to_update)
    if config_to_update.storage == "redis" then
        config_to_update.storage_config.redis = {
            host = config_to_update.storage_config.redis.host,
            port = config_to_update.storage_config.redis.port,
            auth = config_to_update.storage_config.redis.password,
            database = config_to_update.storage_config.redis.database,
            ssl = config_to_update.storage_config.redis.ssl,
            ssl_verify = config_to_update.storage_config.redis.ssl_verify,
            ssl_server_name = config_to_update.storage_config.redis.server_name,
            namespace = config_to_update.storage_config.redis.extra_options.namespace,
            scan_count = config_to_update.storage_config.redis.extra_options.scan_count
        }

        return true
    end

    return false
end

return {
    adapter = adapter
}
