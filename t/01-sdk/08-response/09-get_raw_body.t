use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: response.get_raw_body() returns full raw body
--- config
    location = /t {
        content_by_lua_block {
            -- TODO: implement
        }
    }
--- request
GET /t
--- response_body

--- no_error_log
[error]
