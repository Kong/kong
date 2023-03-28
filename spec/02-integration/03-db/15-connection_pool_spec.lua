-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("#postgres Postgres connection pool", function()
  local client

  setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "plugins",
    }, {
      "slow-query"
    })

    bp.plugins:insert({
      name = "slow-query",
    })

    assert(helpers.start_kong({
      database = "postgres",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "slow-query",
      nginx_worker_processes = 1,
      pg_pool_size = 1,
      pg_backlog = 0,
    }))
    client = helpers.admin_client()
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end)

  it("results in query error too many waiting connect operations", function()
    helpers.wait_timer("slow-query", true, "all-finish", 10)

    helpers.wait_until(function()
      local res = assert(client:send {
        method = "GET",
        path = "/slow-resource?prime=true",
        headers = { ["Content-Type"] = "application/json" }
      })
      res:read_body()
      return res.status == 204
    end, 10)

    helpers.wait_timer("slow-query", true, "any-running")

    local res = assert(client:send {
      method = "GET",
      path = "/slow-resource",
      headers = { ["Content-Type"] = "application/json" }
    })
    local body = assert.res_status(500 , res)
    local json = cjson.decode(body)
    assert.same({ error = "too many waiting connect operations" }, json)
  end)
end)

describe("#postgres Postgres connection pool with backlog", function()
  local client

  setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "plugins",
    }, {
      "slow-query"
    })

    bp.plugins:insert({
      name = "slow-query",
    })

    assert(helpers.start_kong({
      database = "postgres",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "slow-query",
      nginx_worker_processes = 1,
      pg_pool_size = 1,
      pg_backlog = 1,
    }))
    client = helpers.admin_client()
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end)

  it("results in query error too many waiting connect operations when backlog exceeds", function()
    helpers.wait_timer("slow-query", true, "all-finish", 10)

    -- send 2 requests, both should succeed as pool size is 1 and backlog is 1
    helpers.wait_until(function()
      local ok = true
      for _ = 0, 1 do
        local res = assert(client:send {
          method = "GET",
          path = "/slow-resource?prime=true",
          headers = { ["Content-Type"] = "application/json" }
        })
        res:read_body()
        ok = ok and res.status == 204
      end
      return ok
    end, 10)

    -- make sure both the timers are running
    helpers.wait_timer("slow-query", true, "all-running")

    -- now the request should fail as both pool and backlog is full
    local res = assert(client:send {
      method = "GET",
      path = "/slow-resource",
      headers = { ["Content-Type"] = "application/json" }
    })
    local body = assert.res_status(500 , res)
    local json = cjson.decode(body)
    assert.same({ error = "too many waiting connect operations" }, json)
  end)
end)
