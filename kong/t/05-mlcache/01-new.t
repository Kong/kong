# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) + 4;

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm 1m;
};

run_tests();

__DATA__

=== TEST 1: module has version number
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            ngx.say(mlcache._VERSION)
        }
    }
--- request
GET /t
--- response_body_like
\d+\.\d+\.\d+
--- no_error_log
[error]



=== TEST 2: new() validates name
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new)
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
name must be a string



=== TEST 3: new() validates shm
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name")
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
shm must be a string



=== TEST 4: new() validates opts
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", "foo")
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
opts must be a table



=== TEST 5: new() ensures shm exists
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "foo")
            if not cache then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
no such lua_shared_dict: foo



=== TEST 6: new() supports ipc_shm option and validates it
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", { ipc_shm = 1 })
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
ipc_shm must be a string



=== TEST 7: new() supports opts.ipc_shm and ensures it exists
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "cache_shm", { ipc_shm = "ipc" })
            if not cache then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- ignore_response_body
--- error_log eval
qr/\[error\] .*? no such lua_shared_dict: ipc/
--- no_error_log
[crit]



=== TEST 8: new() supports ipc options and validates it
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", { ipc = false })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
opts.ipc must be a table
--- no_error_log
[error]



=== TEST 9: new() prevents both opts.ipc_shm and opts.ipc to be given
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                ipc_shm = "ipc",
                ipc = {}
            })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
cannot specify both of opts.ipc_shm and opts.ipc
--- no_error_log
[error]



=== TEST 10: new() validates ipc.register_listeners + ipc.broadcast + ipc.poll (type: custom)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local args = {
                "register_listeners",
                "broadcast",
                "poll",
            }

            for _, arg in ipairs(args) do
                local ipc_opts = {
                    register_listeners = function() end,
                    broadcast = function() end,
                    poll = function() end,
                }

                ipc_opts[arg] = false

                local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                    ipc = ipc_opts,
                })
                if not ok then
                    ngx.say(err)
                end
            end
        }
    }
--- request
GET /t
--- response_body
opts.ipc.register_listeners must be a function
opts.ipc.broadcast must be a function
opts.ipc.poll must be a function
--- no_error_log
[error]



=== TEST 11: new() ipc.register_listeners can return nil + err (type: custom)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "cache_shm", {
                ipc = {
                    register_listeners = function()
                        return nil, "something happened"
                    end,
                    broadcast = function() end,
                    poll = function() end,
                }
            })
            if not cache then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body_like
failed to initialize custom IPC \(opts\.ipc\.register_listeners returned an error\): something happened
--- no_error_log
[error]



=== TEST 12: new() calls ipc.register_listeners with events array (type: custom)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "cache_shm", {
                ipc = {
                    register_listeners = function(events)
                        local res = {}
                        for ev_name, ev in pairs(events) do
                            table.insert(res, string.format("%s | channel: %s | handler: %s",
                                                            ev_name, ev.channel, type(ev.handler)))
                        end

                        table.sort(res)

                        for i = 1, #res do
                            ngx.say(res[i])
                        end
                    end,
                    broadcast = function() end,
                    poll = function() end,
                }
            })
            if not cache then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
invalidation | channel: mlcache:invalidations:name | handler: function
purge | channel: mlcache:purge:name | handler: function
--- no_error_log
[error]



=== TEST 13: new() ipc.poll is optional (some IPC libraries might not need it
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function() end,
                    poll = nil
                }
            })
            if not cache then
                ngx.say(err)
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 14: new() validates opts.lru_size
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                lru_size = "",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
opts.lru_size must be a number



=== TEST 15: new() validates opts.ttl
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                ttl = ""
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                ttl = -1
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
opts.ttl must be a number
opts.ttl must be >= 0



=== TEST 16: new() validates opts.neg_ttl
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                neg_ttl = ""
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                neg_ttl = -1
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
opts.neg_ttl must be a number
opts.neg_ttl must be >= 0



=== TEST 17: new() validates opts.resty_lock_opts
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                resty_lock_opts = false,
            })
            if not ok then
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
opts.resty_lock_opts must be a table



=== TEST 18: new() validates opts.shm_set_tries
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local values = {
                false,
                -1,
                0,
            }

            for _, v in ipairs(values) do
                local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                    shm_set_tries = v,
                })
                if not ok then
                    ngx.say(err)
                end
            end
        }
    }
--- request
GET /t
--- response_body
opts.shm_set_tries must be a number
opts.shm_set_tries must be >= 1
opts.shm_set_tries must be >= 1
--- no_error_log
[error]



=== TEST 19: new() validates opts.shm_miss
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                shm_miss = false,
            })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
opts.shm_miss must be a string
--- no_error_log
[error]



=== TEST 20: new() ensures opts.shm_miss exists
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = mlcache.new("name", "cache_shm", {
                shm_miss = "foo",
            })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
no such lua_shared_dict for opts.shm_miss: foo
--- no_error_log
[error]



=== TEST 21: new() creates an mlcache object with default attributes
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("name", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
            end

            ngx.say(type(cache))
            ngx.say(type(cache.ttl))
            ngx.say(type(cache.neg_ttl))
        }
    }
--- request
GET /t
--- response_body
table
number
number
--- no_error_log
[error]



=== TEST 22: new() accepts user-provided LRU instances via opts.lru
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache          = require "kong.resty.mlcache"
            local pureffi_lrucache = require "resty.lrucache.pureffi"

            local my_lru = pureffi_lrucache.new(100)

            local cache = assert(mlcache.new("name", "cache_shm", { lru = my_lru }))

            ngx.say("lru is user-provided: ", cache.lru == my_lru)
        }
    }
--- request
GET /t
--- response_body
lru is user-provided: true
--- no_error_log
[error]
