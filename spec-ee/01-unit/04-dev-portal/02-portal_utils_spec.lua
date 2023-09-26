-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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

  describe("should sanitize developer name correctly", function ()
    it("should replace &, <, >, \", ', / with their HTML entities", function ()
      local res = portal_utils.sanitize_developer_name("&amp;<script>alert('foo' + \"bar\")</script>")
      assert.equal(res, "<a href=\"\">&amp;amp;&lt;script&gt;alert(&#39;foo&#39; + &quot;bar&quot;)&lt;&#47;script&gt;</a>")
    end)

    it("should wrap name with <a> tag if it may be recognized as link", function ()
      local res = portal_utils.sanitize_developer_name("foo.bar")
      assert.equal(res, '<a href="">foo.bar</a>')

      res = portal_utils.sanitize_developer_name("https://foo.bar")
      assert.equal(res, '<a href="">https:&#47;&#47;foo.bar</a>')

      res = portal_utils.sanitize_developer_name("foo//bar")
      assert.equal(res, '<a href="">foo&#47;&#47;bar</a>')

      res = portal_utils.sanitize_developer_name("username:password@localhost")
      assert.equal(res, '<a href="">username:password@localhost</a>')
    end)

    it("should not sanitize non-string values", function ()
      local res = portal_utils.sanitize_developer_name(123)
      assert.equal(res, 123)

      res = portal_utils.sanitize_developer_name({ foo = "bar" })
      assert.same(res, { foo = "bar" })

      res = portal_utils.sanitize_developer_name(nil)
      assert.equal(res, nil)
    end)
  end)
end)
