# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';

repeat_each(2);

run_tests();

__DATA__

=== TEST 53: HTTP2 request without content-len header read body body works fine
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