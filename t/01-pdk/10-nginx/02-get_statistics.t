=begin
1. Check test counts of plan
2. Refer to https://openresty.gitbooks.io/programming-openresty/content/testing/
=end
=cut

use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

no_long_string();
run_tests();


__DATA__


=== TEST 1: nginx.get_statistics()
returns Nginx connections and requests states
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local nginx_statistics = pdk.nginx.get_statistics()
            local ngx = ngx
            ngx.say("Nginx statistics:")
            ngx.say("connections_active: ", nginx_statistics["connections_active"])
            ngx.say("connections_reading: ", nginx_statistics["connections_reading"])
            ngx.say("connections_writing: ", nginx_statistics["connections_writing"])
            ngx.say("connections_waiting: ", nginx_statistics["connections_waiting"])
            ngx.say("connections_accepted: ", nginx_statistics["connections_accepted"])
            ngx.say("connections_handled: ", nginx_statistics["connections_handled"])
            ngx.print("total_requests: ", nginx_statistics["total_requests"])
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body_like eval
qr/Nginx statistics:
connections_active: \d+
connections_reading: \d+
connections_writing: \d+
connections_waiting: \d+
connections_accepted: \d+
connections_handled: \d+/
--- no_error_log
[error]