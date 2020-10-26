local bu = require "spec.fixtures.balancer_utils"
local helpers = require "spec.helpers"

for _, consistency in ipairs(bu.consistencies) do
  for _, strategy in helpers.each_strategy() do
    describe("Balancing with round-robin #" .. consistency, function()
      local bp

      lazy_setup(function()
        bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
          "routes",
          "services",
          "plugins",
          "upstreams",
          "targets",
        })

        local fixtures = {
          dns_mock = helpers.dns_mock.new()
        }

        fixtures.dns_mock:SRV {
          name = "my.srv.test.com",
          target = "a.my.srv.test.com",
          port = 80,  -- port should fail to connect
        }
        fixtures.dns_mock:A {
          name = "a.my.srv.test.com",
          address = "127.0.0.1",
        }

        fixtures.dns_mock:A {
          name = "multiple-ips.test",
          address = "127.0.0.1",
        }
        fixtures.dns_mock:A {
          name = "multiple-ips.test",
          address = "127.0.0.2",
        }

        fixtures.dns_mock:SRV {
          name = "srv-changes-port.test",
          target = "a-changes-port.test",
          port = 90,  -- port should fail to connect
        }

        fixtures.dns_mock:A {
          name = "a-changes-port.test",
          address = "127.0.0.3",
        }
        fixtures.dns_mock:A {
          name = "another.multiple-ips.test",
          address = "127.0.0.1",
        }
        fixtures.dns_mock:A {
          name = "another.multiple-ips.test",
          address = "127.0.0.2",
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          db_update_frequency = 0.1,
          worker_consistency = consistency,
          worker_state_update_frequency = bu.CONSISTENCY_FREQ,
        }, nil, nil, fixtures))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)


      it("over multiple targets", function()

        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local port2 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        local requests = bu.SLOTS * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = bu.http_server("127.0.0.1", port1, { requests / 2 })
        local server2 = bu.http_server("127.0.0.1", port2, { requests / 2 })

        -- Go hit them with our test requests
        local oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:done()
        local _, count2 = server2:done()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)
      end)

      it("adding a target", function()

        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1", nil, { weight = 10 })
        local port2 = bu.add_target(bp, upstream_id, "127.0.0.1", nil, { weight = 10 })
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        local requests = bu.SLOTS * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = bu.http_server("127.0.0.1", port1, { requests / 2 })
        local server2 = bu.http_server("127.0.0.1", port2, { requests / 2 })

        -- Go hit them with our test requests
        local oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:done()
        local _, count2 = server2:done()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- add a new target 3
        -- shift proportions from 50/50 to 40/40/20
        bu.begin_testcase_setup_update(strategy, bp)
        local port3 = bu.add_target(bp, upstream_id, "127.0.0.1", nil, { weight = 5 })
        bu.end_testcase_setup(strategy, bp, consistency)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        local server3
        server1 = bu.http_server("127.0.0.1", port1, { requests * 0.4 })
        server2 = bu.http_server("127.0.0.1", port2, { requests * 0.4 })
        server3 = bu.http_server("127.0.0.1", port3, { requests * 0.2 })

        -- Go hit them with our test requests
        oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:done()
        _, count2 = server2:done()
        local _, count3 = server3:done()

        -- verify
        assert.are.equal(requests * 0.4, count1)
        assert.are.equal(requests * 0.4, count2)
        assert.are.equal(requests * 0.2, count3)
      end)

      it("removing a target #db", function()
        local requests = bu.SLOTS * 2 -- go round the balancer twice

        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local port2, target2 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = bu.http_server("127.0.0.1", port1, { requests / 2 })
        local server2 = bu.http_server("127.0.0.1", port2, { requests / 2 })

        -- Go hit them with our test requests
        local oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:done()
        local _, count2 = server2:done()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for target 2, set to 0
        bu.begin_testcase_setup_update(strategy, bp)
        bu.update_target(bp, upstream_id, "127.0.0.1", port2, {
          id = target2.id,
          weight = 0, -- disable this target
        })
        bu.end_testcase_setup(strategy, bp, consistency)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        server1 = bu.http_server("127.0.0.1", port1, { requests })

        -- Go hit them with our test requests
        oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:done()

        -- verify all requests hit server 1
        assert.are.equal(requests, count1)
      end)
      it("modifying target weight #db", function()
        local requests = bu.SLOTS * 2 -- go round the balancer twice

        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local port2 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = bu.http_server("127.0.0.1", port1, { requests / 2 })
        local server2 = bu.http_server("127.0.0.1", port2, { requests / 2 })

        -- Go hit them with our test requests
        local oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:done()
        local _, count2 = server2:done()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for target 2
        bu.begin_testcase_setup_update(strategy, bp)
        bu.update_target(bp, upstream_id, "127.0.0.1", port2, {
          weight = 15,   -- shift proportions from 50/50 to 40/60
        })
        bu.end_testcase_setup(strategy, bp, consistency)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        server1 = bu.http_server("127.0.0.1", port1, { requests * 0.4 })
        server2 = bu.http_server("127.0.0.1", port2, { requests * 0.6 })

        -- Go hit them with our test requests
        oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:done()
        _, count2 = server2:done()

        -- verify
        assert.are.equal(requests * 0.4, count1)
        assert.are.equal(requests * 0.6, count2)
      end)

      it("failure due to targets all 0 weight #db", function()
        local requests = bu.SLOTS * 2 -- go round the balancer twice

        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local port2 = bu.add_target(bp, upstream_id, "127.0.0.1")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = bu.http_server("127.0.0.1", port1, { requests / 2 })
        local server2 = bu.http_server("127.0.0.1", port2, { requests / 2 })

        -- Go hit them with our test requests
        local oks = bu.client_requests(requests, api_host)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:done()
        local _, count2 = server2:done()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for both targets, set to 0
        bu.begin_testcase_setup_update(strategy, bp)
        bu.update_target(bp, upstream_id, "127.0.0.1", port1, { weight = 0 })
        bu.update_target(bp, upstream_id, "127.0.0.1", port2, { weight = 0 })
        bu.end_testcase_setup(strategy, bp, consistency)

        -- now go and hit the same balancer again
        -----------------------------------------

        local _, _, status = bu.client_requests(1, api_host)
        assert.same(503, status)
      end)

      it("failure due to targets all 0 weight #off", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "127.0.0.1", nil, { weight = 0 })
        local port2 = bu.add_target(bp, upstream_id, "127.0.0.1", nil, { weight = 0 })
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        bu.http_server("127.0.0.1", port1, 1)
        bu.http_server("127.0.0.1", port2, 1)

        local _, _, status = bu.client_requests(1, api_host)
        assert.same(503, status)
      end)
    end)

    describe("Balancing with no targets #" .. consistency, function()
      local bp

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
          worker_consistency = consistency,
          worker_state_update_frequency = bu.CONSISTENCY_FREQ,
        }))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)
      it("failure due to no targets", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name = bu.add_upstream(bp)
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- Go hit it with a request
        local _, _, status = bu.client_requests(1, api_host)
        assert.same(503, status)
      end)

      for mode, localhost in pairs(bu.localhosts) do
        it("removing and adding the same target #db #" .. mode, function()

          bu.begin_testcase_setup(strategy, bp)
          local upstream_name, upstream_id = bu.add_upstream(bp)
          local port = bu.add_target(bp, upstream_id, localhost, nil, { weight = 100 })
          local api_host = bu.add_api(bp, upstream_name)
          bu.end_testcase_setup(strategy, bp, consistency)

          local requests = 20

          local server = bu.http_server(localhost, port, { requests })
          local oks = bu.client_requests(requests, api_host)
          local _, count = server:done()
          assert.equal(requests, oks)
          assert.equal(requests, count)

          -- remove target
          bu.begin_testcase_setup_update(strategy, bp)
          bu.update_target(bp, upstream_id, localhost, port, {
            weight = 0,
          })
          bu.end_testcase_setup(strategy, bp, consistency)

          server = bu.http_server(localhost, port, { requests })
          oks = bu.client_requests(requests, api_host)
          _, count = server:done()
          assert.equal(0, oks)
          assert.equal(0, count)

          -- add the target back with same weight as initial weight
          bu.begin_testcase_setup_update(strategy, bp)
          bu.update_target(bp, upstream_id, localhost, port, {
            weight = 100,
          })
          bu.end_testcase_setup(strategy, bp, consistency)

          server = bu.http_server(localhost, port, { requests })
          oks = bu.client_requests(requests, api_host)
          _, count = server:done()
          assert.equal(requests, oks)
          assert.equal(requests, count)
        end)
      end
    end)

  end
end

