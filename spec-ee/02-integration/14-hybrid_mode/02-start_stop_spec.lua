local helpers = require "spec.helpers"


describe("invalid config are rejected", function()
  describe("role is control_plane", function()
    it("can not disable cluster_telemetry_listen", function()
      local ok, err = helpers.start_kong({
        role = "control_plane",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_telemetry_listen = "off",
      })

      assert.False(ok)
      assert.matches("Error: cluster_telemetry_listen must be specified when role = \"control_plane\"", err, nil, true)
    end)

  end)

end)
