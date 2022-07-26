local helpers = require "spec.helpers"
local ssl = require "ngx.ssl"
local http = require "resty.http"
local read_file = require("pl.file").read

local function new_conf(extra)
  local t = {
    cluster_cert          = "spec/fixtures/ocsp_certs/kong_data_plane.crt",
    cluster_cert_key      = "spec/fixtures/ocsp_certs/kong_data_plane.key",
    cluster_mtls          = "pki",
    cluster_listen        = "127.0.0.1:9005",
    cluster_control_plane = "127.0.0.1:9005",
    cluster_ca_cert       = "spec/fixtures/ocsp_certs/ca.crt",
    cluster_server_name   = "kong_clustering",

    nginx_conf = "spec/fixtures/custom_nginx.template",
  }

  for k, v in pairs(extra or {}) do
    t[k] = v
  end

  return t
end

local dp_cert, dp_key
do
  local conf = new_conf()
  dp_cert = assert(ssl.parse_pem_cert(assert(read_file(conf.cluster_cert))))
  dp_key = assert(ssl.parse_pem_priv_key(assert(read_file(conf.cluster_cert_key))))
end

for _, proto in ipairs({ "json", "wrpc" }) do

  for _, strategy in helpers.each_strategy() do

    local is_legacy = proto == "json"
    local exp_status = is_legacy and 404 or 200
    local enabled = is_legacy and "enabled" or "disabled"

    describe("legacy_hybrid_protocol (" .. enabled .. ")", function()
      lazy_setup(function()
        assert(helpers.start_kong(new_conf({
          role = "control_plane",
          database = strategy,

          legacy_hybrid_protocol = is_legacy,
          cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
        })))

        assert(helpers.start_kong(new_conf({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",

          legacy_hybrid_protocol = is_legacy,
          proxy_listen = "0.0.0.0:9002",
        })))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2", true)
        helpers.stop_kong(nil, true)
      end)

      it("data-plane nodes connect using the correct endpoint/protocol", function()
        if is_legacy then
          -- ensure that the data-plane has connected _before_ asserting that
          -- no `[wrpc-clustering]` log line exists
          assert.logfile().has_line("[clustering] data plane connected", true)
          assert.logfile().has_no_line("[wrpc-clustering] ", true)
        else
          assert.logfile().has_line("[wrpc-clustering] ", true)
        end
      end)

      it("wRPC endpoint returns HTTP " .. tostring(exp_status), function()
        local conf = new_conf()

        local httpc = assert(http.new())

        assert.not_nil(httpc:connect({
          host = conf.cluster_control_plane:match("[^:]+"),
          port = conf.cluster_control_plane:match("[0-9]+$"),
          scheme = "https",
          ssl_client_cert = dp_cert,
          ssl_client_priv_key = dp_key,
          ssl_verify = false,
        }))

        finally(function() http:close() end)

        local res, err = httpc:request({
          path = "/v1/wrpc",
          method = "HEAD",
        })

        assert.not_nil(res, err)
        assert.res_status(exp_status, res)
      end)
    end)
  end
end
