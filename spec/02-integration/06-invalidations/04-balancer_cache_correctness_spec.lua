-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local POLL_INTERVAL = 0.3

for _, strategy in helpers.each_strategy() do
  describe("balancer cache [#" .. strategy .. "]", function()

    lazy_setup(function()
      -- truncate the database so we have zero upstreams
      helpers.get_db_utils(strategy, { "upstreams", })

      assert(helpers.start_kong {
        log_level             = "debug",
        database              = strategy,
        proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
        admin_listen          = "0.0.0.0:8001",
        db_update_frequency   = POLL_INTERVAL,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)


    -- https://github.com/Kong/kong/issues/8970
    it("upstreams won't reload at unusual rate", function()
      assert.logfile().has.line("loading upstreams dict into memory", true, 5)
      -- turncate log
      io.open("./servroot/logs/error.log", "w"):close()
      assert.logfile().has.no.line("loading upstreams dict into memory", true, 20)
    end)
  end)
end
