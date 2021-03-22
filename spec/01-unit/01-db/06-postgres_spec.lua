local config = {
  pg_database = "kong"
}


local Schema = require "kong.db.schema"
local connector = require "kong.db.strategies.postgres.connector".new(config)


describe("kong.db [#postgres] connector", function()
  describe(":infos()", function()
    it("returns infos db_ver always with two digit groups divided with dot (.)", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      local infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_version = 9, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "10.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "10.5",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when missing major_minor_version", function()
      local infos = connector.infos{ major_version = 9, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_version = 10, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when invalid major_minor_version", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)

      infos = connector.infos{ major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = false,
      }, infos)
    end)

    it("returns db_readonly = true when readonly connection is enabled", function()
      local infos = connector.infos{ config = config, config_ro = config, }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
        db_readonly = true,
      }, infos)
    end)
  end)

  describe(":query() semaphore", function()
    describe("max 1", function()
      -- connector in a new scope
      local connector

      setup(function()
        local new_config = {
          pg_database = "kong",
          pg_max_concurrent_queries = 1,
          pg_semaphore_timeout = 1000,
        }

        connector = require "kong.db.strategies.postgres.connector".new(new_config)

        connector.get_stored_connection = function()
          return {
            query = function(_, s) ngx.sleep(s) end
          }
        end
      end)

      it("functions as a mutex", function()
        local errors = {}

        local co1 = ngx.thread.spawn(function()
          local _, err = connector:query(0.001)
          if err then
            table.insert(errors, err)
          end
        end)

        local co2 = ngx.thread.spawn(function()
          local _, err = connector:query(0.001)
          if err then
            table.insert(errors, err)
          end
        end)

        ngx.thread.wait(co2)
        ngx.thread.wait(co1)

        assert.same(0, #errors)
      end)

      it("times out failing to acquire a lock", function()
        local errors = {}

        local co1 = ngx.thread.spawn(function()
          local _, err = connector:query(1)
          if err then
            table.insert(errors, err)
          end
        end)

        local co2 = ngx.thread.spawn(function()
          local _, err = connector:query(0.1)
          if err then
            table.insert(errors, err)
          end
        end)

        ngx.thread.wait(co2)
        ngx.thread.wait(co1)

        assert.same(1, #errors)
      end)
    end)

    describe("max more than 1", function()
      -- connector in a new scope
      local connector

      setup(function()
        local new_config = {
          pg_database = "kong",
          pg_max_concurrent_queries = 2,
          pg_semaphore_timeout = 100,
        }

        connector = require "kong.db.strategies.postgres.connector".new(new_config)

        connector.get_stored_connection = function()
          return {
            query = function(_, s) ngx.sleep(s) end
          }
        end
      end)

      it("allows multiple functions to run concurrently", function()
        local errors = {}

        local co1 = ngx.thread.spawn(function()
          local _, err = connector:query(0.001)
          if err then
            table.insert(errors, err)
          end
        end)

        local co2 = ngx.thread.spawn(function()
          local _, err = connector:query(0.001)
          if err then
            table.insert(errors, err)
          end
        end)

        ngx.thread.wait(co2)
        ngx.thread.wait(co1)

        assert.same(0, #errors)
      end)

      it("times out failing to acquire a lock", function()
        local errors = {}

        local co1 = ngx.thread.spawn(function()
          local _, err = connector:query(1)
          if err then
            table.insert(errors, err)
          end
        end)

        local co2 = ngx.thread.spawn(function()
          local _, err = connector:query(0.1)
          if err then
            table.insert(errors, err)
          end
        end)

        local co3 = ngx.thread.spawn(function()
          local _, err = connector:query(0.1)
          if err then
            table.insert(errors, err)
          end
        end)

        ngx.thread.wait(co3)
        ngx.thread.wait(co2)
        ngx.thread.wait(co1)

        assert.same(1, #errors)
      end)
    end)
  end)

  describe("connector.get_topologically_sorted_table_names", function()
    local function schema_new(s)
      return { schema = assert(Schema.new(s)) }
    end

    local ts = connector._get_topologically_sorted_table_names

    it("prepends cluster_events no matter what", function()
      assert.same({"cluster_events"},  ts({}))
    end)

    it("sorts an array of unrelated schemas alphabetically by name", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local b = schema_new({ name = "b", ttl = true, fields = {} })
      local c = schema_new({ name = "c", ttl = true, fields = {} })

      assert.same({"cluster_events", "a", "b", "c"},  ts({ c, a, b }))
    end)

    it("ignores non-ttl schemas", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local b = schema_new({ name = "b", fields = {} })
      local c = schema_new({ name = "c", ttl = true, fields = {} })

      assert.same({"cluster_events", "a", "c"},  ts({ c, a, b }))
    end)

    it("it puts destinations first", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local c = schema_new({
        name = "c",
        ttl = true,
        fields = {
          { a = { type = "foreign", reference = "a" }, },
        }
      })
      local b = schema_new({
        name = "b",
        ttl = true,
        fields = {
          { a = { type = "foreign", reference = "a" }, },
          { c = { type = "foreign", reference = "c" }, },
        }
      })

      assert.same({"cluster_events", "a", "c", "b"},  ts({ a, b, c }))
    end)

    it("puts core entities first, even when no relations", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local routes = schema_new({ name = "routes", ttl = true, fields = {} })

      assert.same({"cluster_events", "routes", "a"},  ts({ a, routes }))
    end)

    it("puts workspaces before core and others, when no relations", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local workspaces = schema_new({ name = "workspaces", ttl = true, fields = {} })
      local routes = schema_new({ name = "routes", ttl = true, fields = {} })

      assert.same({"cluster_events", "workspaces", "routes", "a"},  ts({ a, routes, workspaces }))
    end)

    it("puts workspaces first, core entities second, and other entities afterwards, even with relations", function()
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local services = schema_new({ name = "services", ttl = true, fields = {} })
      local b = schema_new({
        name = "b",
        ttl = true,
        fields = {
          { service = { type = "foreign", reference = "services" }, },
          { a = { type = "foreign", reference = "a" }, },
        }
      })
      local routes = schema_new({
        name = "routes",
        ttl = true,
        fields = {
          { service = { type = "foreign", reference = "services" }, },
        }
      })
      local workspaces = schema_new({ name = "workspaces", ttl = true, fields = {} })
      assert.same({ "cluster_events", "workspaces", "services", "routes", "a", "b" },
                  ts({ services, b, a, workspaces, routes }))
    end)

    it("overrides core order if dependencies force it", function()
      -- This scenario is here in case in the future we allow plugin entities to precede core entities
      -- Not applicable today (kong 2.3.x) but maybe in future releases
      local a = schema_new({ name = "a", ttl = true, fields = {} })
      local services = schema_new({ name = "services", ttl = true, fields = {
        { a = { type = "foreign", reference = "a" } } -- we somehow forced services to depend on a
      }})
      local workspaces = schema_new({ name = "workspaces", ttl = true, fields = {
        { a = { type = "foreign", reference = "a" } } -- we somehow forced workspaces to depend on a
      } })

      assert.same({ "cluster_events", "a", "workspaces", "services" },  ts({ services, a, workspaces }))
    end)

    it("returns an error if cycles are found", function()
      local a = schema_new({
        name = "a",
        ttl = true,
        fields = {
          { b = { type = "foreign", reference = "b" }, },
        }
      })
      local b = schema_new({
        name = "b",
        ttl = true,
        fields = {
          { a = { type = "foreign", reference = "a" }, },
        }
      })
      local x, err = ts({ a, b })
      assert.is_nil(x)
      assert.equals("Cycle detected, cannot sort topologically", err)
    end)
  end)
end)
