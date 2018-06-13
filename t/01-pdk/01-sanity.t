use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: PDK loads latest version by default
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"

            ngx.say("major_versions: ", type(PDK.major_versions))
            ngx.say("instantiating pdk")

            local pdk = PDK.new()
            ngx.say("pdk.pdk_major_version: ", pdk.pdk_major_version)

            ngx.say("is latest: ", pdk.pdk_major_version == PDK.major_versions.latest)
        }
    }
--- request
GET /t
--- response_body_like chomp
major_versions: table
instantiating pdk
pdk\.pdk_major_version: \d+
is latest: true
--- no_error_log
[error]



=== TEST 2: has pdk_major_version and pdk_version fields
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"

            local pdk = PDK.new()

            ngx.say("pdk_major_version: ", pdk.pdk_major_version)
            ngx.say("pdk_version: ", pdk.pdk_version)
        }
    }
--- request
GET /t
--- response_body_like chomp
pdk_major_version: \d+
pdk_version: \d+\.\d+.\d+
--- no_error_log
[error]



=== TEST 3: can load given major version
--- SKIP: skip me since 1st release will only have version 0
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"

            local pdk_latest = PDK.new()
            local pdk_previous = PDK.new(0)

            ngx.say("different version: ", pdk_latest.pdk_major_version ~= pdk_previous.pdk_major_version)
        }
    }
--- request
GET /t
--- response_body
different version: true
--- no_error_log
[error]
