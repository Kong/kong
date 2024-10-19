-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ds_context = require "kong.enterprise_edition.debug_session.context"

describe("debuggability - context", function()
  local snapshot
  local context

  setup(function()
    helpers.get_db_utils("off")
    context = ds_context:new()
  end)

  before_each(function()
    snapshot = assert:snapshot()
    context:flush()
  end)

  after_each(function()
    snapshot:revert()
  end)

  lazy_teardown(function()
    context:flush()
  end)

  describe("#incr-counters", function ()
    after_each(function()
      context:flush()
    end)

    it("#incr_counter", function()
      local c = context:incr_counter()
      assert.equals(c, 1)
      c = context:incr_counter()
      assert.equals(c, 2)
    end)
  end)

  describe("#state-helpers", function()
    after_each(function()
      context:flush()
    end)

    it("#is_session_active", function()
      assert(context:set_session({
        id = "session-id",
        action = "START",
      }))
      assert.equals(context:is_session_active(), true)
    end)

    it("#get_exceeded_max_samples", function()
      assert(context:set_session({
        id = "session-id",
        action = "START",
      }))
      context:set_exceeded_max_samples()
      assert.equals(context:get_exceeded_max_samples(), true)
    end)

    it("#check_exceeded_max_samples", function ()
      assert(context:set_session({
        id = "session-id",
        action = "START",
        max_samples = 2,
      }))
      local max_samples = context:get_session_max_samples()
      assert.is_false(context:check_exceeded_max_samples(1))
      assert.is_true(context:check_exceeded_max_samples(max_samples + 1))
    end)

    it("#is_session_expired", function()
      assert(context:set_session({
        id = "session-id",
        action = "START",
        duration = 10,
      }))
      context.shm:set("started_at", ngx.now() - 10)
      assert.equals(context:is_session_expired(), true)
    end)
  end)

  describe("#getters", function()

    after_each(function()
      context:flush()
    end)

    it("#get_session_id", function()
      context.shm:set("id", "session-id")
      assert.equals(context:get_session_id(), "session-id")
    end)

    it("#get_event_id", function()
      context:set_event_id("event-id")
      assert.equals(context:get_event_id(), "event-id")
    end)

    it("#get_session_max_samples", function()
      context.shm:set("max_samples", 123)
      assert.equals(context:get_session_max_samples(), 123)
    end)

    it("#get_session_remaining_ttl", function()
      local some_duration = 10
      context.shm:set("duration", some_duration)
      context.shm:set("started_at", ngx.now())
      assert.equals(context:get_session_remaining_ttl(), some_duration) -- meh
    end)
  end)

  describe("#setters", function()

    after_each(function()
      context:flush()
    end)

    it("#set_event_id", function()
      context:set_event_id("event-id")
      assert.equals(context:get_event_id(), "event-id")
    end)

    it("#set_session_active", function()
      context:set_session_active()
      assert.equals(context.shm:get("active"), true)
    end)

    it("#set_session_inactive", function()
      context:set_session_inactive()
      assert.equals(context.shm:get("active"), false)
    end)
  end)

  describe("#set_session", function()
    local set_session_snapshot

    before_each(function()
      set_session_snapshot = assert:snapshot()
    end)

    after_each(function()
      set_session_snapshot:revert()
      context.shm:flush()
    end)

    it("#id and sampling_rule", function()
      stub(context, "set_session_active")
      local sampling_rule = 'http.path ^= "/foo/bar'
      assert(context:set_session({
        id = "session-id",
        action = "START",
        sampling_rule = sampling_rule,
      }))
      assert.equals(context:get_session_id(), "session-id")
      assert.stub(context.set_session_active).was.called_with(context)
      assert.equals(context:get_sampling_rule(), sampling_rule)
    end)

    it("#id no sampling_rule", function()
      stub(context, "set_session_active")
      assert(context:set_session({
        id = "session-id",
        action = "START",
        sampling_rule = nil,
      }))
      assert.equals(context:get_session_id(), "session-id")
      assert.stub(context.set_session_active).was.called_with(context)
      assert.equals(context:get_sampling_rule(), "")
    end)

    it("#id empty string sampling_rule", function()
      stub(context, "set_session_active")
      assert(context:set_session({
        id = "session-id",
        action = "START",
        sampling_rule = "",
      }))
      assert.equals(context:get_session_id(), "session-id")
      assert.stub(context.set_session_active).was.called_with(context)
      assert.equals(context:get_sampling_rule(), "")
    end)


    it("#no id", function()
      local res, err = context:set_session({
        action = "START",
        sampling_rule = nil,
      })
      assert.is_nil(res)
      assert.is_not_nil(err)
    end)

    it("#no action", function()
      stub(context, "set_session_active")
      local res, err = context:set_session({
        id = "session-id",
      })
      assert.is_nil(res)
      assert.is_not_nil(err)
    end)
  end)
end)
