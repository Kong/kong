-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local reporter_mod = require "kong.enterprise_edition.debug_session.reporter"

describe("debuggability - reporter", function()
  local reporter
  local dispatcher

  setup(function()
    helpers.get_db_utils("off")
    reporter = reporter_mod:new()
    dispatcher = reporter.dispatcher
  end)

  describe("#init", function ()
    it("initializes the telemetry dispatcher", function()
      stub(dispatcher, "init_connection")
      reporter:init()

      assert.stub(dispatcher.init_connection).was.called(1)
    end)
  end)

  describe("#stop", function ()
    it("stops the telemetry dispatcher", function()
      stub(dispatcher, "stop")
      reporter:stop()

      assert.stub(dispatcher.stop).was.called(1)
    end)
  end)

  describe("#encode_and_send", function ()
    it("sends the encoded data through the dispatcher", function()
      local conf = {
        encoding_func = function() end,
        dispatcher = dispatcher,
      }
      local data = { foo = "bar" }

      stub(dispatcher, "is_initialized").returns(true)
      stub(dispatcher, "is_connected").returns(true)
      stub(dispatcher, "send").returns(true)
      stub(conf, "encoding_func").returns(data)

      reporter._encode_and_send(conf, data)

      assert.stub(dispatcher.is_initialized).was.called(2)
      assert.stub(dispatcher.is_connected).was.called(3)
      assert.stub(conf.encoding_func).was.called_with(data, {})
      assert.stub(dispatcher.send).was.called_with(dispatcher, data)
    end)
  end)

  describe("#dispatcher_send", function ()
    it("initializes the dispatcher if not initialized", function()
      stub(dispatcher, "is_initialized").returns(false)
      stub(dispatcher, "init_connection")
      reporter._dispatcher_send(dispatcher, {})

      assert.stub(dispatcher.init_connection).was.called(1)
    end)

    it("stops the dispatcher if initialized but not connected", function()
      stub(dispatcher, "is_initialized").returns(true)
      stub(dispatcher, "is_connected").returns(false)
      stub(dispatcher, "init_connection")
      stub(dispatcher, "stop")

      reporter._dispatcher_send(dispatcher, {})

      assert.stub(dispatcher.stop).was.called(1)
      assert.stub(dispatcher.init_connection).was.called(1)
    end)

    it("sends the payload through the dispatcher", function()
      stub(dispatcher, "is_initialized").returns(true)
      stub(dispatcher, "is_connected").returns(true)
      stub(dispatcher, "send").returns(true)

      local payload = { foo = "bar" }
      local ok, err = reporter._dispatcher_send(dispatcher, payload)

      assert.equals(ok, true)
      assert.is_nil(err)
      assert.stub(dispatcher.send).was.called_with(dispatcher, payload)
    end)
  end)
end)
