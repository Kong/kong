# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';

repeat_each(1);

our $HttpConfig = qq{
    lua_shared_dict prometheus_metrics 5m;
    init_worker_by_lua_block {
      package.loaded['prometheus_resty_counter'] = require("resty.counter")

      local prometheus = require("kong.plugins.prometheus.prometheus")
      _G.prom = prometheus.init("prometheus_metrics", "kong_")
    }
};

run_tests();

__DATA__

=== TEST 1: check metric names
--- http_config eval: $::HttpConfig
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


=== TEST 2: check metric label names
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          local m

          m = _G.prom:counter("mem1", "h", {"lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem2", "h", {"_lua_"})
          ngx.say(not not m)

          m = _G.prom:counter("mem3", "h", {":lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem4", "h", {"0lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem5", "h", {"lua*"})
          ngx.say(not not m)
        }
    }
--- request
GET /t
--- response_body
true
true
false
false
false


