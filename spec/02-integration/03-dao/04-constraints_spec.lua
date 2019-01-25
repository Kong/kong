local utils = require "kong.tools.utils"
<<<<<<< HEAD
local DB = require "kong.db"
local helper = require "spec.helpers"
local singletons = require "kong.singletons"
||||||| merged common ancestors
local DB = require "kong.db"
=======
local errors = require "kong.db.errors"
local helpers = require "spec.helpers"
>>>>>>> 0.15.0

for _, strategy in helpers.each_strategy() do
  describe("Model (Constraints) with DB: #" .. strategy, function()
    local service_fixture
    local plugin_fixture
    local db

<<<<<<< HEAD
    setup(function()
      db = assert(DB.new(kong_config, kong_config.database))
      assert(db:init_connector())

      dao = assert(Factory.new(kong_config, db))
      assert(dao:run_migrations())

      singletons.dao = dao
      singletons.db = db
||||||| merged common ancestors
    setup(function()
      db = assert(DB.new(kong_config, kong_config.database))
      assert(db:init_connector())

      dao = assert(Factory.new(kong_config, db))
      assert(dao:run_migrations())
=======
    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {})
>>>>>>> 0.15.0
    end)

    before_each(function()
<<<<<<< HEAD
      dao:truncate_tables()
      assert(db:truncate())
      helper.register_consumer_relations(dao)
      ngx.ctx.workspaces = dao.workspaces:find_all({ name = "default" })
||||||| merged common ancestors
      dao:truncate_tables()
      assert(db:truncate())
=======
      assert(db:truncate("plugins"))
      assert(db:truncate("consumers"))
      assert(db:truncate("routes"))
      assert(db:truncate("services"))
>>>>>>> 0.15.0

      local service, _, err_t = db.services:insert({
        protocol = "http",
        host     = "example.com",
      })
      assert.is_nil(err_t)

      service_fixture = service

      plugin_fixture = {
        name    = "key-auth",
        service = { id = service.id },
      }
    end)

    -- Check behavior just in case
    describe("plugins insert()", function()
      it("insert a valid plugin", function()
        local plugin, err = db.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(service_fixture.id, plugin.service.id)
        assert.same({
          run_on_preflight = true,
          hide_credentials = false,
          key_names        = {"apikey"},
          key_in_body      = false,
        }, plugin.config)
      end)
      it("insert a valid plugin bis", function()
        plugin_fixture.config = { key_names = { "api-key" } }

        local plugin, err = db.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(service_fixture.id, plugin.service.id)
        assert.same({
          run_on_preflight = true,
          hide_credentials = false,
          key_names        = {"api-key"},
          key_in_body      = false,
        }, plugin.config)
      end)

      describe("uniqueness", function()
        it("per Service", function()
          local plugin, err = db.plugins:insert(plugin_fixture)
          assert.falsy(err)
          assert.truthy(plugin)

          local err_t
          plugin, err, err_t = db.plugins:insert(plugin_fixture)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = errors.codes.UNIQUE_VIOLATION,
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on ']] ..
                      [[{consumer=null,api=null,service={id="]] ..
                      service_fixture.id ..
                      [["},name="key-auth",route=null}']],
            strategy = strategy,
            fields = {
              api = ngx.null,
              consumer = ngx.null,
              name = "key-auth",
              route = ngx.null,
              service = { id = service_fixture.id },
            }
          }, err_t)
        end)

        it("Service/Consumer", function()
          local consumer, err = db.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name     = "rate-limiting",
            service  = { id = service_fixture.id },
            consumer = { id = consumer.id },
            config   = { minute = 1 }
          }

          local plugin, err = db.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(consumer.id, plugin.consumer.id)

          local err_t
          plugin, err, err_t = db.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = errors.codes.UNIQUE_VIOLATION,
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on ']] ..
                      [[{consumer={id="]] ..
                      consumer.id ..
                      [["},api=null,service={id="]] ..
                      service_fixture.id ..
                      [["},name="rate-limiting",route=null}']],
            strategy = strategy,
            fields = {
              api = ngx.null,
              consumer = { id = consumer.id },
              name = "rate-limiting",
              route = ngx.null,
              service = { id = service_fixture.id },
            }
          }, err_t)
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
            name    = "rate-limiting",
            service = { id = service_fixture.id },
            route   = { id = route.id },
            config  = { minute = 1 }
          }

          local plugin, err = db.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route.id)

          plugin, err, err_t = db.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = errors.codes.UNIQUE_VIOLATION,
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on ']] ..
                      [[{consumer=null,api=null,service={id="]] ..
                      service_fixture.id ..
                      [["},name="rate-limiting",route={id="]] ..
                      route.id ..
                      [["}}']],
            strategy = strategy,
            fields = {
              api = ngx.null,
              consumer = ngx.null,
              name = "rate-limiting",
              route = { id = route.id },
              service = { id = service_fixture.id },
            }
          }, err_t)
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

          local consumer, err = db.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name     = "rate-limiting",
            route    = { id = route.id },
            consumer = { id = consumer.id },
            config   = { minute = 1 }
          }

          local plugin, err = db.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route.id)
          assert.equal(consumer.id, plugin.consumer.id)

          plugin, err, err_t = db.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = errors.codes.UNIQUE_VIOLATION,
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on ']] ..
                      [[{consumer={id="]] ..
                      consumer.id ..
                      [["},api=null,service=null,name="rate-limiting",route={id="]] ..
                      route.id ..
                      [["}}']],
            strategy = strategy,
            fields = {
              api = ngx.null,
              consumer = { id = consumer.id },
              name = "rate-limiting",
              route = { id = route.id },
              service = ngx.null,
            }
          }, err_t)
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

          local consumer, err = db.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name     = "rate-limiting",
            service  = { id = service_fixture.id },
            route    = { id = route.id },
            consumer = { id = consumer.id },
            config   = { minute = 1 }
          }

          local plugin, err = db.plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(route.id, plugin.route.id)
          assert.equal(service_fixture.id, plugin.service.id)
          assert.equal(consumer.id, plugin.consumer.id)

          plugin, err, err_t = db.plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = errors.codes.UNIQUE_VIOLATION,
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on ']] ..
                      [[{consumer={id="]] ..
                      consumer.id ..
                      [["},api=null,service={id="]] ..
                      service_fixture.id ..
                      [["},name="rate-limiting",route={id="]] ..
                      route.id ..
                      [["}}']],
            strategy = strategy,
            fields = {
              api = ngx.null,
              consumer = { id = consumer.id },
              name = "rate-limiting",
              route = { id = route.id },
              service = { id = service_fixture.id },
            }
          }, err_t)
        end)
      end)
    end)

    describe("FOREIGN constraints", function()
      it("not insert plugin if invalid Service foreign key", function()
        local fake_id = utils.uuid()
        plugin_fixture.service = { id = fake_id }

        local plugin, err, err_t = db.plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          strategy = strategy,
          code = errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          fields = {
            service = { id = fake_id },
          },
          message = [[the foreign key '{id="]] .. fake_id ..
                    [["}' does not reference an existing 'services' entity.]]
        }, err_t)
      end)

      it("not insert plugin if invalid Route foreign key", function()
        local fake_id = utils.uuid()
        plugin_fixture.service = nil
        plugin_fixture.route = { id = fake_id }

        local plugin, err, err_t = db.plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          strategy = strategy,
          code = errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          fields = {
            route = { id = fake_id },
          },
          message = [[the foreign key '{id="]] .. fake_id ..
                    [["}' does not reference an existing 'routes' entity.]]
        }, err_t)
      end)

      it("not insert plugin if invalid Consumer foreign key", function()
        local fake_id = utils.uuid()
        local plugin_tbl = {
          name     = "rate-limiting",
          service  = { id = service_fixture.id },
          consumer = { id = fake_id },
          config   = { minute = 1 }
        }

        local plugin, err, err_t = db.plugins:insert(plugin_tbl)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          strategy = strategy,
          code = errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          fields = {
            consumer = { id = fake_id },
          },
          message = [[the foreign key '{id="]] .. fake_id ..
                    [["}' does not reference an existing 'consumers' entity.]]
        }, err_t)
      end)

      it("does not update plugin if invalid foreign key", function()
        local plugin, err = db.plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.truthy(plugin)

        local fake_id = utils.uuid()
        plugin.service = { id = fake_id }
        local err_t
        plugin, err, err_t = db.plugins:update({ id = plugin.id }, plugin)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          strategy = strategy,
          code = errors.codes.FOREIGN_KEY_VIOLATION,
          name = "foreign key violation",
          fields = {
            service = { id = fake_id },
          },
          message = [[the foreign key '{id="]] .. fake_id ..
                    [["}' does not reference an existing 'services' entity.]]
        }, err_t)
      end)
    end)

    describe("CASCADE delete", function()
      it("deleting Service deletes associated Plugin", function()
        local plugin, err = db.plugins:insert {
          name = "key-auth",
          service = { id = service_fixture.id },
        }
        assert.falsy(err)

        local pk = { id = plugin.id }

        -- plugin exists
        plugin, err = db.plugins:select(pk)
        assert.falsy(err)
        assert.truthy(plugin)

        -- delete Service
        local ok, err, err_t = db.services:delete {
          id = service_fixture.id
        }
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.is_truthy(ok)

        -- no more Service
        local api, err = db.services:select {
          id = service_fixture.id
        }
        assert.falsy(err)
        assert.falsy(api)

        -- no more plugin
        plugin, err = db.plugins:select(pk)
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

        local plugin, err = db.plugins:insert {
          name    = "key-auth",
          route   = { id = route.id },
          service = { id = service.id },
        }
        assert.falsy(err)

        local pk = { id = plugin.id }

        -- plugin exists
        plugin, err = db.plugins:select(pk)
        assert.falsy(err)
        assert.truthy(plugin)

        -- delete Route
        local ok, err, err_t = db.routes:delete {
          id = route.id
        }
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.is_truthy(ok)

        -- no more Route
        local api, err = db.routes:select {
          id = route.id
        }
        assert.falsy(err)
        assert.falsy(api)

        -- no more Plugin
        plugin, err = db.plugins:select(pk)
        assert.falsy(err)
        assert.falsy(plugin)
      end)

      it("deleting Consumer deletes associated Plugin", function()
        local consumer_fixture, err = db.consumers:insert {
          username = "bob"
        }

        assert.falsy(err)
        local plugin, err = db.plugins:insert {
          name     = "rate-limiting",
          service  = { id = service_fixture.id },
          consumer = { id = consumer_fixture.id },
          config   = { minute = 1 },
        }
        assert.falsy(err)

        local pk = { id = plugin.id }

        local res, err = db.consumers:delete({ id = consumer_fixture.id })
        assert.falsy(err)
        assert.truthy(res)

        local consumer, err = db.consumers:select({ id = consumer_fixture.id })
        assert.falsy(err)
        assert.falsy(consumer)

        plugin, err = db.plugins:select(pk)
        assert.falsy(err)
        assert.falsy(plugin)
      end)
    end)
  end) -- describe
end -- for each db
