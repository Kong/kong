local helpers = require "spec.helpers"

-- Note: remove the below hack when https://github.com/Kong/kong/pull/6952 is merged
local stream_available, _ = pcall(require, "kong.tools.stream_api")

local spec_path = debug.getinfo(1).source:match("@?(.*/)")

local nginx_conf
if stream_available then
  nginx_conf = spec_path .. "/fixtures/prometheus/custom_nginx.template"
else
  nginx_conf = "./spec/fixtures/custom_nginx.template"
end
-- Note ends

local t = pending
local pok = pcall(require, "kong.enterprise_edition.licensing")
if pok then
  t = describe
end

t("Plugin: prometheus (exporter) enterprise licenses", function()
  local admin_client

  setup(function()
    local bp = helpers.get_db_utils()

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus",
    }

    assert(helpers.start_kong {
        nginx_conf = nginx_conf,
        plugins = "bundled, prometheus",
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

    assert.matches('kong_enterprise_license_signature %d+', body, nil, true)
    assert.matches('kong_enterprise_license_expiration %d+', body, nil, true)
    assert.matches('kong_enterprise_license_features{feature="ee_plugins"}', body, nil, true)
    assert.matches('kong_enterprise_license_features{feature="write_admin_api"}', body, nil, true)

    assert.matches('kong_enterprise_license_errors 0', body, nil, true)
    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)
