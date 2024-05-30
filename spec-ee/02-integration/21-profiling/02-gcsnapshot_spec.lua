-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local mp = require 'MessagePack'
local ltn12 = require 'ltn12'

local DEBUG_LISTEN_HOST = "0.0.0.0"
local DEBUG_LISTEN_PORT = 9200

for _, strategy in helpers.each_strategy() do
for __, deploy in ipairs({ "traditional", "hybrid" }) do

describe("GC snapshot #" .. strategy .. " #" .. deploy, function ()
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

  it("debug_listen is enabled", function ()
    local http_client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(http_client:send {
      method = "GET",
      path = "/debug/profiling/gc-snapshot",
    })

    assert.res_status(200, res)
  end)

  it("snapshot GC", function ()
    local admin_client = assert(helpers.admin_client())

    local res = assert(admin_client:send {
      method = "POST",
      path = "/debug/profiling/gc-snapshot",
    })

    assert.res_status(201, res)

    local path

    helpers.pwait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/debug/profiling/gc-snapshot",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.same("stopped", json.status, "expected status to be 'stopped, got '" .. json.status .. "'")
      assert.truthy(json.path)

      path = json.path
    end, 30) -- CI is very slow for computing task

    helpers.wait_for_file_contents(path, 15)

    local data = ltn12.source.file(io.open(path, 'rb'))
    local has_table = false
    local has_cdata = false
    local iterator = mp.unpacker(data)
    iterator() -- skip the first item, which is the meta data
    --[[
      Just traverse the snapshot and check if the encoding protocol is right.
      At the same time, check if there are both tables and cdata in the snapshot.
    --]]
    for _, v in iterator do
      if v.type == "table" then
        has_table = true
      end

      if v.type == "cdata" then
        has_cdata = true
      end
    end

    assert(has_table and has_cdata, "expected to find both tables and cdata in the snapshot")
  end)

  it("accept a valid PID", function ()
    local worker_pids = helpers.get_kong_workers()
    local admin_client = assert(helpers.admin_client())

    for _, pid in ipairs(worker_pids) do
      local res = assert(admin_client:send {
        method = "POST",
        path = "/debug/profiling/gc-snapshot",
        body = {
          pid = pid,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.same(json.message, "Dumping snapshot in progress on pid: " .. pid, "gc-snapshot is not on specified pid")

      helpers.pwait_until(function()
        res = assert(admin_client:send {
          method = "GET",
          path = "/debug/profiling/gc-snapshot",
          body = {
            pid = pid,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same("stopped", json.status)
        assert.equals(pid, json.pid)
        assert.truthy(json.path)
      end, 30) -- CI is very slow for computing task
    end
  end)

end)


end
end
