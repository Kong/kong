# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use lib '.';
use t::Util;

workers(2);

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) + 2;

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm 1m;
    lua_shared_dict  ipc_shm   1m;

    init_by_lua_block {
        -- local verbose = true
        local verbose = false
        local outfile = "$Test::Nginx::Util::ErrLogFile"
        -- local outfile = "/tmp/v.log"
        if verbose then
            local dump = require "jit.dump"
            dump.on(nil, outfile)
        else
            local v = require "jit.v"
            v.on(outfile)
        end

        require "resty.core"
        -- jit.opt.start("hotloop=1")
        -- jit.opt.start("loopunroll=1000000")
        -- jit.off()
    }
};

run_tests();

__DATA__

=== TEST 1: update() with ipc_shm catches up with invalidation events
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }))

            cache.ipc:subscribe(cache.events.invalidation.channel, function(data)
                ngx.log(ngx.NOTICE, "received event from invalidations: ", data)
            end)

            assert(cache:delete("my_key"))
            assert(cache:update())
        }
    }
--- request
GET /t
--- ignore_response_body
--- no_error_log
[error]
--- error_log
received event from invalidations: my_key



=== TEST 2: update() with ipc_shm timeouts when waiting for too long
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }))

            cache.ipc:subscribe(cache.events.invalidation.channel, function(data)
                ngx.log(ngx.NOTICE, "received event from invalidations: ", data)
            end)

            assert(cache:delete("my_key"))
            assert(cache:delete("my_other_key"))
            ngx.shared.ipc_shm:delete(2)

            local ok, err = cache:update(0.1)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
could not poll ipc events: timeout
--- no_error_log
[error]
received event from invalidations: my_other
--- error_log
received event from invalidations: my_key



=== TEST 3: update() with ipc_shm JITs when no events to catch up
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }))
            for i = 1, 10e3 do
                assert(cache:update())
            end
        }
    }
--- request
GET /t
--- ignore_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[TRACE\s+\d+ content_by_lua\(nginx\.conf:\d+\):7 loop\]/



=== TEST 4: set() with ipc_shm invalidates other workers' LRU cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local opts = {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }

            local cache = assert(mlcache.new("namespace", "cache_shm", opts))
            local cache_clone = assert(mlcache.new("namespace", "cache_shm", opts))

            do
                local lru_delete = cache.lru.delete
                cache.lru.delete = function(self, key)
                    ngx.say("called lru:delete() with key: ", key)
                    return lru_delete(self, key)
                end
            end

            assert(cache:set("my_key", nil, nil))

            ngx.say("calling update on cache")
            assert(cache:update())

            ngx.say("calling update on cache_clone")
            assert(cache_clone:update())
        }
    }
--- request
GET /t
--- response_body
calling update on cache
called lru:delete() with key: my_key
calling update on cache_clone
called lru:delete() with key: my_key
--- no_error_log
[error]



=== TEST 5: delete() with ipc_shm invalidates other workers' LRU cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local opts = {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }

            local cache = assert(mlcache.new("namespace", "cache_shm", opts))
            local cache_clone = assert(mlcache.new("namespace", "cache_shm", opts))

            do
                local lru_delete = cache.lru.delete
                cache.lru.delete = function(self, key)
                    ngx.say("called lru:delete() with key: ", key)
                    return lru_delete(self, key)
                end
            end

            assert(cache:delete("my_key"))

            ngx.say("calling update on cache")
            assert(cache:update())

            ngx.say("calling update on cache_clone")
            assert(cache_clone:update())
        }
    }
--- request
GET /t
--- response_body
called lru:delete() with key: my_key
calling update on cache
called lru:delete() with key: my_key
calling update on cache_clone
called lru:delete() with key: my_key
--- no_error_log
[error]



=== TEST 6: purge() with mlcache_shm invalidates other workers' LRU cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local opts = {
                ipc_shm = "ipc_shm",
                debug = true -- allows same worker to receive its own published events
            }

            local cache = assert(mlcache.new("namespace", "cache_shm", opts))
            local cache_clone = assert(mlcache.new("namespace", "cache_shm", opts))

            local lru = cache.lru

            ngx.say("both instances use the same lru: ", cache.lru == cache_clone.lru)

            do
                local lru_flush_all = lru.flush_all
                cache.lru.flush_all = function(self)
                    ngx.say("called lru:flush_all()")
                    return lru_flush_all(self)
                end
            end

            assert(cache:purge())

            ngx.say("calling update on cache_clone")
            assert(cache_clone:update())

            ngx.say("both instances use the same lru: ", cache.lru == cache_clone.lru)
            ngx.say("lru didn't change after purge: ", cache.lru == lru)
        }
    }
--- request
GET /t
--- response_body
both instances use the same lru: true
called lru:flush_all()
calling update on cache_clone
called lru:flush_all()
both instances use the same lru: true
lru didn't change after purge: true
--- no_error_log
[error]
