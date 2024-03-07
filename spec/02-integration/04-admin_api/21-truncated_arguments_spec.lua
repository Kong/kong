-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("Admin API - truncated arguments #" .. strategy, function()
    local max_uri_args_overflow = 1000 + 1
    local max_post_args_overflow = 1000 + 1

    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    it("return 400 if reach maximum post arguments number", function()
      local items = {}
      for i = 1, max_post_args_overflow do
        table.insert(items, "config.allow=" .. i)
      end
      local body = "name=ip-restriction&" .. table.concat(items, "&")
      local res = assert(client:send {
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] =  "application/x-www-form-urlencoded",
        },
        body = body,
      })
      assert.response(res).has.status(400)
      local json = assert.response(res).has.jsonbody()
      assert.same({ message = "Too many arguments" }, json)
    end)

    it("return 400 if reach maximum uri arguments number", function()
      local items = {}
      for i = 1, max_uri_args_overflow do
        table.insert(items, "a=" .. i)
      end
      local querystring = table.concat(items, "&")
      local res = assert(client:send {
        method = "GET",
        path = "/plugins?" .. querystring,
      })
      assert.response(res).has.status(400)
      local json = assert.response(res).has.jsonbody()
      assert.same({ message = "Too many arguments" }, json)
    end)

  end)

end
