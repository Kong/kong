-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: prometheus (API)",function()
  local admin_client

  describe("with no 'prometheus_metrics' shm defined", function()
    setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        plugins = "bundled, prometheus",
      }))

      admin_client = helpers.admin_client()
    end)
    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    -- skipping since Kong always injected a `prometheus_metrics` shm when
    -- prometheus plugin is loaded into memory
    pending("prometheus plugin cannot be configured", function()
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/plugins",
        body    = {
          name  = "prometheus"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal(json.config, "ngx shared dict 'prometheus_metrics' not found")
    end)
  end)

  describe("with 'prometheus_metrics' defined", function()
    setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        plugins = "bundled, prometheus",
      }))

      admin_client = helpers.admin_client()
    end)
    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    it("prometheus plugin can be configured", function()
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/plugins",
        body    = {
          name  = "prometheus"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)
    end)
  end)
end)
