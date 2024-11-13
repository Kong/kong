# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm 1m;
    lua_shared_dict  ipc_shm   1m;
};

run_tests();

__DATA__

=== TEST 1: multiple instances with the same name have same lua-resty-lru instance
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache_1 = assert(mlcache.new("my_mlcache", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache", "cache_shm"))

            ngx.say("lua-resty-lru instances are the same: ",
                    cache_1.lru == cache_2.lru)
        }
    }
--- request
GET /t
--- response_body
lua-resty-lru instances are the same: true
--- no_error_log
[error]



=== TEST 2: multiple instances with different names have different lua-resty-lru instances
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm"))

            ngx.say("lua-resty-lru instances are the same: ",
                    cache_1.lru == cache_2.lru)
        }
    }
--- request
GET /t
--- response_body
lua-resty-lru instances are the same: false
--- no_error_log
[error]



=== TEST 3: garbage-collected instances also GC their lru instance
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            collectgarbage("collect")
            local cache_1 = assert(mlcache.new("my_mlcache", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache", "cache_shm"))

            -- cache something in cache_1's LRU

            cache_1.lru:set("key", 123)

            -- GC cache_1 (the LRU should survive because it is shared with cache_2)

            cache_1 = nil
            collectgarbage("collect")

            -- prove LRU survived

            ngx.say((cache_2.lru:get("key")))

            -- GC cache_2 (and the LRU this time, since no more references)

            cache_2 = nil
            collectgarbage("collect")

            -- re-create the caches and a new LRU

            cache_1 = assert(mlcache.new("my_mlcache", "cache_shm"))
            cache_2 = assert(mlcache.new("my_mlcache", "cache_shm"))

            -- this is a new LRU, it has nothing in it

            ngx.say((cache_2.lru:get("key")))
        }
    }
--- request
GET /t
--- response_body
123
nil
--- no_error_log
[error]



=== TEST 4: multiple instances with different names get() of the same key are isolated
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            -- create 2 mlcache

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm"))

            -- set a value in both mlcaches

            local data_1 = assert(cache_1:get("my_key", nil, function() return "value A" end))
            local data_2 = assert(cache_2:get("my_key", nil, function() return "value B" end))

            -- get values from LRU

            local lru_1_value = cache_1.lru:get("my_key")
            local lru_2_value = cache_2.lru:get("my_key")

            ngx.say("cache_1 lru has: ", lru_1_value)
            ngx.say("cache_2 lru has: ", lru_2_value)

            -- delete values from LRU

            cache_1.lru:delete("my_key")
            cache_2.lru:delete("my_key")

            -- get values from shm

            local shm_1_value = assert(cache_1:get("my_key", nil, function() end))
            local shm_2_value = assert(cache_2:get("my_key", nil, function() end))

            ngx.say("cache_1 shm has: ", shm_1_value)
            ngx.say("cache_2 shm has: ", shm_2_value)
        }
    }
--- request
GET /t
--- response_body
cache_1 lru has: value A
cache_2 lru has: value B
cache_1 shm has: value A
cache_2 shm has: value B
--- no_error_log
[error]



=== TEST 5: multiple instances with different names delete() of the same key are isolated
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            -- create 2 mlcache

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            -- set 2 values in both mlcaches

            local data_1 = assert(cache_1:get("my_key", nil, function() return "value A" end))
            local data_2 = assert(cache_2:get("my_key", nil, function() return "value B" end))

            -- test if value is set from shm (safer to check due to the key)

            local shm_v = ngx.shared.cache_shm:get(cache_1.name .. "my_key")
            ngx.say("cache_1 shm has a value: ", shm_v ~= nil)

            -- delete value from mlcache 1

            ngx.say("delete from cache_1")
            assert(cache_1:delete("my_key"))

            -- ensure cache 1 key is deleted from LRU

            local lru_v = cache_1.lru:get("my_key")
            ngx.say("cache_1 lru has: ", lru_v)

            -- ensure cache 1 key is deleted from shm

            local shm_v = ngx.shared.cache_shm:get(cache_1.name .. "my_key")
            ngx.say("cache_1 shm has: ", shm_v)

            -- ensure cache 2 still has its value

            local shm_v_2 = ngx.shared.cache_shm:get(cache_2.name .. "my_key")
            ngx.say("cache_2 shm has a value: ", shm_v_2 ~= nil)

            local lru_v_2 = cache_2.lru:get("my_key")
            ngx.say("cache_2 lru has: ", lru_v_2)
        }
    }
--- request
GET /t
--- response_body
cache_1 shm has a value: true
delete from cache_1
cache_1 lru has: nil
cache_1 shm has: nil
cache_2 shm has a value: true
cache_2 lru has: value B
--- no_error_log
[error]



=== TEST 6: multiple instances with different names peek() of the same key are isolated
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            -- must reset the shm so that when repeated, this tests doesn't
            -- return unpredictible TTLs (0.9xxxs)
            ngx.shared.cache_shm:flush_all()
            ngx.shared.cache_shm:flush_expired()

            local mlcache = require "kong.resty.mlcache"

            -- create 2 mlcaches

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            -- reset LRUs so repeated tests allow the below get() to set the
            -- value in the shm

            cache_1.lru:delete("my_key")
            cache_2.lru:delete("my_key")

            -- set a value in both mlcaches

            local data_1 = assert(cache_1:get("my_key", { ttl = 1 }, function() return "value A" end))
            local data_2 = assert(cache_2:get("my_key", { ttl = 2 }, function() return "value B" end))

            -- peek cache 1

            local ttl, err, val = assert(cache_1:peek("my_key"))

            ngx.say("cache_1 ttl: ", ttl)
            ngx.say("cache_1 value: ", val)

            -- peek cache 2

            local ttl, err, val = assert(cache_2:peek("my_key"))

            ngx.say("cache_2 ttl: ", ttl)
            ngx.say("cache_2 value: ", val)
        }
    }
--- request
GET /t
--- response_body
cache_1 ttl: 1
cache_1 value: value A
cache_2 ttl: 2
cache_2 value: value B
--- no_error_log
[error]



=== TEST 7: non-namespaced instances use different delete() broadcast channel
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            -- create 2 mlcaches

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function(channel)
                        ngx.say("cache_1 channel: ", channel)
                        return true
                    end,
                    poll = function() end,
                }
            }))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function(channel)
                        ngx.say("cache_2 channel: ", channel)
                        return true
                    end,
                    poll = function() end,
                }
            }))

            assert(cache_1:delete("my_key"))
            assert(cache_2:delete("my_key"))
        }
    }
--- request
GET /t
--- response_body
cache_1 channel: mlcache:invalidations:my_mlcache_1
cache_2 channel: mlcache:invalidations:my_mlcache_2
--- no_error_log
[error]



=== TEST 8: non-namespaced instances use different purge() broadcast channel
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            -- create 2 mlcaches

            local cache_1 = assert(mlcache.new("my_mlcache_1", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function(channel)
                        ngx.say("cache_1 channel: ", channel)
                        return true
                    end,
                    poll = function() end,
                }
            }))
            local cache_2 = assert(mlcache.new("my_mlcache_2", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function(channel)
                        ngx.say("cache_2 channel: ", channel)
                        return true
                    end,
                    poll = function() end,
                }
            }))

            assert(cache_1:purge())
            assert(cache_2:purge())
        }
    }
--- request
GET /t
--- response_body
cache_1 channel: mlcache:purge:my_mlcache_1
cache_2 channel: mlcache:purge:my_mlcache_2
--- no_error_log
[error]
