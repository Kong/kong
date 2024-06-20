use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 4) - 1;

run_tests();

__DATA__

=== TEST 1: should work in rewrite phase
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")
            pdk_rl.store_response_header(ngx.ctx, "X-1", 1)
            pdk_rl.store_response_header(ngx.ctx, "X-2", 2)

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)

            pdk_rl.apply_response_headers(ngx.ctx)
        }

        content_by_lua_block {
            ngx.say("ok")
        }

        log_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)
        }
    }
--- request
GET /t
--- response_headers
X-1: 1
X-2: 2
--- no_error_log
[error]



=== TEST 2: should work in access phase
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")
            pdk_rl.store_response_header(ngx.ctx, "X-1", 1)
            pdk_rl.store_response_header(ngx.ctx, "X-2", 2)

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)

            pdk_rl.apply_response_headers(ngx.ctx)
        }

        content_by_lua_block {
            ngx.say("ok")
        }

        log_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)
        }
    }
--- request
GET /t
--- response_headers
X-1: 1
X-2: 2
--- no_error_log
[error]


=== TEST 3: should work in header_filter phase
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        header_filter_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")
            pdk_rl.store_response_header(ngx.ctx, "X-1", 1)
            pdk_rl.store_response_header(ngx.ctx, "X-2", 2)

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)

            pdk_rl.apply_response_headers(ngx.ctx)
        }

        content_by_lua_block {
            ngx.say("ok")
        }

        log_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")

            local value = pdk_rl.get_stored_response_header(ngx.ctx, "X-1")
            assert(value == 1, "unexpected value: " .. value)

            value = pdk_rl.get_stored_response_header(ngx.ctx, "X-2")
            assert(value == 2, "unexpected value: " .. value)
        }
    }
--- request
GET /t
--- response_headers
X-1: 1
X-2: 2
--- no_error_log
[error]



=== TEST 4: should not accept invalid arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local pdk_rl = require("kong.pdk.private.rate_limiting")
            local ok, err, errmsg

            ok, err = pcall(pdk_rl.store_response_header, ngx.ctx, nil, 1)
            assert(not ok, "pcall should fail")
            errmsg = string.format(
                "arg #%d `key` for function `%s` must be a string, got %s",
                2,
                "store_response_header",
                type(nil)
            )
            assert(
                err:find(errmsg, nil, true),
                "unexpected error message: " .. err
            )
            for _k, v in ipairs({ 1, true, {}, function() end, ngx.null }) do
                ok, err = pcall(pdk_rl.store_response_header, ngx.ctx, v, 1)
                assert(not ok, "pcall should fail")
                errmsg = string.format(
                    "arg #%d `key` for function `%s` must be a string, got %s",
                    2,
                    "store_response_header",
                    type(v)
                )
                assert(
                    err:find(errmsg, nil, true),
                    "unexpected error message: " .. err
                )
            end

            ok, err = pcall(pdk_rl.store_response_header, ngx.ctx, "X-1", nil)
            assert(not ok, "pcall should fail")
            errmsg = string.format(
                "arg #%d `value` for function `%s` must be a string or a number, got %s",
                3,
                "store_response_header",
                type(nil)
            )
            assert(
                err:find(errmsg, nil, true),
                "unexpected error message: " .. err
            )
            for _k, v in ipairs({ true, {}, function() end, ngx.null }) do
                ok, err = pcall(pdk_rl.store_response_header, ngx.ctx, "X-1", v)
                assert(not ok, "pcall should fail")
                errmsg = string.format(
                    "arg #%d `value` for function `%s` must be a string or a number, got %s",
                    3,
                    "store_response_header",
                    type(v)
                )
                assert(
                    err:find(errmsg, nil, true),
                    "unexpected error message: " .. err
                )
            end

            ok, err = pcall(pdk_rl.get_stored_response_header, ngx.ctx, nil)
            assert(not ok, "pcall should fail")
            errmsg = string.format(
                "arg #%d `key` for function `%s` must be a string, got %s",
                2,
                "get_stored_response_header",
                type(nil)
            )
            assert(
                err:find(errmsg, nil, true),
                "unexpected error message: " .. err
            )
            for _k, v in ipairs({ 1, true, {}, function() end, ngx.null }) do
                ok, err = pcall(pdk_rl.get_stored_response_header, ngx.ctx, v)
                assert(not ok, "pcall should fail")
                errmsg = string.format(
                    "arg #%d `key` for function `%s` must be a string, got %s",
                    2,
                    "get_stored_response_header",
                    type(v)
                )
                assert(
                    err:find(errmsg, nil, true),
                    "unexpected error message: " .. err
                )
            end
        }

        content_by_lua_block {
            ngx.print("ok")
        }
    }
--- request
GET /t
--- response_body eval
"ok"
--- no_error_log
[error]
