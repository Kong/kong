describe("describe kong.plugins.collector.backend", function()
  local backend = require("kong.plugins.collector.backend")
  local http = require("resty.http")
  local match = require("luassert.match")

  describe("http_get", function()
    local expected_response = {}
    local expected_error = {}
    local host = "localhost"
    local port = 5000
    local timeout = 30
    local path = "/"
    local query = "test=1"
    local http_returned = {}
    function http_returned:connect(host, port) return true, false end
    function http_returned:set_timeout(timeout)  end
    function http_returned:request(args) return expected_response, expected_error end

    local http_mock = mock(http_returned)

    setup(function()
      http.new = function() return http_mock end
    end)

    teardown(function()
      mock.revert(http_mock)
    end)

    it("it prepares correctly before request", function()
      backend.http_get(host, port, timeout, path, query)
      assert.spy(http_mock.set_timeout).was.called_with(match.is_ref(http_returned), timeout)
      assert.spy(http_mock.connect).was.called_with(match.is_ref(http_returned), host, port)
    end)

    it("it forwards path and query correctly", function()
      backend.http_get(host, port, timeout, path, query)
      local parameters = { method = "GET", path = path, query = query }
      assert.spy(http_mock.request).was.called_with(match.is_ref(http_returned), parameters)
    end)

    it("it returns response and error", function()
      local response, response_error = backend.http_get(host, port, timeout, path, query)
      assert.are.same(response, expected_response)
      assert.are.same(response_error, expected_error)
    end)
  end)
end)
