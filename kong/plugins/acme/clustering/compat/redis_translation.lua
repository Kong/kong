local function adapter(config_to_update)
    if config_to_update.storage == "redis" then
        config_to_update.storage_config.redis = {
            host = config_to_update.storage_config.redis.base.host,
            port = config_to_update.storage_config.redis.base.port,
            auth = config_to_update.storage_config.redis.base.password,
            database = config_to_update.storage_config.redis.base.database,
            ssl = config_to_update.storage_config.redis.base.ssl,
            ssl_verify = config_to_update.storage_config.redis.base.ssl_verify,
            ssl_server_name = config_to_update.storage_config.redis.base.server_name,
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
