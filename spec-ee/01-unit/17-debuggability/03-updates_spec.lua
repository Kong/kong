-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local updates_mod = require "kong.enterprise_edition.debug_session.updates"

describe("debuggability - reporter", function()
  setup(function()
    helpers.get_db_utils("off")
    kong.rpc = kong.rpc or {}
  end)

  describe("#get", function ()
    it("makes the expected rpc call to get updates", function()
      stub(kong.rpc, "call")

      local event_id = "foo"
      updates_mod.get(event_id)

      assert.stub(kong.rpc.call).was.called_with(kong.rpc, "control_plane", "kong.debug_session.v1.get_updates", event_id)
    end)
  end)

  describe("#report_state", function ()
    it("reports the state via rpc", function()
      stub(kong.rpc, "call")

      local session_id = "bar"
      local state = "some_state"
      updates_mod.report_state(session_id, state)

      assert.stub(kong.rpc.call).was.called_with(kong.rpc, "control_plane", "kong.debug_session.v1.set_some_state", session_id)
    end)

    it("defaults to done state", function()
      stub(kong.rpc, "call")

      local session_id = "bar"
      updates_mod.report_state(session_id)

      assert.stub(kong.rpc.call).was.called_with(kong.rpc, "control_plane", "kong.debug_session.v1.set_done", session_id)
    end)
  end)
end)
