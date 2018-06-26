local helpers = require "spec.helpers"
local cjson = require "cjson"
local proxy_prefix = require("kong.enterprise_edition.proxies").proxy_prefix

for _, strategy in helpers.each_strategy() do
  describe("proxied Admin API on " .. strategy, function()
    local bp
    local db
    local dao
    local client

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("/_kong/admin with authentication", function()
      setup(function()
        helpers.stop_kong()
        assert(db:truncate())

        helpers.register_consumer_relations(dao)

        assert(helpers.start_kong({
          database   = strategy,
          admin_gui_auth = "basic-auth",
          admin_gui_auth_config = "{ \"hide_credentials\": true }",
        }))

        local admin_consumer = bp.consumers:insert {
          username = "gruce",
        }

        assert(dao.basicauth_credentials:insert {
          username    = "gruce",
          password    = "kong",
          consumer_id = admin_consumer.id,
        })
      end)

      before_each(function()
        client = assert(helpers.proxy_client())
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      describe("GET", function()
        it("returns 401 when unauthenticated", function()
          local res = assert(client:send {
            method = "GET",
            path = "/" .. proxy_prefix .. "/admin",
          })

          assert.res_status(401, res)
        end)

        it("returns 200 when authenticated", function()
          local res = assert(client:send {
            method = "GET",
            path = "/" .. proxy_prefix .. "/admin",
            headers = {
              ["Authorization"] = "Basic " .. ngx.encode_base64("gruce:kong"),
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("Welcome to kong", json.tagline)
        end)
      end)
    end)

    describe("/_kong/admin without authentication", function()
      setup(function()
        helpers.stop_kong()
        assert(db:truncate())

        assert(helpers.start_kong({
          database = strategy,
        }))
      end)

      before_each(function()
        client = assert(helpers.proxy_client())
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      describe("GET", function()
        it("works", function()
          local res = assert(client:send {
            method = "GET",
            path = "/" .. proxy_prefix .. "/admin",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("Welcome to kong", json.tagline)
        end)
      end)
    end)
  end)
end
