local helpers = require "spec.helpers"
local cjson = require "cjson"

local WORKER_PROCS = 4

local function count_common_values(t1, t2)
  local counts = {}

  for _, item in ipairs(t1) do
    assert(counts[item] == nil, "duplicate item in table")
    counts[item] = 1
  end

  for _, item in ipairs(t2) do
    counts[item] = (counts[item] or 0) + 1
  end

  local common = 0

  for _, c in pairs(counts) do
    if c > 1 then
      common = common + 1
    end
  end

  return common
end


describe("worker respawn", function()
  local admin_client, proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_main_worker_processes = WORKER_PROCS,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  before_each(function()
    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end

    if proxy_client then
      proxy_client:close()
    end
  end)

  it("rotates pids and deletes the old ones", function()
    local res = admin_client:get("/")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local pids = json.pids.workers

    assert.same(WORKER_PROCS, #pids, "unexpected number of worker pids")

    helpers.signal_workers(nil, "-TERM")

    assert.eventually(function()
      local pok, admin_client2 = pcall(helpers.admin_client)
      if not pok then
        return nil, "failed creating admin client: " .. tostring(admin_client2)
      end

      local res2 = admin_client2:get("/")
      local body2 = assert.res_status(200, res2)
      local json2 = cjson.decode(body2)
      local pids2 = json2.pids.workers

      admin_client2:close()

      if #pids2 ~= WORKER_PROCS then
        return nil, "unexpected number of new worker pids: " .. tostring(#pids2)
      end

      if count_common_values(pids, pids2) > 0 then
        return nil, "old and new worker pids both present"
      end

      return true
    end)
    .is_truthy("expected the admin API to report only new (respawned) worker pids")
  end)

  it("rotates kong:mem stats and deletes the old ones", function()
    local proxy_res = proxy_client:get("/")
    assert.res_status(404, proxy_res)

    local res = admin_client:get("/status")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local mem = json.memory.workers_lua_vms

    helpers.signal_workers(nil, "-TERM")

    helpers.wait_until(function()
      local pok, proxy_client2 = pcall(helpers.proxy_client)
      if not pok then
        return false
      end

      local proxy_res2 = proxy_client2:get("/")
      assert.res_status(404, proxy_res2)
      proxy_client2:close()

      local admin_client2
      pok, admin_client2 = pcall(helpers.admin_client)
      if not pok then
        return false
      end

      local res2 = admin_client2:get("/status")
      local body2 = assert.res_status(200, res2)
      local json2 = cjson.decode(body2)
      local mem2 = json2.memory.workers_lua_vms

      admin_client2:close()

      assert.equal(#mem, #mem2)

      local matching = 0
      for _, value in ipairs(mem) do
        for _, value2 in ipairs(mem2) do
          assert.not_nil(value.pid)
          assert.not_nil(value2.pid)

          if value.pid == value2.pid then
            matching = matching + 1
          end
        end
      end

      assert.equal(0, matching)

      return true
    end)
  end)

  it("lands on the correct cache page #5799", function()
    local res = assert(admin_client:send {
      method = "POST",
      path = "/config",
      body = {
        config = string.format([[
        _format_version: "1.1"
        services:
        - name: my-service
          host: %s
          port: %s
          path: /
          protocol: http
          plugins:
          - name: key-auth
          routes:
          - name: my-route
            paths:
            - /

        consumers:
        - username: my-user
          keyauth_credentials:
          - key: my-key
        ]], helpers.mock_upstream_host, helpers.mock_upstream_port),
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.response(res).has.status(201)

    helpers.wait_until(function()
      res = assert(proxy_client:get("/"))

      return pcall(function()
        assert.res_status(401, res)
      end)
    end, 10)

    res = assert(proxy_client:get("/", {
      headers = {
        apikey = "my-key"
      }
    }))
    assert.res_status(200, res)

    -- kill all the workers forcing all of them to respawn
    helpers.signal_workers(nil, "-TERM")

    proxy_client:close()
    proxy_client = assert(helpers.proxy_client())

    res = assert(proxy_client:get("/"))
    assert.res_status(401, res)

    res = assert(proxy_client:get("/", {
      headers = {
        apikey = "my-key"
      }
    }))
    assert.res_status(200, res)
  end)
end)
