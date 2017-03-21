local utils = require "kong.tools.utils"
local Events = require "kong.core.events"
local helpers = require "spec.02-integration.02-dao.helpers"
local Factory = require "kong.dao.factory"
local spec_helpers = require "spec.helpers"

helpers.for_each_dao(function(kong_config)
  describe("Quiet with #" .. kong_config.database, function()
    local factory
    local events

    setup(function()
      factory = Factory.new(kong_config)
      assert(factory:run_migrations())
      factory:truncate_tables()
    end)

    before_each(function()
      events = Events()
      factory = Factory.new(kong_config, events)
    end)

    local i = 0

    local function do_insert(quiet, id)
      local api, err = factory.apis:insert({
        id = id,
        name = "mockbin." .. i,
        hosts = { "mockbin-" .. i .. ".com" },
        upstream_url = "http://mockbin.com"
      }, { ttl = 1, quiet = quiet })

      assert.falsy(err)
      assert.is_table(api)

      i = i + 1

      return api.id
    end

    describe("insert()", function()
      it("propagates event", function()
        local received
        local api_id = utils.uuid()

        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_CREATED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
          end
        end)

        do_insert(nil, api_id)

        spec_helpers.wait_until(function()
          return received
        end)
      end)

      it("does not propagate when quiet", function()
        local received
        local api_id = utils.uuid()

        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_CREATED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
          end
        end)

        do_insert(true, api_id)

        assert.has_error(function()
          spec_helpers.wait_until(function()
            return received
          end, 2)
        end, "wait_until() timeout (after delay 2s)")
      end)
    end)

    describe("update()", function()
      local api_id

      before_each(function()
        api_id = do_insert()
      end)

      local do_update = function(quiet)
        local api, err = factory.apis:update({
          name = "mockbin" .. i .. "-updated"
        }, {
          id = api_id,
        }, { quiet = quiet })

        assert.falsy(err)
        assert.equal(api_id, api.id)
      end

      it("propagates event", function()
        local received

        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_UPDATED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
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
          if message_t.type == "ENTITY_UPDATED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
          end
        end)

        do_update(true)

        assert.has_error(function()
          spec_helpers.wait_until(function()
            return received
          end)
        end, "wait_until() timeout (after delay 2s)")
      end)
    end)

    describe("delete()", function()
      local api_id

      before_each(function()
        api_id = do_insert()
      end)

      local do_delete = function(quiet)
        local api, err = factory.apis:delete({
          id = api_id
        }, { quiet = quiet })
        assert.falsy(err)
        assert.equal(api_id, api.id)
      end

      it("propagates event", function()
        local received

        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_DELETED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
          end
        end)

        do_delete()

        spec_helpers.wait_until(function()
          return received
        end)
      end)

      it("does not propagate when quiet", function()
        local received

        events:subscribe(Events.TYPES.CLUSTER_PROPAGATE, function(message_t)
          if message_t.type == "ENTITY_DELETED"
             and message_t.collection == "apis" then
            received = message_t.entity.id == api_id
          end
        end)

        do_delete(true)

        assert.has_error(function()
          spec_helpers.wait_until(function()
            return received
          end)
        end, "wait_until() timeout (after delay 2s)")
      end)
    end)
  end)
end)
