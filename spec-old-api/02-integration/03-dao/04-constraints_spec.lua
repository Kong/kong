local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"

local api_tbl = {
  name         = "example",
  hosts        = { "example.com" },
  uris         = { "/example" },
  strip_uri    = true,
  upstream_url = "https://example.com",
}

local plugin_tbl = {
  name = "key-auth"
}

for _, strategy in helpers.each_strategy() do
  describe("Model (Constraints) with DB: #" .. strategy, function()
    local plugin_fixture, api_fixture
    local apis, plugins
    local bp, db, dao
    lazy_setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
      apis = dao.apis
      plugins = db.plugins
    end)
    before_each(function()
      plugin_fixture = utils.shallow_copy(plugin_tbl)
      local api, err = apis:insert(api_tbl)
      assert.falsy(err)
      api_fixture = api
    end)
    after_each(function()
      dao:truncate_table("apis")
      assert(db:truncate("plugins"))
      assert(db:truncate("consumers"))
    end)

    -- Check behavior just in case
    describe("plugins insert()", function()
      it("insert a valid plugin", function()
        plugin_fixture.api = { id = api_fixture.id }

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(api_fixture.id, plugin.api.id)
        assert.same({
            run_on_preflight = true,
            hide_credentials = false,
            key_names = {"apikey"},
            key_in_body = false,
          }, plugin.config)
      end)
      it("insert a valid plugin bis", function()
        plugin_fixture.api = { id = api_fixture.id }
        plugin_fixture.config = {key_names = {"api-key"}}

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(api_fixture.id, plugin.api.id)
        assert.same({
            run_on_preflight = true,
            hide_credentials = false,
            key_names = {"api-key"},
            key_in_body = false,
          }, plugin.config)
      end)
      describe("unique per API/Consumer", function()
        it("API/Plugin", function()
          plugin_fixture.api = { id = api_fixture.id }

          local plugin, err = plugins:insert(plugin_fixture)
          assert.falsy(err)
          assert.truthy(plugin)

          local err_t
          plugin, err, err_t = plugins:insert(plugin_fixture)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = 5,
            fields = {
              api = { id = api_fixture.id },
              consumer = ngx.null,
              name = "key-auth",
              route = ngx.null,
              service = ngx.null,
            },
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on '{consumer=null,api={id="]] ..
                      api_fixture.id ..
                      [["},service=null,name="key-auth",route=null}']],
            strategy = strategy,
          }, err_t)
        end)
        it("API/Consumer/Plugin", function()
          local consumer, err = bp.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name = "rate-limiting",
            api = { id = api_fixture.id },
            consumer = { id = consumer.id },
            config = {minute = 1}
          }

          local plugin, err = plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(consumer.id, plugin.consumer.id)

          local err_t
          plugin, err, err_t = plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.same({
            code = 5,
            fields = {
              api = { id = api_fixture.id },
              consumer = { id = consumer.id },
              name = "rate-limiting",
              route = ngx.null,
              service = ngx.null,
            },
            name = "unique constraint violation",
            message = [[UNIQUE violation detected on '{consumer={id="]] ..
                      consumer.id .. [["},api={id="]] ..
                      api_fixture.id ..
                      [["},service=null,name="rate-limiting",route=null}']],
            strategy = strategy,
          }, err_t)
        end)
      end)
    end)

    describe("FOREIGN constraints", function()

      it("not insert plugin if invalid API foreign key", function()
        local bad_id = utils.uuid()
        plugin_fixture.api = { id = bad_id }

        local plugin, err, err_t = plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          code = 4,
          fields = {
            api = { id = bad_id },
          },
          message = [[the foreign key '{id="]] .. bad_id ..
                    [["}' does not reference an existing 'apis' entity.]],
          name = "foreign key violation",
          strategy = strategy,
        }, err_t)
      end)
      it("not insert plugin if invalid Consumer foreign key", function()
        local bad_id = utils.uuid()
        local plugin_tbl = {
          name = "rate-limiting",
          api = { id = api_fixture.id },
          consumer = { id = bad_id },
          config = {minute = 1}
        }

        local plugin, err, err_t = plugins:insert(plugin_tbl)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          code = 4,
          fields = {
            consumer = { id = bad_id },
          },
          message = [[the foreign key '{id="]] .. bad_id ..
                    [["}' does not reference an existing 'consumers' entity.]],
          name = "foreign key violation",
          strategy = strategy,
        }, err_t)
      end)
      it("does not update plugin if invalid foreign key", function()
        plugin_fixture.api = { id = api_fixture.id }

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.truthy(plugin)

        local fake_api_id = utils.uuid()
        plugin.api = { id = fake_api_id }
        local err_t
        plugin, err, err_t = plugins:update({id = plugin.id}, plugin)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.same({
          code = 4,
          fields = {
            api = { id = fake_api_id },
          },
          message = [[the foreign key '{id="]] .. fake_api_id ..
                    [["}' does not reference an existing 'apis' entity.]],
          name = "foreign key violation",
          strategy = strategy,
        }, err_t)
      end)
    end)

    describe("CASCADE delete", function()
      local api_fixture, consumer_fixture
      before_each(function()
        local err
        api_fixture, err = apis:insert {
          name         = "to-delete",
          hosts        = { "to-delete.com" },
          uris         = { "/to-delete" },
          upstream_url = "https://example.com",
        }
        assert.falsy(err)

        consumer_fixture, err = bp.consumers:insert {
          username = "bob"
        }
        assert.falsy(err)
      end)
      after_each(function()
        dao:truncate_table("apis")
        assert(db:truncate("plugins"))
        assert(db:truncate("consumers"))
      end)

      it("delete", function()
        local plugin, err = plugins:insert {
          name = "key-auth",
          api = { id = api_fixture.id },
        }
        assert.falsy(err)

        local res, err = apis:delete(api_fixture)
        assert.falsy(err)
        assert.is_table(res)

        -- no more API
        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.falsy(api)

        -- no more plugin
        local plugin, err = plugins:select({ id = plugin.id })
        assert.falsy(err)
        assert.falsy(plugin)
      end)

      it("delete bis", function()
        local plugin, err = plugins:insert {
          name = "rate-limiting",
          api = { id = api_fixture.id },
          consumer = { id = consumer_fixture.id },
          config = {minute = 1}
        }
        assert.falsy(err)

        local res, err = db.consumers:delete({ id = consumer_fixture.id })
        assert.falsy(err)
        assert.is_truthy(res)

        local consumer, err = db.consumers:select(consumer_fixture)
        assert.truthy(err)
        assert.falsy(consumer)

        plugin, err = plugins:select({ id = plugin.id })
        assert.falsy(err)
        assert.falsy(plugin)
      end)
    end)
  end) -- describe
end -- for each db
