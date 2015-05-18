local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local TCP_PORT = 7771

describe("DNS", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("DNS", function()

    it("should work when calling local IP", function()
      local thread = spec_helper.start_tcp_server(TCP_PORT) -- Starting the mock TCP server

      local _, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns1.com" })
      assert.are.equal(200, status)

      thread:join() -- Wait til it exists
    end)

    it("should work when calling local hostname", function()
      local thread = spec_helper.start_tcp_server(TCP_PORT) -- Starting the mock TCP server

      local _, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns2.com" })
      assert.are.equal(200, status)

      thread:join() -- Wait til it exists
    end)

  end)

end)
