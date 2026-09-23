use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
do "./t/Util.pm";

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: request.get_uri_captures()
--- http_config eval: $t::Util::HttpConfig
--- config
  location /t {
    access_by_lua_block {
      local PDK = require "kong.pdk"
      local pdk = PDK.new()

      local m = ngx.re.match(ngx.var.uri, [[^\/t((\/\d+)(?P<tag>\/\w+))?]], "jo")

      ngx.ctx.router_matches = {
        uri_captures = m,
      }

      local captures = pdk.request.get_uri_captures()
      ngx.say("uri_captures: ", "tag: ", captures.named["tag"],
              ", 0: ", captures.unnamed[0], ", 1: ", captures.unnamed[1],
              ", 2: ", captures.unnamed[2], ", 3: ", captures.unnamed[3])

      array_mt = assert(require("cjson").array_mt, "expected array_mt to be truthy")
      assert(getmetatable(captures.unnamed) == array_mt, "expected the 'unnamed' captures to be an array")
    }
  }
--- request
GET /t/01/ok
--- response_body
uri_captures: tag: /ok, 0: /t/01/ok, 1: /01/ok, 2: /01, 3: /ok
--- no_error_log
[error]
