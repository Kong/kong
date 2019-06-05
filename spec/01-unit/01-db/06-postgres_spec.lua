local config = {
  pg_database = "kong"
}


local connector = require "kong.db.strategies.postgres.connector".new(config)


describe("kong.db [#postgres] connector", function()
  describe(":infos()", function()
    it("returns infos db_ver always with two digit groups divided with dot (.)", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      local infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 9, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 9.5, major_minor_version = "9.5.1", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "9.5",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "10.5", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "10.5",
        strategy = "PostgreSQL",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when missing major_minor_version", function()
      local infos = connector.infos{ major_version = 9, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)
    end)

    it("returns infos with db_ver as \"unknown\" when invalid major_minor_version", function()
      local infos = connector.infos{ major_version = 9, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_version = 10, major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
      }, infos)

      infos = connector.infos{ major_minor_version = "invalid", config = config }
      assert.same({
        db_desc  = "database",
        db_ver   = "unknown",
        strategy = "PostgreSQL",
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
end)
