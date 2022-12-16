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
    local res = assert(client:send {
      method = "GET",
      path = "/slow-resource?prime=true",
      headers = { ["Content-Type"] = "application/json" }
    })
    assert.res_status(204 , res)

    helpers.wait_timer("slow-query", true, "any-running")

    res = assert(client:send {
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
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("results in query error too many waiting connect operations when backlog exceeds", function()
    helpers.wait_timer("slow-query", true, "all-finish")

    local handler = function()
      local client = helpers.admin_client()
      local res = assert(client:send {
        method = "GET",
        path = "/slow-resource?prime=true",
        headers = { ["Content-Type"] = "application/json" }
      })
      assert.res_status(204 , res)
      client:close()
    end

    -- send 2 requests, both should succeed as pool size is 1 and backlog is 1
    for i = 0, 1 do
      ngx.thread.spawn(handler)
    end

    -- make sure both the timers are running
    helpers.wait_timer("slow-query", true, "all-running")

    -- now the request should fail as both pool and backlog is full
    local client = helpers.admin_client()
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
