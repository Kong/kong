local helpers = require "spec.helpers"
local cjson   = require "cjson"

local function get_log(typ, n)
  local entries
  helpers.wait_until(function()
    local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                              helpers.mock_upstream_port))
    local res = client:get("/read_log/" .. typ, {
      headers = {
        Accept = "application/json"
      }
    })
    local raw = assert.res_status(200, res)
    local body = cjson.decode(raw)

    entries = body.entries
    return #entries > 0
  end, 10)
  if n then
    assert(#entries == n, "expected " .. n .. " log entries, but got " .. #entries)
  end
  return entries
end

for _, strategy in helpers.each_strategy() do
  describe("Balancer: respect max retries [#" .. strategy .. "]", function()
    local service

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      service = bp.services:insert {
        name            = "retry_service",
        host            = "127.0.0.1",
        port            = 62351,
        retries         = 5,
      }

      local route = bp.routes:insert {
        service    = service,
        paths      = { "/hello" },
        strip_path = false,
      }

      bp.plugins:insert {
        route = { id = route.id },
        name     = "http-log",
        config   = {
          queue_size = 1,
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http"
        }
      }

      local fixtures = {
        http_mock = {}
      }

      fixtures.http_mock.my_server_block = [[
        server {
          listen 0.0.0.0:62351;
          location /hello {
            content_by_lua_block {
              local request_counter = ngx.shared.request_counter
              local first_request = request_counter:get("first_request")
              if first_request == nil then
                request_counter:set("first_request", "yes")
                ngx.say("hello")
              else
                ngx.exit(ngx.HTTP_CLOSE)
              end
            }
          }
        }
      ]]

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        nginx_http_lua_shared_dict = "request_counter 1m",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("exceeded limit", function()
      -- First request should succeed and save connection to upstream in keepalive pool
      local proxy_client1 = helpers.proxy_client()
      local res = assert(proxy_client1:send {
        method = "GET",
        path = "/hello",
      })

      assert.res_status(200, res)

      proxy_client1:close()

      -- Second request should failed 1 times and retry 5 times and then return 502
      local proxy_client2 = helpers.proxy_client()

      res = assert(proxy_client2:send {
        method = "GET",
        path = "/hello",
      })

      assert.res_status(502, res)

      -- wait for the http-log plugin to flush the log
      ngx.sleep(1)

      local entries = get_log("http", 2)
      assert.equal(#entries[2].tries, 6)
    end)
  end)

  describe("Balancer: ensure Nginx's balancer retry work without Kong's lua balancer [#" .. strategy .. "]", function()
    lazy_setup(function()
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        nginx_http_include = "../spec/fixtures/balancer/pure_nginx_balancer.conf",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("Nginx's balancer work well", function()
      local proxy_client = helpers.proxy_client(nil, 62340)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/pure_ngx_balancer",
      })

      assert.res_status(200, res)
      local body = res:read_body()
      local up_port = tonumber(body)
      assert.same(62341, up_port)

      res = assert(proxy_client:send {
        method = "GET",
        path = "/pure_ngx_balancer",
      })

      assert.res_status(502, res)
      proxy_client:close()

      assert.logfile().has.line("free keepalive peer: saving connection")
      assert.logfile().has.line("get keepalive peer: using connection")
      assert.logfile().has.line("get rr peer")
      assert.logfile().has.line("free rr peer")
      assert.logfile().has.no.line("core dumped")
    end)
  end)
end
