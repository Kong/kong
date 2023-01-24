use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: service.request.set_raw_query() works if preceded by
request.get_raw_query() github issue #10080
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lualib/?.lua;;";
    lua_kong_load_var_index $args;
    init_by_lua_block {
        require("resty.kong.var").patch_metatable()
    }
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local q = pdk.request.get_raw_query()
            pdk.service.request.set_raw_query("test=val")
            ngx.say("args: ", ngx.var.args)
        }
    }
--- request
GET /t
--- response_body
args: test=val
