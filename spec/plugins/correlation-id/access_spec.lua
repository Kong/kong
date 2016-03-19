local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local json = require "cjson"

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
        {request_host = "correlation3.com", upstream_url = "http://mockbin.com"}
      },
      plugin = {
        {name = "correlation-id", config = {}, __api = 1},
        {name = "correlation-id", config = {header_name = "Foo-Bar-Id"}, __api = 2},
        {name = "correlation-id", config = {generator = "uuid"}, __api = 3}
      }
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  local function test_with(host, header, pattern)
    local response1, status1 = http_client.get(STUB_GET_URL, nil, {host = host})
    assert.equal(200, status1)
    local correlation_id1 = json.decode(response1).headers[header:lower()]
    assert.truthy(correlation_id1:match(pattern))

    local response2, status2 = http_client.get(STUB_GET_URL, nil, {host = host})
    assert.equal(200, status2)
    local correlation_id2 = json.decode(response2).headers[header:lower()]
    assert.truthy(correlation_id2:match(pattern))

    assert.are_not_equals(correlation_id1, correlation_id2)

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

  it("should increment the counter", function()
    test_with("correlation1.com", DEFAULT_HEADER_NAME, UUID_COUNTER_PATTERN)
  end)

  it("should use the header in the configuration", function()
    test_with("correlation2.com", "Foo-Bar-Id", UUID_COUNTER_PATTERN)
  end)

  it("should generate a unique UUID for every request using default header", function()
    test_with("correlation3.com", DEFAULT_HEADER_NAME, UUID_PATTERN)
  end)

  it("should honour the existing header", function()
    local existing_correlation_id = "foo"
    local response, status = http_client.get(
      STUB_GET_URL,
      nil,
      {host = "correlation1.com", [DEFAULT_HEADER_NAME] = existing_correlation_id})
    assert.equal(200, status)
    local correlation_id = json.decode(response).headers[DEFAULT_HEADER_NAME:lower()]
    assert.equals(existing_correlation_id, correlation_id)
  end)
end)
