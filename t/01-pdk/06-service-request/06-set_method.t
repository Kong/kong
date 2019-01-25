use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_method() errors if not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_method, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
method must be a string
--- no_error_log
[error]



=== TEST 2: service.request.set_method() errors if given no arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_method)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
method must be a string
--- no_error_log
[error]



=== TEST 3: service.request.set_method() fails if given an invalid method
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_method, "FOO")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid method: FOO
--- no_error_log
[error]



=== TEST 4: service.request.set_method() demands uppercase methods
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_method, "get")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid method: get
--- no_error_log
[error]



=== TEST 5: service.request.set_method() sets the request method to GET
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("GET")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: GET
--- no_error_log
[error]



=== TEST 6: service.request.set_method() sets the request method to HEAD
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.log(ngx.ERR, "method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("HEAD")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
--- error_log
method: HEAD



=== TEST 7: service.request.set_method() sets the request method to PUT
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("PUT")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: PUT
--- no_error_log
[error]



=== TEST 8: service.request.set_method() sets the request method to POST
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("POST")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: POST
--- no_error_log
[error]



=== TEST 9: service.request.set_method() sets the request method to DELETE
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("DELETE")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: DELETE
--- no_error_log
[error]



=== TEST 10: service.request.set_method() sets the request method to OPTIONS
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("OPTIONS")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: OPTIONS
--- no_error_log
[error]



=== TEST 11: service.request.set_method() sets the request method to MKCOL
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("MKCOL")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: MKCOL
--- no_error_log
[error]



=== TEST 12: service.request.set_method() sets the request method to COPY
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("COPY")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: COPY
--- no_error_log
[error]



=== TEST 13: service.request.set_method() sets the request method to MOVE
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("MOVE")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: MOVE
--- no_error_log
[error]



=== TEST 14: service.request.set_method() sets the request method to PROPFIND
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("PROPFIND")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: PROPFIND
--- no_error_log
[error]



=== TEST 15: service.request.set_method() sets the request method to PROPPATCH
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("PROPPATCH")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: PROPPATCH
--- no_error_log
[error]



=== TEST 16: service.request.set_method() sets the request method to LOCK
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("LOCK")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: LOCK
--- no_error_log
[error]



=== TEST 17: service.request.set_method() sets the request method to UNLOCK
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("UNLOCK")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: UNLOCK
--- no_error_log
[error]



=== TEST 18: service.request.set_method() sets the request method to PATCH
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("PATCH")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
method: PATCH
--- no_error_log
[error]



=== TEST 19: service.request.set_method() sets the request method to TRACE (for which Nginx always returns 405)
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("this never runs")
            }
        }
    }
}
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_method("TRACE")
        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- error_code: 405
--- response_body_like chomp
405 Not Allowed
--- no_error_log
[error]
