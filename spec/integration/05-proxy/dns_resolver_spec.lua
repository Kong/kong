local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local TCP_PORT = spec_helper.find_port()

describe("DNS", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-dns-1", request_host = "dns1.com", upstream_url = "http://127.0.0.1:"..TCP_PORT },
        { name = "tests-dns-2", request_host = "dns2.com", upstream_url = "http://localhost:"..TCP_PORT }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("DNS", function()
    it("should work when calling local IP", function()
      local thread = spec_helper.start_http_server(TCP_PORT) -- Starting the mock TCP server

      local _, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns1.com" })
      assert.are.equal(200, status)

      thread:join()
    end)
    it("should work when calling local hostname", function()
      local thread = spec_helper.start_http_server(TCP_PORT) -- Starting the mock TCP server
      local _, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns2.com" })
      assert.are.equal(200, status)
      thread:join()
    end)
  end)
end)
