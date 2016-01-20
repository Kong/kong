local event_types = require "kong.core.events".TYPES
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"

local env = spec_helper.get_env() -- test environment
local dao_factory = env.dao_factory
local events = env.events

describe("Events #dao #cass", function()

  setup(function()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    spec_helper.prepare_db()
  end)

  it("should fire event on insert", function()
    local received = false

    events:subscribe(event_types.CLUSTER_PROPAGATE, function(message_t)
      if message_t.type == event_types.ENTITY_CREATED then
        assert.equals(event_types.ENTITY_CREATED, message_t.type)
        assert.equals("apis", message_t.collection)
        assert.truthy(message_t.entity)
        assert.equals(1, utils.table_size(message_t.entity))
        assert.truthy(message_t.entity.id)
        received = true
      end
    end)

    local res, err = dao_factory.apis:insert({
      request_host = "test.com",
      upstream_url = "http://mockbin.org"
    })

    assert.truthy(res)
    assert.falsy(err)

    while not received do
      -- Wait
    end
    assert.True(received)
  end)

  it("should fire event on update", function()
    local received = false

    events:subscribe(event_types.CLUSTER_PROPAGATE, function(message_t)

      if message_t.type == event_types.ENTITY_UPDATED then
        assert.equals(event_types.ENTITY_UPDATED, message_t.type)
        assert.equals("apis", message_t.collection)
        assert.truthy(message_t.entity)
        assert.equals(1, utils.table_size(message_t.entity))
        assert.truthy(message_t.entity.id)

        local new_entity = dao_factory.apis:find_by_primary_key({id=message_t.entity.id})
        assert.equals("http://mockbin2.org", new_entity.upstream_url)

        received = true
      end
    end)

    local res, err = dao_factory.apis:insert({
      request_host = "test.com",
      upstream_url = "http://mockbin.org"
    })
    assert.truthy(res)
    assert.falsy(err)

    -- Update entity
    res.upstream_url = "http://mockbin2.org"
    local res, err = dao_factory.apis:update(res)
    assert.truthy(res)
    assert.falsy(err)

    while not received do
      -- Wait
    end
    assert.True(received)
  end)

  it("should fire event on delete", function()
    local received = false

    events:subscribe(event_types.CLUSTER_PROPAGATE, function(message_t)
      if message_t.type == event_types.ENTITY_DELETED then
        assert.equals(event_types.ENTITY_DELETED, message_t.type)
        assert.equals("apis", message_t.collection)
        assert.truthy(message_t.entity)
        assert.equals(1, utils.table_size(message_t.entity))
        assert.truthy(message_t.entity.id)

        received = true
      end
    end)

    local res, err = dao_factory.apis:insert({
      request_host = "test.com",
      upstream_url = "http://mockbin.org"
    })
    assert.truthy(res)
    assert.falsy(err)

    dao_factory.apis:delete({id=res.id})

    while not received do
      -- Wait
    end
    assert.True(received)
  end)

end)
