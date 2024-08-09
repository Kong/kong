-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local DEBUG_LISTEN_HOST = "0.0.0.0"
local DEBUG_LISTEN_PORT = 9200

for _, strategy in helpers.each_strategy() do
for __, deploy in ipairs({ "traditional", "hybrid" }) do

describe("Memory analyzer #" .. strategy .. " #" .. deploy, function ()
  -- Test cases like following need a clean setup to run. So before_each is used.
  --  "run memory analyzer when already running"
  --  "run memory analyzer into timeout"
  before_each(function()
    helpers.get_db_utils(strategy)

    if deploy == "traditional" then
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
        nginx_main_worker_processes = 4
      }))

    elseif deploy == "hybrid" then
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
        nginx_main_worker_processes = 4
      }))

    else
      error("unknown deploy mode: " .. deploy)
    end
  end)

  after_each(function()
    assert(helpers.stop_kong())

    if deploy == "hybrid" then
      assert(helpers.stop_kong("servroot2"))
    end
  end)

  it("check debug_listen is enabled", function ()
    local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(client:send {
      method = "GET",
      path = "/debug/profiling/memory-analyzer",
    })

    assert.res_status(200, res)
  end)

  it("run memory analyzer", function ()
    local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(client:send {
      method = "POST",
      path = "/debug/profiling/memory-analyzer",
    })

    assert.res_status(201, res)

    local path

    helpers.pwait_until(function()
      local res = assert(client:send {
        method = "GET",
        path = "/debug/profiling/memory-analyzer",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.same("stopped", json.status, "expected status to be 'stopped, got '" .. json.status .. "'")
      assert.truthy(json.path)

      path = json.path
    end, 30) -- CI is very slow for computing task

    helpers.wait_for_file_contents(path, 15)

    local f = io.open(path)
    local iter = f:lines()
    local line = iter()
    assert(line == "\"Root\"  addr=0x0 0", "not expected first line: " .. line)
  end)

  -- on hybrid mode, can not get the worker_pids to do this test.
  if deploy == "traditional" then
    it("check accepting a valid PID", function ()
      local worker_pids = helpers.get_kong_workers()
      local picked_pid = worker_pids[1]
      local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

      local res = assert(client:send {
        method = "POST",
        path = "/debug/profiling/memory-analyzer",
        body = {
          pid = picked_pid,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.same(json.message, "Running memory analyzer on pid: " .. picked_pid, "Memory analyzer is not on specified pid")

      helpers.pwait_until(function()
        res = assert(client:send {
          method = "GET",
          path = "/debug/profiling/memory-analyzer",
          body = {
            pid = picked_pid,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same("stopped", json.status)
        assert.equals(picked_pid, json.pid)
        assert.truthy(json.path)
      end, 30) -- CI is very slow for computing task
    end)
  end

  it("check reject invalid PID", function ()
    local invalid_worker_pid = 1
    local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(client:send {
      method = "POST",
      path = "/debug/profiling/memory-analyzer",
      body = {
        pid = invalid_worker_pid,
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    local body = assert.res_status(400, res)
    local json = cjson.decode(body)
    assert.same(json.message, "Invalid pid: " .. invalid_worker_pid, "Memory analyzer is on invalid pid")
  end)

  it("run memory analyzer when already running", function ()
    local trigger_analyzer = function()
      local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))
      return assert(client:send {
        method = "POST",
        path = "/debug/profiling/memory-analyzer",
      })
    end

    -- the memory analyzer is a blocking call. So to trigger another
    -- request at the same time, a thread is needed.
    ngx.thread.spawn(trigger_analyzer)

    -- sleep to ensure the first trigger_analyzer call has been executed.
    ngx.sleep(1)
    -- trigger a second call.
    local res = trigger_analyzer()

    assert.res_status(409, res)
  end)

  it("run memory analyzer into timeout", function ()
    local client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(client:send {
      method = "POST",
     path = "/debug/profiling/memory-analyzer",
      body = {
        timeout = 0.1,
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(400, res)
  end)

end)

end
end
