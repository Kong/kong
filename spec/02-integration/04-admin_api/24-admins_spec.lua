local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local enums      = require "kong.enterprise_edition.dao.enums"
local utils      = require "kong.tools.utils"
local ee_jwt     = require "kong.enterprise_edition.jwt"
local ee_helpers = require "spec.ee_helpers"
local escape = require("socket.url").escape

local post = ee_helpers.post


for _, strategy in helpers.each_strategy() do
  describe("Admin API - Admins #" .. strategy, function()
    local client
    local dao
    local bp
    local admin, proxy_consumer
    local another_ws
    local admins = {}

    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = 'basic-auth',
        enforce_rbac = "on",
      }))

      another_ws = assert(dao.workspaces:insert({
        name = "another-one",
      }))

      ee_helpers.register_rbac_resources(dao)
      ee_helpers.register_token_statuses(dao)

      for i = 1, 3 do
        -- admins that are already approved
        local consumer = assert(bp.consumers:insert {
          username = "admin-" .. i .. "@test.com",
          custom_id = "admin-" .. i,
          email = "admin-" .. i .. "@test.com",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        })

        local rbac_user = assert(dao.rbac_users:insert {
          name = "admin-" .. i,
          user_token = utils.uuid(),
          enabled = true,
        })

        assert(dao.consumers_rbac_users_map:insert {
          consumer_id = consumer.id,
          user_id = rbac_user.id,
        })

        -- for now, an admin is a munging of consumer + rbac_user
        consumer.rbac_user = rbac_user

        admins[i] = consumer

      end

      -- developers don't show up as admins
      assert(bp.consumers:insert {
        username = "developer-1",
        custom_id = "developer-1",
        email = "developer-1@test.com",
        type = enums.CONSUMERS.TYPE.DEVELOPER,
      })

      -- proxy users don't show up as admins
      proxy_consumer = assert(bp.consumers:insert {
        username = "consumer-1",
        custom_id = "consumer-1",
        email = "consumer-1@test.com",
        type = enums.CONSUMERS.TYPE.PROXY,
      })

      admin = admins[1]
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("/admins", function()
      describe("GET", function ()
        it("retrieves list of admins only", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
            },
          })

          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(3, #json.data)
        end)

      end)

      describe("POST", function ()
        it("creates an admin", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              custom_id = "cooper",
              username  = "dale",
              email = "twinpeaks@konghq.com",
            },
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)

          assert.equal("dale", json.consumer.username)
          assert.equal("cooper", json.consumer.custom_id)
          assert.equal("twinpeaks@konghq.com", json.consumer.email)
          assert.equal(enums.CONSUMERS.TYPE.ADMIN, json.consumer.type)
          assert.equal(enums.CONSUMERS.STATUS.INVITED, json.consumer.status)
          assert.truthy(utils.is_valid_uuid(json.rbac_user.user_token))
          assert.equal("dale", json.rbac_user.name)

          local consumer_reset_secrets, err = dao.consumer_reset_secrets:find_all {
            consumer_id = json.consumer.id,
          }

          assert.is_nil(err)
          assert.same(json.consumer.id, consumer_reset_secrets[1].consumer_id)
        end)

        it("uses the admins_helpers validator", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/" .. another_ws.name .. "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              custom_id = "admin-1",
              username  = "i-am-unique",
              email = "twinpeaks@konghq.com",
            },
          })
          assert.res_status(409, res)
        end)
      end)
    end)

    describe("/admins/:admin_id", function()
      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/" .. admins[1].id,
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same(admins[1], json)
        end)

        it("retrieves by username", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/" .. escape("admin-2@test.com"),
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(admins[2], json)
        end)

        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/not-an-admin",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it("updates by id", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/" .. admin.id,
              body = {
                username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(admin.id, json.id)

            local in_db = assert(bp.consumers:find {id = admin.id})
            assert.same(json, in_db)
          end
        end)

        it("updates by username", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/" .. admin.username,
              body = {
                username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(admin.id, json.id)

            local in_db = assert(bp.consumers:find {id = admin.id})
            assert.same(json, in_db)
          end
        end)

        it("returns 404 if not found", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/not-an-admin",
              body = {
               username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end
        end)
      end)

      describe("DELETE", function()
        local admin_id, expected

        before_each(function()
          dao:truncate_table('rbac_users')
          dao:truncate_table('rbac_roles')
          dao:truncate_table('consumers')
          dao:truncate_table('consumers_rbac_users_map')

          local res = assert(client:send {
            method = "POST",
            path  = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              username = "gruce",
              email = "gruce@konghq.com",
            },
          })

          assert.res_status(200, res)

          admin_id = dao.db:query("select * from consumers_rbac_users_map")[1].consumer_id
        end)

        it("deletes by id", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/" .. admin_id,
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)

          if dao.db_type == "postgres" then
            expected = {}
          else
            expected = {
              meta = {
                has_more_pages = false
              },
              type = "ROWS"
            }
          end

          assert.same(dao.db:query("select * from consumers_rbac_users_map"), expected)
          assert.same(dao.db:query("select * from rbac_users"), expected)
          assert.same(dao.db:query("select * from consumers"), expected)
          assert.same(dao.db:query("select * from rbac_roles"), expected)
        end)

        it("deletes by username", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/gruce",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)

          if dao.db_type == "postgres" then
            expected = {}
          else
            expected = {
              meta = {
                has_more_pages = false
              },
              type = "ROWS"
            }
          end

          assert.same(dao.db:query("select * from consumers_rbac_users_map"), expected)
          assert.same(dao.db:query("select * from rbac_users"), expected)
          assert.same(dao.db:query("select * from consumers"), expected)
          assert.same(dao.db:query("select * from rbac_roles"), expected)
        end)

        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/not-an-admin",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          assert.res_status(404, res)
        end)
      end)

      describe("/admins/:consumer_id/workspaces", function()
        describe("GET", function()
          it("retrieves workspaces", function()
            local res = assert(client:send {
              method = "POST",
              path = "/admins",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
              body  = {
                custom_id = "cooper",
                username  = "dale",
                email = "twinpeaks@konghq.com",
              },
            })

            local body = assert.res_status(200, res)
            admin = cjson.decode(body)

            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.consumer.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(1, #json)
            assert.equal("default", json[1].name)
          end)

          it("returns multiple workspaces admin belongs to", function()
            local res = assert(client:send {
              method = "POST",
              path = "/workspaces/" .. another_ws.name .. "/entities",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
              body  = {
                entities = admin.consumer.id .. "," .. admin.rbac_user.id
              },
            })
            assert.res_status(201, res)

            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.consumer.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            local names = { json[1].name, json[2].name }
            assert.equal(2, #json)
            assert.contains("default", names)
            assert.contains(another_ws.name, names)
          end)

          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.rbac_user.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end)

          it("returns 404 if consumer is not of type admin", function()
            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. proxy_consumer.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)

  describe("Admin API - Admins Register #" .. strategy, function()
    local client
    local dao

    describe("/admins/register basic-auth", function()
      local headers = {
        ["Content-Type"] = "application/json",
        ["Kong-Admin-Token"] = "letmein",
      }

      before_each(function()
        _, _, dao = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_url = "http://manager.konghq.com",
          admin_gui_auth = 'basic-auth',
          enforce_rbac = "on",
        }))
        ee_helpers.register_rbac_resources(dao)
        ee_helpers.register_token_statuses(dao)
        client = assert(helpers.admin_client())
      end)

      after_each(function()
        if client then client:close() end
        assert(helpers.stop_kong())
      end)

      describe("/admins/register", function()
        it("denies invalid emails", function()
          local res = assert(client:send {
            method = "POST",
            path = "/admins/register",
            headers = {
              ["Content-Type"] = "application/json",
            },
            body  = {
              username  = "dale",
              email = "not-valid.com",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.truthy(string.match(json.message, "Invalid email"))
        end)

        it("successfully registers an invited admin", function()
          local admin = post(client, "/admins", {
                                      username = "bob",
                                      email = "hong@konghq.com",
                                    }, headers, 200)

          local reset_secret = dao.consumer_reset_secrets:find_all({
            consumer_id = admin.consumer.id
          })[1]
          assert.equal(enums.TOKENS.STATUS.PENDING, reset_secret.status)

          local claims = {id = admin.consumer.id, exp = ngx.time() + 100000}
          local valid_jwt = ee_jwt.generate_JWT(claims, reset_secret.secret,
                                                "HS256")

          local res = assert(client:send {
            method = "POST",
            path = "/admins/register",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body  = {
              username = "bob",
              email = "hong@konghq.com",
              token = valid_jwt,
              password = "clawz"
            },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("bob", json.consumer.username)
          assert.equal("bob", json.credential.username)
          assert.is.falsy("clawz" == json.credential.password)

          reset_secret = dao.consumer_reset_secrets:find_all({
            id = reset_secret.id
          })[1]

          assert.equal(enums.TOKENS.STATUS.CONSUMED, reset_secret.status)
        end)
      end)
    end)

    describe("/admins/register ldap-auth-advanced", function()
      local headers = {
        ["Content-Type"] = "application/json",
        ["Kong-Admin-Token"] = "letmein", -- super-admin
      }

      before_each(function()
        _, _, dao = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_url = "http://manager.konghq.com",
          admin_gui_auth = 'ldap-auth-advanced',
          enforce_rbac = "on",
        }))
        ee_helpers.register_rbac_resources(dao)
        ee_helpers.register_token_statuses(dao)
        client = assert(helpers.admin_client())
      end)

      after_each(function()
        if client then client:close() end
        assert(helpers.stop_kong())
      end)

      describe("/admins/register", function()
        it("cannot register an invited admin with ldap", function()
          local admin = post(client, "/admins", {
                                      username = "bob",
                                      email = "hong@konghq.com",
                                    }, headers, 200)

          local reset_secret = dao.consumer_reset_secrets:find_all({
            consumer_id = admin.consumer.id
          })[1]
          assert.equal(nil, reset_secret)

          local res = assert(client:send {
            method = "POST",
            path = "/admins/register",
            headers = {
              ["Content-Type"] = "application/json"
              -- no auth headers!
            },
            body  = {
              username = "bob",
              email = "hong@konghq.com",
              password = "clawz"
            },
          })

          assert.res_status(400, res)
        end)
      end)
    end)
  end)

  describe("Admin API - auto-approval #" .. strategy, function()
    local client
    local dao
    local consumer

    before_each(function()
      _, _, dao = helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = 'basic-auth',
        enforce_rbac = "on",
      }))
      ee_helpers.register_rbac_resources(dao)
      ee_helpers.register_token_statuses(dao)
      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then client:close() end
      assert(helpers.stop_kong())
    end)

    it("manages state transition for invited admins", function()
      -- create an admin who is pending
      local res = assert(client:send {
        method = "POST",
        path  = "/admins",
        headers = {
          ["Kong-Admin-Token"] = "letmein",
          ["Content-Type"] = "application/json",
        },
        body  = {
          custom_id = "gruce",
          username = "gruce@konghq.com",
          email = "gruce@konghq.com",
        },
      })
      res = assert.res_status(200, res)
      local json = cjson.decode(res)
      consumer = json.consumer

      -- he's invited
      assert.same(enums.CONSUMERS.STATUS.INVITED, consumer.status)

      -- add credentials for him
      assert(dao.basicauth_credentials:insert {
        username    = "gruce@konghq.com",
        password    = "kong",
        consumer_id = consumer.id,
      })

      -- make an API call
      assert(client:send{
        method = "GET",
        path = "/",
        headers = {
          ["Kong-Admin-User"] = "gruce@konghq.com",
          ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong")
        }
      })

      local updated_consumers = dao.consumers:find_all { id = consumer.id }
      assert.same(enums.CONSUMERS.STATUS.APPROVED, updated_consumers[1].status)
    end)
  end)

  describe("Admin API - /admins/password_resets for admin #" .. strategy, function()
    local client
    local dao
    local admin

    before_each(function()
      _, _, dao = helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = "basic-auth",
        enforce_rbac = "on",
      }))
      ee_helpers.register_rbac_resources(dao)
      ee_helpers.register_token_statuses(dao)
      client = assert(helpers.admin_client())

      local res = assert(client:send {
        method = "POST",
        path  = "/admins",
        headers = {
          ["Kong-Admin-Token"] = "letmein",
          ["Content-Type"] = "application/json",
        },
        body  = {
          custom_id = "gruce",
          username = "gruce@konghq.com",
          email = "gruce@konghq.com",
        }
      })
      res = assert.res_status(200, res)
      local json = cjson.decode(res)
      admin = json.consumer

      -- add credentials for him
      assert(dao.basicauth_credentials:insert {
        username    = "gruce@konghq.com",
        password    = "kong",
        consumer_id = admin.id,
      })
    end)

    after_each(function()
      if client then client:close() end
      assert(helpers.stop_kong())
    end)

    it("creates a consumer_reset_secret", function()
      local res = assert(client:send {
        method = "POST",
        path  = "/admins/password_resets",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body  = {
          email = "gruce@konghq.com",
        }
      })
      assert.res_status(201, res)

      local resets, err = dao.consumer_reset_secrets:find_all({
        consumer_id = admin.id
      })

      assert.is_nil(err)

      -- one when he was invited, one when he forgot password
      assert.same(2, #resets)
    end)

    it("returns 404 if you're not an admin", function()
      local res = assert(client:send {
        method = "POST",
        path = "/admins/password_resets",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          email = "developer-1@test.com",
        }
      })

      assert.res_status(404, res)
    end)

  end)

  describe("Admin API - /admins/password_resets for admin #" .. strategy, function()
    local client
    local dao

    before_each(function()
      _, _, dao = helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = "ldap-auth-advanced",
        enforce_rbac = "on",
      }))
      ee_helpers.register_rbac_resources(dao)
      ee_helpers.register_token_statuses(dao)
      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then client:close() end
      assert(helpers.stop_kong())
    end)

    it("returns 404 for 3rd-party auth", function()
      local res = assert(client:send {
        method = "POST",
        path = "/admins/password_resets",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          email = "admin-1@test.com",
        }
      })

      assert.res_status(404, res)
    end)

  end)
end
