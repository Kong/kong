-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ds_mod = require "kong.enterprise_edition.debug_session"
local updates = require "kong.enterprise_edition.debug_session.updates"

local utils = require "kong.enterprise_edition.debug_session.utils"

local sample_rpc_response = {
  event_id = "1",
  sessions = { {
    id = "session-id",
    sampling_rule = "",
    action = "START"
  } }
}

describe("debuggability", function()
  local snapshot
  local ds
  local shm
  local context
  local reporter

  local old_mod_enabled

  setup(function()
    helpers.get_db_utils("off")
    ds = ds_mod:new(true)
    context = ds.context
    reporter = ds.reporter
    shm = context.shm
    kong.worker_events = kong.worker_events or
        kong.cache and kong.cache.worker_events or
        assert(require "kong.global".init_worker_events(kong.configuration))
    stub(kong.worker_events, "post")
    stub(updates, "get").returns(sample_rpc_response)
    old_mod_enabled = ds_mod.module_enabled
    ds_mod.module_enabled = true
  end)

  before_each(function()
    snapshot = assert:snapshot()
    shm:flush()
  end)

  after_each(function()
    snapshot:revert()
  end)

  lazy_teardown(function()
    kong.worker_events.post:revert()
    updates.get:revert()
    ds_mod.module_enabled = old_mod_enabled
  end)

  it("#exposes the same functionalities in NOOP mode", function()
    local old_ngx_config_subsystem = ngx.config.subsystem
    -- at the moment active tracing does not support the "stream"
    -- subsystem: new() returns a noop instance
    ngx.config.subsystem = "stream" -- luacheck: ignore
    local noop_ds = ds_mod:new(true)
    ngx.config.subsystem = "http" -- luacheck: ignore
    local http_ds = ds_mod:new(true)

    -- Restore old value
    ngx.config.subsystem = old_ngx_config_subsystem -- luacheck: ignore

    -- Check that functionalities are the same.
    -- In non-noop mode functionalities are in the metatable
    local MT = getmetatable(http_ds)
    for k, _ in pairs(MT) do
      if k ~= "__index" then
        assert.same(type(MT[k]), type(noop_ds[k]), "key: " .. k .. " not found")
      end
    end
  end)

  it("#update_sessions_from_cp", function()
    stub(ds, "process_updates")
    ds.update_sessions_from_cp(ds)
    assert.stub(updates.get).was.called(1)
    assert.stub(ds.process_updates).was.called_with(ds, sample_rpc_response)
    assert.stub(ds.process_updates).was.called(1)
  end)

  it("#init_session", function()
    stub(reporter, "init")
    ds:init_session("foo")
    assert.stub(reporter.init).was.called(1)
  end)

  describe("#process_updates", function()
    local update_snapshot

    before_each(function()
      update_snapshot = assert:snapshot()
    end)

    after_each(function()
      context:flush()
      update_snapshot:revert()
    end)

    local sample_rpc_response_start = {
      event_id = "1",
      sessions = { {
        id = "session-id",
        sampling_rule = "",
        action = "START"
      } }
    }

    local sample_rpc_response_stop = {
      event_id = "2",
      sessions = { {
        id = "session-id",
        sampling_rule = "",
        action = "STOP"
      } }
    }

    local sample_rpc_response_start_stop = {
      event_id = "3",
      sessions = { {
        id = "session-id",
        sampling_rule = "",
        action = "START"
      }, {
        id = "session-id",
        sampling_rule = "",
        action = "STOP"
      } }
    }

    local sample_rpc_response_no_sessions = {
      event_id = "4",
      sessions = {}
    }

    it("#nodata", function()
      stub(ds, "handle_action")
      local res, err = ds:process_updates()
      assert.is_nil(res)
      assert.is_not_nil(err)
      assert.stub(ds.handle_action).was.called(0)
    end)

    it("#nosessions", function()
      stub(ds, "handle_action")
      ds:process_updates(sample_rpc_response_no_sessions)
      assert.stub(ds.handle_action).was.called(0)
    end)

    it("#start1", function()
      stub(ds, "handle_action")
      ds:process_updates(sample_rpc_response_start)
      assert.stub(ds.handle_action).was.called_with(ds, sample_rpc_response_start.sessions[1])
    end)

    it("#stop", function()
      stub(ds, "handle_action")
      ds:process_updates(sample_rpc_response_stop)
      assert.stub(ds.handle_action).was.called_with(ds, sample_rpc_response_stop.sessions[1])
    end)

    it("#start_stop", function()
      stub(ds, "handle_action")
      ds:process_updates(sample_rpc_response_start_stop)
      assert.stub(ds.handle_action).was.called_with(ds, sample_rpc_response_start_stop.sessions[1])
      assert.stub(ds.handle_action).was.called_with(ds, sample_rpc_response_start_stop.sessions[2])
      assert.stub(ds.handle_action).was.called(2)
    end)
  end)

  describe("#handle_action", function()
    local handle_action_snapshot

    before_each(function()
      stub(ds, "set_start_session")
      stub(ds, "set_stop_session")
      handle_action_snapshot = assert:snapshot()
    end)

    after_each(function()
      context:flush()
      handle_action_snapshot:revert()
    end)

    local session_start = {
      action = "START"
    }

    local session_stop = {
      action = "STOP"
    }

    local session_unknown = {
      action = "UNKNOWN"
    }

    local session_noaction = {}

    it("#nosession", function()
      ds:handle_action()
      assert.stub(ds.set_start_session).was.called(0)
      assert.stub(ds.set_stop_session).was.called(0)
    end)

    it("#start", function()
      ds:handle_action(session_start)
      assert.stub(ds.set_start_session).was.called_with(ds, session_start)
      assert.stub(ds.set_start_session).was.called(1)
      assert.stub(ds.set_stop_session).was.called(0)
    end)

    it("#stop", function()
      ds:handle_action(session_stop)
      assert.stub(ds.set_stop_session).was.called_with(ds, session_stop)
      assert.stub(ds.set_stop_session).was.called(1)
      assert.stub(ds.set_start_session).was.called(0)
    end)

    it("#unknown", function()
      ds:handle_action(session_unknown)
      assert.stub(ds.set_start_session).was.called(0)
      assert.stub(ds.set_stop_session).was.called(0)
    end)

    it("#noaction", function()
      ds:handle_action(session_noaction)
      assert.stub(ds.set_start_session).was.called(0)
      assert.stub(ds.set_stop_session).was.called(0)
    end)
  end)

  describe("#set_start_session", function()
    local set_start_session_snapshot

    before_each(function()
      -- TODO: is re-stubbing needed?
      set_start_session_snapshot = assert:snapshot()
      stub(kong.worker_events, "post")
      stub(ds, "init_session")
    end)

    after_each(function()
      context:flush()
      set_start_session_snapshot:revert()
    end)

    local session_start = {
      id = "session-id",
      action = "START"
    }

    it("#no session", function()
      assert(context:set_session({
        id = session_start.id,
        action = "START",
      }))

      ds:set_start_session()
      assert.stub(ds.init_session).was.called(0)
      assert.stub(kong.worker_events.post).was.called(0)
    end)

    it("#already started", function()
      assert(context:set_session(session_start))
      ds:set_start_session(session_start)
      assert.stub(ds.init_session).was.called(0)
      assert.stub(kong.worker_events.post).was.called(0)
    end)

    it("#active session and new incoming session TBD", function()
      assert(context:set_session({
        id = "completely-different-session-id",
        action = "START",
      }))
      stub(context, "set_session").returns(true)
      ds:set_start_session(session_start)
      assert.stub(context.set_session).was.called_with(context, session_start)
      assert.stub(kong.worker_events.post).was.called(1)
      assert.stub(kong.worker_events.post).was.called_with("debug_session", "start", {
        session_id = session_start.id
      })
    end)

    it("#no active session", function()
      ds:set_start_session(session_start)
      assert.stub(kong.worker_events.post).was.called(1)
      assert.stub(kong.worker_events.post).was.called_with("debug_session", "start", {
        session_id = session_start.id
      })
    end)
  end)

  describe("#set_stop_session", function()

    before_each(function()
      -- TODO: is re-stubbing needed?
      stub(kong.worker_events, "post")
      stub(ds, "init_session")
      spy.on(ds, "broadcast_end_session")
    end)

    after_each(function()
      context:flush()
    end)

    local session_stop = {
      id = "session-id",
      action = "STOP"
    }

    it("#no session", function()
      assert(context:set_session({
        id = session_stop.id,
        action = "STOP",
      }))
      ds:set_stop_session()
      assert.stub(kong.worker_events.post).was.called(0)
      assert.stub(ds.broadcast_end_session).was.called(0)
    end)

    it("#not running", function()
      -- check that we don't stop a running session when receiving a stop event for
      -- a different session
      assert(context:set_session({
        id = "another-session-id",
        action = "STOP",
      }))
      ds:set_stop_session(session_stop)
      assert.stub(kong.worker_events.post).was.called(0)
      assert.stub(ds.broadcast_end_session).was.called(0)
    end)

    it("#stopping the active session", function()
      assert(context:set_session(session_stop))
      ds:set_stop_session(session_stop)
      assert.stub(kong.worker_events.post).was.called(1)
      assert.spy(kong.worker_events.post).was.called_with("debug_session", "stop", {
        session_id = session_stop.id
      })
      assert.stub(ds.broadcast_end_session).was.called(1)
    end)
  end)

  describe("#broadcast_end_session", function()
    before_each(function()
      stub(reporter, "stop")
      stub(ds, "clear_session_data")
    end)

    it("stops the reporter and clears session data", function()
      ds:broadcast_end_session(123)
      assert.stub(kong.worker_events.post).was.called(1)
      assert.spy(kong.worker_events.post).was.called_with("debug_session", "stop", {
        session_id = 123
      })
      assert.stub(ds.clear_session_data).was.called(1)
    end)
  end)

  describe("#should_record_samples", function()
    after_each(function()
      context:flush()
    end)

    it("#no_active_session", function()
      assert.is_false(ds:should_record_samples())
    end)

    it("#active_session", function()
      context:set_session({
        id = "session-id",
        action = "START",
      })
      assert.is_true(ds:should_record_samples())
    end)

    it("#module_disabled", function()
      ds_mod.module_enabled = false
      context:set_session({
        id = "session-id",
        action = "START",
      })
      assert.is_false(ds:should_record_samples())
      ds_mod.module_enabled = true
    end)

    it("#ngx.ctx.ACTIVE_TRACING_skip_sample is true", function()
      context:set_session({
        id = "session-id",
        action = "START",
      })
      local ctx_key = utils.get_ctx_key("skip_sample")
      ngx.ctx[ctx_key] = true
      assert.is_false(ds:should_record_samples())
      ngx.ctx[ctx_key] = nil
    end)
  end)


  describe("#report", function()
    local report_snapshot
    local reporter = ds.reporter

    before_each(function()
      report_snapshot = assert:snapshot()
    end)

    after_each(function()
      report_snapshot:revert()
      context:flush()
    end)

    it("#active_session_and_done", function()
      -- do not report if there is no active session
      context:set_session({
        id = "session-id",
        action = "START",
      })
      stub(ds, "should_record_samples").returns(true)
      stub(reporter, "has_traces").returns(true)
      stub(context, "incr_counter")
      stub(context, "check_exceeded_max_samples").returns(true)
      stub(context, "expired")
      stub(reporter, "report_traces")
      ds:report()
      assert.stub(ds.should_record_samples).was.called(1)
      assert.stub(reporter.has_traces).was.called(1)
      assert.stub(context.incr_counter).was.called(1)
      assert.stub(context.check_exceeded_max_samples).was.called(1)
      -- returned before
      assert.stub(reporter.report_traces).was.called(0)
    end)

    it("#no_active_session", function()
      stub(context, "incr_counter")
      ds:report()
      assert.stub(context.incr_counter).was.called(0)
    end)

    it("#active_session_limit_not_reached", function()
      context:set_session({
        id = "session-id",
        action = "START",
      })
      stub(ds, "should_record_samples").returns(true)
      stub(reporter, "has_traces").returns(true)
      stub(context, "incr_counter")
      stub(context, "check_exceeded_max_samples").returns(false)
      stub(context, "is_session_expired").returns(false)
      stub(reporter, "report_traces")
      ds:report()
      assert.stub(ds.should_record_samples).was.called(1)
      assert.stub(reporter.has_traces).was.called(1)
      assert.stub(context.incr_counter).was.called(1)
      assert.stub(context.check_exceeded_max_samples).was.called(1)
      assert.stub(context.is_session_expired).was.called(1)
      assert.stub(reporter.report_traces).was.called(1)
    end)
  end)
end)
