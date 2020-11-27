local bu = require "spec.fixtures.balancer_utils"
local helpers = require "spec.helpers"
local https_server = require "spec.fixtures.https_server"


for _, strategy in helpers.each_strategy() do
  for mode, localhost in pairs(bu.localhosts) do
    describe("Balancing with consistent hashing #" .. mode, function()
      local bp

      describe("over multiple targets", function()
        lazy_setup(function()
          bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
            "routes",
            "services",
            "plugins",
            "upstreams",
            "targets",
          })

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            db_update_frequency = 0.1,
          }, nil, nil, nil))

        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("hashing on header", function()
          local requests = bu.SLOTS * 2 -- go round the balancer twice

          bu.begin_testcase_setup(strategy, bp)
          local upstream_name, upstream_id = bu.add_upstream(bp, {
            hash_on = "header",
            hash_on_header = "hashme",
          })
          local port1 = bu.add_target(bp, upstream_id, localhost)
          local port2 = bu.add_target(bp, upstream_id, localhost)
          local api_host = bu.add_api(bp, upstream_name)
          bu.end_testcase_setup(strategy, bp)

          -- setup target servers
          local server1 = https_server.new(port1, localhost)
          local server2 = https_server.new(port2, localhost)
          server1:start()
          server2:start()

          -- Go hit them with our test requests
          local oks = bu.client_requests(requests, {
            ["Host"] = api_host,
            ["hashme"] = "just a value",
          })
          assert.are.equal(requests, oks)

          -- collect server results; hitcount
          -- one should get all the hits, the other 0
          local count1 = server1:shutdown()
          local count2 = server2:shutdown()

          -- verify
          assert(count1.total == 0 or count1.total == requests, "counts should either get 0 or ALL hits")
          assert(count2.total == 0 or count2.total == requests, "counts should either get 0 or ALL hits")
          assert(count1.total + count2.total == requests)
        end)

        describe("hashing on cookie", function()
          it("does not reply with Set-Cookie if cookie is already set", function()
            bu.begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = bu.add_upstream(bp, {
              hash_on = "cookie",
              hash_on_cookie = "hashme",
            })
            local port = bu.add_target(bp, upstream_id, localhost)
            local api_host = bu.add_api(bp, upstream_name)
            bu.end_testcase_setup(strategy, bp)

            -- setup target server
            local server = https_server.new(port, localhost)
            server:start()

            -- send request
            local client = helpers.proxy_client()
            local res = client:send {
              method = "GET",
              path = "/",
              headers = {
                ["Host"] = api_host,
                ["Cookie"] = "hashme=some-cookie-value",
              }
            }
            local set_cookie = res.headers["Set-Cookie"]

            client:close()
            server:shutdown()

            -- verify
            assert.is_nil(set_cookie)
          end)

          it("replies with Set-Cookie if cookie is not set", function()
            local requests = bu.SLOTS * 2 -- go round the balancer twice

            bu.begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = bu.add_upstream(bp, {
              hash_on = "cookie",
              hash_on_cookie = "hashme",
            })
            local port1 = bu.add_target(bp, upstream_id, localhost)
            local port2 = bu.add_target(bp, upstream_id, localhost)
            local api_host = bu.add_api(bp, upstream_name)
            bu.end_testcase_setup(strategy, bp)

            -- setup target servers
            local server1 = https_server.new(port1, localhost)
            local server2 = https_server.new(port2, localhost)
            server1:start()
            server2:start()

            -- initial request without the `hash_on` cookie
            local client = helpers.proxy_client()
            local res = client:send {
              method = "GET",
              path = "/",
              headers = {
                ["Host"] = api_host,
                ["Cookie"] = "some-other-cooke=some-other-value",
              }
            }
            local cookie = res.headers["Set-Cookie"]:match("hashme%=(.*)%;")

            client:close()

            -- subsequent requests add the cookie that was set by the first response
            local oks = 1 + bu.client_requests(requests - 1, {
              ["Host"] = api_host,
              ["Cookie"] = "hashme=" .. cookie,
            })
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            -- one should get all the hits, the other 0
            local count1 = server1:shutdown()
            local count2 = server2:shutdown()

            -- verify
            assert(count1.total == 0 or count1.total == requests,
                   "counts should either get 0 or ALL hits, but got " .. count1.total .. " of " .. requests)
            assert(count2.total == 0 or count2.total == requests,
                   "counts should either get 0 or ALL hits, but got " .. count2.total .. " of " .. requests)
            assert(count1.total + count2.total == requests)
          end)

        end)

      end)
    end)
  end
end
