local function redis_config_adapter(conf)
    return {
        host = conf.base.host,
        port = conf.base.port,
        database = conf.base.database,
        auth = conf.base.auth,
        ssl = conf.base.ssl,
        ssl_verify = conf.base.ssl_verify,
        ssl_server_name = conf.base.server_name,

        namespace = conf.extra_options.namespace,
        scan_count = conf.extra_options.scan_count,
    }
end

return redis_config_adapter
