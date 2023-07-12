# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use lib '.';
use t::Util;

no_long_string();

workers(2);

#repeat_each(2);

plan tests => repeat_each() * ((blocks() * 3) + 12 * 3); # n * 3 -> for debug error_log concurrency tests

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm      1m;
    #lua_shared_dict  cache_shm_miss 1m;

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

=== TEST 1: get_bulk() validates bulk
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local pok, perr = pcall(cache.get_bulk, cache)
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
bulk must be a table
--- no_error_log
[error]



=== TEST 2: get_bulk() ensures bulk has n field
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return 1 end, nil,
            })
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
bulk must have n field
--- no_error_log
[error]



=== TEST 3: get_bulk() validates operations keys
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, function() return 1 end, nil,
                false, nil, function() return 1 end, nil,
                n = 2,
            })
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
key at index 5 must be a string for operation 2 (got boolean)
--- no_error_log
[error]



=== TEST 4: get_bulk() validates operations callbacks
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_b", nil, nil, nil,
                "key_a", nil, function() return 1 end, nil,
                n = 2,
            })
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, false, nil,
                n = 2,
            })
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
callback at index 3 must be a function for operation 1 (got nil)
callback at index 7 must be a function for operation 2 (got boolean)
--- no_error_log
[error]



=== TEST 5: get_bulk() validates opts argument
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb() end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, true)
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, {})
            if not pok then
                ngx.say(perr)
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
opts must be a table
ok
--- no_error_log
[error]



=== TEST 6: get_bulk() validates opts.concurrency
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb() end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, { concurrency = true })
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, { concurrency = 0 })
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, { concurrency = -1 })
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }, { concurrency = 1 })
            if not pok then
                ngx.say(perr)
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
opts.concurrency must be a number
opts.concurrency must be > 0
opts.concurrency must be > 0
ok
--- no_error_log
[error]



=== TEST 7: get_bulk() multiple fetch L3
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return 2 end, nil,
                "key_c", nil, function() return 3 end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 3
2 nil 3
3 nil 3
--- no_error_log
[error]



=== TEST 8: get_bulk() multiple fetch L2
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            assert(cache:get("key_a", nil, function() return 1 end))
            assert(cache:get("key_b", nil, function() return 2 end))
            assert(cache:get("key_c", nil, function() return 3 end))

            cache.lru:delete("key_a")
            cache.lru:delete("key_b")
            cache.lru:delete("key_c")

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return -3 end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 2
2 nil 2
3 nil 2
--- no_error_log
[error]



=== TEST 9: get_bulk() multiple fetch L1
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            assert(cache:get("key_a", nil, function() return 1 end))
            assert(cache:get("key_b", nil, function() return 2 end))
            assert(cache:get("key_c", nil, function() return 3 end))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return -3 end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 1
2 nil 1
3 nil 1
--- no_error_log
[error]



=== TEST 10: get_bulk() multiple fetch L1/single fetch L3
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            assert(cache:get("key_a", nil, function() return 1 end))
            assert(cache:get("key_b", nil, function() return 2 end))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return 3 end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 1
2 nil 1
3 nil 3
--- no_error_log
[error]



=== TEST 11: get_bulk() multiple fetch L1/single fetch L3 (with nils)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local _, err = cache:get("key_a", nil, function() return nil end)
            assert(err == nil, err)
            local _, err = cache:get("key_b", nil, function() return nil end)
            assert(err == nil, err)

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return nil end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
nil nil 1
nil nil 1
nil nil 3
--- no_error_log
[error]



=== TEST 12: get_bulk() mixed fetch L1/L2/L3
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            assert(cache:get("key_a", nil, function() return 1 end))
            assert(cache:get("key_b", nil, function() return 2 end))

            -- remove key_b from L1
            cache.lru:delete("key_b")

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return 3 end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 1
2 nil 2
3 nil 3
--- no_error_log
[error]



=== TEST 13: get_bulk() mixed fetch L1/L2/L3 (with nils)
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local _, err = cache:get("key_a", nil, function() return nil end)
            assert(err == nil, err)
            local _, err = cache:get("key_b", nil, function() return nil end)
            assert(err == nil, err)

            -- remove key_b from L1
            cache.lru:delete("key_b")

            local res, err = cache:get_bulk {
                "key_a", nil, function() return -1 end, nil,
                "key_b", nil, function() return -2 end, nil,
                "key_c", nil, function() return nil end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
nil nil 1
nil nil 2
nil nil 3
--- no_error_log
[error]



=== TEST 14: get_bulk() returns callback-returned errors
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return 2 end, nil,
                "key_c", nil, function() return nil, "some error" end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 3
2 nil 3
nil some error nil
--- no_error_log
[error]



=== TEST 15: get_bulk() returns callback runtime errors
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return 2 end, nil,
                "key_c", nil, function() return error("some error") end, nil,
                n = 3,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body_like
1 nil 3
2 nil 3
nil callback threw an error: some error
stack traceback:
.*? nil
--- no_error_log
[error]



=== TEST 16: get_bulk() runs L3 callback on expired keys
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local n = 0
            local function cb()
                n = n + 1
                return n
            end

            assert(cache:get("key_a", { ttl = 0.2 }, cb))

            ngx.sleep(0.2)

            local res, err = cache:get_bulk {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
2 nil 3
3 nil 3
--- no_error_log
[error]



=== TEST 17: get_bulk() honors ttl and neg_ttl instance attributes
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 0.2,
                neg_ttl = 0.3,
            }))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return nil end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end

            ngx.say()
            local ttl, _, value = assert(cache:peek("key_a"))
            ngx.say("key_a: ", value, " (ttl: ", ttl, ")")
            local ttl, _, value = assert(cache:peek("key_b"))
            ngx.say("key_b: ", value, " (ttl: ", ttl, ")")
        }
    }
--- request
GET /t
--- response_body
1 nil 3
nil nil 3

key_a: 1 (ttl: 0.2)
key_b: nil (ttl: 0.3)
--- no_error_log
[error]



=== TEST 18: get_bulk() validates operations ttl and neg_ttl
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", { ttl = true }, function() return 1 end, nil,
                "key_b", nil, function() return 2 end, nil,
                n = 2,
            })
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(cache.get_bulk, cache, {
                "key_a", nil, function() return 1 end, nil,
                "key_b", { neg_ttl = true }, function() return 2 end, nil,
                n = 2,
            })
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
options at index 2 for operation 1 are invalid: opts.ttl must be a number
options at index 6 for operation 2 are invalid: opts.neg_ttl must be a number
--- no_error_log
[error]



=== TEST 19: get_bulk() accepts ttl and neg_ttl for each operation
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 1,
                neg_ttl = 2,
            }))

            local res, err = cache:get_bulk {
                "key_a", { ttl = 0.4, neg_ttl = 3 }, function() return 1 end, nil,
                "key_b", { neg_ttl = 0.8 }, function() return nil end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end

            ngx.say()
            local ttl, _, value = assert(cache:peek("key_a"))
            ngx.say("key_a: ", value, " (ttl: ", ttl, ")")
            local ttl, _, value = assert(cache:peek("key_b"))
            ngx.say("key_b: ", value, " (ttl: ", ttl, ")")
        }
    }
--- request
GET /t
--- response_body
1 nil 3
nil nil 3

key_a: 1 (ttl: 0.4)
key_b: nil (ttl: 0.8)
--- no_error_log
[error]



=== TEST 20: get_bulk() honors ttl from callback return values
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 1,
            }))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return 1, nil, 0.2 end, nil,
                "key_b", nil, function() return 2 end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end

            ngx.say()
            local ttl, _, value = assert(cache:peek("key_a"))
            ngx.say("key_a: ", value, " (ttl: ", ttl, ")")
            local ttl, _, value = assert(cache:peek("key_b"))
            ngx.say("key_b: ", value, " (ttl: ", ttl, ")")
        }
    }
--- request
GET /t
--- response_body
1 nil 3
2 nil 3

key_a: 1 (ttl: 0.2)
key_b: 2 (ttl: 1)
--- no_error_log
[error]



=== TEST 21: get_bulk() honors resurrect_ttl instance attribute
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 0.2,
                resurrect_ttl = 0.3,
            }))

            local i = 0
            local function cb()
                i = i + 1
                if i == 2 then
                    return nil, "some error"
                end
                return i
            end

            assert(cache:get("key_a", nil, cb))

            ngx.sleep(0.2)

            local res, err = cache:get_bulk {
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end

            ngx.sleep(0.1)

            ngx.say()
            local ttl, _, value = cache:peek("key_a")
            ngx.say(string.format("key_a: %d ttl: %.2f", value, ttl))
            local ttl, _, value = cache:peek("key_b")
            ngx.say(string.format("key_b: %d ttl: %.2f", value, ttl))
        }
    }
--- request
GET /t
--- response_body_like
1 nil 4
3 nil 3

key_a: 1 ttl: 0\.(?:2|1)\d+
key_b: 3 ttl: 0\.(?:1|0)\d+
--- no_error_log
[error]



=== TEST 22: get_bulk() accepts resurrect_ttl for each operation
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                ttl = 0.2,
                resurrect_ttl = 3,
            }))

            local i = 0
            local function cb()
                i = i + 1
                if i == 2 then
                    return nil, "some error"
                end
                return i
            end

            assert(cache:get("key_a", nil, cb))

            ngx.sleep(0.2)

            local res, err = cache:get_bulk {
                "key_a", { resurrect_ttl = 0.3 }, cb, nil,
                "key_b", nil, cb, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end

            ngx.sleep(0.1)

            ngx.say()
            local ttl, _, value = cache:peek("key_a")
            ngx.say(string.format("key_a: %d ttl: %.2f", value, ttl))
            local ttl, _, value = cache:peek("key_b")
            ngx.say(string.format("key_b: %d ttl: %.2f", value, ttl))
        }
    }
--- request
GET /t
--- response_body_like
1 nil 4
3 nil 3

key_a: 1 ttl: 0\.(?:2|1)\d+
key_b: 3 ttl: 0\.(?:1|0)\d+
--- no_error_log
[error]



=== TEST 23: get_bulk() honors l1_serializer instance attribute
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                l1_serializer = function(t)
                    return t.x
                end
            }))

            local res, err = cache:get_bulk {
                "key_a", nil, function() return { x = "hello" } end, nil,
                "key_b", nil, function() return { x = "world" } end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
hello nil 3
world nil 3
--- no_error_log
[error]



=== TEST 24: get_bulk() accepts l1_serializer for each operation
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                l1_serializer = function(t)
                    return t.x
                end
            }))

            local function l1_serializer_a(t) return t.x end
            local function l1_serializer_b(t) return t.y end

            local res, err = cache:get_bulk {
                "key_a", { l1_serializer = l1_serializer_a }, function() return { x = "hello" } end, nil,
                "key_b", { l1_serializer = l1_serializer_b }, function() return { y = "world" } end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
hello nil 3
world nil 3
--- no_error_log
[error]



=== TEST 25: get_bulk() honors shm_set_tries instance attribute
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.cache_shm
            dict:flush_all()
            dict:flush_expired()

            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_set_tries = 1,
            }))

            -- fill up shm

            local idx = 0

            while true do
                local ok, err, forcible = dict:set(idx, string.rep("a", 2^2))
                if not ok then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if forcible then
                    break
                end

                idx = idx + 1
            end

            -- now, trigger a hit with a value ~3 times as large
            -- which should trigger retries and eventually remove 3 other
            -- cached items (but still not enough memory)

            local res, err = cache:get_bulk {
                "key_a", nil, function() return string.rep("a", 2^12) end, nil,
                "key_b", nil, function() return 2 end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
        }
    }
--- request
GET /t
--- ignore_response_body
--- no_error_log
[error]
--- error_log
could not write to lua_shared_dict 'cache_shm' after 1 tries (no memory)



=== TEST 26: get_bulk() accepts shm_set_tries for each operation
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.cache_shm
            dict:flush_all()
            dict:flush_expired()

            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                shm_set_tries = 3,
            }))

            -- fill up shm

            local idx = 0

            while true do
                local ok, err, forcible = dict:set(idx, string.rep("a", 2^2))
                if not ok then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if forcible then
                    break
                end

                idx = idx + 1
            end

            -- now, trigger a hit with a value ~3 times as large
            -- which should trigger retries and eventually remove 3 other
            -- cached items (but still not enough memory)

            local res, err = cache:get_bulk {
                "key_a", { shm_set_tries = 1 }, function() return string.rep("a", 2^12) end, nil,
                "key_b", nil, function() return 2 end, nil,
                n = 2,
            }
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
        }
    }
--- request
GET /t
--- ignore_response_body
--- no_error_log
[error]
--- error_log
could not write to lua_shared_dict 'cache_shm' after 1 tries (no memory)



=== TEST 27: get_bulk() operations wait on lock if another thread is fetching the same key
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache_1 = assert(mlcache.new("my_mlcache", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache", "cache_shm"))

            local function cb(wait)
                if wait then
                    ngx.sleep(wait)
                end

                return "hello"
            end

            local t1_data, t1_hit_lvl
            local t2_res

            local t1 = ngx.thread.spawn(function()
                local err
                t1_data, err, t1_hit_lvl = cache_1:get("key", nil, cb, 0.3)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end)

            local t2 = ngx.thread.spawn(function()
                local err
                t2_res, err = cache_2:get_bulk {
                    "key_a", nil, cb, nil,
                    "key", nil, cb, nil,
                    n = 2,
                }
                if not t2_res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end)

            assert(ngx.thread.wait(t1))
            assert(ngx.thread.wait(t2))

            ngx.say("t1\n", t1_data, " ", t1_hit_lvl)

            ngx.say()
            ngx.say("t2")
            for i = 1, t2_res.n, 3 do
                ngx.say(tostring(t2_res[i]), " ",
                        tostring(t2_res[i + 1]), " ",
                        tostring(t2_res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
t1
hello 3

t2
hello nil 3
hello nil 2
--- no_error_log
[error]



=== TEST 28: get_bulk() operations reports timeout on lock if another thread is fetching the same key
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache_1 = assert(mlcache.new("my_mlcache", "cache_shm"))
            local cache_2 = assert(mlcache.new("my_mlcache", "cache_shm", {
                resty_lock_opts = { timeout = 0.2 }
            }))

            local function cb(wait)
                if wait then
                    ngx.sleep(wait)
                end

                return "hello"
            end

            local t1_data, t1_hit_lvl
            local t2_res

            local t1 = ngx.thread.spawn(function()
                local err
                t1_data, err, t1_hit_lvl = cache_1:get("key", nil, cb, 0.3)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end)

            local t2 = ngx.thread.spawn(function()
                local err
                t2_res, err = cache_2:get_bulk {
                    "key_a", nil, cb, nil,
                    "key", nil, cb, nil,
                    n = 2,
                }
                if not t2_res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end)

            assert(ngx.thread.wait(t1))
            assert(ngx.thread.wait(t2))

            ngx.say("t1\n", t1_data, " ", t1_hit_lvl)

            ngx.say()
            ngx.say("t2")
            for i = 1, t2_res.n, 3 do
                ngx.say(tostring(t2_res[i]), " ",
                        tostring(t2_res[i + 1]), " ",
                        tostring(t2_res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
t1
hello 3

t2
hello nil 3
nil could not acquire callback lock: timeout nil
--- no_error_log
[error]



=== TEST 29: get_bulk() opts.concurrency: default is 3 (with 3 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                n = 3,
            })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 2 threads to run 3 callbacks
thread 1 running callbacks 1 to 1
thread 2 running callbacks 2 to 2
main thread running callbacks 3 to 3
--- no_error_log
[error]



=== TEST 30: get_bulk() opts.concurrency: default is 3 (with 6 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                "key_d", nil, cb, nil,
                "key_e", nil, cb, nil,
                "key_f", nil, cb, nil,
                n = 6,
            })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 2 threads to run 6 callbacks
thread 1 running callbacks 1 to 2
thread 2 running callbacks 3 to 4
main thread running callbacks 5 to 6
--- no_error_log
[error]



=== TEST 31: get_bulk() opts.concurrency: default is 3 (with 7 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                "key_d", nil, cb, nil,
                "key_e", nil, cb, nil,
                "key_f", nil, cb, nil,
                "key_g", nil, cb, nil,
                n = 7,
            })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 2 threads to run 7 callbacks
thread 1 running callbacks 1 to 3
thread 2 running callbacks 4 to 6
main thread running callbacks 7 to 7
--- no_error_log
[error]



=== TEST 32: get_bulk() opts.concurrency: default is 3 (with 1 op)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                n = 1,
            })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 0 threads to run 1 callbacks
main thread running callbacks 1 to 1
--- no_error_log
[warn]
[error]
[alert]



=== TEST 33: get_bulk() opts.concurrency: 1 (with 3 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                n = 3,
            }, { concurrency = 1 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 0 threads to run 3 callbacks
main thread running callbacks 1 to 3
--- no_error_log
[warn]
[error]
[alert]



=== TEST 34: get_bulk() opts.concurrency: 1 (with 6 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                "key_d", nil, cb, nil,
                "key_e", nil, cb, nil,
                "key_f", nil, cb, nil,
                n = 6,
            }, { concurrency = 1 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 0 threads to run 6 callbacks
main thread running callbacks 1 to 6
--- no_error_log
[warn]
[error]
[alert]



=== TEST 35: get_bulk() opts.concurrency: 6 (with 3 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                n = 3,
            }, { concurrency = 6 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 2 threads to run 3 callbacks
thread 1 running callbacks 1 to 1
thread 2 running callbacks 2 to 2
main thread running callbacks 3 to 3
--- no_error_log
[error]



=== TEST 36: get_bulk() opts.concurrency: 6 (with 6 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                "key_d", nil, cb, nil,
                "key_e", nil, cb, nil,
                "key_f", nil, cb, nil,
                n = 6,
            }, { concurrency = 6 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 5 threads to run 6 callbacks
thread 1 running callbacks 1 to 1
thread 2 running callbacks 2 to 2
thread 3 running callbacks 3 to 3
thread 4 running callbacks 4 to 4
thread 5 running callbacks 5 to 5
main thread running callbacks 6 to 6
--- no_error_log
[warn]
[error]
[alert]



=== TEST 37: get_bulk() opts.concurrency: 6 (with 7 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                "key_b", nil, cb, nil,
                "key_c", nil, cb, nil,
                "key_d", nil, cb, nil,
                "key_e", nil, cb, nil,
                "key_f", nil, cb, nil,
                "key_g", nil, cb, nil,
                n = 7,
            }, { concurrency = 6 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 5 threads to run 7 callbacks
thread 1 running callbacks 1 to 2
thread 2 running callbacks 3 to 4
thread 3 running callbacks 5 to 6
thread 4 running callbacks 7 to 7
--- no_error_log
[error]



=== TEST 38: get_bulk() opts.concurrency: 6 (with 1 op)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm", {
                debug = true,
            }))

            local function cb(wait)
                return "hello"
            end

            local res, err = cache:get_bulk({
                "key_a", nil, cb, nil,
                n = 1,
            }, { concurrency = 6 })
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
spawning 0 threads to run 1 callbacks
main thread running callbacks 1 to 1
--- no_error_log
[warn]
[error]
[alert]



=== TEST 39: get_bulk() opts.concurrency: 6 (with 7 ops)
--- http_config eval: $::HttpConfig
--- log_level: debug
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"
            local cache = assert(mlcache.new("my_mlcache", "cache_shm"))

            local res, err = cache:get_bulk({
                "key_a", nil, function() return 1 end, nil,
                "key_b", nil, function() return 2 end, nil,
                "key_c", nil, function() return 3 end, nil,
                "key_d", nil, function() return 4 end, nil,
                "key_e", nil, function() return 5 end, nil,
                "key_f", nil, function() return 6 end, nil,
                "key_g", nil, function() return 7 end, nil,
                n = 7,
            }, { concurrency = 6 })
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            for i = 1, res.n, 3 do
                ngx.say(tostring(res[i]), " ",
                        tostring(res[i + 1]), " ",
                        tostring(res[i + 2]))
            end
        }
    }
--- request
GET /t
--- response_body
1 nil 3
2 nil 3
3 nil 3
4 nil 3
5 nil 3
6 nil 3
7 nil 3
--- no_error_log
[error]
