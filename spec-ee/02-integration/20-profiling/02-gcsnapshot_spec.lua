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

describe("GC snapshot #" .. strategy, function ()
  lazy_setup(function()
    helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
    }))
  end)

  lazy_teardown(function()
      assert(helpers.stop_kong())
  end)

  it("debug_listen is enabled", function ()
    local http_client = assert(helpers.http_client("localhost", DEBUG_LISTEN_PORT))

    local res = assert(http_client:send {
      method = "GET",
      path = "/debug/profiling/cpu",
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
    --[[
      Just traverse the snapshot and check if the encoding protocol is right.
      At the same time, check if there are both tables and cdata in the snapshot.
    --]]
    for _, v in mp.unpacker(data) do
      if v.type == "table" then
        has_table = true
      end

      if v.type == "cdata" then
        has_cdata = true
      end
    end

    assert(has_table and has_cdata, "expected to find both tables and cdata in the snapshot")
  end)

end)


end