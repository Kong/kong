local utils = require "kong.tools.utils"
local timestamp = require "kong.tools.timestamp"

describe("Timestamp", function()

  it("should get UTC time", function()
    assert.truthy(timestamp.get_utc())
    assert.are.same(13, string.len(tostring(timestamp.get_utc())))
  end)

  it("should get timestamps table when no timestamp is provided", function()
    local timestamps = timestamp.get_timestamps()
    assert.truthy(timestamps)
    assert.are.same(6, utils.table_size(timestamps))

    assert.truthy(timestamps.second)
    assert.truthy(timestamps.minute)
    assert.truthy(timestamps.hour)
    assert.truthy(timestamps.day)
    assert.truthy(timestamps.month)
    assert.truthy(timestamps.year)
  end)

  it("should get timestamps table when no timestamp is provided", function()
    local timestamps = timestamp.get_timestamps(timestamp.get_utc())
    assert.truthy(timestamps)
    assert.are.same(6, utils.table_size(timestamps))

    assert.truthy(timestamps.second)
    assert.truthy(timestamps.minute)
    assert.truthy(timestamps.hour)
    assert.truthy(timestamps.day)
    assert.truthy(timestamps.month)
    assert.truthy(timestamps.year)
  end)

  it("should give the same timestamps table for the same time", function()
    -- Wait til the beginning of a new second before starting the test
    -- to avoid ending up in an edge case when the second is about to end
    local now = os.time()
    while os.time() < now + 1 do
      -- Nothing
    end

    local timestamps_one = timestamp.get_timestamps()
    local timestamps_two = timestamp.get_timestamps(timestamp.get_utc())
    assert.truthy(timestamps_one)
    assert.truthy(timestamps_two)
    assert.are.same(6, utils.table_size(timestamps_one))
    assert.are.same(6, utils.table_size(timestamps_two))
    assert.are.same(timestamps_one, timestamps_two)
  end)

end)
