local pg_strategy = require "kong.counters.sales.strategies.postgres"
local utils       = require "kong.tools.utils"
local helpers     = require "spec.helpers"

local LICENSE_DATA_TNAME = "license_data"
local license_creation_date = "2019-03-03"


for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("Postgres strategy", function()
    local strategy
    local db
    local snapshot


    setup(function()
      db = select(2, helpers.get_db_utils(strategy))
      strategy = pg_strategy:new(db)
      db = db.connector
    end)


    before_each(function()
      snapshot = assert:snapshot()

      assert(db:query("truncate table " .. LICENSE_DATA_TNAME))
    end)


    after_each(function()
      snapshot:revert()
    end)


    teardown(function()
      assert(db:query("truncate table " .. LICENSE_DATA_TNAME))
    end)

    describe(":insert_stats()", function()
      it("should flush data to cassandra from one node", function()
        local data = {
          request_count = 10,
          license_creation_date = license_creation_date,
          node_id = utils.uuid()
        }

        strategy:flush_data(data)

        local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

        local expected_data = {
          node_id  = data.node_id,
          license_creation_date = license_creation_date .. " 00:00:00",
          req_cnt = 10
        }

        assert.same(expected_data, res[1])
      end)

      it("should flush data to cassandra with more than one row from node", function()
        local data = {
          request_count = 10,
          license_creation_date = license_creation_date,
          node_id = utils.uuid()
        }

        strategy:flush_data(data)

        local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

        local expected_data = {
          node_id  = data.node_id,
          license_creation_date = license_creation_date .. " 00:00:00",
          req_cnt = 10
        }

        assert.same(expected_data, res[1])

        local data = {
          request_count = 269,
          license_creation_date = license_creation_date,
          node_id = data.node_id
        }

        strategy:flush_data(data)

        res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

        local expected_data = {
          node_id  = data.node_id,
          license_creation_date = license_creation_date .. " 00:00:00",
          req_cnt = 279
        }

        assert.same(expected_data, res[1])
      end)

      it("should flush data to cassandra from more than one node", function()
        local data = {
          request_count = 10,
          license_creation_date = license_creation_date,
          node_id = utils.uuid()
        }

        strategy:flush_data(data)

        local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

        local expected_data = {
          node_id  = data.node_id,
          license_creation_date = license_creation_date .. " 00:00:00",
          req_cnt = 10
        }

        assert.same(expected_data, res[1])

        local data = {
          request_count = 58,
          license_creation_date = license_creation_date,
          node_id = utils.uuid()
        }

        strategy:flush_data(data)

        res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

        local expected_data = {
          node_id  = data.node_id,
          license_creation_date = license_creation_date .. " 00:00:00",
          req_cnt = 58
        }

        assert.same(expected_data, res[1])
      end)
    end)
  end)
end
