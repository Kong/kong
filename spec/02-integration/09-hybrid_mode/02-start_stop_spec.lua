local helpers = require "spec.helpers"


for _, cluster_protocol in ipairs{"json", "wrpc"} do
  describe("invalid config are rejected, protocol " .. cluster_protocol, function()
    describe("role is control_plane", function()
      it("can not disable admin_listen", function()
        local ok, err = helpers.start_kong({
          role = "control_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          admin_listen = "off",
        })

        assert.False(ok)
        assert.matches("Error: admin_listen must be specified when role = \"control_plane\"", err, nil, true)
      end)

      it("can not disable cluster_listen", function()
        local ok, err = helpers.start_kong({
          role = "control_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          cluster_listen = "off",
        })

        assert.False(ok)
        assert.matches("Error: cluster_listen must be specified when role = \"control_plane\"", err, nil, true)
      end)

      it("can not use DB-less mode", function()
        local ok, err = helpers.start_kong({
          role = "control_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          database = "off",
        })

        assert.False(ok)
        assert.matches("Error: in-memory storage can not be used when role = \"control_plane\"", err, nil, true)
      end)

      it("must define cluster_ca_cert", function()
        local ok, err = helpers.start_kong({
          role = "control_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          cluster_mtls = "pki",
        })

        assert.False(ok)
        assert.matches("Error: cluster_ca_cert must be specified when cluster_mtls = \"pki\"", err, nil, true)
      end)
    end)

    describe("role is proxy", function()
      it("can not disable proxy_listen", function()
        local ok, err = helpers.start_kong({
          role = "data_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          proxy_listen = "off",
        })

        assert.False(ok)
        assert.matches("Error: proxy_listen must be specified when role = \"data_plane\"", err, nil, true)
      end)

      it("can not use DB mode", function()
        local ok, err = helpers.start_kong({
          role = "data_plane",
          cluster_protocol = cluster_protocol,
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
        })

        assert.False(ok)
        assert.matches("Error: only in-memory storage can be used when role = \"data_plane\"\n" ..
          "Hint: set database = off in your kong.conf", err, nil, true)
      end)
    end)

    for _, param in ipairs({ { "control_plane", "postgres" }, { "data_plane", "off" }, }) do
      describe("role is " .. param[1], function()
        it("errors if cluster certificate is not found", function()
          local ok, err = helpers.start_kong({
            role = param[1],
            cluster_protocol = cluster_protocol,
            database = param[2],
            prefix = "servroot2",
          })

          assert.False(ok)
          assert.matches("Error: cluster certificate and key must be provided to use Hybrid mode", err, nil, true)
        end)

        it("errors if cluster certificate key is not found", function()
          local ok, err = helpers.start_kong({
            role = param[1],
            cluster_protocol = cluster_protocol,
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
end
