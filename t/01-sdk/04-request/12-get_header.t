use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_header()
--- config
    location = /t {
        content_by_lua_block {

        }
    }
--- request
GET /t
--- response_body
--- no_error_log
[error]
