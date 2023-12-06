-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do

describe("jq API #" .. strategy, function()
  local admin_client, bp

  lazy_setup(function()
    bp = helpers.get_db_utils(strategy, nil, { "jq" })

    assert(bp.routes:insert {
      name  = "test",
      hosts = { "test1.test" },
    })

    assert(helpers.start_kong({
      database   = strategy,
      plugins = "jq",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
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
      assert.same("at least one of these fields must be non-empty: 'request_jq_program', 'response_jq_program'", body.fields.config["@entity"][1])
    end)

    it("accepts minimal config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "jq",
          config = {
            request_jq_program = ".[0]",
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

end

