-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Keyring [#" .. strategy .. "]", function()
    local proxy_client, proxy_client2
    local admin_client, admin_client2
    local db_strategy = strategy ~= "off" and strategy or nil
    local consumer_basicauth_credentials

    local conf = {
      database = db_strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      plugins = "encrypted-field,basic-auth",
      prefix = "node1",
      db_update_frequency = 1,
    }

    local conf2 = {
      database = db_strategy,
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      plugins = "encrypted-field,basic-auth",
      prefix = "node2",
      proxy_listen = "0.0.0.0:9100",
      admin_listen = "127.0.0.1:9101",
      admin_gui_listen = "127.0.0.1:9109",
      db_update_frequency = 1,
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
      assert(helpers.start_kong(conf2))
    end)

    lazy_teardown(function() 
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong("node1")
      helpers.stop_kong("node2")
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
        proxy_client = nil
      end
      if admin_client then
        admin_client:close()
        admin_client = nil
      end
    end)

    describe("Admin API", function()
      before_each(function()
        proxy_client2 = helpers.proxy_client(nil, 9100)
        admin_client2 = helpers.admin_client(nil, 9101)
      end)

      it("Add Plugins", function()
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
      end)

      it("Add Consumer and basic-auth", function()
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
      end)

      it("Make sure both nodes get the keyring material and can decrypt the fields", function()
        helpers.pwait_until(function ()
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

          local res = assert(admin_client:send {
            method = "GET",
            path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
          })
          local body = assert.res_status(200, res)
          assert.equal(consumer_basicauth_credentials.password, cjson.decode(body).password)

          local res = assert(proxy_client2:send {
            method = "GET",
            path = "/a",
          })
          local body = assert.res_status(200, res)
          assert.same({ message = "a" }, cjson.decode(body))

          local res = assert(proxy_client2:send {
            method = "GET",
            path = "/b",
          })
          local body = assert.res_status(200, res)
          assert.same({ message = "b" }, cjson.decode(body))

          local res = assert(admin_client2:send {
            method = "GET",
            path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
          })
          local body = assert.res_status(200, res)
          assert.equal(consumer_basicauth_credentials.password, cjson.decode(body).password)
        end, 30)
      end)
    end)

    describe("Keyring after Kong node restarted", function()
      lazy_setup(function()
        helpers.clean_logfile("node1/logs/error.log")

        assert(helpers.restart_kong(conf))

        helpers.pwait_until(function ()
          -- wait for the node to start
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/a",
          })
          assert.res_status(200, res)
          proxy_client:close()
          proxy_client = nil

          -- wait for the keyring material
          assert.logfile("node1/logs/error.log").has.line("[keyring cluster] requesting key IDs", true)
          assert.logfile("node1/logs/error.log").has.line("[cluster_events] new event (channel: 'keyring_broadcast')", true)
          assert.logfile("node1/logs/error.log").has.line("[keyring] activating key", true)
        end, 60)
      end)

      it("Plugin should return decrypted field after Kong Node restarted", function()
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

      it("Consumer should return decrypted field after Kong Node restarted", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. consumer_basicauth_credentials.id,
        })
        local body = assert.res_status(200, res)
        assert.equal(consumer_basicauth_credentials.password, cjson.decode(body).password)
      end)
    end)
  end)
end
