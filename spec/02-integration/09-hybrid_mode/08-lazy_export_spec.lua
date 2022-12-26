local helpers = require "spec.helpers"

local admin_client

local function cp(strategy)
  helpers.get_db_utils(strategy) -- make sure the DB is fresh n' clean
  assert(helpers.start_kong({
    role = "control_plane",
    cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
    database = strategy,
    cluster_listen = "127.0.0.1:9005",
    nginx_conf = "spec/fixtures/custom_nginx.template",
    -- additional attributes for PKI:
    cluster_mtls = "pki",
    cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
  }))
  admin_client = assert(helpers.admin_client())
end

local n = 0
local function touch_config()
  n = n + 1
  assert(admin_client:send({
    method = "POST",
    path = "/services",
    body = {
      name = "test" .. n,
      host = "localhost",
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  }))
end

local function json_dp()
  assert(helpers.start_kong({
    role = "data_plane",
    database = "off",
    prefix = "dp1",
    cluster_cert = "spec/fixtures/ocsp_certs/kong_data_plane.crt",
    cluster_cert_key = "spec/fixtures/ocsp_certs/kong_data_plane.key",
    cluster_control_plane = "127.0.0.1:9005",
    proxy_listen = "0.0.0.0:9002",
    -- additional attributes for PKI:
    cluster_mtls = "pki",
    cluster_server_name = "kong_clustering",
    cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
  }))
end


for _, strategy in helpers.each_strategy() do

describe("lazy_export with #".. strategy, function()
  describe("no DP", function ()
    setup(function()
      cp(strategy)
    end)
    teardown(function ()
      helpers.stop_kong()
    end)
    it("test", function ()
      touch_config()
      assert.logfile().has.line("[clustering] skipping config push (no connected clients)", true)
    end)
  end)

  describe("only json DP", function()
    setup(function()
      cp(strategy)
      json_dp()
    end)
    teardown(function ()
      helpers.stop_kong("dp1")
      helpers.stop_kong()
    end)

    it("test", function ()
      touch_config()
      assert.logfile().has.line("[clustering] exporting config", true)
      assert.logfile().has.line("[clustering] config pushed to 1 data-plane nodes", true)
    end)
  end)

end)

end
