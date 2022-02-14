-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("/certificates with DB: #" .. strategy, function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "certificates",
        "vaults_beta",
      })

      assert(helpers.start_kong {
        database = strategy,
        vaults = "env",
      })

      client = assert(helpers.admin_client(10000))

      local res = client:put("/vaults-beta/test-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "env",
        },
      })

      assert.res_status(200, res)
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("create certificates with cert and key as secret", function()
      finally(function()
        helpers.unsetenv("CERT")
        helpers.unsetenv("KEY")
      end)
      helpers.setenv("CERT", ssl_fixtures.cert)
      helpers.setenv("KEY", ssl_fixtures.key)
      local res, err  = client:post("/certificates", {
        body    = {
          cert  = "{vault://test-vault/cert}",
          key   = "{vault://test-vault/key}",
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.is_nil(err)
      local body = assert.res_status(201, res)
      local certificate = cjson.decode(body)
      assert.not_nil(certificate.key)
      assert.not_nil(certificate.cert)
    end)
  end)
end
