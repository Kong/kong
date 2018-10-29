local dao_helpers = require "spec.02-integration.03-dao.helpers"
local Factory = require "kong.dao.factory"
local utils = require "kong.tools.utils"
local DB = require "kong.db"
local helper = require "spec.helpers"
local singletons = require "kong.singletons"

dao_helpers.for_each_dao(function(kong_config)
  describe("Model (Constraints) with DB: #" .. kong_config.database, function()
    local service_fixture
    local plugin_fixture
    local dao
    local db

    setup(function()
      db = assert(DB.new(kong_config, kong_config.database))
      assert(db:init_connector())

      dao = assert(Factory.new(kong_config, db))
      assert(dao:run_migrations())

      singletons.dao = dao
      singletons.db = db
    end)

    before_each(function()
      dao:truncate_tables()
      assert(db:truncate())
      helper.register_consumer_relations(dao)
      ngx.ctx.workspaces = dao.workspaces:find_all({ name = "default" })

      local service, _, err_t = db.services:insert {
        protocol = "http",
        host     = "example.com",
      }
      assert.is_nil(err_t)

      service_fixture = service

      plugin_fixture = {
        name       = "key-auth",
        service_id = service.id,
      }
    end)

    -- Check behavior just in case
    describe("plugins insert()", function()
      it("insert a valid plugin", function()
        local plugin, err = dao.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(service_fixture.id, plugin.service_id)
        assert.same({
          run_on_preflight = true,
          hide_credentials = false,
          key_names        = {"apikey"},
          anonymous        = "",
          key_in_body      = false,
        }, plugin.config)
      end)
      it("insert a valid plugin bis", function()
        plugin_fixture.config = { key_names = { "api-key" } }

        local plugin, err = dao.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(service_fixture.id, plugin.service_id)
        assert.same({
          run_on_preflight = true,
          hide_credentials = false,
          key_names        = {"api-key"},
          anonymous        = "",
          key_in_body      = false,
        }, plugin.config)
      end)

      describe("uniqueness", function()
        it("per Service", function()
          local plugin, err = dao.plugins:insert(plugin_fixture)
          assert.falsy(err)
          assert.truthy(plugin)

          plugin, err = dao.plugins:insert(plugin_fixture)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'key-auth'",
                         err, nil, true)
        end)

        it("Service/Consumer", function()
          local consumer, err = dao.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name = "rate-limiting",
            service_id = service_fixture.id,
            consumer_id = consumer.id,
            config = { minute = 1 }
          }

          local plugin, err = dao.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(consumer.id, plugin.consumer_id)

          plugin, err = dao.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'rate-limiting'",
                         err, nil, true)
        end)

        it("Service/Route", function()
          local err_t, service, route, _

          service, _, err_t = db.services:insert {
            host = "example.com",
          }

          assert.is_nil(err_t)

          route, _, err_t = db.routes:insert {
            protocols = { "http" },
            hosts     = { "example.com" },
            service   = service,
          }

          assert.is_nil(err_t)

          local plugin_tbl = {
            name       = "rate-limiting",
            service_id = service_fixture.id,
            route_id   = route.id,
            config     = { minute = 1 }
          }

          local plugin, err = dao.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route_id)

          plugin, err = dao.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'rate-limiting'",
                         err, nil, true)
        end)

        it("Route/Consumer", function()
          local err_t, service, route, _

          service, _, err_t = db.services:insert {
            host = "example.com",
          }

          assert.is_nil(err_t)

          route, _, err_t = db.routes:insert {
            protocols = { "http" },
            hosts     = { "example.com" },
            service   = service,
          }
          assert.is_nil(err_t)

          local consumer, err = dao.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name        = "rate-limiting",
            route_id    = route.id,
            consumer_id = consumer.id,
            config      = { minute = 1 }
          }

          local plugin, err = dao.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route_id)
          assert.equal(consumer.id, plugin.consumer_id)

          plugin, err = dao.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'rate-limiting'",
                         err, nil, true)
        end)

        it("Service/Route/Consumer", function()
          local err_t, service, route, _

          service, _, err_t = db.services:insert {
            host = "example.com",
          }

          assert.is_nil(err_t)

          route, _, err_t = db.routes:insert {
            protocols = { "http" },
            hosts     = { "example.com" },
            service   = service,
          }

          assert.is_nil(err_t)

          local consumer, err = dao.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name        = "rate-limiting",
            service_id  = service_fixture.id,
            route_id    = route.id,
            consumer_id = consumer.id,
            config      = { minute = 1 }
          }

          local plugin, err = dao.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route_id)
          assert.equal(service_fixture.id, plugin.service_id)
          assert.equal(consumer.id, plugin.consumer_id)

          plugin, err = dao.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'rate-limiting'",
                         err, nil, true)
        end)
      end)
    end)

    describe("FOREIGN constraints", function()
      it("not insert plugin if invalid Service foreign key", function()
        plugin_fixture.service_id = utils.uuid()

        local plugin, err = dao.plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.equal("no such Service (id=" .. plugin_fixture.service_id .. ")",
                     err.message)
      end)

      it("not insert plugin if invalid Route foreign key", function()
        plugin_fixture.service_id = nil
        plugin_fixture.route_id = utils.uuid()

        local plugin, err = dao.plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.equal("no such Route (id=" .. plugin_fixture.route_id .. ")",
                     err.message)
      end)

      it("not insert plugin if invalid Consumer foreign key", function()
        local plugin_tbl = {
          name        = "rate-limiting",
          service_id  = service_fixture.id,
          consumer_id = utils.uuid(),
          config      = {minute = 1}
        }

        local plugin, err = dao.plugins:insert(plugin_tbl)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.matches("consumer_id=does not exist with value '" .. plugin_tbl.consumer_id .. "'", tostring(err), nil, true)
      end)

      it("does not update plugin if invalid foreign key", function()
        local plugin, err = dao.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.truthy(plugin)

        local fake_service_id = utils.uuid()
        plugin.service_id = fake_service_id
        plugin, err = dao.plugins:update(plugin, {id = plugin.id})
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.equal("no such Service (id=" .. fake_service_id .. ")",
                     err.message)
      end)
    end)

    describe("CASCADE delete", function()
      it("deleting Service deletes associated Plugin", function()
        local plugin, err = dao.plugins:insert {
          name = "key-auth",
          service_id = service_fixture.id
        }
        assert.falsy(err)

        -- plugin exists
        plugin, err = dao.plugins:find(plugin)
        assert.falsy(err)
        assert.truthy(plugin)

        -- delete Service
        local ok, err, err_t = db.services:delete {
          id = service_fixture.id
        }
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.is_true(ok)

        -- no more Service
        local api, err = db.services:select {
          id = service_fixture.id
        }
        assert.falsy(err)
        assert.falsy(api)

        -- no more plugin
        plugin, err = dao.plugins:find(plugin)
        assert.falsy(err)
        assert.falsy(plugin)
      end)

      it("deleting Route deletes associated Plugin", function()
        local err_t, service, route, _

        service, _, err_t = db.services:insert {
          host = "example.com",
        }

        assert.is_nil(err_t)

        route, _, err_t = db.routes:insert {
          protocols = { "http" },
          hosts     = { "example.com" },
          service   = service,
        }
        assert.is_nil(err_t)

        local plugin, err = dao.plugins:insert {
          name       = "key-auth",
          route_id   = route.id,
          service_id = service.id,
        }
        assert.falsy(err)

        -- plugin exists
        plugin, err = dao.plugins:find(plugin)
        assert.falsy(err)
        assert.truthy(plugin)

        -- delete Route
        local ok, err, err_t = db.routes:delete {
          id = route.id
        }
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.is_true(ok)

        -- no more Route
        local api, err = db.routes:select {
          id = route.id
        }
        assert.falsy(err)
        assert.falsy(api)

        -- no more Plugin
        plugin, err = dao.plugins:find(plugin)
        assert.falsy(err)
        assert.falsy(plugin)
      end)

      it("deleting Consumer deletes associated Plugin", function()
        local consumer_fixture, err = dao.consumers:insert {
          username = "bob"
        }

        assert.falsy(err)
        local plugin, err = dao.plugins:insert {
          name        = "rate-limiting",
          service_id  = service_fixture.id,
          consumer_id = consumer_fixture.id,
          config      = { minute = 1 },
        }
        assert.falsy(err)

        local res, err = dao.consumers:delete(consumer_fixture)
        assert.falsy(err)
        assert.is_table(res)

        local consumer, err = dao.consumers:find(consumer_fixture)
        assert.falsy(err)
        assert.falsy(consumer)

        plugin, err = dao.plugins:find(plugin)
        assert.falsy(err)
        assert.falsy(plugin)
      end)
    end)
  end) -- describe
end) -- for each db
