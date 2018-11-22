return [[
log_format basic '$remote_addr [$time_local] '
                 '$protocol $status $bytes_sent $bytes_received '
                 '$session_time';

lua_shared_dict stream_kong                5m;
lua_shared_dict stream_kong_db_cache       ${{MEM_CACHE_SIZE}};
lua_shared_dict stream_kong_db_cache_miss 12m;
lua_shared_dict stream_kong_locks          8m;
lua_shared_dict stream_kong_process_events 5m;
lua_shared_dict stream_kong_cluster_events 5m;
lua_shared_dict stream_kong_healthchecks   5m;
lua_shared_dict stream_kong_rate_limiting_counters 12m;
> if database == "cassandra" then
lua_shared_dict stream_kong_cassandra      5m;
> end
lua_shared_dict stream_prometheus_metrics  5m;

upstream kong_upstream {
    server 0.0.0.1:1;
    balancer_by_lua_block {
        Kong.balancer()
    }
}

init_by_lua_block {
    -- shared dictionaries conflict between stream/http modules. use a prefix.
    local shared = ngx.shared
    ngx.shared = setmetatable({}, {
        __index = function(t, k)
            return shared["stream_"..k]
        end,
    })

    -- XXX: lua-resty-core doesn't load the ffi regex module in the stream
    -- subsystem. The code it binds is part of the http module. However
    -- without it we can't use regex during the init phase.
    require "resty.core.regex"

    Kong = require 'kong'
    Kong.init()
}

init_worker_by_lua_block {
    Kong.init_worker()
}

server {
> for i = 1, #stream_listeners do
    listen $(stream_listeners[i].listener);
> end

    access_log ${{PROXY_ACCESS_LOG}} basic;
    error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

    ssl_preread on;
    preread_by_lua_block {
        Kong.preread()
    }
    proxy_pass kong_upstream;

    log_by_lua_block {
        Kong.log()
    }
}
]]
