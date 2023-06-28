# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

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

          m = _G.prom:counter("mem1", nil, {"lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem2", nil, {"_lua_"})
          ngx.say(not not m)

          m = _G.prom:counter("mem3", nil, {":lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem4", nil, {"0lua"})
          ngx.say(not not m)

          m = _G.prom:counter("mem5", nil, {"lua*"})
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


=== TEST 3: check metric full name
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          local shm = ngx.shared["prometheus_metrics"]
          local m

          m = _G.prom:counter("mem", nil, {"lua"})
          ngx.say(not not m)

          m:inc(1, {"2.1"})
          ngx.sleep(1.05)

          ngx.say(shm:get([[mem{lua="2.1"}]]))
        }
    }
--- request
GET /t
--- response_body
true
1


