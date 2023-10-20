-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pg_strategy = require "kong.enterprise_edition.counters.sales.strategies.postgres"
local utils       = require "kong.tools.utils"
local helpers     = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

local LICENSE_DATA_TNAME = "license_data"
local license_creation_date = "2019-03-03"

local current_date = tostring(os.date("%Y-%m-%d"))
local current_year = tonumber(os.date("%Y"))
local current_month = tonumber(os.date("%m"))
local license_strategies = {
  "licensed",
  "unlicensed",
}

local function get_license_creation_date(license_strategy)
  if license_strategy == "licensed" then
    return license_creation_date
  end

  return current_date
end

local ffi = require('ffi')
ffi.cdef([[
  int unsetenv(const char* name);
]])

for _, strategy in helpers.each_strategy({"postgres"}) do
  for _, license_strategy in ipairs(license_strategies) do
    describe("Sales counters strategy #" .. strategy .. " for #" .. license_strategy .. " Kong", function()
      local strategy
      local db
      local snapshot


      setup(function()
        if license_strategy == license_strategies.unlicensed then
          ffi.C.unsetenv("KONG_LICENSE_DATA")
          ffi.C.unsetenv("KONG_LICENSE_PATH")
        end

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
        it("should flush data to postgres from one node", function()
          local data = {
            request_count = 10,
            license_creation_date = get_license_creation_date(license_strategy),
            node_id = utils.uuid()
          }

          strategy:flush_data(data)

          local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

          local expected_data = {
            node_id  = data.node_id,
            license_creation_date = get_license_creation_date(license_strategy) .. " 00:00:00",
            req_cnt = 10,
            year = current_year,
            month = current_month,
          }

          assert.same(expected_data.node_id, res[1].node_id)
          assert.same(expected_data.license_creation_date, res[1].license_creation_date)
          assert.same(expected_data.req_cnt, res[1].req_cnt)
          assert.same(expected_data.year, res[1].year)
          assert.same(expected_data.month, res[1].month)
        end)

        it("should flush data to postgres with more than one row from node", function()
          local data = {
            request_count = 10,
            license_creation_date = get_license_creation_date(license_strategy),
            node_id = utils.uuid()
          }

          strategy:flush_data(data)

          local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

          local expected_data = {
            node_id  = data.node_id,
            license_creation_date = get_license_creation_date(license_strategy) .. " 00:00:00",
            req_cnt = 10,
            year = current_year,
            month = current_month,
          }

          assert.same(expected_data.node_id, res[1].node_id)
          assert.same(expected_data.license_creation_date, res[1].license_creation_date)
          assert.same(expected_data.req_cnt, res[1].req_cnt)
          assert.same(expected_data.year, res[1].year)
          assert.same(expected_data.month, res[1].month)

          local data = {
            request_count = 269,
            license_creation_date = get_license_creation_date(license_strategy),
            node_id = data.node_id
          }

          strategy:flush_data(data)

          res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

          local expected_data = {
            node_id  = data.node_id,
            license_creation_date = get_license_creation_date(license_strategy) .. " 00:00:00",
            req_cnt = 279,
            year = current_year,
            month = current_month,
          }

          assert.same(expected_data.node_id, res[1].node_id)
          assert.same(expected_data.license_creation_date, res[1].license_creation_date)
          assert.same(expected_data.req_cnt, res[1].req_cnt)
          assert.same(expected_data.year, res[1].year)
          assert.same(expected_data.month, res[1].month)
        end)

        it("should flush data to postgres from more than one node", function()
          local data = {
            request_count = 10,
            license_creation_date = get_license_creation_date(license_strategy),
            node_id = utils.uuid()
          }

          strategy:flush_data(data)

          local res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

          local expected_data = {
            node_id  = data.node_id,
            license_creation_date = get_license_creation_date(license_strategy) .. " 00:00:00",
            req_cnt = 10,
            year = current_year,
            month = current_month,
          }

          assert.same(expected_data.node_id, res[1].node_id)
          assert.same(expected_data.license_creation_date, res[1].license_creation_date)
          assert.same(expected_data.req_cnt, res[1].req_cnt)
          assert.same(expected_data.year, res[1].year)
          assert.same(expected_data.month, res[1].month)

          local data = {
            request_count = 58,
            license_creation_date = get_license_creation_date(license_strategy),
            node_id = utils.uuid()
          }

          strategy:flush_data(data)

          res, _ = db:query("select * from " .. LICENSE_DATA_TNAME .. " WHERE node_id = '" .. tostring(data.node_id) .. "'")

          local expected_data = {
            node_id  = data.node_id,
            license_creation_date = get_license_creation_date(license_strategy) .. " 00:00:00",
            req_cnt = 58,
            year = current_year,
            month = current_month,
          }

          assert.same(expected_data.node_id, res[1].node_id)
          assert.same(expected_data.license_creation_date, res[1].license_creation_date)
          assert.same(expected_data.req_cnt, res[1].req_cnt)
          assert.same(expected_data.year, res[1].year)
          assert.same(expected_data.month, res[1].month)
        end)
      end)
    end)
  end

  describe("should GET the license report", function()
    local client, reset_distribution

    lazy_setup(function()
      reset_distribution = setup_distribution()
      helpers.unsetenv("KONG_LICENSE_DATA")

      assert(conf_loader(nil, {
        plugins = "bundled,aws-lambda,kafka-upstream",
      }))

      local _, db = helpers.get_db_utils(strategy, {
        "workspaces",
        "routes",
        "services",
        "plugins",
        "licenses",
        "workspace_entity_counters",
      }, { "aws-lambda", "kafka-upstream" })


      local service1 = db.services:insert {
        name = "service-1",
        host = "example.com",
        protocol = "http",
        port = 80,
      }

      local route1 = db.routes:insert {
        hosts   = { "lambda1.com" },
        service = service1,
      }

      local route2 = db.routes:insert {
        hosts       = { "lambda2.com" },
        service     = null,
      }

      local route3 = db.routes:insert {
        hosts       = { "lambda3.com" },
        service     = null,
      }

      db.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "kongLambdaTest",
          invocation_type = "Event",
        },
      }

      db.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route2.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "kongLambdaTest",
          invocation_type = "Event",
        },
      }

      db.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route3.id },
        config   = {
          port            = 10001,
          aws_key         = "mock-key",
          aws_secret      = "mock-secret",
          aws_region      = "us-east-1",
          function_name   = "kongLambdaTest",
          invocation_type = "Event",
        },
      }

      db.plugins:insert {
        name = "kafka-upstream",
        route = { id = route1.id },
        config = {
          bootstrap_servers = { { host = "mock-host", port = 9092 } },
          producer_async = false,
          topic = 'sync_topic',
        }
      }

      db.plugins:insert {
        name = "kafka-upstream",
        route = { id = route2.id },
        config = {
          bootstrap_servers = { { host = "mock-host", port = 9092 } },
          producer_async = false,
          topic = 'sync_topic',
        }
      }

      db.plugins:insert {
        name = "kafka-upstream",
        route = { id = route3.id },
        config = {
          bootstrap_servers = { { host = "mock-host", port = 9092 } },
          producer_async = false,
          topic = 'sync_topic',
        }
      }

      local default_workspace = db.workspaces:select_by_name("default")

      db.workspace_entity_counters:insert {
        workspace_id = default_workspace.id,
        entity_type = "services",
        count = 1,
      }

      db.workspace_entity_counters:insert {
        workspace_id = default_workspace.id,
        entity_type = "routes",
        count = 3,
      }

      db.workspace_entity_counters:insert {
        workspace_id = default_workspace.id,
        entity_type = "plugins",
        count = 6,
      }

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,aws-lambda,kafka-upstream",
        license_path = "spec-ee/fixtures/mock_license.json",
      })
      client = helpers.admin_client(10000)
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    it("/license/report response", function()
      local res, err = client:send({
        method = "GET",
        path = "/license/report",
      })

      assert.is_nil(err)
      assert.res_status(200, res)

      local report = assert.response(res).has.jsonbody()

      assert.not_nil(report.license.license_key, "missing license_key")
      assert.not_nil(report.license.license_expiration_date, "missing license_expiration_date")
      assert.not_nil(report.timestamp, "missing timestamp")
      assert.not_nil(report.checksum, "missing checksum")
      assert.not_nil(report.deployment_info, "missing deployment_info")
      assert.not_nil(report.plugins_count, "missing plugins_count")
      assert.equals(1, report.services_count)
      assert.equals(3, report.routes_count)
      assert.equals(1, report.plugins_count.unique_route_lambdas)
      assert.equals(1, report.plugins_count.unique_route_kafkas)
      assert.equals(3, report.plugins_count.tiers.enterprise["kafka-upstream"])
      assert.equals(3, report.plugins_count.tiers.free["aws-lambda"])
    end)
  end)
end
