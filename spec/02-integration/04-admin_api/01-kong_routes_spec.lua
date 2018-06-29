local helpers = require "spec.helpers"
local cjson = require "cjson"

local DAOFactory = require "kong.dao.factory"

local dao_helpers = require "spec.02-integration.03-dao.helpers"

local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

describe("Admin API - Kong routes", function()
  describe("/", function()
    local meta = require "kong.meta"
    local client

    setup(function()
      assert(helpers.dao:run_migrations())
      assert(helpers.start_kong {
        pg_password = "hide_me"
      })
      client = helpers.admin_client(10000)
    end)

    teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("returns Kong's version number and tagline", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(meta._VERSION, json.version)
      assert.equal("Welcome to kong", json.tagline)
    end)
    it("returns a UUID as the node_id", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.matches(UUID_PATTERN, json.node_id)
    end)
    it("response has the correct Server header", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      assert.res_status(200, res)
      assert.equal(string.format("%s/%s", meta._NAME, meta._VERSION), res.headers.server)
      assert.is_nil(res.headers.via) -- Via is only set for proxied requests
    end)
    it("returns 405 on invalid method", function()
      local methods = {"POST", "PUT", "DELETE", "PATCH", "GEEEET"}
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)
    it("exposes the node's configuration", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.configuration)
    end)
    it("enabled_in_cluster property is an array", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      assert.matches('"enabled_in_cluster":[', body, nil, true)
    end)
    it("obfuscates sensitive settings from the configuration", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_string(json.configuration.pg_password)
      assert.not_equal("hide_me", json.configuration.pg_password)
    end)
    it("returns PRNG seeds", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.response(res).has.status(200)
      local json = cjson.decode(body)
      assert.is_table(json.prng_seeds)
      for k in pairs(json.prng_seeds) do
        assert.matches("pid: %d+", k)
        assert.matches("%d+", k)
      end
    end)
  end)

  dao_helpers.for_each_dao(function(kong_conf)
    describe("/status with DB: #" .. kong_conf.database, function()
      local client
      local dao

      setup(function()
        dao = assert(DAOFactory.new(kong_conf))
        assert(dao:run_migrations())

        assert(helpers.start_kong {
          database = kong_conf.database,
        })
        client = helpers.admin_client(10000)
      end)

      teardown(function()
        if client then client:close() end
        helpers.stop_kong()
      end)

      it("returns status info", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.database)
        assert.is_table(json.server)

        assert.is_boolean(json.database.reachable)

        assert.is_number(json.server.connections_accepted)
        assert.is_number(json.server.connections_active)
        assert.is_number(json.server.connections_handled)
        assert.is_number(json.server.connections_reading)
        assert.is_number(json.server.connections_writing)
        assert.is_number(json.server.connections_waiting)
        assert.is_number(json.server.total_requests)
      end)

      it("database.reachable is `true` when DB connection is healthy", function()
        -- In this test, we know our DB is reachable because it must be
        -- so in our test suite. Ideally, a test when the DB isn't reachable
        -- should be provided (start Kong, kill DB, request `/status`),
        -- but this isn't currently possible in our test suite.
        -- Additionally, let's emphasize that we only test DB connection, not
        -- the health of said DB itself.

        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(json.database.reachable)
      end)
    end)

    describe('/userinfo', function()
      local proxy_prefix = require("kong.enterprise_edition.proxies").proxy_prefix
      local enums = require "kong.enterprise_edition.dao.enums"
      local utils = require "kong.tools.utils"

      local strategy = kong_conf.database
      local client
      local dao
      local bp

      after_each(function()
        helpers.stop_kong()
      end)

      teardown(function()
        dao = select(3, helpers.get_db_utils(strategy))
        dao:truncate_tables()
      end)

      it("return 404 on user info when admin_auth is off", function()
        helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
        }))

        client = assert(helpers.proxy_client())

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
        })
        assert.res_status(404, res)
      end)

      it("returns 403 with admin_auth = on, invalid credentials", function()
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = 'basic-auth'
        }))

        client = assert(helpers.proxy_client())

        bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
          ["Authorization"] = "Basic " .. ngx.encode_base64("iam:invalid"),
        })

        assert.res_status(401, res)
      end)

      it("returns user info of admin consumer with no rbac", function()
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = 'basic-auth',
        }))

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        client = assert(helpers.proxy_client())

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equals(json.consumer.username, 'hawk')
        assert.equals(json.consumer.status, enums.CONSUMERS.STATUS.APPROVED)
        assert.equals(json.consumer.type, enums.CONSUMERS.TYPE.ADMIN)
        assert.is_true(utils.is_valid_uuid(json.consumer.id))

        assert.is_nil(json.rbac_user)
      end)

      it("returns user info of admin consumer with rbac", function()
        local ee_helpers = require "spec.ee_helpers"
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        local super_admin = ee_helpers.register_rbac_resources(dao)

        client = assert(helpers.proxy_client())

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        assert(dao.consumers_rbac_users_map:insert {
          consumer_id = consumer.id,
          user_id = super_admin.id
        })

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
            ["Kong-Admin-Token"] = super_admin.user_token,
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        assert.same(consumer, json.consumer)
        assert.same(super_admin, json.rbac_user)
      end)

      it("is whitelisted", function()
        local ee_helpers = require "spec.ee_helpers"
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        local super_admin = ee_helpers.register_rbac_resources(dao)

        client = assert(helpers.proxy_client())

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        assert(dao.consumers_rbac_users_map:insert {
          consumer_id = consumer.id,
          user_id = super_admin.id
        })

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        assert.same(consumer, json.consumer)
        assert.same(super_admin, json.rbac_user)
      end)

    end)
  end)
end)
