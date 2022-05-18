local ssl = require "ngx.ssl"

local pl_file = require "pl.file"

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local KONG_VERSION = require "kong.meta"._VERSION

local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS


local VNEG_ENDPOINT = "/version-handshake"
local SERVER_NAME = "kong_clustering"
local CERT_FNAME = "spec/fixtures/kong_clustering.crt"
local CERT_KEY_FNAME = "spec/fixtures/kong_clustering.key"

local CLIENT_CERT = assert(ssl.parse_pem_cert(assert(pl_file.read(CERT_FNAME))))
local CLIENT_PRIV_KEY = assert(ssl.parse_pem_priv_key(assert(pl_file.read(CERT_KEY_FNAME))))


for _, strategy in helpers.each_strategy() do
  describe("[ #" .. strategy .. " backend]", function()
    describe("connect to endpoint", function()
      local bp, db
      local client_setup = {
        host = "127.0.0.1",
        port = 9005,
        scheme = "https",
        ssl_verify = false,
        ssl_client_cert = CLIENT_CERT,
        ssl_client_priv_key = CLIENT_PRIV_KEY,
        ssl_server_name = SERVER_NAME,
      }

      lazy_setup(function()
        bp, db = helpers.get_db_utils(strategy, {
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

      before_each(function()
        db:truncate("clustering_data_planes")
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
          local client = helpers.http_client(client_setup)
          local res = assert(client:send({ method = req_method, path = VNEG_ENDPOINT }))
          assert.res_status(400, res)
        end)
      end

      it("rejects text body", function()
        local client = helpers.http_client(client_setup)
        local res = assert(client:post(VNEG_ENDPOINT, {
          headers = { ["Content-Type"] = "text/html; charset=UTF-8"},
          body = "stuff",
        }))
        assert.res_status(400, res)
      end)

      it("accepts HTTPS method \"POST\"", function()
        local client = helpers.http_client(client_setup)
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

      it("rejects if there's something weird in the services_requested array", function()
        local client = helpers.http_client(client_setup)
        local res = assert(client:post(VNEG_ENDPOINT, {
          headers = { ["Content-Type"] = "application/json"},
          body = {
            node = {
              id = utils.uuid(),
              type = "KONG",
              version = KONG_VERSION,
              hostname = "localhost",
            },
            services_requested = { "hi" },
          },
        }))
        assert.res_status(400, res)
      end)

      it("rejects if missing fields", function()
        local client = helpers.http_client(client_setup)
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

      it("API shows DP status", function()
        local client = helpers.http_client(client_setup)
        do
          local node_id = utils.uuid()
          local res = assert(client:post(VNEG_ENDPOINT, {
            headers = { ["Content-Type"] = "application/json"},
            body = {
              node = {
                id = node_id,
                type = "KONG",
                version = KONG_VERSION,
                hostname = "localhost",
              },
              services_requested = {
                {
                  name = "Config",
                  versions = { "v0" },
                },
                {
                  name = "infundibulum",
                  versions = { "chronoscolastic", "kitchen" }
                }
              },
            },
          }))

          assert.res_status(200, res)
          local body = assert.response(res).jsonbody()
          assert.is_string(body.node.id)
          assert.same({
            {
              name = "config",
              version = "v0",
              message = "JSON over WebSocket",
            },
          }, body.services_accepted)
          assert.same({
            { name = "infundibulum", message = "unknown service." },
          }, body.services_rejected)
        end

        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          assert.res_status(200, res)
          local body = assert.response(res).jsonbody()

          for _, v in pairs(body.data) do
            if v.ip == "127.0.0.1" then
              assert.near(14 * 86400, v.ttl, 3)
              assert.matches("^(%d+%.%d+)%.%d+", v.version)
              assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)

              return true
            end
          end
        end, 10)
      end)

      it("negotiation client", function()
        -- (re)load client with special set of requested services
        package.loaded["kong.clustering.version_negotiation.services_requested"] = {
          {
            name = "Config",
            versions = { "v0", "v1" },
          },
          {
            name = "infundibulum",
            versions = { "chrono-synclastic", "kitchen" }
          },
        }
        package.loaded["kong.clustering.version_negotiation"] = nil
        local version_negotiation = require "kong.clustering.version_negotiation"

        local conf = {
          cluster_control_plane = "127.0.0.1:9005",
          cluster_mtls = "shared",
        }
        local data = assert(version_negotiation.request_version_handshake(conf, CLIENT_CERT, CLIENT_PRIV_KEY))
        -- returns data in standard form
        assert.same({
          { name = "config", version = "v1", message = "wRPC" },
        }, data.services_accepted)
        assert.same({
          { name = "infundibulum", message = "unknown service." },
        }, data.services_rejected)

        -- stored node-wise as Lua-style values
        -- accepted
        assert.same({ "v1", "wRPC" }, { version_negotiation.get_negotiated_service("Config") })
        -- rejected
        assert.same({ nil, "unknown service." }, { version_negotiation.get_negotiated_service("infundibulum") })
        -- not even requested
        assert.same({}, { version_negotiation.get_negotiated_service("thingamajig") })
      end)

    end)
  end)
end
