use Test::Nginx::Socket::Kong;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_host() returns host from Host header (1/2)
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("host: ", sdk.request.get_host())
        }
    }
--- request
GET /t
--- response_body
host: localhost
--- no_error_log
[error]



=== TEST 2: request.get_host() returns host from Host header (2/2)
--- config
    location = /t {
        proxy_set_header Host "kong.com";
        proxy_pass http://127.0.0.1:$server_port/proxy;
    }

    location /proxy {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()
            --sdk.init(nil, "ip")

            ngx.say("host: ", sdk.request.get_host())
        }
    }
--- request
GET /t
--- response_body
host: kong.com
--- no_error_log
[error]
