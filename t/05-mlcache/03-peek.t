# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(2);

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) + 2;

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm      1m;
    lua_shared_dict  cache_shm_miss 1m;

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

=== TEST 1: peek() validates key
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = pcall(cache.peek, cache)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
key must be a string
--- no_error_log
[error]



=== TEST 2: peek() returns nil if a key has never been fetched before
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local ttl, err = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", ttl)
        }
    }
--- request
GET /t
--- response_body
ttl: nil
--- no_error_log
[error]



=== TEST 3: peek() returns the remaining ttl if a key has been fetched before
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local function cb()
                return nil
            end

            local val, err = cache:get("my_key", { neg_ttl = 20 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1.1)

            local ttl, err = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl < 19: ", tostring(math.floor(ttl) < 19))

            ngx.sleep(1.1)

            local ttl, err = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl < 18: ", tostring(math.floor(ttl) < 18))
        }
    }
--- request
GET /t
--- response_body
ttl < 19: true
ttl < 18: true
--- no_error_log
[error]



=== TEST 4: peek() returns 0 as ttl when a key never expires in positive cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb()
                return "cat"
            end

            local val, err = cache:get("my_key", { ttl = 0 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1)

            local ttl, _, _, _, no_ttl = assert(cache:peek("my_key"))
            ngx.say("ttl: ", math.ceil(ttl))
            ngx.say("no ttl: ", tostring(no_ttl))

            ngx.sleep(1)

            ttl, _, _, _, no_ttl = assert(cache:peek("my_key"))
            ngx.say("ttl: ", math.ceil(ttl))
            ngx.say("no ttl: ", tostring(no_ttl))
        }
    }
--- request
GET /t
--- response_body
ttl: 0
no ttl: true
ttl: 0
no ttl: true
--- no_error_log
[error]



=== TEST 5: peek() never returns no_ttl = true when key has positive ttl 0 in positive cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss",
            }))

            local function cb()
                return "cat"
            end

            local val, err = cache:get("my_key", { ttl = 0.2 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
            ngx.say("ttl positive: ", tostring(ttl > 0))
            ngx.say("no ttl: ", tostring(no_ttl))

            local zero_printed

            while true do
                ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
                assert(no_ttl == false, "should never return 'no_ttl = true'")
                if ttl == 0 and not zero_printed then
                    zero_printed = true
                    ngx.say("ttl zero: ", tostring(ttl == 0))
                    ngx.say("no ttl: ", tostring(no_ttl))

                elseif ttl < 0 then
                    break
                end
                ngx.sleep(0)
            end

            ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
            ngx.say("ttl negative: ", tostring(ttl < 0))
            ngx.say("no ttl: ", tostring(no_ttl))
        }
    }
--- request
GET /t
--- response_body
ttl positive: true
no ttl: false
ttl zero: true
no ttl: false
ttl negative: true
no ttl: false
--- no_error_log
[error]



=== TEST 6: peek() returns 0 as ttl when a key never expires in negative cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb()
                return nil
            end

            local val, err = cache:get("my_key", { neg_ttl = 0 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1)

            local ttl, _, _, _, no_ttl = assert(cache:peek("my_key"))
            ngx.say("ttl: ", math.ceil(ttl))
            ngx.say("no ttl: ", tostring(no_ttl))

            ngx.sleep(1)

            ttl, _, _, _, no_ttl = assert(cache:peek("my_key"))
            ngx.say("ttl: ", math.ceil(ttl))
            ngx.say("no ttl: ", tostring(no_ttl))
        }
    }
--- request
GET /t
--- response_body
ttl: 0
no ttl: true
ttl: 0
no ttl: true
--- no_error_log
[error]



=== TEST 7: peek() never returns no_ttl = true when key has positive ttl 0 in negative cache
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss",
            }))

            local function cb()
                return nil
            end

            local val, err = cache:get("my_key", { neg_ttl = 0.2 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
            ngx.say("ttl positive: ", tostring(ttl > 0))
            ngx.say("no ttl: ", tostring(no_ttl))

            local zero_printed

            while true do
                ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
                assert(no_ttl == false, "should never return 'no_ttl = true'")
                if ttl == 0 and not zero_printed then
                    zero_printed = true
                    ngx.say("ttl zero: ", tostring(ttl == 0))
                    ngx.say("no ttl: ", tostring(no_ttl))

                elseif ttl < 0 then
                    break
                end
                ngx.sleep(0)
            end

            ttl, _, _, _, no_ttl = assert(cache:peek("my_key", true))
            ngx.say("ttl negative: ", tostring(ttl < 0))
            ngx.say("no ttl: ", tostring(no_ttl))
        }
    }
--- request
GET /t
--- response_body
ttl positive: true
no ttl: false
ttl zero: true
no ttl: false
ttl negative: true
no ttl: false
--- no_error_log
[error]



=== TEST 8: peek() returns remaining ttl if shm_miss is specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss",
            }))

            local function cb()
                return nil
            end

            local val, err = cache:get("my_key", { neg_ttl = 20 }, cb)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1.1)

            local ttl, err = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl < 19: ", tostring(math.floor(ttl) < 19))

            ngx.sleep(1.1)

            local ttl, err = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl < 18: ", tostring(math.floor(ttl) < 18))
        }
    }
--- request
GET /t
--- response_body
ttl < 19: true
ttl < 18: true
--- no_error_log
[error]



=== TEST 9: peek() returns the value if a key has been fetched before
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local function cb_number()
                return 123
            end

            local function cb_nil()
                return nil
            end

            local val, err = cache:get("my_key", nil, cb_number)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local val, err = cache:get("my_nil_key", nil, cb_nil)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local ttl, err, val = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", math.ceil(ttl), " val: ", val)

            local ttl, err, val = cache:peek("my_nil_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", math.ceil(ttl), " nil_val: ", val)
        }
    }
--- request
GET /t
--- response_body_like
ttl: \d* val: 123
ttl: \d* nil_val: nil
--- no_error_log
[error]



=== TEST 10: peek() returns the value if shm_miss is specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss",
            }))

            local function cb_nil()
                return nil
            end

            local val, err = cache:get("my_nil_key", nil, cb_nil)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local ttl, err, val = cache:peek("my_nil_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", math.ceil(ttl), " nil_val: ", val)
        }
    }
--- request
GET /t
--- response_body_like
ttl: \d* nil_val: nil
--- no_error_log
[error]



=== TEST 11: peek() JITs on hit
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb()
                return 123456
            end

            local val = assert(cache:get("key", nil, cb))
            ngx.say("val: ", val)

            for i = 1, 10e3 do
                assert(cache:peek("key"))
            end
        }
    }
--- request
GET /t
--- response_body
val: 123456
--- no_error_log
[error]
--- error_log eval
qr/\[TRACE\s+\d+ content_by_lua\(nginx\.conf:\d+\):13 loop\]/



=== TEST 12: peek() JITs on miss
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            for i = 1, 10e3 do
                local ttl, err, val = cache:peek("key")
                assert(err == nil)
                assert(ttl == nil)
                assert(val == nil)
            end
        }
    }
--- request
GET /t
--- response_body

--- no_error_log
[error]
--- error_log eval
qr/\[TRACE\s+\d+ content_by_lua\(nginx\.conf:\d+\):6 loop\]/



=== TEST 13: peek() returns nil if a value expired
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(cache:get("my_key", { ttl = 0.3 }, function()
                return 123
            end))

            ngx.sleep(0.3)

            local ttl, err, data, stale = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", ttl)
            ngx.say("data: ", data)
            ngx.say("stale: ", stale)
        }
    }
--- request
GET /t
--- response_body
ttl: nil
data: nil
stale: nil
--- no_error_log
[error]



=== TEST 14: peek() returns nil if a value expired in 'shm_miss'
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss"
            })
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local data, err = cache:get("my_key", { neg_ttl = 0.3 }, function()
                return nil
            end)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(0.3)

            local ttl, err, data, stale = cache:peek("my_key")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", ttl)
            ngx.say("data: ", data)
            ngx.say("stale: ", stale)
        }
    }
--- request
GET /t
--- response_body
ttl: nil
data: nil
stale: nil
--- no_error_log
[error]



=== TEST 15: peek() accepts stale arg and returns stale values
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm")
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(cache:get("my_key", { ttl = 0.3 }, function()
                return 123
            end))

            ngx.sleep(0.31)

            local ttl, err, data, stale = cache:peek("my_key", true)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", ttl)
            ngx.say("data: ", data)
            ngx.say("stale: ", stale)
        }
    }
--- request
GET /t
--- response_body_like chomp
ttl: -0\.\d+
data: 123
stale: true
--- no_error_log
[error]



=== TEST 16: peek() accepts stale arg and returns stale values from 'shm_miss'
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache, err = mlcache.new("my_mlcache", "cache_shm", {
                shm_miss = "cache_shm_miss"
            })
            if not cache then
                ngx.log(ngx.ERR, err)
                return
            end

            local data, err = cache:get("my_key", { neg_ttl = 0.3 }, function()
                return nil
            end)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(0.31)

            local ttl, err, data, stale = cache:peek("my_key", true)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("ttl: ", ttl)
            ngx.say("data: ", data)
            ngx.say("stale: ", stale)
        }
    }
--- request
GET /t
--- response_body_like chomp
ttl: -0\.\d+
data: nil
stale: true
--- no_error_log
[error]



=== TEST 17: peek() does not evict stale items from L2 shm
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 0.3,
            }))

            local data, err = cache:get("key", nil, function()
                return 123
            end)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(0.31)

            for i = 1, 3 do
                remaining_ttl, err, data = cache:peek("key", true)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end
                ngx.say("remaining_ttl: ", remaining_ttl)
                ngx.say("data: ", data)
            end
        }
    }
--- request
GET /t
--- response_body_like chomp
remaining_ttl: -\d\.\d+
data: 123
remaining_ttl: -\d\.\d+
data: 123
remaining_ttl: -\d\.\d+
data: 123
--- no_error_log
[error]



=== TEST 18: peek() does not evict stale negative data from L2 shm_miss
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                neg_ttl = 0.3,
                shm_miss = "cache_shm_miss",
            }))

            local data, err = cache:get("key", nil, function()
                return nil
            end)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(0.31)

            for i = 1, 3 do
                remaining_ttl, err, data = cache:peek("key", true)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end
                ngx.say("remaining_ttl: ", remaining_ttl)
                ngx.say("data: ", data)
            end
        }
    }
--- request
GET /t
--- response_body_like chomp
remaining_ttl: -\d\.\d+
data: nil
remaining_ttl: -\d\.\d+
data: nil
remaining_ttl: -\d\.\d+
data: nil
--- no_error_log
[error]
