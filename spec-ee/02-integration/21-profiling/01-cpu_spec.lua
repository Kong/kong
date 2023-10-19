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


local function wait_for_profiler_started()
  local json

  assert.eventually(function()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/debug/profiling/cpu",
    })
    local body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.same("started", json.status)
  end)
  .with_timeout(3)
  .has_no_error("failed to wait the profiler to be started")

  return json
end


local function wait_for_proifler_stopped()
  local json

  assert.eventually(function()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/debug/profiling/cpu",
    })
    local body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.same("stopped", json.status)
  end)
  .with_timeout(10)
  .has_no_error("failed to wait the profiler to be stopped")

  return json
end

for _, strategy in helpers.each_strategy() do
for __, deploy in ipairs({ "traditional", "hybrid" }) do

  describe("CPU profiling #" .. strategy .. " #" .. deploy, function ()
  lazy_setup(function()
    helpers.get_db_utils(strategy)

    if deploy == "traditional" then
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
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
      }))

    else
      error("unknown deploy mode: " .. deploy)
    end
  end)

  lazy_teardown(function()
    assert(helpers.stop_kong())

    if deploy == "hybrid" then
      assert(helpers.stop_kong("servroot2"))
    end
  end)

  before_each(function()
    --[[
      We need to wait for one second to make Kong generate a unique path of result file,
      beacuase kong uses `ngx.time()` to generate the path.
    --]]
    ngx.update_time()
    ngx.sleep(1.2)

    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/debug/profiling/cpu",
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.same("stopped", json.status)
  end)

  it("debug_listen is enabled", function ()
    local http_client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(http_client:send {
      method = "GET",
      path = "/debug/profiling/cpu",
    })

    assert.res_status(200, res)
  end)

  it("allow only one profiler instance at the same time", function ()
    local admin_client = assert(helpers.admin_client())
    local body = {
      mode = "instruction",
      step = 100,
      timeout = 5,
    }

    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/cpu",
      body = body,
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    wait_for_profiler_started()

    res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/cpu",
      body = body,
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    local body = assert.res_status(409, res)
    local json = cjson.decode(body)

    assert.same("error", json.status)
    local found = string.find(json.message, "Profiling is already active on pid: ", 0, true)
    assert(found, "expected message to start with 'Profiling is already active on pid: '")

    res = assert(admin_client:send {
      method = "DELETE",
      path = "/debug/profiling/cpu",
    })

    assert.res_status(204, res)
  end)

  for _, mode in ipairs({ "instruction", "time" }) do
    it(string.format("profiling #%s-based", mode), function ()
      local admin_client = assert(helpers.admin_client())
      local body

      if mode == "instruction" then
        body = {
          mode = "instruction",
          step = 50,
          timeout = 5,
        }
      else
        body = {
          mode = "time",
          interval = 1,
          timeout = 5,
        }
      end

      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/cpu",
        body = body,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.res_status(201, res)

      local json = wait_for_profiler_started()
      assert.truthy(json.path)
      assert.truthy(json.pid)
      assert.truthy(json.remain)
      assert.truthy(json.samples)
      assert.same("started", json.status)
      assert.same(mode, json.mode)

      if mode == "instruction" then
        assert.falsy(json.interval)
        assert.same(50, json.step)

      else
        assert.falsy(json.step)
        assert.same(1, json.interval)
      end

      for i = 1, 100 do
        local client = assert(helpers.admin_client())

        client:send {
          method = "GET",
          path = "/routes",
        }

        client:close()
        ngx.sleep(0.002)
      end

      ngx.sleep(5 + 1) -- wait for profiling to timeout

      local path = json.path

      assert.same(path, wait_for_proifler_stopped().path)

      helpers.wait_for_file_contents(path, 10)
    end)
  end

  it("stop profiling manually", function ()
    for _, mode in ipairs({ "instruction", "time" }) do
      local admin_client = assert(helpers.admin_client())
      local body

      if mode == "instruction" then
        body = {
          mode = "instruction",
          step = 50,
          timeout = 5,
        }
      else
        body = {
          mode = "time",
          interval = 1,
          timeout = 5,
        }
      end

      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/cpu",
        body = body,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.res_status(201, res)

      local path

      -- wait for the worker events to be processed
      helpers.pwait_until(function()
        res = assert(admin_client:send {
          method = "GET",
          path = "/debug/profiling/cpu",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        path = json.path

        assert(json.status == "started")
      end, 3)

      res = assert(admin_client:send {
        method = "DELETE",
        path = "/debug/profiling/cpu",
      })

      assert.res_status(204, res)
      local state = assert(cjson.decode(res.headers["X-Kong-Profiling-State"]), "missing X-Kong-Profiling-State header")
      assert.same(path, state.path)
      assert.truthy(state.pid)

      helpers.wait_for_file("file", path, 5)
    end
  end)

  it("general constrains", function()
    local requests = {
      {
        request_body = {
          mode = "invalid",
        },
        response_body = {
          status = "error",
          message = "Invalid mode (must be 'time' or 'instruction'): invalid",
        },
      },
      {
        request_body = {
          pid = "1",      -- invalid worker pid
        },
        response_body = {
          status = "error",
          message = "Invalid pid: 1",
        },
      },
      {
        request_body = {
          timeout = 0,
        },
        response_body = {
          status = "error",
          message = "Invalid timeout (must be between 1 and 600): 0",
        },
      },
      {
        request_body = {
          timeout = 601,
        },
        response_body = {
          status = "error",
          message = "Invalid timeout (must be between 1 and 600): 601",
        },
      },
    }

    for _, request in ipairs(requests) do
      local admin_client = assert(helpers.admin_client())

      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/cpu",
        body = request.request_body,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.res_status(400, res)
      local json = cjson.decode(body)

      assert.same(request.response_body, json)
    end

  end)

  it("constrains for instruction-counter-based profiling", function ()
    local admin_client = assert(helpers.admin_client())

    for _, steps in ipairs({1, 1001}) do
      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/cpu",
        body = {
          mode = "instruction",
          step = steps,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.res_status(400, res)
      local json = cjson.decode(body)

      assert.same({
        status = "error",
        message = "Invalid step (must be between 50 and 1000): " .. steps
      }, json)
    end
  end)

  it("constrains for time-based profiling", function ()
      local admin_client = assert(helpers.admin_client())

      for _, interval in ipairs({0, 1000001}) do
        local res = assert(admin_client:send {
          method = "POST",
          path = "/debug/profiling/cpu",
          body = {
            mode = "time",
            interval = interval,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.same("error", json.status)
        assert.same("Invalid interval (must be between 1 and 1000000): " .. interval, json.message)
      end
  end)

  it("don't return the path if reload during the profiling", function ()
    local admin_client = assert(helpers.admin_client())
    local body = {
      mode = "instruction",
      step = 50,
      timeout = 5,
    }

    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/cpu",
      body = body,
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    local path

    -- wait for the worker events to be processed
    helpers.pwait_until(function()
      res = assert(admin_client:send {
        method = "GET",
        path = "/debug/profiling/cpu",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.same("started", json.status)
      path = json.path
    end, 3)

    -- reload
    assert(helpers.reload_kong("reload --prefix " .. helpers.test_conf.prefix))

    -- wait for automatic recovery
    helpers.pwait_until(function()
      -- remove the file to emulate a crash
      os.execute("rm -rf " .. path)

      --[[
        since we are reloading, the old connection will be closed,
        so we need to create a new one  
      --]]
      local admin_client = assert(helpers.admin_client())
      res = assert(admin_client:send {
        method = "GET",
        path = "/debug/profiling/cpu",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      admin_client:close()

      assert.same("stopped", json.status)
    end, 5 + 10 + 5) -- 5 seconds for the profiling timeout
                     -- 10 seconds for the key in shdict timeout
                     -- 5 seconds for the tolerance

  end)

  it("accept a valid PID", function ()
    local worker_pids = helpers.get_kong_workers()
    local admin_client = assert(helpers.admin_client())

    for _, pid in ipairs(worker_pids) do
      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/cpu",
        body = {
          pid = pid,
          mode = "instruction",
          step = 50,
          timeout = 5,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.res_status(201, res)

      -- wait for the worker events to be processed
      helpers.pwait_until(function()
        res = assert(admin_client:send {
          method = "GET",
          path = "/debug/profiling/cpu",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert(json.status == "started")
      end, 3)

      -- wait for the profiling to be stopped
      ngx.sleep(5 - 3)

      helpers.pwait_until(function()
        res = assert(admin_client:send {
          method = "GET",
          path = "/debug/profiling/cpu",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert(json.status == "stopped" and json.path, "profiling not stopped")
      end, 10)
    end
  end)

  it("check the profiler state before stopping it", function ()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "DELETE",
      path = "/debug/profiling/cpu",
    })

    local body = assert.res_status(400, res)
    local json = cjson.decode(body)

    assert.same("error", json.status)
    assert.same("Profiling is not active", json.message)
  end)
end)

end
end
