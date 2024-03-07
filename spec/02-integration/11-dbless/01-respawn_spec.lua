local helpers = require "spec.helpers"
local cjson = require "cjson"

local WORKER_PROCS = 4

-- transient errors can leave holes in worker PID tables/arrays,
-- which may be encoded as NULL by cjson, so we need to filter those
-- out before attempting any maths
local function remove_nulls(t)
  local n = 0

  for i = 1, #t do
    local item = t[i]
    t[i] = nil

    if item ~= cjson.null then
      n = n + 1
      t[n] = item
    end
  end
end


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
    helpers.stop_kong()
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
    local pids

    assert.eventually(function()
      local res = admin_client:get("/")
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      pids = json.pids.workers
      remove_nulls(pids)

      if #pids == WORKER_PROCS then
        return true
      end

      return nil, {
                    err = "invalid worker pid count",
                    exp = WORKER_PROCS,
                    got = #pids,
                  }
    end)
    .is_truthy("expected / API endpoint to return the current number of workers")

    helpers.signal_workers(nil, "-TERM")

    -- `helpers.wait_until_no_common_workers()` is not used here because it
    -- works by using the very same API that this case is supposed to test
    assert.eventually(function()
      local res2 = admin_client:get("/")
      local body2 = assert.res_status(200, res2)
      local json2 = cjson.decode(body2)
      local pids2 = json2.pids.workers
      remove_nulls(pids2)

      if count_common_values(pids, pids2) > 0 then
        return nil, "old and new worker pids both present"

      elseif #pids2 ~= WORKER_PROCS then
        return nil, {
                      err = "unexpected number of worker pids",
                      exp = WORKER_PROCS,
                      got = #pids2,
                    }
      end

      return true
    end)
    .ignore_exceptions(true)
    .is_truthy("expected the admin API to report only new (respawned) worker pids")
  end)

  it("rotates kong:mem stats and deletes the old ones", function()
    local mem

    assert.eventually(function()
      local res = admin_client:get("/status")
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      mem = json.memory.workers_lua_vms
      remove_nulls(mem)

      if #mem == WORKER_PROCS then
        return true
      end

      return nil, {
                    err = "unexpected worker count",
                    exp = WORKER_PROCS,
                    got = #mem,
                  }
    end)
    .is_truthy("expected /status API endpoint to return the current number of workers")

    helpers.signal_workers(nil, "-TERM")

    -- `helpers.wait_until_no_common_workers()` is not used here because it
    -- more-or-less relies on the same mechanism that is being tested here.
    assert.eventually(function()
      local res2 = admin_client:get("/status")
      local body2 = assert.res_status(200, res2)
      local json2 = cjson.decode(body2)
      local mem2 = json2.memory.workers_lua_vms
      remove_nulls(mem2)

      local matching = 0
      for _, value in ipairs(mem) do
        for _, value2 in ipairs(mem2) do
          assert.not_nil(value.pid)
          assert.not_nil(value2.pid)

          if value.pid == value2.pid then
            matching = matching + 1
            break
          end
        end
      end

      if matching > 0 then
        return nil, "old and new worker mem stats still present"

      elseif #mem2 ~= WORKER_PROCS then
        return nil, {
                      err = "unexpected number of workers",
                      exp = WORKER_PROCS,
                      got = #mem2,
                    }
      end

      return true
    end)
    .ignore_exceptions(true)
    .is_truthy("expected defunct worker memory stats to be cleared")
  end)

  it("lands on the correct cache page #5799", function()
    local res = assert(admin_client:send {
      method = "POST",
      path = "/config",
      body = {
        config = string.format([[
        _format_version: "3.0"
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

    local workers = helpers.get_kong_workers(WORKER_PROCS)
    proxy_client:close()

    -- kill all the workers forcing all of them to respawn
    helpers.signal_workers(nil, "-TERM")

    helpers.wait_until_no_common_workers(workers, WORKER_PROCS)

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
