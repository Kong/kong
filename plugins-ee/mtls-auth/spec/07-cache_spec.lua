-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson   = require "cjson"
local fmt     = string.format
local http_mock = require "spec.helpers.http_mock"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local CA1 = pl_file.read(helpers.get_fixtures_path() .. "/ca1.crt")
local CA2 = pl_file.read(helpers.get_fixtures_path() .. "/ca2.crt")
local Other_CA = pl_file.read("./spec/fixtures/mtls_certs/ca.crt")

local HTTP_SERVER_PORT = helpers.get_available_port()

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (cache) [#" .. strategy .. "]", function()
    local mtls_client
    local bp, db
    local service, route
    local ca_cert1, ca_cert2
    local consumer1, consumer2
    local credential1, credential2
    local db_strategy = strategy ~= "off" and strategy or nil
    local mock
    local admin_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "mtls_auth_credentials",
      }, { "mtls-auth", })

      ca_cert1 = assert(db.ca_certificates:insert({
        cert = CA1,
      }))

      ca_cert2 = assert(db.ca_certificates:insert({
        cert = CA2,
      }))

      consumer1 = bp.consumers:insert {
        username = "kongclient1"
      }

      consumer2 = bp.consumers:insert {
        username = "kongclient2"
      }

      credential1 = assert(db.mtls_auth_credentials:insert {
        consumer = { id = consumer1.id },
        subject_name = "kongclient",
        ca_certificate = { id = ca_cert1.id },
      })

      credential2 = assert(db.mtls_auth_credentials:insert {
        consumer = { id = consumer2.id },
        subject_name = "kongclient",
        ca_certificate = { id = ca_cert2.id },
      })

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      route = bp.routes:insert {
        hosts   = { "example.com" },
        service = { id = service.id, },
      }

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route.id },
        config = {
          ca_certificates = { ca_cert1.id, ca_cert2.id},
          revocation_check_mode = "SKIP",
        },
      })

      local format = [[
      proxy_ssl_certificate ]] .. helpers.get_fixtures_path() .. [[/%s.crt;
      proxy_ssl_certificate_key ]] .. helpers.get_fixtures_path() .. [[/%s.key;
      proxy_ssl_name example.com;
      proxy_ssl_server_name on;
      proxy_set_header Host example.com;
      proxy_pass https://127.0.0.1:9443/get;
      ]]
      -- client1 and client2 have the same CN but are issued by different CAs
      mock = http_mock.new(HTTP_SERVER_PORT, {
        ["/client1"] = {
          directives = fmt(format, "client1", "client1"),
        },
        ["/client2"] = {
          directives = fmt(format, "client2", "client2"),
        },
      }, {
        hostname = "mtls_test_client",
      })
      assert(mock:start())

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    before_each(function()
      admin_client = assert(helpers.admin_client())
      mtls_client = assert(mock:get_client())
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end

      if mtls_client then
        mtls_client:close()
      end
      mock.client = nil
    end)

    it("match the correct consumer via credential", function()
      local res = assert(mtls_client:send {
        method  = "GET",
        path    = "/client1",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("kongclient1", json.headers["x-consumer-username"])
      assert.equal(consumer1.id, json.headers["x-consumer-id"])

      local res = assert(mtls_client:send {
        method  = "GET",
        path    = "/client2",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("kongclient2", json.headers["x-consumer-username"])
      assert.equal(consumer2.id, json.headers["x-consumer-id"])
    end)

    it("still match the correct consumer via credential after the CAs updated", function()
      -- switch the ca certificates so that
      -- ca_cert1.id binds to CA2, ca_cert2.id binds to CA1
      -- We first update it to Other_CA to avoid unique field violation as the `cert_digest`
      -- field of `ca_certificates` is a unique field. Thus we use Other_CA as a transition.
      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert1.id,
        body    = {
          cert = Other_CA,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert2.id,
        body    = {
          cert = CA1,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      local res = assert(admin_client:send({
        method  = "PATCH",
        path    = "/ca_certificates/" .. ca_cert1.id,
        body    = {
          cert = CA2,
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      }))
      assert.res_status(200, res)

      -- need update the credentials as well after updating the ca certificates
      local res = assert(admin_client:send {
        method  = "DELETE",
        path    = "/consumers/kongclient1/mtls-auth/" .. credential1.id,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(204, res)

      local res = assert(admin_client:send {
        method  = "DELETE",
        path    = "/consumers/kongclient2/mtls-auth/" .. credential2.id,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(204, res)

      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/consumers/kongclient1/mtls-auth/",
        body    = {
          id = credential1.id,
          subject_name = "kongclient",
          ca_certificate = { id = ca_cert2.id },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)

      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/consumers/kongclient2/mtls-auth/",
        body    = {
          id = credential2.id,
          subject_name = "kongclient",
          ca_certificate = { id = ca_cert1.id },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, res)

      -- switch back
      finally(function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert1.id,
          body    = {
            cert = Other_CA,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert2.id,
          body    = {
            cert = CA2,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/ca_certificates/" .. ca_cert1.id,
          body    = {
            cert = CA1,
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        }))
        assert.res_status(200, res)

        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/kongclient1/mtls-auth/" .. credential1.id,
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/kongclient2/mtls-auth/" .. credential2.id,
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers/kongclient1/mtls-auth/",
          body    = {
            id = credential1.id,
            subject_name = "kongclient",
            ca_certificate = { id = ca_cert1.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers/kongclient2/mtls-auth/",
          body    = {
            id = credential2.id,
            subject_name = "kongclient",
            ca_certificate = { id = ca_cert2.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)
      end)

      assert.eventually(function()
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/client1",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("kongclient1", json.headers["x-consumer-username"])
        assert.equal(consumer1.id, json.headers["x-consumer-id"])

        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/client2",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("kongclient2", json.headers["x-consumer-username"])
        assert.equal(consumer2.id, json.headers["x-consumer-id"])
      end).with_timeout(3)
          .has_no_error("match the correct consumer")
    end)
  end)
end
