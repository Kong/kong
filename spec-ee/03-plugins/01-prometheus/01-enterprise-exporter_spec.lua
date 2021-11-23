-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

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
    assert.matches('kong_enterprise_license_features{feature="ee_plugins"}', body, nil, true)
    assert.matches('kong_enterprise_license_features{feature="write_admin_api"}', body, nil, true)

    assert.matches('kong_enterprise_license_errors 0', body, nil, true)
    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)
