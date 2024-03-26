local function redis_config_adapter(conf)
    return {
        host = conf.host,
        port = conf.port,
        database = conf.database,
        auth = conf.password,
        ssl = conf.ssl,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = conf.server_name,

        namespace = conf.extra_options.namespace,
        scan_count = conf.extra_options.scan_count,
    }
end

return redis_config_adapter
