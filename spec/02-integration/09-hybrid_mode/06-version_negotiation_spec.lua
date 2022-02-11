local ssl = require "ngx.ssl"

local pl_file = require "pl.file"

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local KONG_VERSION = require "kong.meta"._VERSION

local VNEG_ENDPOINT = "/version-handshake"
local SERVER_NAME = "kong_clustering"
local CERT_FNAME = "spec/fixtures/kong_clustering.crt"
local CERT_KEY_FNAME = "spec/fixtures/kong_clustering.key"

local CLIENT_CERT = assert(ssl.parse_pem_cert(assert(pl_file.read(CERT_FNAME))))
local CLIENT_PRIV_KEY = assert(ssl.parse_pem_priv_key(assert(pl_file.read(CERT_KEY_FNAME))))


for _, strategy in helpers.each_strategy() do
  describe("[ #" .. strategy .. " backend]", function()
    describe("connect to endpoint", function()
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "upstreams",
          "targets",
          "certificates",
          "clustering_data_planes",
        }) -- runs migrations

        bp.plugins:insert {
          name = "key-auth",
        }

        assert(helpers.start_kong({
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          database = strategy,
          db_update_frequency = 3,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          cluster_version_check = "major_minor",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)


      it("rejects plaintext request", function()
        local client = helpers.http_client{
          host = "127.0.0.1",
          port = 9005,
          scheme = "http",
        }
        local res = assert(client:post(VNEG_ENDPOINT))
        assert.res_status(400, res)
      end)

      for _, req_method in ipairs{"GET", "HEAD", "PUT", "DELETE", "PATCH"} do
        it(string.format("rejects HTTPS method %q", req_method), function()
          local client = helpers.http_client{
            host = "127.0.0.1",
            port = 9005,
            scheme = "https",
            ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
            client_cert = CLIENT_CERT,
            client_priv_key = CLIENT_PRIV_KEY,
            server_name = SERVER_NAME,
          }
          local res = assert(client:send({ method = req_method, path = VNEG_ENDPOINT }))
          --assert(res.status >= 400 and res.status < 500)
          assert.res_status(403, res)
        end)
      end

      it("rejects text body", function()
        local client = helpers.http_client{
          host = "127.0.0.1",
          port = 9005,
          scheme = "https",
          ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
          client_cert = CLIENT_CERT,
          client_priv_key = CLIENT_PRIV_KEY,
          server_name = SERVER_NAME,
        }
        local res = assert(client:post(VNEG_ENDPOINT, {
          headers = { ["Content-Type"] = "text/html; charset=UTF-8"},
          body = "stuff",
        }))
        assert.res_status(400, res)
      end)

      it("accepts HTTPS method \"POST\"", function()
        local client = helpers.http_client{
          host = "127.0.0.1",
          port = 9005,
          scheme = "https",
          ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
          client_cert = CLIENT_CERT,
          client_priv_key = CLIENT_PRIV_KEY,
          server_name = SERVER_NAME,
        }
        local res = assert(client:post(VNEG_ENDPOINT, {
          headers = { ["Content-Type"] = "application/json"},
          body = {
            node = {
              id = utils.uuid(),
              type = "KONG",
              version = KONG_VERSION,
              hostname = "localhost",
            },
            services_requested = {},
          },
        }))
        assert.res_status(200, res)
        assert.response(res).jsonbody()

      end)

      it("rejects if missing fields", function()
        local client = helpers.http_client{
          host = "127.0.0.1",
          port = 9005,
          scheme = "https",
          ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
          client_cert = CLIENT_CERT,
          client_priv_key = CLIENT_PRIV_KEY,
          server_name = SERVER_NAME,
        }
        local res = assert(client:post(VNEG_ENDPOINT, {
          headers = { ["Content-Type"] = "application/json"},
          body = {
            node = {
              id = utils.uuid(),
              version = KONG_VERSION,
              hostname = "localhost",
            },
            services_requested = {},
          },
        }))
        assert.res_status(400, res)
        local body = assert.response(res).jsonbody()
        assert.is_string(body.message)
      end)

    end)
  end)
end
