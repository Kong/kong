-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local client
local db

local function run_kong(cmd, env)
  env = env or {}
  env.database = "postgres"
  env.plugins = env.plugins or "off"

  local cmdline = cmd .. " -c " .. helpers.test_conf_path
  local _, code, stdout, stderr = helpers.kong_exec(cmdline, env, true)
  return code, stdout, stderr
end

local function compare_all_field(src, expected)
  for k, t in pairs(src) do
    for k_2, v in pairs(t) do
      assert.same(v, expected[k][k_2])
    end
  end
end

for _, strategy in helpers.each_strategy() do
  describe("consumer groups entity #" .. strategy, function()
    lazy_setup(function()
      if strategy == "postgres" then
        assert(run_kong('migrations reset --yes'))
        assert(run_kong('migrations bootstrap'))
      end

      _, db = helpers.get_db_utils(strategy)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("#schema and migration", function()
      lazy_setup(function()
        helpers.stop_kong()

        assert(helpers.start_kong({
          database  = strategy,
        }))
        client = assert(helpers.admin_client())

        assert(db.consumer_groups)
        assert(db.consumer_group_consumers)
        assert(db.consumer_group_plugins)
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end
      end)

      it("the consumer_groups schema in Lua should be init correctly", function()
        local expected_schema = {
          {
            id = {
              type = "string",
              uuid = true,
              auto = true
            }
          },
          {
            created_at = {
              timestamp = true,
              type = "integer",
              auto = true
            }
          },
          {
            updated_at = {
              timestamp = true,
              type = "integer",
              auto = true
            }
          },
          {
            name = {
              unique = true,
              required = true,
              indexed = true,
              type = "string"
            }
          },
          {
            tags = {
              type = "set",
              elements = {
                required = true,
                type = "string"
              },
            }
          },
        }

        local res = assert(client:send {
          method = "GET",
          path = "/schemas/consumer_groups"
        })

        local json = assert.res_status(200, res)
        local schema = assert(cjson.decode(json).fields)

        for i, v in pairs(schema) do
          compare_all_field(v, expected_schema[i])
        end
      end)

      it("the consumer_group_consumers schema in Lua should be init correctly", function()
        local expected_schema = {
          {
            created_at = {
              timestamp = true,
              type = "integer",
              auto = true
            }
          },
          {
            updated_at = {
              timestamp = true,
              type = "integer",
              auto = true
            }
          },
          {
            consumer_group = {
              type = "foreign",
              required = true,
              reference = "consumer_groups",
              on_delete = "cascade"
            }
          },
          {
            consumer = {
              type = "foreign",
              required = true,
              reference = "consumers",
              on_delete = "cascade"
            }
          },
        }

        local res = assert(client:send {
          method = "GET",
          path = "/schemas/consumer_group_consumers"
        })

        local json = assert.res_status(200, res)
        local schema = assert(cjson.decode(json).fields)

        for i, v in pairs(schema) do
          compare_all_field(v, expected_schema[i])
        end
      end)

      it("a consumer group 'name' should be required during creation", function()
        local _, _, err_t = db.consumer_groups:insert({
          id = utils.uuid()
        })

        assert.same("schema violation", err_t.name)
        assert(err_t.fields.name)
      end)

      it("default creation with 'name'", function()
        local submission = {
          name = "test_consumer_group_identity" .. utils.uuid(),
        }

        local res_insert = assert(db.consumer_groups:insert(submission))

        assert.same(submission.name, res_insert.name)
      end)

      it("the 'name' should be unique", function()
        local submission = { name = "test_consumer_group_identity" .. utils.uuid() }

        assert(db.groups:insert(submission))

        local _, _, err_t = db.groups:insert(submission)

        assert.same("unique constraint violation", err_t.name)
      end)
    end)

    describe("delete cascade should work as expected", function()

      local consumer_group, consumer

      local function insert_and_delete(dao_name, delete_id)
        local mapping = {
          consumer= { id = consumer.id },
          consumer_group     = { id = consumer_group.id }
        }

        assert(db.consumer_group_consumers:insert(mapping))

        assert(db[dao_name]:delete({ id = delete_id }))

        assert.is_nil(db.consumer_group_consumers:select(mapping))
      end

      local function config_and_delete(dao_name, delete_id)

        local config_id = utils.uuid()
        assert(db.consumer_group_plugins:insert(
          {
            id = config_id,
            name = "rate-limiting-advanced",
            consumer_group = { id = consumer_group.id, },
            config = {
              window_size = { 10 },
              limit = { 10 },
            }
          }))
        assert(db[dao_name]:delete({ id = delete_id }))
        assert.is_nil(db.consumer_group_plugins:select({ id = config_id }))
      end

      lazy_setup(function()
        helpers.stop_kong()

        assert(helpers.start_kong({
          database  = strategy,
        }))
        client = assert(helpers.admin_client())

        assert(db.consumer_groups)
        assert(db.consumer_group_consumers)
        assert(db.consumer_group_plugins)
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end
      end)

      before_each(function()
        consumer_group = assert(db.consumer_groups:insert{ name = "test_group_" .. utils.uuid()})
        consumer = assert(db.consumers:insert{ username = "test_consumer_" .. utils.uuid()})
      end)

      it("mapping should be removed after referenced consumer group has been removed", function()
        insert_and_delete("consumer_groups", consumer_group.id)
      end)

      it("mapping should be removed after referenced consumer has been removed", function()
        insert_and_delete("consumers", consumer.id)
      end)

      it("config should be removed after referenced consumer group has been removed", function()
        config_and_delete("consumer_groups", consumer_group.id)
      end)

    end)
  end)
end
