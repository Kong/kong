local helpers = require "spec.helpers"


describe("invalid config are rejected", function()
  describe("role is admin", function()
    it("can not disable admin_listen", function()
      local ok, err = helpers.start_kong({
        role = "admin",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        admin_listen = "off",
      })

      assert.False(ok)
      assert.matches("Error: admin_listen must be specified when role = \"admin\"", err, nil, true)
    end)

    it("can not disable cluster_listen", function()
      local ok, err = helpers.start_kong({
        role = "admin",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        cluster_listen = "off",
      })

      assert.False(ok)
      assert.matches("Error: cluster_listen must be specified when role = \"admin\"", err, nil, true)
    end)

    it("can not use DB-less mode", function()
      local ok, err = helpers.start_kong({
        role = "admin",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        database = "off",
      })

      assert.False(ok)
      assert.matches("Error: in-memory storage can not be used when role = \"admin\"", err, nil, true)
    end)
  end)

  describe("role is proxy", function()
    it("can not disable proxy_listen", function()
      local ok, err = helpers.start_kong({
        role = "proxy",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        proxy_listen = "off",
      })

      assert.False(ok)
      assert.matches("Error: proxy_listen must be specified when role = \"proxy\"", err, nil, true)
    end)

    it("can not use DB mode", function()
      local ok, err = helpers.start_kong({
        role = "proxy",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
      })

      assert.False(ok)
      assert.matches("Error: only in-memory storage can be used when role = \"proxy\"\n" ..
                     "Hint: set database = off in your kong.conf", err, nil, true)
    end)
  end)

  for _, param in ipairs({ { "admin", "postgres" }, { "proxy", "off" }, }) do
    describe("role is " .. param[1], function()
      it("errors if cluster certificate is not found", function()
        local ok, err = helpers.start_kong({
          role = param[1],
          database = param[2],
          prefix = "servroot2",
        })

        assert.False(ok)
        assert.matches("Error: cluster certificate and key must be provided to use Hybrid mode", err, nil, true)
      end)

      it("errors if cluster certificate key is not found", function()
        local ok, err = helpers.start_kong({
          role = param[1],
          database = param[2],
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
        })

        assert.False(ok)
        assert.matches("Error: cluster certificate and key must be provided to use Hybrid mode", err, nil, true)
      end)
    end)
  end
end)
