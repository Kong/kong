local helpers = require "spec.helpers"
local cjson = require "cjson"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local proxy_prefix = require("kong.enterprise_edition.proxies").proxy_prefix
local enums = require "kong.enterprise_edition.dao.enums"
local ee_helpers = require "spec.ee_helpers"


describe("Admin API - ee-specific Kong routes", function()
  dao_helpers.for_each_dao(function(kong_conf)
    describe("/userinfo with db " .. kong_conf.database, function()

      local strategy = kong_conf.database
      local client
      local dao
      local bp

      after_each(function()
        helpers.stop_kong()
      end)

      teardown(function()
        -- this is just truncating tables, a side effect
        helpers.get_db_utils(strategy)
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

        local expected = {
          consumer = consumer,
          permissions = {
            endpoints = {
              ["*"] = {
                ["*"] = {
                  actions = { "delete", "create", "update", "read", },
                  negative = false,
                }
              }
            },
            entities = {
              ["*"] = {
                actions = { "delete", "create", "update", "read", },
                negative = false,
              },
            },
          },
        }

        assert.same(expected, json)
      end)

      it("returns user info of admin consumer with rbac", function()
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

        local expected = {
          consumer = consumer,
          rbac_user = super_admin,
          permissions = {
            endpoints = {
              ["*"] = {
                ["*"] = {
                  actions = { "delete", "create", "update", "read", },
                  negative = false,
                }
              }
            },
            entities = {
              ["*"] = {
                actions = { "delete", "create", "update", "read", },
                negative = false,
              },
            },
          },
        }

        assert.same(expected, json)
      end)

      it("is whitelisted", function()
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

      it("returns 404 on user info when consumer is not mapped to rbac user, ", function()
        local bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "on",
        }))

        ee_helpers.register_rbac_resources(dao)

        client = assert(helpers.proxy_client())

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.PROXY,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/admin/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        assert.res_status(404, res)
      end)
    end)
  end)
end)
