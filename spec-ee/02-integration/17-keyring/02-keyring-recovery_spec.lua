-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Keyring [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local db_strategy = strategy ~= "off" and strategy or nil
    local consumer_basicauth_credentials

    local conf = {
      database = db_strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/crypto_cert.pem",
      plugins = "encrypted-field,basic-auth",
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyring_meta",
        "keyring_keys",
        "basicauth_credentials",
      }, { "encrypted-field" })

      local service_a = bp.services:insert {
        name = "service_a",
        protocol = helpers.mock_upstream_protocol,
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      }
      bp.routes:insert {
        paths = { "/a" },
        service = service_a,
      }

      local service_b = bp.services:insert {
        name = "service_b",
        protocol = helpers.mock_upstream_protocol,
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      }
      bp.routes:insert {
        paths = { "/b" },
        service = service_b,
      }

      assert(helpers.start_kong(conf))

      admin_client = helpers.admin_client()

      -- Add Plugins
      local res = assert(admin_client:send {
        method = "POST",
        path = "/services/service_a/plugins",
        body = { name = "encrypted-field", config = { message = "a" } },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(201, res)
      assert.same({ message = "a" }, cjson.decode(body).config)

      local res = assert(admin_client:send {
        method = "POST",
        path = "/services/service_b/plugins",
        body = { name = "encrypted-field", config = { message = "b" } },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(201, res)
      assert.same({ message = "b" }, cjson.decode(body).config)

      -- Add Consumer and basic-auth
      local res = assert(admin_client:send {
        method = "POST",
        path = "/consumers",
        body = { username = "bob" },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, res)

      local res = assert(admin_client:send {
        method = "POST",
        path = "/consumers/bob/basic-auth",
        body = {
          username = "bob",
          password = "supersecretpassword",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(201, res)
      consumer_basicauth_credentials = cjson.decode(body)

      admin_client:close()
      helpers.wait_for_all_config_update()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end
    end)

    describe("Keyring after Kong reloaded", function()
      lazy_setup(function()
        local workers = helpers.get_kong_workers()
        assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path, conf))
        helpers.wait_until_no_common_workers(workers, 1, { timeout = 15, step = 2 })
      end)

      it("Plugin should return decrypted field after Kong reloaded", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/a",
        })
        local body = assert.res_status(200, res)
        assert.same({ message = "a" }, cjson.decode(body))

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/b",
        })
        local body = assert.res_status(200, res)
        assert.same({ message = "b" }, cjson.decode(body))
      end)

      it("Consumer should return decrypted field after Kong reloaded", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
        })
        local body = assert.res_status(200, res)
        assert.equal(consumer_basicauth_credentials.password, cjson.decode(body).password)
      end)
    end)

    describe("Keyring after Kong restarted", function()
      lazy_setup(function()
        assert(helpers.restart_kong(conf))
      end)

      it("Plugin should return encrypted field after Kong restarted", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/a",
        })
        local body = assert.res_status(200, res)
        assert.not_same({ message = "a" }, cjson.decode(body))

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/b",
        })
        local body = assert.res_status(200, res)
        assert.not_same({ message = "b" }, cjson.decode(body))
      end)

      it("Admin API throws error after Kong restarted", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
        })
        local body = assert.res_status(500, res)
        assert.same({ message = "An unexpected error occurred" }, cjson.decode(body))
      end)

      describe("Kerying after importing recovery private key", function()
        lazy_setup(function()
          admin_client = helpers.admin_client()
          local privkey_pem, err = pl_file.read("spec-ee/fixtures/keyring/crypto_key.pem")
          assert.is_nil(err)
          local res = assert(admin_client:send {
            method = "POST",
            path = "/keyring/recover",
            body = {
              ["recovery_private_key"] = privkey_pem,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.recovered)
          admin_client:close()
        end)

        it("Plugin should return decrypted field after importing recovery private key", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/a",
          })
          local body = assert.res_status(200, res)
          assert.same({ message = "a" }, cjson.decode(body))

          local res = assert(proxy_client:send {
            method = "GET",
            path = "/b",
          })
          local body = assert.res_status(200, res)
          assert.same({ message = "b" }, cjson.decode(body))
        end)

        it("Consumer should return decrypted field after importing recovery private key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
          })
          local body = assert.res_status(200, res)
          assert.equal(consumer_basicauth_credentials.password, cjson.decode(body).password)
        end)
      end)
    end)
  end)
end
