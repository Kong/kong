-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers	   = require "spec.helpers"
local cjson 	   = require "cjson"
local utils 	   = require "kong.tools.utils"
local null = ngx.null
local client
local db

local function truncate_tables(db)
  db:truncate("consumers")
  db:truncate("consumer_groups")
  db:truncate("consumer_group_plugins")
  db:truncate("consumer_group_consumers")
end

local function get_request(url, params)
  local json = assert.res_status(200, assert(client:send {
    method = "GET",
    path = url,
    query = params,
    headers = {
      ["Content-Type"] = "application/json",
    },
  }))

  local res = cjson.decode(json)

  return res, res.data and #res.data or 0
end

for _, strategy in helpers.each_strategy() do
  describe("Consumer Groups API #" .. strategy, function()


    lazy_setup(function()
      helpers.stop_kong()

      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database  = strategy,
      }))
      client = assert(helpers.admin_client())
      assert(db.consumers)
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

      lazy_teardown(function()
        db:truncate("consumer_groups")
      end)

      it("GET The endpoint should list consumer groups entities as expected", function()
        local name = "test_group_" .. utils.uuid()
        local res

        assert(db.consumer_groups:insert{ name = name})
        res = get_request("/consumer_groups")
        local group = res.data[1]
        assert.is_nil(group.consumers_count)
        assert.same(name, group.name)
      end)

      it("The endpoint should list consumer groups has consumers_count as expected when counter is true", function()
        local name = "counter_group_" .. utils.uuid()
        local consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
        local consumer_group = assert(db.consumer_groups:insert { name = name})
        local mapping = {
            consumer       = { id = consumer.id },
            consumer_group = { id = consumer_group.id },
        }

        assert(db.consumer_group_consumers:insert(mapping))
        local res = get_request("/consumer_groups?counter=true")
        for _, group in pairs(res.data) do
          if group.name == name then
            consumer_group = group
            break
          end

        end
        assert.is_not_nil(consumer_group.consumers_count)
        assert.equal(1, consumer_group.consumers_count)
      end)

      it("GET The endpoint should list a consumer group by id", function()
        local res_insert = insert_group()

        local res_select = get_request("/consumer_groups/" .. res_insert.id).consumer_group

        assert.same(res_insert, res_select)
      end)

      it("GET The endpoint should list a consumer group by name", function()
        local res_insert = insert_group()

        local res_select = get_request("/consumer_groups/" .. res_insert.name).consumer_group

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

      describe("GET The endpoint should filter consumer groups by tag", function()
        local name1, name2, res

        lazy_setup(function()
          name1 = "test_group_" .. utils.uuid()
          name2 = "test_group_" .. utils.uuid()

          assert(db.consumer_groups:insert{
            name = name1,
            tags = { "tag1", "tag2" }
          })
          assert(db.consumer_groups:insert{
            name = name2,
            tags = { "tag2", "tag3" }
          })
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("with a single tag, filter the right group", function()
          res = get_request("/consumer_groups", { tags = "tag1" })
          assert.same(1, #res.data)
          assert.same(name1, res.data[1].name)
        end)

        it("with a shared tag, filter the right groups", function()
          res = get_request("/consumer_groups", { tags = "tag2" })
          assert.same(2, #res.data)
        end)

        it("with multiple tags, filter the right group (AND)", function()
          res = get_request("/consumer_groups", { tags = "tag2,tag3" })
          assert.same(1, #res.data)
          assert.same(name2, res.data[1].name)
        end)

        it("with multiple tags, filter the right groups (OR)", function()
          res = get_request("/consumer_groups", { tags = "tag2/tag3" })
          assert.same(2, #res.data)
        end)

        it("with a tag that does not exist, return empty response", function()
          res = get_request("/consumer_groups", { tags = "wrongtag" })
          assert.same(0, #res.data)
        end)
      end)
    end)

    describe("/consumer_groups/:consumer_groups :", function()
      local function insert_entities()
        local consumer_group = assert(db.consumer_groups:insert{ name = "test_group_" .. utils.uuid()})
        local consumer = assert(db.consumers:insert( {username = "test_consumer_" .. utils.uuid()}))
        local consumer_group_plugin = assert(db.consumer_group_plugins:insert(
          {
            id = utils.uuid(),
            name = "rate-limiting-advanced",
            consumer_group = { id = consumer_group.id, },
            config = {
              window_size = { 10 },
              limit = { 10 },
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
          truncate_tables(db)
        end)

        it("The endpoint should list consumers and plugins by a group id", function()
          local res = get_request("/consumer_groups/" .. consumer_group.id)

          assert.same(res.consumer_group.id, consumer_group.id)
          assert.same(res.consumers[1].id, consumer.id)
          assert.same(res.plugins[1].id, consumer_group_plugin.id)
        end)

        it("The endpoint should list consumers and plugins by a group name", function()
          local res = get_request("/consumer_groups/" .. consumer_group.name)

          assert.same(res.consumer_group.name, consumer_group.name)
          assert.same(res.consumers[1].id, consumer.id)
          assert.same(res.plugins[1].id, consumer_group_plugin.id)
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

          local json = assert.res_status(404, assert(client:send {
            method = "GET",
            path = "/consumer_groups/" .. key,
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local res = cjson.decode(json)

          assert.same("Group '" .. key .. "' not found", res.message)
        end

        before_each(function()
          consumer_group, consumer = insert_entities()
          insert_mapping(consumer_group, consumer)
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("The endpoint should delete a mapping with correct params by id", function()
          check_delete(consumer_group.id)
        end)

        it("The endpoint should delete a mapping with correct params by group name", function()
          check_delete(consumer_group.name)
        end)
      end)
    end)

    describe("/consumer_groups/:consumer_groups/consumers :", function()
      local function insert_entities()
        local consumer_group = assert(db.consumer_groups:insert{ name = "test_group_" .. utils.uuid()})
        local consumer = assert(db.consumers:insert( {username = "test_consumer_" .. utils.uuid()}))
        local consumer2 = assert(db.consumers:insert( {username = "test_consumer2_" .. utils.uuid()}))

        return consumer_group, consumer, consumer2
      end

      local function insert_mapping(consumer_group, consumer)

        local mapping = {
          consumer          = { id = consumer.id },
          consumer_group 	  = { id = consumer_group.id },
        }

        assert(db.consumer_group_consumers:insert(mapping))
      end

      describe("POST", function()
        local consumer_group, consumer

        local function check_create(res_code, key, consumer_group, consumer)
          local json = assert.res_status(res_code, assert(client:send {
            method = "POST",
            path = "/consumer_groups/" .. key .."/consumers",
            body = {
              consumer = { consumer.id },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          if res_code ~= 201 then
            return nil
          end

          local res = cjson.decode(json)

          assert.same(res.consumer_group.id, consumer_group.id)
        end

        lazy_setup(function()
          consumer_group, consumer = insert_entities()
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("The endpoint should not create a mapping with incorrect params", function()
          do
            -- body params need to be correct
            local json_no_consumer = assert.res_status(400, assert(client:send {
              method = "POST",
              path = "/consumer_groups/" .. consumer_group.id .. "/consumers",
              body = {
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
            assert.same("must provide consumer", cjson.decode(json_no_consumer).message)
          end

          do
            -- entities need to be found
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/consumer_groups/" .. consumer_group.id .. "/consumers",
              body = {
                consumer = { utils.uuid() },
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
          end
        end)

        it("The endpoint should not create a mapping with incorrect ids", function()
          check_create(404, utils.uuid(), consumer_group, consumer)
        end)

        it("The endpoint should create a mapping with correct params by group id", function()
          check_create(201, consumer_group.id, consumer_group, consumer)
        end)

        it("The endpoint should create a mapping with correct params by group name", function()
          db:truncate("consumer_group_consumers")
          check_create(201, consumer_group.name, consumer_group, consumer)
        end)
      end)

      describe("GET", function()
        local consumer_group

        lazy_setup(function()
          consumer_group = assert(db.consumer_groups:insert { name = "test_group_" .. utils.uuid() })
          for i = 1, 101, 1 do
            local consumer = assert(db.consumers:insert({ username = "test_consumer_" .. utils.uuid() }))
            insert_mapping(consumer_group, consumer)
          end
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("should list consumers in the consumer_group by default size 100", function()
          local res = get_request("/consumer_groups/" .. consumer_group.id .. "/consumers")

          assert.same(100, #res.data)
          assert.is_not_nil(res.offset)

          res = get_request("/consumer_groups/" .. consumer_group.id .. "/consumers?offset=" .. res.offset)
          assert.same(1, #res.data)
          assert.is_nil(res.offset)
        end)

        it("should list consumers in the consumer_group by size", function()
          local res = get_request("/consumer_groups/" .. consumer_group.id .. "/consumers?size=1")
          assert.same(1, #res.data)
          assert.is_not_nil(res.offset)
          local res = get_request("/consumer_groups/" ..
            consumer_group.id .. "/consumers?size=1&offset=" .. res.offset)
          assert.same(1, #res.data)
          assert.is_not_nil(res.offset)
        end)
      end)

      describe("DELETE", function()
        local consumer_group, consumer, consumer2

        local function check_delete(key)
          assert.res_status(204, assert(client:send {
            method = "DELETE",
            path = "/consumer_groups/" .. key .. "/consumers",
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local json = assert.res_status(200, assert(client:send {
            method = "GET",
            path = "/consumer_groups/" .. key .. "/consumers",
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local res = cjson.decode(json)
          assert.same({ data = {}, next = null }, res)
        end

        before_each(function()
          consumer_group, consumer, consumer2 = insert_entities()
          insert_mapping(consumer_group, consumer)
          insert_mapping(consumer_group, consumer2)
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("The endpoint should delete all consumers in group by group id ", function()
          check_delete(consumer_group.id)
        end)

        it("The endpoint should delete all consumers in group by group name ", function()
          check_delete(consumer_group.name)
        end)

      end)
    end)

    describe("/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced :", function()
      local function insert_entities()
        local consumer_group = assert(db.consumer_groups:insert{ name = "test_group_" .. utils.uuid()})
        return consumer_group
      end

      local function check_create(res_code, key, plugin, config)
        local json = assert.res_status(res_code, assert(client:send {
          method = "PUT",
          path = "/consumer_groups/" .. key .. "/overrides/plugins/" .. plugin,
          body = {
            config = config,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        if res_code ~= 201 then
          return nil
        end

        local res = cjson.decode(json)

        assert.same(50, res.config.window_size[1])
        assert.same(50, res.config.limit[1])
      end

      describe("PUT", function()
        local consumer_group
        before_each(function()
          consumer_group = insert_entities()
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("The endpoint should create a record in consumer_group_plugins", function()
          local config = {
            window_size = { 50 },
            limit = { 50 },
          }

          check_create(201, consumer_group.id, "rate-limiting-advanced", config)
        end)

        it("The endpoint should not create a record if config is incorrect", function()
          local config = {
            wrong_config = "wrong_config"
          }
          local json = assert.res_status(400, assert(client:send {
            method = "PUT",
            path = "/consumer_groups/" .. consumer_group.id .. "/overrides/plugins/rate-limiting-advanced" ,
            body = {
              config = config,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local res = cjson.decode(json)
          assert.same("schema violation", res.name)
        end)

      end)

      describe("DELETE", function ()
        local consumer_group

        local function check_delete(key, config_id)
          assert.res_status(204, assert(client:send {
            method = "DELETE",
            path = "/consumer_groups/" .. key .. "/overrides/plugins/rate-limiting-advanced" ,
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          assert.is_nil(db.consumer_group_plugins:select({ id = config_id }))
        end

        before_each(function()
          consumer_group = insert_entities()
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("The endpoint should delete the config in consumer_group_plugins", function()
          local config = {
            window_size = { 50 },
            limit = { 50 },
          }

          local consumer_group_config = assert(db.consumer_group_plugins:insert(
            {
              id = utils.uuid(),
              name = "rate-limiting-advanced",
              consumer_group = { id = consumer_group.id, },
              config = config
            }
          ))

          check_delete(consumer_group.id, consumer_group_config.id)

        end)

        it("The endpoint should return 404 if the config is not found", function()
          local json = assert.res_status(404, assert(client:send {
            method = "DELETE",
            path = "/consumer_groups/" .. consumer_group.id .. "/overrides/plugins/rate-limiting-advanced" ,
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          local res = cjson.decode(json)

          assert.same("Consumer group config for id '" .. consumer_group.id .. "' not found", res.message)
        end)

        it("The endpoint should return 404 if the consumer group is not found", function ()
          local wrong_group_id = utils.uuid()
          local json = assert.res_status(404, assert(client:send {
            method = "DELETE",
            path = "/consumer_groups/" .. wrong_group_id .. "/overrides/plugins/rate-limiting-advanced" ,
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          local res = cjson.decode(json)

          assert.same("Group '" .. wrong_group_id .. "' not found", res.message)
        end)

      end)
    end)

    describe("/consumers/:consumer/consumer_groups :", function()

      local function insert_mapping(consumer_group, consumer)
        local mapping = {
          consumer       = { id = consumer.id },
          consumer_group = { id = consumer_group.id },
        }

        assert(db.consumer_group_consumers:insert(mapping))
      end

      lazy_teardown(function()
        truncate_tables(db)
      end)

      it("KAG-1378 - consumer group cache should be invalidated after updating", function()
        local consumer_group = assert(db.consumer_groups:insert { name = "test_group_" .. utils.uuid() })
        local consumer_group_old_name = consumer_group.name

        local consumer = assert(db.consumers:insert({ username = "test_consumer_" .. utils.uuid() }))

        assert(db.consumer_group_consumers:insert({
          consumer       = { id = consumer.id },
          consumer_group = { id = consumer_group.id },
        }))

        -- should have one consumer group with the old name under the consumer
        local res = get_request("/consumers/" .. consumer.id .. "/consumer_groups")
        assert.same(1, #res.data)
        assert.equal(consumer_group_old_name, res.data[1].name)

        local consumer_group_new_name = "test_group_" .. utils.uuid()

        -- update the consumer group's name
        res = assert(
          cjson.decode(
            assert.res_status(200, assert(
              client:send {
                method = "PATCH",
                path = "/consumer_groups/" .. consumer_group.id,
                body = {
                  name = consumer_group_new_name,
                },
                headers = {
                  ["Content-Type"] = "application/json",
                },
              })
            )
          )
        )

        assert.equal(consumer_group_new_name, res.name)

        -- consumer group under the consumer should have the new name
        res = get_request("/consumers/" .. consumer.id .. "/consumer_groups")
        assert.same(1, #res.data)
        assert.equal(consumer_group_new_name, res.data[1].name)
      end)

      describe("GET", function()
        local consumer
        lazy_setup(function()
          
          consumer = assert(db.consumers:insert({ username = "test_consumer_" .. utils.uuid() }))
          for i = 1, 101, 1 do
            local consumer_group = assert(db.consumer_groups:insert { name = "test_group_" .. utils.uuid() })
            insert_mapping(consumer_group, consumer)
          end
        end)

        lazy_teardown(function()
          truncate_tables(db)
        end)

        it("should list consumer_groups in the consumer_group by default size 100", function()
          local res = get_request("/consumers/" .. consumer.id .. "/consumer_groups")

          assert.same(100, #res.data)
          assert.is_not_nil(res.offset)

          res = get_request("/consumers/" .. consumer.id .. "/consumer_groups?offset=" .. res.offset)
          assert.same(1, #res.data)
          assert.is_nil(res.offset)
        end)

        it("should list consumer_groups in the consumers by size", function()
          local res = get_request("/consumers/" .. consumer.id .. "/consumer_groups?size=1")
          assert.same(1, #res.data)
          assert.is_not_nil(res.offset)
          local res = get_request("/consumers/" ..
            consumer.id .. "/consumer_groups?size=1&offset=" .. res.offset)
          assert.same(1, #res.data)
          assert.is_not_nil(res.offset)
        end)
      end)
    end)
  end)

  describe("Consumer Groups API #postgres", function()
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

    it("Search consumer groups entities with name as expected", function()
      for i = 1, 10, 1 do
          assert(db.consumer_groups:insert { name = "test_name_group_" .. utils.uuid() })
      end

      local res = get_request("/consumer_groups?name=test_name_group_")
      local size = #res.data
      assert.equal(10, size)
      local group = res.data[1]
      assert.equal(1, string.find(group.name, 'test_name_group_'))
    end)
  end)

  describe("Consumer Groups Plugin Scoping API #" .. strategy, function()
    local allowed_plugins = {"request-transformer", "request-transformer-advanced", "response-transformer", "response-transformer-advanced", "rate-limiting-advanced"}
    local enabled_plugins = "bundled, " .. table.concat(allowed_plugins, ", ")
    lazy_setup(function()

      _, db = helpers.get_db_utils(strategy, nil, allowed_plugins)

      assert(helpers.start_kong({
        database = strategy,
        plugins = enabled_plugins,
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      client = assert(helpers.admin_client())
      assert(db.consumer_groups)
      assert(db.consumer_group_consumers)
      assert(db.consumer_group_plugins)
    end)

    after_each(function ()
      truncate_tables(db)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    it("POST to setup a plugin scoped to a consumer group (request-size-limiting)", function()
      assert(db.consumer_groups:insert { name = "testing-group" })
      assert.res_status(201, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "request-transformer-advanced",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
    end)

    it("POST to setup a plugin scoped to a consumer group (rate-limiting-advanced)", function()
      assert(db.consumer_groups:insert { name = "testing-group" })
      assert.res_status(201, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "rate-limiting-advanced",
          config = {
            limit = {1},
            window_size = {5},
          }
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
    end)


    it("POST to setup a plugin scoped to a consumer group (request-transformer)", function()
      assert(db.consumer_groups:insert { name = "testing-group" })
      assert.res_status(201, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "request-transformer",
          config = { }
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
    end)

    it("POST to setup a plugin which prohibits the use of consumer-group", function()
      assert(db.consumer_groups:insert { name = "testing-group" })
      assert.res_status(400, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "bot-detection"
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
    end)

    it("GET to retrieve plugins scoped to :consumer_group", function()
      -- create a consumer-group
      local cg = assert(db.consumer_groups:insert { name = "testing-group" })
      -- create a plugin scoped to this group
      assert.res_status(201, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "request-transformer"
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
      -- check if plugin was created
      local plug = assert.res_status(200, assert(client:send {
        method = "GET",
        path = "/consumer_groups/testing-group/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
      local res = cjson.decode(plug)
      assert.is_table(res)
      assert.is_same(res.data[1].consumer_group.id, cg.id)
    end)

  end)

end

for _, strategy in helpers.each_strategy() do
  describe("Consumer Groups Level Plugins - Free License #" .. strategy, function()

    lazy_setup(function()
      helpers.stop_kong()

      _, db = helpers.get_db_utils(strategy)

      -- No license is present
      helpers.unsetenv("KONG_LICENSE_DATA")

      assert(helpers.start_kong({
        database  = strategy,
      }))
      client = assert(helpers.admin_client())
      assert(db.consumers)
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

    it("POST to setup a plugin scoped to a consumer group but Kong is in free-mode", function()
      assert(db.consumer_groups:insert { name = "testing-group" })
      local res, _ = assert.res_status(400, assert(client:send {
        method = "POST",
        path = "/consumer_groups/testing-group/plugins",
        body = {
          name = "request-transformer",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
      local dres = cjson.decode(res)
      assert.same("schema violation (consumer-group scoping requires a license to be used)", dres.message)
    end)
  end)
end
