local cassandra = require "cassandra"
local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"
local DaoError = require "kong.dao.error"
local utils = require "kong.tools.utils"
local uuid = require "lua_uuid"

-- Load everything we need from the spec_helper
local env = spec_helper.get_env() -- test environment
local faker = env.faker
local dao_factory = env.dao_factory
local configuration = env.configuration

-- An utility function to apply tests on core collections.
local function describe_core_collections(tests_cb)
  for type, dao in pairs({ api = dao_factory.apis,
                           consumer = dao_factory.consumers }) do
    local collection = type == "plugin" and "plugins" or type.."s"
    describe(collection, function()
      tests_cb(type, collection)
    end)
  end
end

-- An utility function to test if an object is a DaoError.
-- Naming is due to luassert extensibility's restrictions
local function daoError(state, arguments)
  local stub_err = DaoError("", "")
  return getmetatable(stub_err) == getmetatable(arguments[1])
end

local say = require("say")
say:set("assertion.daoError.positive", "Expected %s\nto be a DaoError")
say:set("assertion.daoError.negative", "Expected %s\nto not be a DaoError")
assert:register("assertion", "daoError", daoError, "assertion.daoError.positive", "assertion.daoError.negative")

describe("Cassandra", function()
  -- Create a parallel session to verify the dao's behaviour
  local session
  setup(function()
    spec_helper.prepare_db()

    local err
    session, err = cassandra.spawn_session {
      shm = "factory_specs",
      keyspace = configuration.dao_config.keyspace,
      contact_points = configuration.dao_config.contact_points
    }
    assert.falsy(err)
  end)

  teardown(function()
    if session ~= nil then
      session:shutdown()
    end
  end)

  describe("Base DAO", function()
    describe("insert()", function()
      setup(function()
        spec_helper.drop_db()
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should throw an error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.apis:insert()
        end, "Cannot insert a nil element")

        assert.has_error(function()
          dao_factory.apis:insert("")
        end, "Entity to insert must be a table")
      end)
      it("should insert in DB and let the schema validation add generated values", function()
        -- API
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)
        assert.truthy(api.id)
        assert.truthy(api.created_at)
        local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api.id)})
        assert.falsy(err)
        assert.True(#rows == 1)
        assert.equal(api.id, rows[1].id)

        -- API
        api, err = dao_factory.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        }
        assert.falsy(err)
        assert.truthy(api.name)
        assert.equal("test.com", api.name)

        -- Consumer
        local consumer_t = faker:fake_entity("consumer")
        local consumer, err = dao_factory.consumers:insert(consumer_t)
        assert.falsy(err)
        assert.truthy(consumer.id)
        assert.truthy(consumer.created_at)
        rows, err = session:execute("SELECT * FROM consumers WHERE id = ?", {cassandra.uuid(consumer.id)})
        assert.falsy(err)
        assert.True(#rows == 1)
        assert.equal(consumer.id, rows[1].id)

        -- Plugin configuration
        local plugin_t = {name = "key-auth", api_id = api.id}
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)
        local plugins, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.True(#plugins > 0)
        assert.equal(plugin.id, plugins[1].id)
      end)
      it("should let the schema validation return errors and not insert", function()
        -- Without an api_id, it's a schema error
        local plugin_t = faker:fake_entity("plugin")
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.schema)
        assert.equal("api_id is required", err.message.api_id)
      end)
      it("should ensure fields with `unique` are unique", function()
        local api_t = faker:fake_entity("api")

        -- Success
        local _, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)

        -- Failure
        local api, err = dao_factory.apis:insert(api_t)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.unique)
        assert.equal("name already exists with value '"..api_t.name.."'", err.message.name)
        assert.falsy(api)
      end)
      it("should ensure fields with `foreign` are existing", function()
        -- Plugin configuration
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = uuid()

        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.foreign)
        assert.equal("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)
      end)
      it("should do insert checks for entities with `self_check`", function()
        local api, err = dao_factory.apis:insert(faker:fake_entity("api"))
        assert.falsy(err)
        assert.truthy(api.id)

        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = api.id

        -- Success: plugin doesn't exist yet
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        -- Failure: the same plugin is already inserted
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.unique)
        assert.equal("Plugin configuration already exists", err.message)
      end)
    end) -- describe insert()

    describe("count_by_keys()", function()
      setup(function()
        spec_helper.drop_db()

        local err = select(2, session:execute("INSERT INTO apis(id, name) VALUES(uuid(), 'foo')"))
        assert.falsy(err)

        for i = 1, 99 do
          err = select(2, session:execute("INSERT INTO apis(id, name) VALUES(uuid(), 'bar')"))
          assert.falsy(err)
        end
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should return the count of rows in a table", function()
        local count, err = dao_factory.apis:count_by_keys()
        assert.falsy(err)
        assert.equal(100, count)
      end)
      it("should return the count of rows in a table with filter columns", function()
        local count, err = dao_factory.apis:count_by_keys({name = "bar"})
        assert.falsy(err)
        assert.equal(99, count)

        count, err = dao_factory.apis:count_by_keys({name = "test"})
        assert.falsy(err)
        assert.equal(0, count)

        count, err = dao_factory.apis:count_by_keys({name = ""})
        assert.falsy(err)
        assert.equal(0, count)
      end)
      it("should return the count of rows in a table from a given paging_state", function()
        local rows, err = session:execute("SELECT * FROM apis", nil, {page_size = 50})
        assert.falsy(err)

        local paging_state = rows.meta.paging_state
        assert.truthy(paging_state)

        local count, err = dao_factory.apis:count_by_keys(nil, paging_state)
        assert.falsy(err)
        assert.equal(50, count)
      end)
      it("should return a filtered value to know if the query was filtered", function()
        local _, err, filtered = dao_factory.apis:count_by_keys()
        assert.falsy(err)
        assert.False(filtered)

        _, err, filtered = dao_factory.apis:count_by_keys({name = "bar"})
        assert.falsy(err)
        assert.False(filtered)

        _, err, filtered = dao_factory.apis:count_by_keys({name = "bar", request_host = ""})
        assert.falsy(err)
        assert.True(filtered)
      end)
      it("should return errors when query is refused by Cassandra", function()
        local count, err = dao_factory.apis:count_by_keys({upstream_url = ""})
        assert.truthy(err)
        assert.falsy(count)
        assert.is_daoError(err)
      end)
    end)

    describe("update()", function()
      setup(function()
        spec_helper.drop_db()
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should error if called with invalid arguments", function()
        assert.has_error(function()
          dao_factory.apis:update()
        end, "Cannot update a nil element")

        assert.has_error(function()
          dao_factory.apis:update("")
        end, "Entity to update must be a table")
      end)
      it("should return nil and no error if no entity was found to update in DB", function()
        local api_t = faker:fake_entity("api")
        api_t.id = uuid()

        -- No entity to update
        local entity, err = dao_factory.apis:update(api_t)
        assert.equal(nil, entity)
        assert.falsy(err)
      end)
      it("should consider no entity to be found if an empty table is given to it", function()
        local api, err = dao_factory.apis:update {}
        assert.falsy(err)
        assert.falsy(api)
      end)
      it("should update an entity's non primary fields", function()
        local UUID = uuid()

        -- API
        local api_t = {
          id = UUID,
          name = "mockbin"
        }
        local _, err = session:execute("INSERT INTO apis(id, name) VALUES(?, ?)", {cassandra.uuid(api_t.id), api_t.name})
        assert.falsy(err)

        api_t.name = api_t.name.."-updated"

        local api, err = dao_factory.apis:update(api_t)
        assert.falsy(err)
        assert.truthy(api)
        assert.equal("mockbin-updated", api.name)

        local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api.id)})
        assert.falsy(err)
        assert.equal(1, #rows)
        assert.equal(api_t.id, rows[1].id)
        assert.equal(api_t.name, rows[1].name)
        assert.equal(api_t.request_host, rows[1].request_host)
        assert.equal(api_t.upstream_url, rows[1].upstream_url)

        -- Consumer
        local consumer_t = {
          id = UUID,
          username = "john"
        }
        _, err = session:execute("INSERT INTO consumers(id, username) VALUES(?, ?)", {
          cassandra.uuid(consumer_t.id),
          consumer_t.username
        })
        assert.falsy(err)

        consumer_t.username = consumer_t.username.."-updated"

        local consumer, err = dao_factory.consumers:update(consumer_t)
        assert.falsy(err)
        assert.truthy(consumer)
        assert.equal("john-updated", consumer.username)

        rows, err = session:execute("SELECT * FROM consumers WHERE id = ?", {cassandra.uuid(consumer_t.id)})
        assert.falsy(err)
        assert.equal(1, #rows)
        assert.equal(consumer_t.name, rows[1].name)

        -- Plugin Configuration
        local plugin_t = {
          id = UUID,
          api_id = UUID,
          name = "key-auth",
          enabled = true
        }
        _, err = session:execute("INSERT INTO plugins(id, api_id, name, enabled) VALUES(?, ?, ?, ?)", {
          cassandra.uuid(plugin_t.id),
          cassandra.uuid(plugin_t.api_id),
          plugin_t.name,
          plugin_t.enabled
        })
        assert.falsy(err)

        plugin_t.enabled = false

        local plugin, err = dao_factory.plugins:update(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)
        assert.False(plugin.enabled)

        rows, err = session:execute("SELECT * FROM plugins WHERE id = ?", {cassandra.uuid(plugin_t.id)})
        assert.falsy(err)
        assert.equal(1, #rows)
        assert.False(rows[1].enabled)
      end)
      describe("with `where_t` argument", function()
        local UUID = uuid()
        before_each(function()
          local _, err = session:execute("INSERT INTO apis(id, name, request_host, upstream_url) VALUES(?, ?, ?, ?)", {
            cassandra.uuid(UUID),
            "to-update",
            "to-update.com",
            "http://mockbin.com"
          })
          assert.falsy(err)

          _, err = session:execute("INSERT INTO apis(id, name) VALUES(uuid(), 'to-not-update')")
          assert.falsy(err)
          _, err = session:execute("INSERT INTO apis(id, name) VALUES(uuid(), 'to-not-update')")
          assert.falsy(err)
        end)
        after_each(function()
          spec_helper.drop_db()
        end)
        it("should be possible to pass a `where_t` with primary key as an argument", function()
          local res, err = dao_factory.apis:update({name = "updated"}, false, {id = UUID})
          assert.falsy(err)
          assert.truthy(res)

          local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(UUID)})
          assert.falsy(err)
          assert.truthy(rows[1])
          assert.equal("updated", rows[1].name)
        end)
        it("should be possible to pass a `where_t` with non primary fields as an argument", function()
          local res, err = dao_factory.apis:update({name = "updated"}, false, {name = "to-update"})
          assert.falsy(err)
          assert.truthy(res)

          local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(UUID)})
          assert.falsy(err)
          assert.truthy(rows[1])
          assert.equal("updated", rows[1].name)
        end)
        it("should not perform an update if more than one entity was found from the `where_t` argument", function()
          local res, err = dao_factory.apis:update({name = "updated"}, false, {name = "to-not-update"})
          assert.falsy(err)
          assert.falsy(res)

          local rows, err = session:execute("SELECT * FROM apis WHERE name = ?", {"to-not-update"})
          assert.falsy(err)
          assert.equal(2, #rows)
        end)
      end)

      describe("edge-cases with an entity", function()
        local api_t
        before_each(function()
          api_t = {
            id = uuid(),
            name = "mockbin",
            created_at = 1450519058000,
            upstream_url = "http://mockbin.com",
            request_path = "/request_path",
            request_host = "host.com"
          }
          local _, err = session:execute("INSERT INTO apis(id, created_at, name, upstream_url, request_path, request_host) VALUES(?, ?, ?, ?, ?, ?)", {
            cassandra.uuid(api_t.id),
            cassandra.timestamp(api_t.created_at),
            api_t.name,
            api_t.upstream_url,
            api_t.request_path,
            api_t.request_host
          })
          assert.falsy(err)
        end)
        after_each(function()
          session:execute("TRUNCATE apis")
        end)
        it("should return the complete updated entity when the argument entity is partial", function()
          api_t.name = "updated"
          -- Only passing a subset of the entity to update()
          local api, err = dao_factory.apis:update {
            id = api_t.id,
            name = api_t.name
          }
          assert.falsy(err)
          assert.truthy(api)
          assert.same(api_t, api)
        end)
        it("should ensure fields with `unique` are unique", function()
          local UUID_bis = uuid()

          local _, err = session:execute("INSERT INTO apis(id, request_host) VALUES(?, ?)", {
            cassandra.uuid(UUID_bis),
            "host2.com"
          })
          assert.falsy(err)

          local api, err = dao_factory.apis:update {
            id = UUID_bis,
            request_host = api_t.request_host
          }
          assert.truthy(err)
          assert.falsy(api)
          assert.is_daoError(err)
          assert.True(err.unique)
          assert.equal("request_host already exists with value 'host.com'", err.message.request_host)

          local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(UUID_bis)})
          assert.falsy(err)
          assert.equal("host2.com", rows[1].request_host)
        end)
        it("should return an error if trying to update `immutable` fields", function()
          local rows, err = session:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.equal(api_t.created_at, rows[1].created_at)

          local api, err = dao_factory.apis:update {
            id = api_t.id,
            created_at = 123
          }
          assert.truthy(err)
          assert.falsy(api)
          assert.is_daoError(err)
          assert.True(err.schema)
          assert.equal("created_at cannot be updated", err.message.created_at)

          rows, err = session:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.equal(api_t.created_at, rows[1].created_at)
        end)
        describe("full update", function()
          it("should set a column to CQL `null` if a field is not specified", function()
            -- Verify the column is set
            local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api_t.id)})
            assert.falsy(err)
            assert.equal(1, #rows)
            assert.equal("/request_path", rows[1].request_path)

            -- Update
            api_t.request_path = nil
            local api, err = dao_factory.apis:update(api_t, true)
            assert.falsy(err)
            assert.truthy(api)
            assert.falsy(api.request_path)

            rows, err = dao_factory.apis:find_by_keys {id = api_t.id}
            assert.falsy(err)
            assert.truthy(rows)
            assert.falsy(rows[1].request_path)

            -- Check update
            rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api_t.id)})
            assert.falsy(err)
            assert.falsy(rows[1].request_path)
          end)
          it("should still check the validity of the schema", function()
            -- Update with invalid value
            api_t.upstream_url = nil
            local api, err = dao_factory.apis:update(api_t, true)
            assert.truthy(err)
            assert.falsy(api)
            assert.equal("upstream_url is required", err.message.upstream_url)

            -- Check update failed
            local rows, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api_t.id)})
            assert.falsy(err)
            assert.equal("http://mockbin.com", rows[1].upstream_url)
          end)
          it("should still select defaults when entity is incomplete", function()
            local plugin, err = dao_factory.plugins:insert {
              name = "key-auth",
              api_id = api_t.id,
              config = {hide_credentials = true}
            }
            assert.falsy(err)
            assert.same({"apikey"}, plugin.config.key_names)
            assert.True(plugin.config.hide_credentials)

            plugin, err = dao_factory.plugins:update({
              name = "key-auth",
              id = plugin.id,
              api_id = api_t.id
            }, true)
            assert.falsy(err)
            assert.same({"apikey"}, plugin.config.key_names)
            assert.False(plugin.config.hide_credentials)
          end)
          it("should return an error if trying to update `immutable` fields", function()
            api_t.created_at = 123
            api_t.name = "updated"
            local api, err = dao_factory.apis:update(api_t, true)
            assert.truthy(err)
            assert.falsy(api)
            assert.is_daoError(err)
            assert.True(err.schema)
            assert.equal("created_at cannot be updated", err.message.created_at)
          end)
        end)
      end)
    end) -- describe update()

    describe("find_by_keys()", function()
      setup(function()
        spec_helper.drop_db()

        local err = select(2, session:execute("INSERT INTO apis(id, request_host, upstream_url) VALUES(uuid(), 'foo.com', 'http://foo.com')"))
        assert.falsy(err)

        for i = 1, 99 do
          err = select(2, session:execute("INSERT INTO apis(id, request_host, upstream_url) VALUES(uuid(), 'foo.com', 'http://bar.com')"))
          assert.falsy(err)
        end
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.apis:find_by_keys("")
        end, "where_t must be a table")
      end)
      it("should handle empty search fields", function()
        local apis, err = dao_factory.apis:find_by_keys({})
        assert.falsy(err)
        assert.truthy(apis)
        assert.True(#apis > 0)
      end)
      it("should handle nil search fields", function()
        local apis, err = dao_factory.apis:find_by_keys(nil)
        assert.falsy(err)
        assert.truthy(apis)
        assert.True(#apis > 0)
      end)
      it("should query an entity from the given fields and return if filtering was needed", function()
        -- No filtering needed
        local apis, err, needs_filtering = dao_factory.apis:find_by_keys {
          request_host = 'foo.com',
        }
        assert.falsy(err)
        assert.equal(100, #apis)
        assert.False(needs_filtering)

        -- Filtering needed
        apis, err, needs_filtering = dao_factory.apis:find_by_keys {
          request_host = 'foo.com',
          upstream_url = 'http://foo.com'
        }
        assert.falsy(err)
        assert.equal(1, #apis)
        assert.True(needs_filtering)
      end)
    end) -- describe find_by_keys()

    describe("find()", function()
      setup(function()
        spec_helper.drop_db()
        spec_helper.seed_db(10)
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      describe_core_collections(function(type, collection)
        it("should find entities", function()
          local entities, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local results, err = dao_factory[collection]:find()
          assert.falsy(err)
          assert.truthy(results)
          assert.same(#entities, #results)
        end)

        it("should allow pagination", function()
          -- 1st page
          local rows_1, err = dao_factory[collection]:find(2)
          assert.falsy(err)
          assert.truthy(rows_1)
          assert.same(2, #rows_1)
          assert.truthy(rows_1.next_page)

          -- 2nd page
          local rows_2, err = dao_factory[collection]:find(2, rows_1.next_page)
          assert.falsy(err)
          assert.truthy(rows_2)
          assert.same(2, #rows_2)
        end)
      end)
    end) -- describe find()

    describe("find_by_primary_key()", function()
      local api_t = {
        id = uuid(),
        name = "mockbin"
      }
      setup(function()
        spec_helper.drop_db()
        local err = select(2, session:execute("INSERT INTO apis(id, name) VALUES(?, ?)", {
          cassandra.uuid(api_t.id),
          api_t.name
        }))
        assert.falsy(err)
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.apis:find_by_primary_key("")
        end, "where_t must be a table")
      end)
      it("should return nil (not found) if where_t is empty", function()
        local res, err = dao_factory.apis:find_by_primary_key {}
        assert.falsy(err)
        assert.falsy(res)
      end)
      it("should find one entity by its primary key", function()
        local api, err = dao_factory.apis:find_by_primary_key {id = api_t.id}
        assert.falsy(err)
        assert.truthy(api)
        assert.same(api_t, api)
      end)
      it("should handle an invalid uuid value", function()
        local api, err = dao_factory.apis:find_by_primary_key {id = "abcd"}
        assert.falsy(api)
        assert.True(err.invalid_type)
        assert.equal("abcd is an invalid uuid", err.message.id)
      end)

      describe("plugins", function()
        local plugin_t = {
          id = uuid(),
          name = "key-auth",
          api_id = api_t.id,
          config = [[{"key_names": ["test_key"]}]]
        }
        setup(function()
          local err = select(2, session:execute("INSERT INTO plugins(id, api_id, name, config) VALUES(?, ?, ?, ?)", {
            cassandra.uuid(plugin_t.id),
            cassandra.uuid(plugin_t.api_id),
            plugin_t.name,
            plugin_t.config
          }))
          assert.falsy(err)
        end)
        it("should unmarshall the `config` field", function()
          local plugin, err = dao_factory.plugins:find_by_primary_key {
            id = plugin_t.id,
            name = plugin_t.name
          }
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal("table", type(plugin.config))
        end)
      end)
    end) -- describe find_by_primary_key()

    describe("delete()", function()
      setup(function()
        spec_helper.drop_db()
        local _, err = session:execute("INSERT INTO plugins(id, name) VALUES(uuid(), 'some-plugin')")
        assert.falsy(err)
        _, err = session:execute("INSERT INTO consumers(id, username) VALUES(uuid(), 'to-delete')")
        assert.falsy(err)
        _, err = session:execute("INSERT INTO consumers(id, username) VALUES(uuid(), 'to-not-delete')")
        assert.falsy(err)
        _, err = session:execute("INSERT INTO consumers(id, username) VALUES(uuid(), 'to-not-delete')")
        assert.falsy(err)
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      it("should error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.plugins:delete("")
        end, "where_t must be a table")
      end)
      it("should return false if entity to delete wasn't found", function()
        local ok, err = dao_factory.plugins:delete {id = uuid()}
        assert.falsy(err)
        assert.False(ok)
      end)
      it("should delete an entity when given its primary key", function()
        local rows, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.truthy(rows)
        assert.True(#rows > 0)

        local ok, err = dao_factory.plugins:delete(rows[1])
        assert.falsy(err)
        assert.True(ok)
      end)
      it("should delete an entity when it can be found without its primay key", function()
        local ok, err = dao_factory.consumers:delete(nil, {
          username = "to-delete"
        })
        assert.falsy(err)
        assert.True(ok)
      end)
      it("should not delete an entity which can be found without primary key when there are multiple results", function()
        local ok, err = dao_factory.consumers:delete(nil, {
          username = "to-not-delete"
        })
        assert.falsy(err)
        assert.False(ok)

        local rows, err = session:execute("SELECT * FROM consumers WHERE username = 'to-not-delete'")
        assert.falsy(err)
        assert.equal(2, #rows)
      end)
    end)

    --
    -- APIs additional behaviour
    --

    describe("APIs", function()
      setup(function()
        spec_helper.drop_db()
        for i = 1, 100 do
          local err = select(2, session:execute("INSERT INTO apis(id, name) VALUES(uuid(), 'mockbin')"))
          assert.falsy(err)
        end
      end)
      teardown(function()
        spec_helper.drop_db()
      end)

      describe(":find_all()", function()
        it("should retrieve all APIs", function()
          local apis, err = dao_factory.apis:find_all()
          assert.falsy(err)
          assert.truthy(apis)
          assert.equal(100, #apis)
        end)
      end)
    end)

    --
    -- Nodes tests
    --

    describe("Nodes", function()

      setup(function()
        spec_helper.drop_db()
        spec_helper.seed_db(100)
      end)

      describe(":insert()", function()
        local node, err = dao_factory.nodes:insert({
          cluster_listening_address = "wot.hello.com:1111",
          name = "wot"
        })
        assert.falsy(err)
        assert.truthy(node)
        assert.equal("wot.hello.com:1111", node.cluster_listening_address)
      end)

      describe(":find_by_keys() and :delete()", function()
        local nodes, err = dao_factory.nodes:find_by_keys({
          cluster_listening_address = "wot.hello.com:1111"
        })

        assert.falsy(err)
        assert.truthy(nodes)
        assert.equal(1, #nodes)

        local ok, err = dao_factory.nodes:delete({
          name = table.remove(nodes, 1).name
        })

        assert.True(ok)
        assert.falsy(err)
      end)

      describe(":find_all()", function()
        local nodes, err = dao_factory.nodes:find_all()
        assert.falsy(err)
        assert.truthy(nodes)
        assert.equal(100, #nodes)
      end)

    end)

    --
    -- Plugins configuration additional behaviour
    --

    describe("plugins", function()
      setup(function()
        spec_helper.drop_db()
        faker:insert_from_table {
          api = {
            {name = "tests-distinct-1", request_host = "foo.com", upstream_url = "http://mockbin.com"},
            {name = "tests-distinct-2", request_host = "bar.com", upstream_url = "http://mockbin.com"}
          },
          plugin = {
            {name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 1},
            {name = "rate-limiting", config = { minute = 6}, __api = 1},
            {name = "rate-limiting", config = { minute = 6}, __api = 2},
            {name = "file-log", config = { path = "/tmp/spec.log" }, __api = 1}
          }
        }
      end)
      teardown(function()
        spec_helper.drop_db()
      end)
      describe("find_distinct()", function()
        it("should find distinct plugins configurations", function()
          local res, err = dao_factory.plugins:find_distinct()
          assert.falsy(err)
          assert.truthy(res)

          assert.equal(3, #res)
          assert.truthy(utils.table_contains(res, "key-auth"))
          assert.truthy(utils.table_contains(res, "rate-limiting"))
          assert.truthy(utils.table_contains(res, "file-log"))
        end)
      end)

      describe("insert()", function()
        local api_id
        local inserted_plugin
        it("should insert a plugin and set the consumer_id to a 'null' uuid if none is specified", function()
          -- Since we want to specifically select plugins configurations which have _no_ consumer_id sometimes, we cannot rely on using
          -- NULL (and thus, not inserting the consumer_id column for the row). To fix this, we use a predefined, nullified uuid...

          -- Create an API
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)

          local plugin_t = faker:fake_entity("plugin")
          plugin_t.api_id = api.id

          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.falsy(plugin.consumer_id)

          -- for next test
          api_id = api.id
          inserted_plugin = plugin
          inserted_plugin.consumer_id = nil
        end)
        it("should insert a plugin with an default config if none is specified", function()
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api)

          local plugin, err = dao_factory.plugins:insert {
            name = "request-transformer",
            api_id = api.id
          }

          assert.falsy(err)
          assert.truthy(plugin)
          assert.falsy(plugin.consumer_id)
          assert.equal("request-transformer", plugin.name)
          assert.same({
            add = {
              body = {},
              headers = {},
              querystring = {}
            },
            append = {
              body = {},
              headers = {},
              querystring = {}
            },
            remove = {
              body = {},
              headers = {},
              querystring = {}
            },
            replace = {
              body = {},
              headers = {},
              querystring = {}
            }
          }, plugin.config)
        end)
        it("should select a plugin configuration by 'null' uuid consumer_id and remove the column", function()
          -- Now we should be able to select this plugin
          local rows, err = dao_factory.plugins:find_by_keys {
            api_id = api_id,
            consumer_id = constants.DATABASE_NULL_ID
          }
          assert.falsy(err)
          assert.truthy(rows[1])
          assert.same(inserted_plugin, rows[1])
          assert.falsy(rows[1].consumer_id)
        end)
      end)
    end) -- describe plugins configurations
  end) -- describe Base DAO
end) -- describe Cassandra