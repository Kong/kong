local uuid = require "resty.jit-uuid"
local helpers = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local ratelimiting_metrics = helpers.dao.ratelimiting_metrics

describe("Plugin: rate-limiting (DAO)", function()
  local api_id = uuid()
  local identifier = uuid()

  setup(function()
    helpers.dao:truncate_tables()
  end)
  after_each(function()
    helpers.dao:truncate_tables()
  end)

  it("should return nil when rate-limiting metrics are not existing", function()
    local current_timestamp = 1424217600
    local periods = timestamp.get_timestamps(current_timestamp)
    -- Very first select should return nil
    for period, period_date in pairs(periods) do
      local metric, err = ratelimiting_metrics:find(api_id, identifier, current_timestamp, period)
      assert.falsy(err)
      assert.same(nil, metric)
    end
  end)

  it("should increment rate-limiting metrics with the given period", function()
    local current_timestamp = 1424217600
    local periods = timestamp.get_timestamps(current_timestamp)

    -- First increment
    local ok, err = ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1)
    assert.falsy(err)
    assert.True(ok)

    -- First select
    for period, period_date in pairs(periods) do
      local metric, err = ratelimiting_metrics:find(api_id, identifier, current_timestamp, period)
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = period,
        period_date = period_date,
        value = 1 -- The important part
      }, metric)
    end

    -- Second increment
    local ok = ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1)
    assert.True(ok)

    -- Second select
    for period, period_date in pairs(periods) do
      local metric, err = ratelimiting_metrics:find(api_id, identifier, current_timestamp, period)
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = period,
        period_date = period_date,
        value = 2 -- The important part
      }, metric)
    end

    -- 1 second delay
    current_timestamp = 1424217601
    periods = timestamp.get_timestamps(current_timestamp)

     -- Third increment
    local ok = ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1)
    assert.True(ok)

    -- Third select with 1 second delay
    for period, period_date in pairs(periods) do

      local expected_value = 3

      if period == "second" then
        expected_value = 1
      end

      local metric, err = ratelimiting_metrics:find(api_id, identifier, current_timestamp, period)
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = period,
        period_date = period_date,
        value = expected_value -- The important part
      }, metric)
    end
  end)
end) -- describe rate limiting metrics
