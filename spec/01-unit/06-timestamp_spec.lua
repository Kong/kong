local timestamp = require "kong.tools.timestamp"
local luatz = require "luatz"
local pl_path = require "pl.path"

describe("Timestamp", function()
  local table_size = function(t)
    local s = 0
    for _ in pairs(t) do s = s + 1 end
    return s
  end

  it("should get UTC time", function()
    assert.truthy(timestamp.get_utc())
    assert.are.same(13, #tostring(timestamp.get_utc()))
  end)

  it("should get timestamps table when no timestamp is provided", function()
    local timestamps = timestamp.get_timestamps()
    assert.truthy(timestamps)
    assert.are.same(6, table_size(timestamps))

    assert.truthy(timestamps.second)
    assert.truthy(timestamps.minute)
    assert.truthy(timestamps.hour)
    assert.truthy(timestamps.day)
    assert.truthy(timestamps.month)
    assert.truthy(timestamps.year)
  end)

  it("should get timestamps table when the timestamp is provided", function()
    local timestamps = timestamp.get_timestamps(timestamp.get_utc())
    assert.truthy(timestamps)
    assert.are.same(6, table_size(timestamps))

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
    assert.are.same(6, table_size(timestamps_one))
    assert.are.same(6, table_size(timestamps_two))
    assert.are.same(timestamps_one, timestamps_two)
  end)

  it("should provide correct timestamp values", function()
    for i = 1, 2 do
      local factor
      if i == 1 then
        factor = 1  -- use base time in seconds
      else
        factor = 1000 -- use base time in milliseconds
      end
      local base = luatz.timetable.new(2016, 10, 10, 10, 10, 10):timestamp()
      local ts = timestamp.get_timestamps(base * factor)
      -- timestamps are always in milliseconds
      assert.equal(base * 1000, ts.second)
      base = base - 10
      assert.equal(base * 1000, ts.minute)
      base = base - 10 * 60
      assert.equal(base * 1000, ts.hour)
      base = base - 10 * 60 * 60
      assert.equal(base * 1000, ts.day)
      base = base - 9 * 60 * 60 * 24
      assert.equal(base * 1000, ts.month)
      base = base - (31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30) * 60 * 60 * 24
      assert.equal(base * 1000, ts.year)
    end
  end)

  it("should get correct local timestamp when local timezone is UTC", function()
    local localtime_symlink = pl_path.exists("/etc/localtime")
    if localtime_symlink then
      os.execute("mv /etc/localtime /etc/localtime_backup")
    end
    local utc_timestamp = timestamp.get_utc()
    local local_timestamp = timestamp.get_tz_time()
    -- both are in milliseconds so the difference is less than a second
    local time_offset = local_timestamp - utc_timestamp
    assert.is_true(time_offset > 0)
    assert.is_true(time_offset < 1000)
    if localtime_symlink then
      os.execute("mv /etc/localtime_backup /etc/localtime")
    end
  end)

  it("should get correct local timestamp when timezone is UTC+1", function()
    local utc_timestamp = timestamp.get_utc()
    local local_timestamp = timestamp.get_tz_time("Europe/London")
    --- timezone offset should be 1 hour
    local time_offset = local_timestamp - utc_timestamp - 60 * 60 * 1000
    assert.is_true(time_offset < 1000)
    assert.is_true(time_offset > 0)
  end)

  it("should get correct local timestamp when local timezone is set to UTC+1", function ()
    local localtime_symlink = pl_path.exists("/etc/localtime")
    if localtime_symlink then
      os.execute("mv /etc/localtime /etc/localtime_backup")
    end
    os.execute("ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime")
    local utc_timestamp = timestamp.get_utc()
    local local_timestamp = timestamp.get_tz_time()
    local time_offset = local_timestamp - utc_timestamp - 60 * 60 * 1000
    assert.is_true(time_offset < 1000)
    assert.is_true(time_offset > 0)
    os.execute("rm /etc/localtime")
    if localtime_symlink then
      os.execute("mv /etc/localtime_backup /etc/localtime")
    end
  end)
end)
