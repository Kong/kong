-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format

describe("Plugin: prometheus (exporter) enterprise licenses", function()
  local admin_client

  setup(function()
    local bp = helpers.get_db_utils()

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus",
    }

    assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
    })
    admin_client = helpers.admin_client()
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  it("exports enterprise licenses", function()

    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)

    assert.matches('kong_enterprise_license_signature %d+', body)
    assert.matches('kong_enterprise_license_expiration %d+', body)
    assert.matches('kong_enterprise_license_features{feature="ee_entity_read"}', body, nil, true)
    assert.matches('kong_enterprise_license_features{feature="ee_entity_write"}', body, nil, true)

    assert.matches('kong_enterprise_license_errors 0', body, nil, true)
    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)


for _, strategy in helpers.each_strategy() do
  describe("Plugin: prometheus (exporter) db entity count #" .. strategy, function()
    local admin_client
    local db

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy)

      bp.plugins:insert {
        name = "prometheus",
      }

      for i = 1, 2 do
        local ws = bp.workspaces:insert()

        local opts = { workspace = ws.id }

        bp.consumers:insert(
          { username = "c-" .. i },
          opts
        )

        for j = 1, 2 do
          local service = bp.services:insert({}, opts)

          bp.routes:insert(
            {
              protocols = { "http" },
              paths     = { fmt("/%s/%s/", i, j) },
              service   = service,
            },
            opts
          )

          db.plugins:insert(
            {
              name = "request-termination",
              service   = { id = service.id },
              config    = { },
            },
            opts
          )
        end
      end

      -- the workspace counter hooks don't get executed in this context, so
      -- we need to explicitly initialize them
      require("kong.workspaces.counters").initialize_counters(db)

      assert(helpers.start_kong({ database = strategy }))
      admin_client = assert(helpers.admin_client())
    end)

    after_each(function()
      db:truncate()

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)


    it("exports db entity count", function()
      local count

      -- entity count metrics are collected periodically via a function that
      -- is kicked off with `ngx.timer.at(0, ...)`, so in most cases they
      -- should be ready for us almost immediately on startup, but there's
      -- always that rare case where they aren't
      helpers.wait_until(function()
        local res = admin_client:get("/metrics")
        local body = assert.res_status(200, res)

        count = body:match("kong_db_entities_total (%d+)")
        count = tonumber(count)

        return count ~= nil
      end, 5, 0.5)

      -- we need also count the prometheus plugin itself
      assert.equals(15, count)
    end)
  end)
end
