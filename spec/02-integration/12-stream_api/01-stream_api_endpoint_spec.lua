-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local stream_api = require "kong.tools.stream_api"

describe("Stream module API endpoint", function()

  local socket_path

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      stream_listen = "127.0.0.1:8008",
      plugins = "stream-api-echo",
    })

    socket_path = "unix:" .. helpers.get_running_conf().prefix .. "/stream_rpc.sock"
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("creates listener", function()
    it("error response for unknown path", function()
      local res, err = stream_api.request("not-this", "nope", socket_path)
      assert.is.falsy(res)
      assert.equal("no handler", err)
    end)

    it("calls an echo handler", function ()
      local res, err = stream_api.request("stream-api-echo", "ping!", socket_path)
      assert.equal("back: ping!", res)
      assert.is_nil(err)
    end)

  end)
end)
