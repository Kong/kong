local bu = require "spec.fixtures.balancer_utils"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Balancing with round-robin #" .. strategy, function()
    local bp, proxy_client

    lazy_setup(function()
      bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
        "routes",
        "services",
        "plugins",
        "upstreams",
        "targets",
      })

      local fixtures = {
        http_mock = {
          least_connections = [[

            server {
                listen 10001;

                location ~ "/recreate_test" {
                    content_by_lua_block {
                      ngx.sleep(700)
                      ngx.exit(ngx.OK)
                    }
                }
            }

            server {
                listen 10002;

                location ~ "/recreate_test" {
                    content_by_lua_block {
                      ngx.say("host is: ", ngx.var.http_host)
                      ngx.exit(ngx.OK)
                    }
                }
            }

        ]]
        },
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:A {
        name = "upstream.example.com",
        address = "127.0.0.1",
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        worker_state_update_frequency = bu.CONSISTENCY_FREQ,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    it("balancer retry updates Host header in request buffer", function()
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp)
      bu.add_target(bp, upstream_id, "upstream.example.com", 10001) -- this will timeout
      bu.add_target(bp, upstream_id, "upstream.example.com", 10002)

      local service = assert(bp.services:insert({
        url = "http://" .. upstream_name,
        read_timeout = 500,
      }))

      bp.routes:insert({
        service = { id = service.id },
        paths = { "/", },
      })
      bu.end_testcase_setup(strategy, bp, "strict")

      local res = assert(proxy_client:send {
        method  = "GET",
        path = "/recreate_test",
      })

      local body = assert.response(res).has_status(200)
      assert.equal("host is: upstream.example.com:10002", body)
    end)
  end)
end

