-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.all_strategies() do
  describe("Status API - with strategy #" .. strategy, function()
    it("default enable", function()
      assert.truthy(helpers.kong_exec("start -c spec/fixtures/default_status_listen.conf"))
      local client = helpers.http_client("127.0.0.1", 8007, 20000)
      finally(function()
        helpers.stop_kong()
        client:close()
      end)

      local res = assert(client:send {
        method = "GET",
        path = "/status",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.server)

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
    end)
  end)
end
