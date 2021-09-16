use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => 2;

run_tests();

__DATA__

=== TEST 1: load lua-resty-dns-client
--- config
    location = /t {
        access_by_lua_block {
            local client = require("kong.resty.dns.client")
            assert(client.init())
            local host = "localhost"
            local typ = client.TYPE_A
            local answers, err = assert(client.resolve(host, { qtype = typ }))
            ngx.say(answers[1].address)
        }
    }
--- request
GET /t
--- response_body
127.0.0.1
--- no_error_log
