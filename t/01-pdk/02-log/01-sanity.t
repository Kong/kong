use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

log_level('debug');

plan tests => repeat_each() * (blocks() * 3);

our $HttpConfig = qq{
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

        -- jit.opt.start("hotloop=1")
        -- jit.opt.start("loopunroll=1000000")
        -- jit.off()
    }
};

run_tests();

__DATA__

=== TEST 1: pdk has core logging facility
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("type: ", type(pdk.log))
        }
    }
--- request
GET /t
--- response_body
type: table
--- no_error_log
[error]



=== TEST 2: kong.log() produces core notice message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[notice\] .*? \[kong\] .*? hello world/



=== TEST 3: kong.log.debug() produces core debug message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.debug("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[debug\] .*? \[kong\] .*? hello world/



=== TEST 4: kong.log.info() produces core info message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.info("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[info\] .*? \[kong\] .*? hello world/



=== TEST 5: kong.log.notice() produces core notice message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.notice("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[notice\] .*? \[kong\] .*? hello world/



=== TEST 6: kong.log.warn() produces core warn message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.warn("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[warn\] .*? \[kong\] .*? hello world/



=== TEST 7: kong.log.err() produces core err message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.err("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[crit]
--- error_log eval
qr/\[error\] .*? \[kong\] .*? hello world/



=== TEST 8: kong.log.crit() produces core crit message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.crit("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[alert]
--- error_log eval
qr/\[crit\] .*? \[kong\] .*? hello world/



=== TEST 9: kong.alert() produces core alert message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.alert("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[crit]
--- error_log eval
qr/\[alert\] .*? \[kong\] .*? hello world/



=== TEST 10: kong.log.emerg() produces core emerg message
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.emerg("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[alert]
--- error_log eval
qr/\[emerg\] .*? \[kong\] .*? hello world/



=== TEST 11: kong.log has core logging format & proper stack level (1/2)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local function my_func()
                pdk.log("hello from my_func")
            end

            my_func()
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[notice\] .*? \[kong\] content_by_lua\(nginx\.conf:\d+\):6 hello from my_func/
--- no_error_log
[error]



=== TEST 12: kong.log() has core logging format & proper stack level (2/2)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("hello from my_func")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[notice\] .*? \[kong\] content_by_lua\(nginx\.conf:\d+\):5 hello from my_func/
--- no_error_log
[error]



=== TEST 13: kong.log() JIT compiles when level is below sys_level
--- log_level: warn
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            for i = 1, 1e3 do
                -- notice log
                pdk.log("hello world")
            end
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[TRACE\s+\d+ content_by_lua\(nginx\.conf:\d+\):5 loop\]/
--- no_error_log
[error]



=== TEST 14: kong.log() accepts variadic arguments (string)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log
hello world



=== TEST 15: kong.log() accepts variadic arguments (boolean)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("boolean: ", false)
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log
boolean: false



=== TEST 16: kong.log() accepts variadic arguments (number)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("number: ", 1, " " , 2)
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log
number: 1 2



=== TEST 17: kong.log() accepts variadic arguments (table)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log({})
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/table: 0x\d+/



=== TEST 18: kong.log() accepts variadic arguments (userdata)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log(ngx.null)
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log
userdata: NULL



=== TEST 19: kong.log() format does not include [lua] prefix
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- no_error_log
[error]
--- error_log eval
qr/\[notice\] \d+#\d+: \*\d+ \[kong\]/
