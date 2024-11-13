# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use lib '.';
use t::Util;

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm      1m;
    lua_shared_dict  cache_shm_miss 1m;
    lua_shared_dict  ipc_shm        1m;
};

run_tests();

__DATA__

=== TEST 1: purge() errors if no ipc
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local ok, err = pcall(cache.purge, cache)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
no ipc to propagate purge, specify opts.ipc_shm or opts.ipc
--- no_error_log
[error]



=== TEST 2: purge() deletes all items from L1 + L2 (sanity 1/2)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            -- populate mlcache

            for i = 1, 100 do
                assert(cache:get(tostring(i), nil, function() return i end))
            end

            -- purge

            assert(cache:purge())

            for i = 1, 100 do
                local value, err = cache:get(tostring(i), nil, function() return nil end)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if value ~= nil then
                    ngx.say("key ", i, " had: ", value)
                end
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



=== TEST 3: purge() deletes all items from L1 (sanity 2/2)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            -- populate mlcache

            for i = 1, 100 do
                assert(cache:get(tostring(i), nil, function() return i end))
            end

            -- purge

            assert(cache:purge())

            for i = 1, 100 do
                local value = cache.lru:get(tostring(i))

                if value ~= nil then
                    ngx.say("key ", i, " had: ", value)
                end
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



=== TEST 4: purge() deletes all items from L1 with a custom LRU
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local lrucache = require "resty.lrucache"

            local lru = lrucache.new(100)

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                lru = lru,
            }))

            -- populate mlcache

            for i = 1, 100 do
                assert(cache:get(tostring(i), nil, function() return i end))
            end

            -- purge

            assert(cache:purge())

            for i = 1, 100 do
                local value = cache.lru:get(tostring(i))

                if value ~= nil then
                    ngx.say("key ", i, " had: ", value)
                end
            end

            ngx.say("ok")
            ngx.say("lru instance is the same one: ", lru == cache.lru)
        }
    }
--- request
GET /t
--- response_body
ok
lru instance is the same one: true
--- no_error_log
[error]



=== TEST 5: purge() deletes all items from shm_miss is specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                shm_miss = "cache_shm_miss",
            }))

            -- populate mlcache

            for i = 1, 100 do
                local _, err = cache:get(tostring(i), nil, function() return nil end)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            -- purge

            assert(cache:purge())

            local called = 0

            for i = 1, 100 do
                local value, err = cache:get(tostring(i), nil, function() return i end)

                if value ~= i then
                    ngx.say("key ", i, " had: ", value)
                end
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



=== TEST 6: purge() does not call shm:flush_expired() by default
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            do
                local cache_shm = ngx.shared.cache_shm
                local mt = getmetatable(cache_shm)
                local orig_cache_shm_flush_expired = mt.flush_expired

                mt.flush_expired = function(self, ...)
                    ngx.say("flush_expired called with 'max_count'")

                    return orig_cache_shm_flush_expired(self, ...)
                end
            end

            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            assert(cache:purge())
        }
    }
--- request
GET /t
--- response_body_unlike
flush_expired called with 'max_count'
--- no_error_log
[error]



=== TEST 7: purge() calls shm:flush_expired() if argument specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            do
                local cache_shm = ngx.shared.cache_shm
                local mt = getmetatable(cache_shm)
                local orig_cache_shm_flush_expired = mt.flush_expired

                mt.flush_expired = function(self, ...)
                    local arg = { ... }
                    local n = arg[1]
                    ngx.say("flush_expired called with 'max_count': ", n)

                    return orig_cache_shm_flush_expired(self, ...)
                end
            end

            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            assert(cache:purge(true))
        }
    }
--- request
GET /t
--- response_body
flush_expired called with 'max_count': nil
--- no_error_log
[error]



=== TEST 8: purge() calls shm:flush_expired() if shm_miss is specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            do
                local cache_shm = ngx.shared.cache_shm
                local mt = getmetatable(cache_shm)
                local orig_cache_shm_flush_expired = mt.flush_expired

                mt.flush_expired = function(self, ...)
                    local arg = { ... }
                    local n = arg[1]
                    ngx.say("flush_expired called with 'max_count': ", n)

                    return orig_cache_shm_flush_expired(self, ...)
                end
            end

            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                shm_miss = "cache_shm_miss",
            }))

            assert(cache:purge(true))
        }
    }
--- request
GET /t
--- response_body
flush_expired called with 'max_count': nil
flush_expired called with 'max_count': nil
--- no_error_log
[error]



=== TEST 9: purge() calls broadcast() on purge channel
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc = {
                    register_listeners = function() end,
                    broadcast = function(channel, data, ...)
                        ngx.say("channel: ", channel)
                        ngx.say("data:", data)
                        ngx.say("other args:", ...)
                        return true
                    end,
                    poll = function() end,
                }
            }))

            assert(cache:purge())
        }
    }
--- request
GET /t
--- response_body
channel: mlcache:purge:my_mlcache
data:
other args:
--- no_error_log
[error]
