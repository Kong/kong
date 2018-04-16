use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_body_args() returns arguments with application/x-www-form-urlencoded
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args, err, mime = sdk.request.get_body_args()

            ngx.say("type=", type(args))
            ngx.say("test=", args.test)
            ngx.say("mime=", mime)
        }
    }
--- request
POST /t
test=post
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- response_body
type=table
test=post
mime=application/x-www-form-urlencoded
--- no_error_log
[error]



=== TEST 2: request.get_body_args() returns arguments with application/json
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args, err, mime = sdk.request.get_body_args()

            ngx.say("type=", type(args))
            ngx.say("test=", args.test)
            ngx.say("mime=", mime)
        }
    }
--- request
POST /t
{
  "test": "json"
}
--- more_headers
Content-Type: application/json
--- response_body
type=table
test=json
mime=application/json
--- no_error_log
[error]



=== TEST 3: request.get_body_args() returns arguments with multipart/form-data
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args, err, mime = sdk.request.get_body_args()

            ngx.say("type=", type(args))
            ngx.say("test=", args.test)
            ngx.say("mime=", mime)
        }
    }
--- request
POST /t
--AaB03x
Content-Disposition: form-data; name="test"

form-data
--AaB03x--
--- more_headers
Content-Type: multipart/form-data; boundary=AaB03x
--- response_body
type=table
test=form-data
mime=multipart/form-data
--- no_error_log
[error]



=== TEST 4: request.get_body_args() returns error when missing content type header
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = sdk.request.get_body_args()

            ngx.say("error: ", err)
        }
    }
--- request
POST /t
test=post
--- response_body
error: missing content type
--- no_error_log
[error]



=== TEST 5: request.get_body_args() returns error when using unsupported content type
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = sdk.request.get_body_args()

            ngx.say("error: ", err)
        }
    }
--- request
POST /t
test=post
--- more_headers
Content-Type: application/x-unsupported
--- response_body
error: unsupported content type 'application/x-unsupported'
--- no_error_log
[error]



=== TEST 6: request.get_body_args() returns error with invalid json body
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local _, err = sdk.request.get_body_args()

            ngx.say("error: ", err)
        }
    }
--- request
POST /t
--- more_headers
Content-Type: application/json
--- response_body
error: invalid json body
--- no_error_log
[error]



=== TEST 7: request.get_body_args() content type value is case-insensitive
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local args, err, mime = sdk.request.get_body_args()

            ngx.say("type=", type(args))
            ngx.say("test=", args.test)
            ngx.say("mime=", mime)
        }
    }
--- request
POST /t
test=post
--- more_headers
Content-Type: APPLICATION/x-WWW-form-Urlencoded
--- response_body
type=table
test=post
mime=application/x-www-form-urlencoded
--- no_error_log
[error]
