use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: tracer.active_span() noop tracer not set active span
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local pdk = require "kong.pdk".new()
            pdk.tracing.start_span("access")
        }

        content_by_lua_block {
            local pdk = require "kong.pdk".new()
            local span = pdk.tracing.active_span()
            ngx.say(span and span.name)
        }
    }
--- request
GET /t
--- response_body
nil
--- no_error_log
[error]


=== TEST 2: tracer.set_active_span() sets active span
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local pdk = require "kong.pdk".new()
            local tracer = pdk.tracing.new("t")
            local span = tracer.start_span("access")
            tracer.set_active_span(span)
        }

        content_by_lua_block {
            local pdk = require "kong.pdk".new()
            local span = pdk.tracing("t").active_span()
            ngx.say(span and span.name)
        }
    }
--- request
GET /t
--- response_body
access
--- no_error_log
[error]


=== TEST 3: tracer.active_span() get tracer from active span
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local pdk = require "kong.pdk".new()
            local tracer = pdk.tracing("t")
            local span = tracer.start_span("access")
            tracer.set_active_span(span)
        }

        content_by_lua_block {
            local pdk = require "kong.pdk".new()
            local span = pdk.tracing("t").active_span()
            local tracer = span.tracer
            ngx.say(tracer and tracer.name)
        }
    }
--- request
GET /t
--- response_body
t
--- no_error_log
[error]
