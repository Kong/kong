local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


describe("CP/DP conf check", function()
  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
    }) -- runs migrations
  end)

  describe("role = admin", function()
    it("admin listen not be disabled", function()
      local ok, err = helpers.start_kong({
        role = "admin",
        admin_listen = "off",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        storage = strategy,
      })

      assert.falsy(ok)
      print(err)
    end)
  end)
end)
