-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_path = require "pl.path"

local PLUGIN_NAME = "mocking"

local fixture_path
do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function()
  end)
  fixture_path = info.source
  if fixture_path:sub(1, 1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/fixtures/"
end

local function read_fixture(filename)
  local content = assert(helpers.utils.readfile(fixture_path .. filename))
  return content
end


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, { PLUGIN_NAME })

      local service1 = assert(bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      })

      local route1 = assert(db.routes:insert({
        hosts = { "petstore1.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_specification = read_fixture("path-match-oas.yaml"),
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    it("Encoded path parameter", function()
      local res = assert(client:send {
        method = "GET",
        path = "/user/你好",
        headers = {
          host = "petstore1.test",
        },
      })
      assert.response(res).has.status(200)

      local res = assert(client:send {
        method = "GET",
        path = "/user/%E4%BD%A0%E5%A5%BD",
        headers = {
          host = "petstore1.test",
        },
      })
      assert.response(res).has.status(200)

      local res = assert(client:send {
        method = "GET",
        path = "/user/%E4%BD%A0%E5%A5%BD/report.世界",
        headers = {
          host = "petstore1.test",
        },
      })
      assert.response(res).has.status(201)

      local res = assert(client:send {
        method = "GET",
        path = "/user/%E4%BD%A0%E5%A5%BD/report.%E4%B8%96%E7%95%8C",
        headers = {
          host = "petstore1.test",
        },
      })
      assert.response(res).has.status(201)
    end)

  end)
end
