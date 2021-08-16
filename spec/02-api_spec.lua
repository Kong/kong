-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("jq API", function()
  local admin_client, bp

  setup(function()
    bp = helpers.get_db_utils(nil, nil, { "jq" })

    assert(bp.routes:insert {
      name  = "test",
      hosts = { "test1.com" },
    })

    assert(helpers.start_kong({
      plugins = "jq",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong(nil, true)
  end)

  describe("POST", function()
    it("errors with empty config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "jq",
          config = {},
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("required field missing", body.fields.config.filters)
    end)

    it("accepts minimal config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "jq",
          config = {
            filters = {
              {
                program = ".",
              },
            },
          },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)
    end)
  end)
end)

