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
    local handler = function()
      local res = assert(client:send {
        method = "GET",
        path = "/slow-resource?prime=true&sleep=2",
        headers = { ["Content-Type"] = "application/json" }
      })
      assert.res_status(204 , res)
    end

    for i = 0, 2 do
      handler()
    end

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
