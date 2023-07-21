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

local function wait_for_tracer_started()
  local json

  assert.eventually(function()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/debug/profiling/memory",
    })
    local body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.same("started", json.status)
  end)
  .with_timeout(3)
  .has_no_error("failed to wait the tracer to be started")

  return json
end


local function wait_for_tracer_stopped()
  local json

  assert.eventually(function()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/debug/profiling/memory",
    })
    local body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.same("stopped", json.status)
  end)
  .with_timeout(5)
  .has_no_error("failed to wait the tracer to be stopped")

  return json
end

for _, strategy in helpers.each_strategy() do
for __, deploy in ipairs({ "traditional", "hybrid" }) do

describe("Memory tracing #" .. strategy .. " #" .. deploy, function ()
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
      path = "/debug/profiling/memory",
    })

    assert.res_status(200, res)
  end)

  it("allow only one profiler instance at the same time", function ()
    local admin_client = assert(helpers.admin_client())
    local body = {
      timeout = 5,
    }

    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/memory",
      body = body,
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    wait_for_tracer_started()

    res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/memory",
      body = body,
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    local body = assert.res_status(409, res)
    local json = cjson.decode(body)

    assert.same("error", json.status)
    local found = string.find(json.message, "memory tracing is already active at pid: ", 0, true)
    assert(found, "expected message to start with 'memory tracing is already active at pid: '")

    res = assert(admin_client:send {
      method = "DELETE",
      path = "/debug/profiling/memory",
    })

    assert.res_status(204, res)
  end)

  it("tracing", function ()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/memory",
      body = {
        timeout = 5,
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    local json = wait_for_tracer_started()
    assert(json.path)
    assert(json.remain)

    json = wait_for_tracer_stopped()

    helpers.wait_for_file_contents(string.format("%s-0.bin", json.path), 15)
  end)

  it("stop tracing manually", function ()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/memory",
      body = {
        timeout = 5,
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    local json = wait_for_tracer_started()
    assert(json.path)
    assert(json.remain)

    res = assert(admin_client:send {
      method = "DELETE",
      path = "/debug/profiling/memory",
    })

    assert.res_status(204, res)

    local path = wait_for_tracer_stopped().path
    helpers.wait_for_file_contents(string.format("%s-0.bin", path), 15)
  end)

  it("general constrains", function()
    local requests = {
      {
        request_body = {
          pid = "1",      -- invalid worker pid
        },
        response_body = {
          status = "error",
          message = "invalid pid: 1",
        },
      },
      {
        request_body = {
          timeout = 0,
        },
        response_body = {
          status = "error",
          message = "invalid timeout (must be greater than 1): 0",
        },
      },
      {
        request_body = {
          stack_depth = 0,
        },
        response_body = {
          status = "error",
          message = "invalid stack depth (must be between 1 and 64): 0",
        },
      },
      {
        request_body = {
          stack_depth = 65,
        },
        response_body = {
          status = "error",
          message = "invalid stack depth (must be between 1 and 64): 65",
        },
      },
      {
        request_body = {
          block_size = 1,
        },
        response_body = {
          status = "error",
          message = string.format("invalid block size (must be between %d and %d): %d",
                                  2^20 * 512, 2^30 * 5, 1),
        },
      },
      {
        request_body = {
          block_size = 2^30 * 6,
        },
        response_body = {
          status = "error",
          message = string.format("invalid block size (must be between %d and %d): %d",
                                  2^20 * 512, 2^30 * 5, 2^30 * 6),
        },
      },
    }

    for _, request in ipairs(requests) do
      local admin_client = assert(helpers.admin_client())
      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/memory",
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

  it("accept a valid PID", function ()
    local worker_pids = helpers.get_kong_workers()
    local admin_client = assert(helpers.admin_client())

    for _, pid in ipairs(worker_pids) do
      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/memory",
        body = {
          pid = pid,
          timeout = 5,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.res_status(201, res)

      wait_for_tracer_started()

      local path = wait_for_tracer_stopped().path

      helpers.wait_for_file_contents(string.format("%s-0.bin", path), 15)
    end
  end)

  it("check the profiler state before stopping it", function ()
    local admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "DELETE",
      path = "/debug/profiling/memory",
    })

    local body = assert.res_status(400, res)
    local json = cjson.decode(body)

    assert.same({
      status = "error",
      message = "memory tracing is not active",
    }, json)
  end)
end)


end
end
