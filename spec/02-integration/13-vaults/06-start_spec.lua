-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers" -- initializes 'kong' global for vaults


for _, strategy in helpers.each_strategy() do
for _, vault in ipairs({"env", "aws", "hcv"}) do
  describe("Vault #" .. vault .. " [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "plugins",
      })

      bp.plugins:insert {
        name    = "rate-limiting",
        config  = {
          day = 5,
          redis_password = "{vault://" .. vault .. "/redis/password}"
        },
      }
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("Starts Kong successfully when plugins use references", function()
      assert(helpers.start_kong({
        database   = strategy,
        vaults     = vault,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      -- This warning is expected, here we test the https://konghq.atlassian.net/browse/FT-3184:
      assert.logfile().has.line("unable to resolve reference {vault://" .. vault .. "/redis/password}", true)
    end)
  end)
end
end
