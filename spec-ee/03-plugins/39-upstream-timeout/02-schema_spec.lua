-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local PLUGIN_NAME = "upstream-timeout"

for _, strategy in strategies() do
  describe("Plugin API config validator (#" .. strategy .. ")", function()
    local admin_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      helpers.get_db_utils(db_strategy, {
        "plugins"
      }, { PLUGIN_NAME })

      assert(helpers.start_kong {
        database = db_strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, upstream-timeout"
      })

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    local function make_request(client, conf)
      return (client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = PLUGIN_NAME,
          config = conf,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
    end

    it("fails when timeout conf is not a positive integer", function()
      local res = assert(make_request(admin_client, { read_timeout = "invalid_string_type" }))

      local body = assert.response(res).has.status(400)
      local json = cjson.decode(body)
      assert.same(json.name, "schema violation")

      res = assert(make_request(admin_client, { read_timeout = -2342 }))
      assert.response(res).has.status(400)
      assert.same(json.name, "schema violation")
    end)

    it("succeeds if positive integer", function()
      local res = assert(make_request(admin_client, { read_timeout = 500 }))
      local body = assert.response(res).has.status(201)
      local json = cjson.decode(body)
      assert.same(json.config.read_timeout, 500)
    end)

  end)
end
