local portal_utils  = require "kong.portal.utils"

describe("portal_utils", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("pluralize_time", function()
    it("should return time with the unit if value is 1", function()
      local res = portal_utils.pluralize_time(1, "second")
      assert.equal("1 second", res)
    end)

    it("should return time with the unit (pluralized) if value is not 1", function()
      local res = portal_utils.pluralize_time(0, "second")
      assert.equal("0 seconds", res)

      local res = portal_utils.pluralize_time(5, "hour")
      assert.equal("5 hours", res)
    end)
  end)

  describe("append_time", function()
    it("should add the time to the string if value is greater than 0", function()
      local time_str = "1 hour"
      local value    = 5

      local res = portal_utils.append_time(value, "minute", time_str)
      assert.equal("1 hour 5 minutes", res)
    end)

    it("should add the time to the string if value is 0 and append_zero flag passed", function()
      local time_str    = "6 days"
      local value       = 0
      local append_zero = true

      local res = portal_utils.append_time(value, "minute", time_str, append_zero)
      assert.equal("6 days 0 minutes", res)
    end)

    it("should not add the time to the string if value is 0 and append_zero flag is not passed", function()
      local time_str = "12 minutes"
      local value    = 0

      local res = portal_utils.append_time(value, "seconds", time_str)
      assert.equal("12 minutes", res)
    end)
  end)

  describe("humanize_timestamp", function()
    it("should convert timestamp to a humanized string", function()
      local res = portal_utils.humanize_timestamp(3605)
      assert.equal("1 hour 5 seconds", res)

      res = portal_utils.humanize_timestamp(16)
      assert.equal("16 seconds", res)

      res = portal_utils.humanize_timestamp(183)
      assert.equal("3 minutes 3 seconds", res)

      res = portal_utils.humanize_timestamp(3600)
      assert.equal("1 hour", res)

      res = portal_utils.humanize_timestamp(65000)
      assert.equal("18 hours 3 minutes 20 seconds", res)

      res = portal_utils.humanize_timestamp(5632012)
      assert.equal("65 days 4 hours 26 minutes 52 seconds", res)

      res = portal_utils.humanize_timestamp(53940)
      assert.equal("14 hours 59 minutes", res)
    end)

    it("should include zeros if append_zero flag passed", function()
      local res = portal_utils.humanize_timestamp(3605, true)
      assert.equal("0 days 1 hour 0 minutes 5 seconds", res)

      res = portal_utils.humanize_timestamp(16, true)
      assert.equal("0 days 0 hours 0 minutes 16 seconds", res)

      res = portal_utils.humanize_timestamp(183, true)
      assert.equal("0 days 0 hours 3 minutes 3 seconds", res)

      res = portal_utils.humanize_timestamp(3600, true)
      assert.equal("0 days 1 hour 0 minutes 0 seconds", res)

      res = portal_utils.humanize_timestamp(65000, true)
      assert.equal("0 days 18 hours 3 minutes 20 seconds", res)

      res = portal_utils.humanize_timestamp(5632012, true)
      assert.equal("65 days 4 hours 26 minutes 52 seconds", res)

      res = portal_utils.humanize_timestamp(53940, true)
      assert.equal("0 days 14 hours 59 minutes 0 seconds", res)
    end)
  end)
end)
