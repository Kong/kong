# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 7 - 2);

my $pwd = cwd();

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

log_level('info');
no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: normal http2 alpn
--- http_config

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        listen 60000 ssl;
        server_name   konghq.com;
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_cache off;
        ssl_session_tickets on;
        server_tokens off;
        http2 on;
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
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({'curl', '-vk', '--resolve', 'konghq.com:60000:127.0.0.1', 'https://konghq.com:60000'})
            local stdout_data, err = proc:stdout_read_all()
            if not stdout_data then
                ngx.say(err)
                return
            end

            local stderr_data, err = proc:stderr_read_all()
            if not stderr_data then
                ngx.say(err)
                return
            end

            if string.find(stdout_data, "ALPN: server accepted h2") ~= nil then
                ngx.say("alpn server accepted h2")
                return
            end

            if string.find(stderr_data, "ALPN: server accepted http/1.1") ~= nil then
                ngx.say("alpn server accepted http/1.1")
                return
            end
        }
    }
--- request
GET /t
--- response_body
alpn server accepted http/1.1
--- no_error_log
[error]
[alert]
[warn]
[crit]

=== TEST 2: disable http2 alpn
--- http_config

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        listen 60000 ssl;
        server_name   konghq.com;
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_cache off;
        ssl_session_tickets on;
        server_tokens off;
        http2 on;
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
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({'curl', '-vk', '--resolve', 'konghq.com:60000:127.0.0.1', 'https://konghq.com:60000'})
            local stdout_data, err = proc:stdout_read_all()
            if not stdout_data then
                ngx.say(err)
                return
            end

            local stderr_data, err = proc:stderr_read_all()
            if not stderr_data then
                ngx.say(err)
                return
            end

            if string.find(stdout_data, "ALPN: server accepted h2") ~= nil then
                ngx.say("alpn server accepted h2")
                return
            end

            if string.find(stderr_data, "ALPN: server accepted http/1.1") ~= nil then
                ngx.say("alpn server accepted http/1.1")
                return
            end
        }
    }
--- request
GET /t
--- response_body
alpn server accepted http/1.1
--- no_error_log
[error]
[alert]
[warn]
[crit]
