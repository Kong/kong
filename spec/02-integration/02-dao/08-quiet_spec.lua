local helpers = require "spec.02-integration.02-dao.helpers"
local Events = require "kong.core.events"
local spec_helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

local events = Events()

local API_ID = "0cd4a0d3-2e41-4b51-945a-eb06adbe8d2e"

helpers.for_each_dao(function(kong_config)
  describe("Quiet with #"..kong_config.database, function()
    local factory
    setup(function()
      factory = Factory.new(kong_config, events)
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    local do_insert = function(quiet)
      local api, err = factory.apis:insert({
        id = API_ID,
        name = "mockbin",
        hosts = { "mockbin.com" },
        upstream_url = "http://mockbin.com"
      }, {ttl = 1, quiet = quiet})
      assert.falsy(err)
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

        spec_helpers.wait_until(function()
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
          spec_helpers.wait_until(function()
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
        local api, err = factory.apis:update({id = API_ID}, {
          id = API_ID,
          name = "mockbin2"
        }, {quiet = quiet})

        assert.falsy(err)
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

        spec_helpers.wait_until(function()
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
          spec_helpers.wait_until(function()
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
        local api, err = factory.apis:delete({id = API_ID}, {quiet = quiet})
        assert.falsy(err)
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

        spec_helpers.wait_until(function()
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
          spec_helpers.wait_until(function()
            return received
          end)
        end)
      end)
    end)
  end)
end)
