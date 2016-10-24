local helpers = require "spec.helpers"
local Events = require "kong.core.events"
local Factory = require "kong.dao.factory"

local API_ID = "0cd4a0d3-2e41-4b51-945a-eb06adbe8d2e"

for conf, database in helpers.for_each_db() do
  describe("Quiet with #" .. conf.database, function()
    local events = Events()
    local factory

    setup(function()
      factory = Factory.new(conf, events)
      assert(factory:run_migrations())
    end)
    before_each(function()
      factory:truncate_tables()
    end)

    local do_insert = function(quiet)
      local api = assert(factory.apis:insert({
        id = API_ID,
        name = "mockbin",
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, {ttl = 1, quiet = quiet}))
      assert.equal(API_ID, api.id)
    end

    describe("insert", function()
      it("propagates event", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_CREATED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_insert()

        helpers.wait_until(function()
          return received
        end)
      end)

      it("does not propagate when quiet", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_CREATED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_insert(true)

        assert.has_error(function()
          helpers.wait_until(function()
            return received
          end)
        end)
      end)
    end)

    describe("update", function()
      before_each(function()
        do_insert()
      end)

      local do_update = function(quiet)
        local api = assert(factory.apis:update({id = API_ID}, {
          id = API_ID,
          name = "mockbin2"
        }, {quiet = quiet}))
        assert.equal(API_ID, api.id)
      end

      it("propagates event", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_UPDATED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_update()

        helpers.wait_until(function()
          return received
        end)
      end)

      it("does not propagate when quiet", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_UPDATED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_update(true)

        assert.has_error(function()
          helpers.wait_until(function()
            return received
          end)
        end)
      end)
    end)

    describe("delete", function()
      before_each(function()
        do_insert()
      end)

      local do_update = function(quiet)
        local api = assert(factory.apis:delete({id = API_ID}, {quiet = quiet}))
        assert.equal(API_ID, api.id)
      end

      it("propagates event", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_DELETED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_update()

        helpers.wait_until(function()
          return received
        end)
      end)

      it("does not propagate when quiet", function()
        local received
        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_DELETED" and message_t.collection == "apis" then
            received = message_t.entity.id == API_ID
          end
        end)

        do_update(true)

        assert.has_error(function()
          helpers.wait_until(function()
            return received
          end)
        end)
      end)
    end)
  end)
end
