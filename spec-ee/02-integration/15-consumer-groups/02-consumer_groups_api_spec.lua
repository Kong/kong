-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers	   = require "spec.helpers"
local cjson 	   = require "cjson"
local utils 	   = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"

local client
local db

local function truncate_tables(db)
  db:truncate("consumer_groups")
  db:truncate("consumer_group_plugins")
  db:truncate("consumer_groups_consumers")
end

for _, strategy in helpers.each_strategy() do
  describe("Consumer Groups API #" .. strategy, function()
    local function get_request(url)

      local json = assert.res_status(200, assert(client:send {
        method = "GET",
        path = url,
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))

      local res = cjson.decode(json)

      return res, res.data and #res.data or 0
    end

    lazy_setup(function()
      helpers.stop_kong()

      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database  = strategy,

      }))
      client = assert(helpers.admin_client())
      assert(db.consumer_groups)
      assert(db.consumer_group_consumers)
      assert(db.consumer_group_plugins)
    end)

    lazy_teardown(function()
      truncate_tables(db)

      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("/consumer_groups :", function()
      local function insert_group()
        local submission = { name = "test_group_" .. utils.uuid() }
        local json = assert.res_status(201, assert(client:send {
          method = "POST",
          path = "/consumer_groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        return cjson.decode(json)
      end

      local function check_delete(key)
        assert.res_status(204, assert(client:send {
          method = "DELETE",
          path = "/consumer_groups/" .. key,
        }))

        local res = get_request("/consumer_groups")

        assert.same({}, res.data)
      end

      lazy_setup(function()
        ee_helpers.register_rbac_resources(db)
      end)

      lazy_teardown(function()
        db:truncate("consumer_groups")
      end)

      it("GET The endpoint should list consumer groups entities as expected", function()
        local name = "test_group_" .. utils.uuid()
        local res

        assert(db.groups:insert{ name = name})
        res = get_request("/consumer_groups")

        assert.same(name, res.data[1].name)
      end)

      it("GET The endpoint should list a consumer group by id", function()
        local res_insert = insert_group()

        local res_select = get_request("/groups/" .. res_insert.id)

        assert.same(res_insert, res_select)
      end)

      it("GET The endpoint should list a consumer group by name", function()
        local res_insert = insert_group()

        local res_select = get_request("/consumer_groups/" .. res_insert.name)

        assert.same(res_insert, res_select)
      end)

      it("GET The endpoint should return '404' when the consumer group not found", function()
        assert.res_status(404, assert(client:send {
          method = "GET",
          path = "/consumer_groups/" .. utils.uuid(),
        }))
      end)

      it("POST The endpoint should not create a group entity with out a 'name'", function()
        local submission = {}

        assert.res_status(400, assert(client:send {
          method = "POST",
          path = "/consumer_groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))
      end)

      it("POST The endpoint should create a consumer group entity as expected", function()
        insert_group()
      end)

      it("DELETE The endpoint should delete a consumer group entity by id", function()
        local consumer_group

        db:truncate("consumer_groups")
        consumer_group = insert_group()
        check_delete(consumer_group.id)
      end)

      it("DELETE The endpoint should delete a group entity by name", function()
        local consumer_group

        db:truncate("consumer_groups")
        consumer_group = insert_group()
        check_delete(consumer_group.name)
      end)
    end)

    describe("/consumer_groups/:consumer_groups/ : ", function()
      local function insert_entities()
        local consumer_group = assert(db.consumer_groups:insert{ name = "test_group_" .. utils.uuid()})
        local consumer = assert(db.consumers:insert( {username = "test_consumer_" .. utils.uuid()}))
        local consumer_group_plugin = assert(db.consumer_group_plugins:insert(
          {
            id = utils.uuid(),
            name = "rate-limiting-advanced",
            consumer_group = { id = consumer_group.id, },
            config = {
              window_size = 10,
              limit = 10,
            }
          }))
        return consumer_group, consumer, consumer_group_plugin
      end
      local function insert_mapping(consumer_group, consumer)

        local mapping = {
          consumer          = { id = consumer.id },
          consumer_group 	  = { id = consumer_group.id },
        }

        assert(db.consumer_group_consumers:insert(mapping))
      end

      describe("GET", function()
        local consumer_group, consumer, consumer_group_plugin

        lazy_setup(function()
          consumer_group, consumer, consumer_group_plugin = insert_entities()
          insert_mapping(consumer_group, consumer)
        end)

        lazy_teardown(function()
          db:truncate("consumer_group_consumers")
          db:truncate("consumer_group_plugins")
        end)

        it("The endpoint should list consumers and plugins by a group id", function()
          local res = get_request("/consumer_groups/" .. consumer_group.id)

          assert.same(res.data[1].consumer_group.id, consumer_group.id)
          assert.same(res.data[1].consumers[1].id, consumer.id)
          assert.same(res.data[1].plugins[1].id, consumer_group_plugin.id)
        end)

        it("The endpoint should list consumers and plugins by a group name", function()
          local res = get_request("/consumer_groups/" .. consumer_group.name)

          assert.same(res.data[1].consumer_group.name, consumer_group.id)
          assert.same(res.data[1].consumers[1].id, consumer.id)
          assert.same(res.data[1].plugins[1].id, consumer_group_plugin.id)
        end)

      end)

      describe("POST", function()
        local consumer_group, consumer

        local function check_create(res_code, key, _consumer_group, _consumer)
          local json = assert.res_status(res_code, assert(client:send {
            method = "POST",
            path = "/consumer_groups/" .. key,
            body = {
              consumer = _consumer.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          if res_code ~= 201 then
            return nil
          end

          local res = cjson.decode(json)

          assert.same(res.consumer_group.id, _consumer_group.id)
      
        end

        lazy_setup(function()
          consumer_group, consumer = insert_entities()
          insert_mapping(consumer_group, consumer)
        end)

        lazy_teardown(function()
          db:truncate("consumer_group_consumers")
        end)

        it("The endpoint should not create a mapping with incorrect params", function()
          local _consumer_group = insert_entities()

          do
            -- body params need to be correct
            local json_no_consumer = assert.res_status(400, assert(client:send {
              method = "POST",
              path = "/consumer_groups/" .. _consumer_group.id,
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
            assert.same("No consumer provided", cjson.decode(json_no_consumer).message)
          end

          do
            -- entities need to be found
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/consumer_groups/" .. _consumer_group.id,
              body = {
                consumer = utils.uuid()
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
          end
        end)

        it("The endpoint should not create a mapping with incorrect ids", function()
          local _consumer_group, _consumer = insert_entities()
          check_create(404, utils.uuid(), _consumer_group, _consumer)
        end)

        it("The endpoint should create a mapping with correct params by id", function()
          local _consumer_group, _consumer = insert_entities()
          check_create(201, _consumer_group.id, _consumer_group, _consumer)
        end)

        it("The endpoint should create a mapping with correct params by group name", function()
          local _consumer_group, _consumer = insert_entities()
          check_create(201, _consumer_group.name, _consumer_group, _consumer)
        end)
      end)

      describe("DELETE", function()
        local consumer_group, consumer

        local function check_delete(key)
          assert.res_status(204, assert(client:send {
            method = "DELETE",
            path = "/consumer_groups/" .. key,
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local res = get_request("/consumer_groups/" .. consumer_group.id)

          assert.same({}, res.data)
        end

        before_each(function()
          consumer_group, consumer = insert_entities()
          insert_mapping(consumer_group, consumer)
        end)

        lazy_teardown(function()
          db:truncate("consumer_group_consumers")
        end)

        it("The endpoint should delete a mapping with correct params by id", function()
          check_delete(consumer_group.id)
        end)

        it("The endpoint should delete a mapping with correct params by group name", function()
          check_delete(consumer_group.name)
        end)
      end)
    end)
  end)
end
