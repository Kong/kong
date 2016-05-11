local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local UUID_COUNTER_PATTERN = UUID_PATTERN.."#%d"
local DEFAULT_HEADER_NAME = "Kong-Request-ID"

describe("Correlation ID Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "correlation1.com", upstream_url = "http://mockbin.com"},
        {request_host = "correlation2.com", upstream_url = "http://mockbin.com"},
        {request_host = "correlation3.com", upstream_url = "http://mockbin.com"},
        {request_host = "correlation4.com", upstream_url = "http://mockbin.com"}
      },
      plugin = {
        {name = "correlation-id", config = {echo_downstream = true}, __api = 1},
        {name = "correlation-id", config = {header_name = "Foo-Bar-Id", echo_downstream = true}, __api = 2},
        {name = "correlation-id", config = {generator = "uuid", echo_downstream = true}, __api = 3},
        {name = "correlation-id", config = {}, __api = 4},
      }
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  local function test_with(host, header, pattern)
    local res1, status1, headers1 = http_client.get(STUB_GET_URL, nil, {host = host})
    assert.equal(200, status1)
    local json1 = cjson.decode(res1)
    local id1 = json1.headers[header:lower()] -- headers received by upstream (mockbin)
    assert.matches(pattern, id1)
    assert.equal(id1, headers1[header:lower()]) -- headers echoed back downstream

    local res2, status2, headers2 = http_client.get(STUB_GET_URL, nil, {host = host})
    assert.equal(200, status2)
    local json2 = cjson.decode(res2)
    local id2 = json2.headers[header:lower()] -- headers received by upstream (mockbin)
    assert.matches(pattern, id2)
    assert.equal(id2, headers2[header:lower()]) -- headers echoed back downstream

    assert.not_equals(id1, id2)

    -- TODO kong_TEST.yml's worker_processes has to be 1 for the below to work.
    --[[
    if pattern == UUID_COUNTER_PATTERN then
      local uuid1 = correlation_id1:sub(0, -3)
      local uuid2 = correlation_id2:sub(0, -3)
      assert.equals(uuid1, uuid2)

      local counter1 = correlation_id1:sub(-1)
      local counter2 = correlation_id2:sub(-1)
      assert.True(counter1 + 1 == counter2)
    end
    --]]
  end

  describe("uuid-worker generator", function()
    it("increments the counter", function()
      test_with("correlation1.com", DEFAULT_HEADER_NAME, UUID_COUNTER_PATTERN)
    end)

    it("uses the header name in the configuration", function()
      test_with("correlation2.com", "Foo-Bar-Id", UUID_COUNTER_PATTERN)
    end)
  end)

  describe("uuid genetator", function()
    it("generates a unique UUID for every request using default header", function()
      test_with("correlation3.com", DEFAULT_HEADER_NAME, UUID_PATTERN)
    end)
  end)

  it("preserves an already existing header", function()
    local existing_correlation_id = "foo"
    local response, status = http_client.get(
      STUB_GET_URL,
      nil,
      {host = "correlation1.com", [DEFAULT_HEADER_NAME] = existing_correlation_id})
    assert.equal(200, status)
    local id = cjson.decode(response).headers[DEFAULT_HEADER_NAME:lower()] -- as received by upstream
    assert.equals(existing_correlation_id, id)
  end)

  it("does not echo back the correlation header if not asked to", function()
    local _, status, headers = http_client.get(STUB_GET_URL, nil, {host = "correlation4.com"})
    assert.equal(200, status)
    local id = headers[DEFAULT_HEADER_NAME:lower()]
    assert.falsy(id)
  end)
end)
