-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local function redis_config_adapter(conf)
    return {
        host = conf.host,
        port = conf.port,
        database = conf.database,
        auth = conf.password,
        ssl = conf.ssl,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = conf.server_name,
        username = conf.username,
        password = conf.password,

        namespace = conf.extra_options.namespace,
        scan_count = conf.extra_options.scan_count,
    }
end

return redis_config_adapter
