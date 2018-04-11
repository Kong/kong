use Test::Nginx::Socket::Lua;

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: SDK loads latest version by default
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"

            ngx.say("major_versions: ", type(SDK.major_versions))
            ngx.say("instantiating sdk")

            local sdk = SDK.new()
            ngx.say("sdk.sdk_major_version: ", sdk.sdk_major_version)

            ngx.say("is latest: ", sdk.sdk_major_version == SDK.major_versions.latest)
        }
    }
--- request
GET /t
--- response_body_like chomp
major_versions: table
instantiating sdk
sdk\.sdk_major_version: \d+
is latest: true
--- no_error_log
[error]



=== TEST 2: has sdk_major_version and sdk_version fields
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"

            local sdk = SDK.new()

            ngx.say("sdk_major_version: ", sdk.sdk_major_version)
            ngx.say("sdk_version: ", sdk.sdk_version)
        }
    }
--- request
GET /t
--- response_body_like chomp
sdk_major_version: \d+
sdk_version: \d+\.\d+.\d+
--- no_error_log
[error]



=== TEST 3: can load given major version
--- SKIP: skip me since 1st release will only have version 0
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"

            local sdk_latest = SDK.new()
            local sdk_previous = SDK.new(0)

            ngx.say("different version: ", sdk_latest.sdk_major_version ~= sdk_previous.sdk_major_version)
        }
    }
--- request
GET /t
--- response_body
different version: true
--- no_error_log
[error]
