local helpers = require "spec.helpers"


local confs = helpers.get_clustering_protocols()
for cluster_protocol, conf in pairs(confs) do
  for _, strategy in helpers.each_strategy() do
    local switched_json = (cluster_protocol == "json (by switch)")
    local is_json = switched_json or (cluster_protocol == "json")
    describe("legacy_hybrid_protocol switch", function()
      lazy_setup(function()
        assert(helpers.start_kong({
          role = "control_plane",
          legacy_hybrid_protocol = switched_json,
          cluster_protocol = cluster_protocol,
          cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
          database = strategy,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = conf,
          -- additional attributes for PKI:
          cluster_mtls = "pki",
          cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          legacy_hybrid_protocol = switched_json,
          cluster_protocol = cluster_protocol,
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/ocsp_certs/kong_data_plane.crt",
          cluster_cert_key = "spec/fixtures/ocsp_certs/kong_data_plane.key",
          cluster_control_plane = "127.0.0.1:9005",
          proxy_listen = "0.0.0.0:9002",
          -- additional attributes for PKI:
          cluster_mtls = "pki",
          cluster_server_name = "kong_clustering",
          cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)

      it("legacy_hybrid_protocol: " ..
        (switched_json and "true" or "false") .. " with " .. strategy .. " backend, protocol " .. cluster_protocol,
        function()
          assert.logfile()[is_json and "has_not" or "has"].line("[wrpc-clustering] ", true)
        end)
    end)
  end
end
