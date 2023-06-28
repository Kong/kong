# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';

repeat_each(2);

run_tests();

__DATA__
=== TEST 1: check metric names
--- http_config
    lua_shared_dict prometheus_metrics 5m;
    init_worker_by_lua_block {
      local prometheus = require("kong.plugins.prometheus.prometheus")
      _G.prom = prometheus.init("prometheus_metrics", "kong_")
    }
--- config
    location /t {
        content_by_lua_block {
          local m

          m = _G.prom:counter("mem_used")
          ngx.say(not not m)

          m = _G.prom:counter(":mem_used")
          ngx.say(not not m)

          m = _G.prom:counter("mem_used:")
          ngx.say(not not m)

          m = _G.prom:counter("_mem_used_")
          ngx.say(not not m)

          m = _G.prom:counter("0name")
          ngx.say(not not m)

          m = _G.prom:counter("name$")
          ngx.say(not not m)
        }
    }
--- request
GET /t
--- response_body
true
true
true
true
false
false


