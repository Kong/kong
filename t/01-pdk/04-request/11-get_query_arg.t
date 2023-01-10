use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_query_arg() returns first query arg when multiple is given with same name
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo=1&Foo=2
--- response_body
Foo: 1
--- no_error_log
[error]



=== TEST 2: request.get_query_arg() returns values from case-sensitive table
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
            ngx.say("foo: ", pdk.request.get_query_arg("foo"))
        }
    }
--- request
GET /t?Foo=1&foo=2
--- response_body
Foo: 1
foo: 2
--- no_error_log
[error]



=== TEST 3: request.get_query_arg() returns nil when query argument is missing
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Bar: ", pdk.request.get_query_arg("Bar"))
        }
    }
--- request
GET /t?Foo=1
--- response_body
Bar: nil
--- no_error_log
[error]



=== TEST 4: request.get_query_arg() returns true when query argument has no value
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: ", pdk.request.get_query_arg("Foo"))
        }
    }
--- request
GET /t?Foo
--- response_body
Foo: true
--- no_error_log
[error]



=== TEST 5: request.get_query_arg() returns empty string when query argument's value is empty
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("Foo: '", pdk.request.get_query_arg("Foo"), "'")
        }
    }
--- request
GET /t?Foo=
--- response_body
Foo: ''
--- no_error_log
[error]



=== TEST 6: request.get_query_arg() returns nil when requested query arg does not fit in max_args
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        rewrite_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local args = {}
            for i = 1, 100 do
                args["arg-" .. i] = "test"
            end

            local args = ngx.encode_args(args)
            args = args .. "&arg-101=test"

            ngx.req.set_uri_args(args)
        }

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.say("argument value: ", pdk.request.get_query_arg("arg-101"))
        }
    }
--- request
GET /t
--- response_body
argument value: nil
--- no_error_log
[error]



=== TEST 7: request.get_query_arg() raises error when trying to fetch with invalid argument
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local _, err = pcall(pdk.request.get_query_arg)

            ngx.say("error: ", err)
        }
    }
--- request
GET /t
--- response_body
error: query argument name must be a string
--- no_error_log
[error]

=== TEST 8: request.get_query_arg() can accept 0 as input argument to remove the query limit
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local args, err = pdk.request.get_query(0)
            local count = 0
            for _, _ in pairs(args) do
                count = count + 1
            end

            ngx.say("args_count: ", count, ", error: '", tostring(err), "'")
        }
    }
--- request
GET /t?a0=0&a1=1&a2=2&a3=3&a4=4&a5=5&a6=6&a7=7&a8=8&a9=9&a10=10&a11=11&a12=12&a13=13&a14=14&a15=15&a16=16&a17=17&a18=18&a19=19&a20=20&a21=21&a22=22&a23=23&a24=24&a25=25&a26=26&a27=27&a28=28&a29=29&a30=30&a31=31&a32=32&a33=33&a34=34&a35=35&a36=36&a37=37&a38=38&a39=39&a40=40&a41=41&a42=42&a43=43&a44=44&a45=45&a46=46&a47=47&a48=48&a49=49&a50=50&a51=51&a52=52&a53=53&a54=54&a55=55&a56=56&a57=57&a58=58&a59=59&a60=60&a61=61&a62=62&a63=63&a64=64&a65=65&a66=66&a67=67&a68=68&a69=69&a70=70&a71=71&a72=72&a73=73&a74=74&a75=75&a76=76&a77=77&a78=78&a79=79&a80=80&a81=81&a82=82&a83=83&a84=84&a85=85&a86=86&a87=87&a88=88&a89=89&a90=90&a91=91&a92=92&a93=93&a94=94&a95=95&a96=96&a97=97&a98=98&a99=99&a100=100
--- response_body
args_count: 101, error: 'nil'
--- no_error_log
[error]
