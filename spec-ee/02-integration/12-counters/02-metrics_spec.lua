-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local http_mock = require "spec.helpers.http_mock"

for _, strategy in helpers.each_strategy() do

describe("Sales counter #" .. strategy, function()
  local bp, db
  local mock_service
  local mock, mock_port
  local admin_client, proxy_client
  local healthz_route_id1 = utils.uuid()
  local healthz_route_id2 = utils.uuid()

  lazy_setup(function()
    mock = assert(http_mock.new(nil, {
      ["/"] = {
        content = [[
          ngx.print("congrats, it's a mock")
          ngx.flush(true)
        ]]
      },
    }, nil))
    assert(mock:start())
    mock_port = tonumber(mock:get_default_port())

    bp, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
    })

    mock_service = bp.services:insert({
      host = "localhost",
      port = mock_port,
    })

    local mock_upstream = bp.upstreams:insert({
      name = "mock_upstream",
    })

    bp.targets:insert({
      upstream = { id = mock_upstream.id },
      target = mock_service.host .. ":" .. mock_service.port,
    })

    bp.routes:insert({
      name = "a-regular-route",
      paths = { "/regular" },
      service = mock_service,
    })

    bp.routes:insert({
      name = "another-regular-route",
      paths = { "/also-regular" },
      protocols = { "http" },
      service = mock_service,
    })

    bp.routes:insert({
      name = "healthz-route",
      id = healthz_route_id1,
      paths = { "/healthz" },
      protocols = { "http" },
      service = mock_service,
    })

    bp.routes:insert({
      name = "secondary-healthz-route",
      id = healthz_route_id2,
      paths = { "/statuz" },
      protocols = { "http" },
      service = mock_service,
    })

    assert(helpers.start_kong({
      healthz_ids = string.format("%s, %s", healthz_route_id1, healthz_route_id2),
      database = strategy,
      license_path = "spec-ee/fixtures/mock_license.json",
      analytics_flush_interval = 1,
    }))

  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
    proxy_client = helpers.proxy_client()
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end

    if proxy_client then
      proxy_client:close()
    end
  end)

  describe("request_count", function()

    it("correctly counts requests", function()
      local requests = 10
      local res

      res = assert(admin_client:get("/license/report"))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local original_request_count = tonumber(json.counters.total_requests)

      for i=1,requests do
        res = proxy_client:send({
          method = "GET",
          path = "/regular",
        })
        assert.response(res).has_status(200)

        res = proxy_client:send({
          method = "GET",
          path = "/also-regular",
        })
        assert.response(res).has_status(200)
      end

      assert.eventually(function()
        res = assert(admin_client:get("/license/report"))
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        local total_request_count = tonumber(json.counters.total_requests)
        return (original_request_count + (requests * 2)) == total_request_count
      end)
      .with_timeout(10)
      .is_truthy("failed to count total number of requests")

    end)

    it("do not count health check related entities", function()
      local requests = 10
      local res

      res = assert(admin_client:get("/license/report"))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local original_request_count = tonumber(json.counters.total_requests)

      for i=1,requests do
        res = proxy_client:send({
          method = "GET",
          path = "/regular",
        })
        assert.response(res).has_status(200)

        res = proxy_client:send({
          method = "GET",
          path = "/healthz",
        })
        assert.response(res).has_status(200)

        res = proxy_client:send({
          method = "GET",
          path = "/also-regular",
        })
        assert.response(res).has_status(200)

        res = proxy_client:send({
          method = "GET",
          path = "/statuz",
        })
        assert.response(res).has_status(200)

      end

      assert.eventually(function()
        res = assert(admin_client:get("/license/report"))
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        local total_request_count = tonumber(json.counters.total_requests)
        return (original_request_count + (requests * 2)) == total_request_count
      end)
      .with_timeout(10)
      .is_truthy("failed to count total number of requests")

    end)

  end)

end)

end

