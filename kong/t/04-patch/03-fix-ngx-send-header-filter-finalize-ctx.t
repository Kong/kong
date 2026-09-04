# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: send_header trigger filter finalize does not clear the ctx
--- config
    location /lua {
        content_by_lua_block {
            ngx.header["Last-Modified"] = ngx.http_time(ngx.time())
            ngx.send_headers()
            local phase = ngx.get_phase()
        }
        header_filter_by_lua_block {
            ngx.header["X-Hello-World"] = "Hello World"
        }
    }
--- request
GET /lua
--- more_headers
If-Unmodified-Since: Wed, 01 Jan 2020 07:28:00 GMT
--- error_code: 412
--- no_error_log
unknown phase: 0
