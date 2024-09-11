# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 7 - 1);

my $pwd = cwd();

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

log_level('debug');
no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: disable http2 can not failed
--- http_config

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   konghq.com;
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_cache off;
        ssl_session_tickets on;
        server_tokens off;
        ssl_client_hello_by_lua_block {
            local ssl = require "ngx.ssl"
            local ok, err = ssl.disable_http2()
            if not ok then
                ngx.log(ngx.ERR, "failed to disable http2")
            end
        }
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.exit(200)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            local session
            session, err = sock:sslhandshake(session, "konghq.com")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end
            local req = "GET /foo HTTP/1.1\r\nHost: konghq.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end
            local line, err = sock:receive()
            if not line then
                ngx.say("failed to receive response status line: ", err)
                return
            end
            ngx.say("received: ", line)
            local ok, err = sock:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
received: HTTP/1.1 200 OK
--- no_error_log
[error]
[alert]
[warn]
[crit]