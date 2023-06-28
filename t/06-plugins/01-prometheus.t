# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

our $HttpConfig = qq{
    lua_shared_dict prometheus_metrics 1m;
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

          m = _G.prom:counter("Mem_Used")
          ngx.say(not not m)

          m = _G.prom:counter(":mem_used")
          ngx.say(not not m)

          m = _G.prom:counter("mem_used:")
          ngx.say(not not m)

          m = _G.prom:counter("_mem_used_")
          ngx.say(not not m)

          m = _G.prom:counter("mem-used")
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
true
false
false
false


=== TEST 2: check metric label names
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          local m

          m = _G.prom:counter("mem0", nil, {"LUA"})
          ngx.say(not not m)

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

          m = _G.prom:counter("mem6", nil, {"lua\\5.1"})
          ngx.say(not not m)

          m = _G.prom:counter("mem7", nil, {"lua\"5.1\""})
          ngx.say(not not m)

          m = _G.prom:counter("mem8", nil, {"lua-vm"})
          ngx.say(not not m)
        }
    }
--- request
GET /t
--- response_body
true
true
true
false
false
false
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

          m = _G.prom:counter("file", nil, {"path"})
          ngx.say(not not m)
          m:inc(1, {"\\root"})

          m = _G.prom:counter("user", nil, {"name"})
          ngx.say(not not m)
          m:inc(1, {"\"quote"})

          -- sync to shdict
          _G.prom._counter:sync()

          ngx.say(shm:get([[mem{lua="2.1"}]]))
          ngx.say(shm:get([[file{path="\\root"}]]))
          ngx.say(shm:get([[user{name="\"quote"}]]))
        }
    }
--- request
GET /t
--- response_body
true
true
true
1
1
1


=== TEST 4: emit metric data
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
          local m

          m = _G.prom:counter("mem", nil, {"lua"})
          m:inc(2, {"2.1"})

          m = _G.prom:counter("file", nil, {"path"})
          m:inc(3, {"\\root"})

          m = _G.prom:counter("user", nil, {"name"})
          m:inc(5, {"\"quote"})
          m:inc(1, {"\"quote"})

          _G.prom:collect()
        }
    }
--- request
GET /t
--- response_body
# TYPE kong_file counter
kong_file{path="\\root"} 3
# TYPE kong_mem counter
kong_mem{lua="2.1"} 2
# HELP kong_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE kong_nginx_metric_errors_total counter
kong_nginx_metric_errors_total 0
# TYPE kong_user counter
kong_user{name="\"quote"} 6


