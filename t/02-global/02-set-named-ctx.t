use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

no_long_string();

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: set_named_ctx() can set arbitrary namespaces
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()
            kong_global.init_pdk(kong)

            kong_global.set_named_ctx(kong, "custom", {})
            kong_global.set_named_ctx(kong, "foo", {})

            kong.ctx.custom.cats = "marry"
            kong.ctx.foo.cats = "suzie"

            ngx.say(ngx.ctx.custom)
            ngx.say(ngx.ctx.cats)
            ngx.say(kong.ctx.custom.cats)
            ngx.say(kong.ctx.foo.cats)
        }
    }
--- request
GET /t
--- response_body
nil
nil
marry
suzie
--- no_error_log
[error]



=== TEST 2: set_named_ctx() arbitrary namespaces can be rotated
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()
            kong_global.init_pdk(kong)

            local namespace_key1 = {}
            local namespace_key2 = {}

            kong_global.set_named_ctx(kong, "custom", namespace_key1)
            kong.ctx.custom.cats = "marry"
            ngx.say(kong.ctx.custom.cats)

            kong_global.set_named_ctx(kong, "custom", namespace_key2)
            ngx.say(kong.ctx.custom.cats)

            kong_global.set_named_ctx(kong, "custom", namespace_key1)
            ngx.say(kong.ctx.custom.cats)
        }
    }
--- request
GET /t
--- response_body
marry
nil
marry
--- no_error_log
[error]



=== TEST 3: set_named_ctx() arbitrary namespaces can be discarded
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()
            kong_global.init_pdk(kong)

            kong_global.set_named_ctx(kong, "custom", {})
            kong.ctx.custom.cats = "marry"
            ngx.say(kong.ctx.custom.cats)

            kong_global.set_named_ctx(kong, "custom", nil)
            ngx.say(kong.ctx.custom)
        }
    }
--- request
GET /t
--- response_body
marry
nil
--- no_error_log
[error]



=== TEST 4: set_named_ctx() arbitrary namespaces invalid argument #1
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()
            kong_global.init_pdk(kong)

            local pok, perr = pcall(kong_global.set_named_ctx, nil)
            if not pok then
              ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
arg #1 cannot be nil
--- no_error_log
[error]



=== TEST 5: set_named_ctx() arbitrary namespaces must have a name
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()
            kong_global.init_pdk(kong)

            local pok, perr = pcall(kong_global.set_named_ctx, kong, 123, {})
            if not pok then
              ngx.say(perr)
            end

            pok, perr = pcall(kong_global.set_named_ctx, kong, "", {})
            if not pok then
              ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
name must be a string
name cannot be an empty string
--- no_error_log
[error]



=== TEST 6: set_named_ctx() arbitrary namespaces fail if PDK not initialized
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local kong_global = require "kong.global"
            local kong = kong_global.new()

            local pok, perr = pcall(kong_global.set_named_ctx, kong, "custom", {})
            if not pok then
              ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
ctx PDK module not initialized
--- no_error_log
[error]
