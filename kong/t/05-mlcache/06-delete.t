# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(2);

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

=== TEST 1: delete() errors if no ipc
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local ok, err = pcall(cache.delete, cache, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
no ipc to propagate deletion, specify opts.ipc_shm or opts.ipc
--- no_error_log
[error]



=== TEST 2: delete() validates key
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            local ok, err = pcall(cache.delete, cache, 123)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
key must be a string
--- no_error_log
[error]



=== TEST 3: delete() removes a cached value from LRU + shm
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
            }))

            local value = 123

            local function cb()
                ngx.say("in callback")
                return value
            end

            -- set a value (callback call)

            local data = assert(cache:get("key", nil, cb))
            ngx.say("from callback: ", data)

            -- get a value (no callback call)

            data = assert(cache:get("key", nil, cb))
            ngx.say("from LRU: ", data)

            -- test if value is set from shm (safer to check due to the key)

            local v = ngx.shared.cache_shm:get(cache.name .. "key")
            ngx.say("shm has value before delete: ", v ~= nil)

            -- delete the value

            assert(cache:delete("key"))

            local v = ngx.shared.cache_shm:get(cache.name .. "key")
            ngx.say("shm has value after delete: ", v ~= nil)

            -- ensure LRU was also deleted

            v = cache.lru:get("key")
            ngx.say("from LRU: ", v)

            -- start over from callback again

            value = 456

            data = assert(cache:get("key", nil, cb))
            ngx.say("from callback: ", data)
        }
    }
--- request
GET /t
--- response_body
in callback
from callback: 123
from LRU: 123
shm has value before delete: true
shm has value after delete: false
from LRU: nil
in callback
from callback: 456
--- no_error_log
[error]



=== TEST 4: delete() removes a cached nil from shm_miss if specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                shm_miss = "cache_shm_miss",
            }))

            local value = nil

            local function cb()
                ngx.say("in callback")
                return value
            end

            -- set a value (callback call)

            local data, err = cache:get("key", nil, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("from callback: ", data)

            -- get a value (no callback call)

            data, err = cache:get("key", nil, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("from LRU: ", data)

            -- test if value is set from shm (safer to check due to the key)

            local v = ngx.shared.cache_shm_miss:get(cache.name .. "key")
            ngx.say("shm_miss has value before delete: ", v ~= nil)

            -- delete the value

            assert(cache:delete("key"))

            local v = ngx.shared.cache_shm_miss:get(cache.name .. "key")
            ngx.say("shm_miss has value after delete: ", v ~= nil)

            -- ensure LRU was also deleted

            v = cache.lru:get("key")
            ngx.say("from LRU: ", v)

            -- start over from callback again

            value = 456

            data, err = cache:get("key", nil, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("from callback again: ", data)
        }
    }
--- request
GET /t
--- response_body
in callback
from callback: nil
from LRU: nil
shm_miss has value before delete: true
shm_miss has value after delete: false
from LRU: nil
in callback
from callback again: 456
--- no_error_log
[error]



=== TEST 5: delete() calls broadcast with invalidated key
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
                        ngx.say("data: ", data)
                        ngx.say("other args:", ...)
                        return true
                    end,
                    poll = function() end,
                }
            }))

            assert(cache:delete("my_key"))
        }
    }
--- request
GET /t
--- response_body
channel: mlcache:invalidations:my_mlcache
data: my_key
other args:
--- no_error_log
[error]
