use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

master_on();
workers(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: node.get_memory_stats() returns Lua VM and lua_shared_dict stats
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 24k;
    lua_shared_dict kong_db_cache 32k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)

        -- NOTE: insert garbage
        ngx.shared.kong:set("kong:mem:foo", "garbage")
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats()

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like chomp
\Alua_shared_dicts
  \S+: \d+\/2[45]\d{3}
  \S+: \d+\/3[23]\d{3}
workers_lua_vms
  (?:\d+: \d+\s*){1,2}\Z
--- no_error_log
[error]



=== TEST 2: node.get_memory_stats() returns workers Lua VM reports in PID ascending order
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 24k;
    lua_shared_dict kong_db_cache 32k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)

        -- NOTE: insert mock workers
        ngx.shared.kong:set("kong:mem:1", 1234)
        ngx.shared.kong:set("kong:mem:2", 1234)
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats()

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like
lua_shared_dicts
  \S+: \d+\/2[45]\d{3}
  \S+: \d+\/3[23]\d{3}
workers_lua_vms
  1: 1234
  2: 1234
  (?:\d+: \d+\s*){1,2}
--- no_error_log
[error]



=== TEST 3: node.get_memory_stats() accepts 'unit' argument
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 32k;
    lua_shared_dict kong_db_cache 64k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats("k")

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like
lua_shared_dicts
  \S+: 12\.\d+ KiB\/3[23]\.\d+ KiB
  \S+: 12\.\d+ KiB\/6[45]\.\d+ KiB
workers_lua_vms
  (?:\d+: \d+\.\d+ KiB\s*){1,2}
--- no_error_log
[error]



=== TEST 4: node.get_memory_stats() 'unit = b' returns Lua numbers
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 32k;
    lua_shared_dict kong_db_cache 64k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats("b")

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)

                assert(type(dict_info.allocated_slabs) == "number")
                assert(type(dict_info.capacity) == "number")
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)

                assert(type(worker_info.http_allocated_gc) == "number")
            end
        }
    }
--- request
GET /t
--- response_body_like
lua_shared_dicts
  \S+: \d+\/3[23]\d{3}
  \S+: \d+\/6[45]\d{3}
workers_lua_vms
  (?:\d+: \d+\s*){1,2}
--- no_error_log
[error]



=== TEST 5: node.get_memory_stats() accepts 'scale' argument
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 32k;
    lua_shared_dict kong_db_cache 64k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats("k", 4)

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like
lua_shared_dicts
  \S+: 12\.\d{4} KiB\/3[23]\.\d{4} KiB
  \S+: 12\.\d{4} KiB\/6[45]\.\d{4} KiB
workers_lua_vms
  (?:\d+: \d+\.\d{4} KiB\s*){1,2}
--- no_error_log
[error]



=== TEST 6: node.get_memory_stats() validates arguments
--- http_config eval
qq{
    $t::Util::HttpConfig
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, perr = pcall(pdk.node.get_memory_stats, "V")
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(pdk.node.get_memory_stats, "k", -1)
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
invalid unit 'V' (expected 'k/K', 'm/M', or 'g/G')
scale must be equal or greater than 0
--- no_error_log
[error]



=== TEST 7: node.get_memory_stats() handles bad workers Lua VM reports (no reports)
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 24k;
    lua_shared_dict kong_db_cache 32k;

    init_worker_by_lua_block {
        -- NOTE: workers are not reporting Lua VM GC
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats()

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like chomp
\Alua_shared_dicts
  \S+: \d+\/2[45]\d{3}
  \S+: \d+\/3[23]\d{3}
workers_lua_vms\Z
--- no_error_log
[error]



=== TEST 8: node.get_memory_stats() handles bad workers Lua VM reports (corrupted report)
--- http_config eval
qq{
    $t::Util::HttpConfig

    lua_shared_dict kong 24k;
    lua_shared_dict kong_db_cache 32k;

    init_worker_by_lua_block {
        local runloop_handler = require "kong.runloop.handler"

        runloop_handler._update_lua_mem(true)

        -- NOTE: insert corrupted data
        ngx.shared.kong:set("kong:mem:1", "garbage")
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            -- NOTE: delete memory report for this worker
            ngx.shared.kong:delete("kong:mem:" .. ngx.worker.pid())

            local res = pdk.node.get_memory_stats()

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like
lua_shared_dicts
  \S+: \d+\/2[45]\d{3}
  \S+: \d+\/3[25]\d{3}
workers_lua_vms
  1: could not get worker's HTTP Lua VM memory \(pid: 1\): reported value is corrupted(?:\s*\d+: \d+\s*){0,2}
--- no_error_log
[error]



=== TEST 9: node.get_memory_stats() handles no lua_shared_dict and no Lua VM reports
--- http_config eval
qq{
    $t::Util::HttpConfig

    # NOTE: no lua_shared_dict

    init_worker_by_lua_block {
        -- NOTE: workers are not reporting Lua VM GC
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local res = pdk.node.get_memory_stats()

            ngx.say("lua_shared_dicts")
            for dict_name, dict_info in pairs(res.lua_shared_dicts) do
                ngx.say("  ", dict_name, ": ",
                        dict_info.allocated_slabs, "/", dict_info.capacity)
            end

            ngx.say("workers_lua_vms")
            for _, worker_info in ipairs(res.workers_lua_vms) do
                ngx.say("  ", worker_info.pid, ": ",
                        worker_info.http_allocated_gc or worker_info.err)
            end
        }
    }
--- request
GET /t
--- response_body_like chomp
\Alua_shared_dicts
workers_lua_vms\Z
--- no_error_log
[error]
