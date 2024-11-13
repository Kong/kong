# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict  cache_shm 1m;
    lua_shared_dict  locks_shm 1m;

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

=== TEST 1: new() validates opts.shm_locks
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = pcall(mlcache.new, "name", "cache_shm", {
                shm_locks = false,
            })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
opts.shm_locks must be a string
--- no_error_log
[error]



=== TEST 2: new() ensures opts.shm_locks exists
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local ok, err = mlcache.new("name", "cache_shm", {
                shm_locks = "foo",
            })
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
no such lua_shared_dict for opts.shm_locks: foo
--- no_error_log
[error]



=== TEST 3: get() stores resty-locks in opts.shm_locks if specified
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local mlcache = require "kong.resty.mlcache"

            local cache = assert(mlcache.new("name", "cache_shm", {
                shm_locks = "locks_shm",
            }))

            local function cb()
                local keys = ngx.shared.locks_shm:get_keys()
                for i, key in ipairs(keys) do
                    ngx.say(i, ": ", key)
                end

                return 123
            end

            cache:get("key", nil, cb)
        }
    }
--- request
GET /t
--- response_body
1: lua-resty-mlcache:lock:namekey
--- no_error_log
[error]
