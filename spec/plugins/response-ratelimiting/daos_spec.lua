local spec_helper = require "spec.spec_helpers"
local timestamp = require "kong.tools.timestamp"
local uuid = require "lua_uuid"

local env = spec_helper.get_env()
local dao_factory = env.dao_factory
local response_ratelimiting_metrics = dao_factory.response_ratelimiting_metrics

describe("Rate Limiting Metrics", function()
  local api_id = uuid()
  local identifier = uuid()

  setup(function()
    dao_factory:drop_schema()
    spec_helper.prepare_db()
  end)

  after_each(function()
    spec_helper.drop_db()
  end)

  it("should return nil when ratelimiting metrics are not existing", function()
    local current_timestamp = 1424217600
    local periods = timestamp.get_timestamps(current_timestamp)
    -- Very first select should return nil
    for period, period_date in pairs(periods) do
      local metric, err = response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, period, "video")
      assert.falsy(err)
      assert.are.same(nil, metric)
    end
  end)

  it("should increment ratelimiting metrics with the given period", function()
    local current_timestamp = 1424217600
    local periods = timestamp.get_timestamps(current_timestamp)

    -- First increment
    local ok = response_ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1, "video")
    assert.True(ok)

    -- First select
    for period, period_date in pairs(periods) do
      local metric, err = response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, period, "video")
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = "video_"..period,
        period_date = period_date,
        value = 1 -- The important part
      }, metric)
    end

    -- Second increment
    local ok = response_ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1, "video")
    assert.True(ok)

    -- Second select
    for period, period_date in pairs(periods) do
      local metric, err = response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, period, "video")
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = "video_"..period,
        period_date = period_date,
        value = 2 -- The important part
      }, metric)
    end

    -- 1 second delay
    current_timestamp = 1424217601
    periods = timestamp.get_timestamps(current_timestamp)

     -- Third increment
    local ok = response_ratelimiting_metrics:increment(api_id, identifier, current_timestamp, 1, "video")
    assert.True(ok)

    -- Third select with 1 second delay
    for period, period_date in pairs(periods) do

      local expected_value = 3

      if period == "second" then
        expected_value = 1
      end

      local metric, err = response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, period, "video")
      assert.falsy(err)
      assert.same({
        api_id = api_id,
        identifier = identifier,
        period = "video_"..period,
        period_date = period_date,
        value = expected_value -- The important part
      }, metric)
    end
  end)
end)
