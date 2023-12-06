-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Admin API - Portal GUI intergrate with KM #" .. strategy, function()
    local client

    describe("responds CORS headers when admin_gui_url configured", function()
      local admin_gui_url = "http://manager.konghq.test"

      lazy_setup(function()
        helpers.start_kong({
          database = strategy,
          admin_gui_url = admin_gui_url,
          admin_gui_auth = "basic-auth",
          admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
          enforce_rbac = "on",
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        client = assert(helpers.admin_client())
      end)

      after_each(function()
        if client then client:close() end
      end)

      it("returns 404 bypass CORS plugin preflight with OPTIONS method", function()
        -- have no `Origin` and `Access-Control-Request-Method` header sent
        local res = assert(client:send {
          method = "OPTIONS",
          path = "/",
          headers = {
            ["Kong-Request-Type"] = "editor",
          },
        })

        assert.res_status(404, res)
      end)

      it("returns 200 and ACAO|ACAC|ACAM|vary CORS headers with OPTIONS method", function()
        local res = assert(client:send {
          method = "OPTIONS",
          path = "/",
          headers = {
            ["Kong-Request-Type"] = "editor",
            ["Access-Control-Request-Method"] = "GET",
            Origin = admin_gui_url,
          },
        })

        assert.res_status(200, res)
        assert.equal("GET,PUT,PATCH,DELETE,POST", res.headers["Access-Control-Allow-Methods"])
        assert.equal(admin_gui_url, res.headers["Access-Control-Allow-Origin"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["vary"])
      end)

      it("returns 404 and ACAO|ACAC|vary CORS headers with GET method", function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Kong-Request-Type"] = "editor",
            Origin = admin_gui_url,
          },
        })

        assert.res_status(404, res)
        assert.equal(admin_gui_url, res.headers["Access-Control-Allow-Origin"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["vary"])
      end)
    end)
  end)
end
