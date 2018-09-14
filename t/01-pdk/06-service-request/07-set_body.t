use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_body() errors if args is not a table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_body, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 2: service.request.set_body() errors if given no arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_body)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
args must be a table
--- no_error_log
[error]



=== TEST 3: service.request.set_body() errors if mime is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_body, {}, 123)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
mime must be a string
--- no_error_log
[error]



=== TEST 4: service.request.set_body() for application/x-www-form-urlencoded errors if table values have bad types
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/x-www-form-urlencoded")
            local pok, err = pcall(pdk.service.request.set_body, {
                aaa = "foo",
                bbb = function() end,
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
attempt to use function as query arg value
--- no_error_log
[error]



=== TEST 5: service.request.set_body() for application/x-www-form-urlencoded errors if table keys have bad types
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/x-www-form-urlencoded")
            local pok, err = pcall(pdk.service.request.set_body, {
                aaa = "foo",
                [true] = "what",
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
arg keys must be strings
--- no_error_log
[error]



=== TEST 6: service.request.set_body() for application/x-www-form-urlencoded sets the Content-Type header
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_body({}, "application/x-www-form-urlencoded")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 7: service.request.set_body() for application/x-www-form-urlencoded accepts an empty table
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/x-www-form-urlencoded")
            assert(pdk.service.request.set_body({}))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

foo=hello%20world
--- response_body
body: {nil}
content-length: {0}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 8: service.request.set_body() for application/x-www-form-urlencoded replaces the received post args
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world"
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

foo=bar
--- response_body
body: {foo=hello%20world}
content-length: {17}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 9: service.request.set_body() for application/x-www-form-urlencoded urlencodes table values
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world"
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {foo=hello%20world}
content-length: {17}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 10: service.request.set_body() for application/x-www-form-urlencoded produces a deterministic lexicographical order
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                a = true,
                aa = true,
                zzz = "goodbye world",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {a&aa&foo=hello%20world&zzz=goodbye%20world}
content-length: {42}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 11: service.request.set_body() for application/x-www-form-urlencoded preserves the order of array arguments
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                a = true,
                aa = { "zzz", true, true, "aaa" },
                zzz = "goodbye world",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {a&aa=zzz&aa&aa&aa=aaa&foo=hello%20world&zzz=goodbye%20world}
content-length: {59}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 12: service.request.set_body() for application/x-www-form-urlencoded supports empty values
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                aa = "",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {aa=}
content-length: {3}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 13: service.request.set_body() for application/x-www-form-urlencoded accepts empty keys
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                [""] = "aa",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {=aa}
content-length: {3}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 14: service.request.set_body() for application/x-www-form-urlencoded urlencodes table keys
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                ["hello world"] = "aa",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {hello%20world=aa}
content-length: {16}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 15: service.request.set_body() for application/x-www-form-urlencoded does not force a POST method
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("method: ", ngx.req.get_method())
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "bar",
            }, "application/x-www-form-urlencoded"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: GET
body: {foo=bar}
content-length: {7}
content-type: {application/x-www-form-urlencoded}
--- no_error_log
[error]



=== TEST 16: service.request.set_body() for application/json errors if table values have bad types
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/json")
            local pok, err = pcall(pdk.service.request.set_body, {
                aaa = "foo",
                bbb = function() end,
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
Cannot serialise function: type not supported
--- no_error_log
[error]



=== TEST 17: service.request.set_body() for application/json errors if table keys have bad types
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/json")
            local pok, err = pcall(pdk.service.request.set_body, {
                aaa = "foo",
                [true] = "what",
                ccc = "bar",
            })
            ngx.say(err)
        }

        proxy_pass http://127.0.0.1:9080;
    }
--- request
POST /t
--- response_body
Cannot serialise boolean: table key must be a number or string
--- no_error_log
[error]



=== TEST 18: service.request.set_body() for application/json sets the Content-Type header
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({}, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
content-type: {application/json}
--- no_error_log
[error]



=== TEST 19: service.request.set_body() for application/json accepts an empty table
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("Content-Type", "application/json")
            assert(pdk.service.request.set_body({}))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

foo=hello%20world
--- response_body
body: {{}}
content-length: {2}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 20: service.request.set_body() for application/json replaces the received post args
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world"
            }, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

foo=bar
--- response_body
body: {{"foo":"hello world"}}
content-length: {21}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 21: service.request.set_body() for application/json produces a deterministic lexicographical order
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                a = true,
                aa = true,
                zzz = "goodbye world",
            }, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {{"aa":true,"zzz":"goodbye world","foo":"hello world","a":true}}
content-length: {62}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 22: service.request.set_body() for application/json preserves the order of array arguments
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                a = true,
                aa = { "zzz", true, true, "aaa" },
                zzz = "goodbye world",
            }, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {{"aa":["zzz",true,true,"aaa"],"zzz":"goodbye world","foo":"hello world","a":true}}
content-length: {81}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 23: service.request.set_body() for application/json supports empty values
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                aa = "",
            }, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {{"aa":""}}
content-length: {9}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 24: service.request.set_body() for application/json accepts empty keys
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local headers = ngx.req.get_headers()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
                ngx.say("content-length: {", tostring(headers["Content-Length"]), "}")
                ngx.say("content-type: {", tostring(headers["Content-Type"]), "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                [""] = "aa",
            }, "application/json"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
body: {{"":"aa"}}
content-length: {9}
content-type: {application/json}
--- no_error_log
[error]



=== TEST 25: service.request.set_body() for multipart/form-data can only store scalars in parts
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local ok, err = pcall(pdk.service.request.set_body, {
                foo = "hello world",
                a = true,
                aa = { "zzz", true, true, "aaa" },
                zzz = "goodbye world",
            }, "multipart/form-data")
            ngx.say(err)
        }
    }
--- request
POST /t
--- response_body
invalid value "aa": got table, expected string, number or boolean
--- no_error_log
[error]



=== TEST 26: service.request.set_body() for multipart/form-data when mime given adds the boundary to the Content-Type
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()

                local headers = ngx.req.get_headers()
                local content_type = tostring(headers["Content-Type"])

                local multipart = require "multipart"
                local raw_body = tostring(ngx.req.get_body_data())
                local mpdata = multipart(raw_body, content_type)
                local mpvalues = mpdata:get_all()

                ngx.say(content_type:match("(boundary)"))
                ngx.say("foo: {", mpvalues.foo, "}")
                ngx.say("zzz: {", mpvalues.zzz, "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                zzz = "goodbye world",
            }, "multipart/form-data"))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t
--- response_body
boundary
foo: {hello world}
zzz: {goodbye world}
--- no_error_log
[error]



=== TEST 27: service.request.set_body() for multipart/form-data when mime is not given reuses the boundary from the Content-Type
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()

                local headers = ngx.req.get_headers()
                local content_type = tostring(headers["Content-Type"])

                local multipart = require "multipart"
                local raw_body = tostring(ngx.req.get_body_data())
                local mpdata = multipart(raw_body, content_type)
                local mpvalues = mpdata:get_all()

                ngx.say(content_type)
                ngx.say((raw_body:gsub("\\r", "")))
                ngx.say("foo: {", mpvalues.foo, "}")
                ngx.say("zzz: {", mpvalues.zzz, "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            assert(pdk.service.request.set_body({
                foo = "hello world",
                zzz = "goodbye world",
            }))
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

--xxyyzz
Content-Disposition: form-data; name="field1"

value1
--xxyyzz
Content-Disposition: form-data; name="field2"

value2
--xxyyzz--
--- more_headers
Content-Type: multipart/form-data; boundary=xxyyzz
--- response_body
multipart/form-data; boundary=xxyyzz
--xxyyzz
Content-Disposition: form-data; name="foo"

hello world
--xxyyzz
Content-Disposition: form-data; name="zzz"

goodbye world
--xxyyzz--

foo: {hello world}
zzz: {goodbye world}
--- no_error_log
[error]
