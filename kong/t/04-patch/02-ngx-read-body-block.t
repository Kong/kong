# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';

repeat_each(2);

run_tests();

__DATA__

=== TEST 1: ngx.req.read_body() should work for HTTP2 GET requests that doesn't carry the content-length header
--- config
    location = /test {
        content_by_lua_block {
            local ok, err = pcall(ngx.req.read_body)
            ngx.say(ok, " err: ", err)
        }
    }
--- http2
--- request
GET /test
hello, world
--- more_headers
Content-Length:
--- response_body
true err: nil
--- no_error_log
[error]
[alert]



=== TEST 2: ngx.req.read_body() should work for HTTP2 POST requests that doesn't carry the content-length header
--- config
    location = /test {
        content_by_lua_block {
            local ok, err = pcall(ngx.req.read_body)
            ngx.say(ok, " err: ", err)
        }
    }
--- http2
--- request
POST /test
hello, world
--- more_headers
Content-Length:
--- response_body
true err: nil
--- no_error_log
[error]
[alert]
