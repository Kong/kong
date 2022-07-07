local helpers = require "spec.helpers"


local confs = helpers.get_clustering_protocols()
describe("legacy_hybrid_protocol switch", function()
  for cluster_protocol, conf in pairs(confs) do
    for _, strategy in helpers.each_strategy() do
      local is_not_wrpc = (cluster_protocol == "json (by switch)")
      it("legacy_hybrid_protocol: " .. is_not_wrpc .. " with " .. strategy .. " backend, protocol " .. cluster_protocol, function()
        assert(helpers.start_kong({
          role = "control_plane",
          cluster_protocol = cluster_protocol,
          cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
          cluster_ocsp = "on",
          db_update_frequency = 0.1,
          database = strategy,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = conf,
          -- additional attributes for PKI:
          cluster_mtls = "pki",
          cluster_ca_cert = "spec/fixtures/ocsp_certs/ca.crt",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          legacy_hybrid_protocol = is_not_wrpc,
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

        local perfix = is_not_wrpc and "[clustering] " or "[wrpc-clustering] "

        assert.logfile().has.line(perfix, true)


        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)
    end
  end
end)
