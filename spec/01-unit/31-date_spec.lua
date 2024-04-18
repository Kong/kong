-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local date_tools = require "kong.tools.date"

describe("aip_date_to_timestamp", function()
  describe("when using correct date format (RFC3339)", function()
    it("converts date to timestamp", function()
      -- passing timestamp here explictly to avoid timezone problems
      assert.same(1710167467, date_tools.aip_date_to_timestamp("2024-03-11T14:31:07Z"))
    end)
  end)

  describe("when using incorrect date format", function()
    it("returns error for date with timezone offset", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2013-07-02T09:00:00-07:00")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2013-07-02T09:00:00-07:00' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with fractions of a second", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-11T14:31:07.533Z")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-11T14:31:07.533Z' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date missing Z letter", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-11T14:31:07")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-11T14:31:07' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with something after Z letter", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-11T14:31:07Z32")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-11T14:31:07Z32' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with missing seconds", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-11T14:31Z")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-11T14:31Z' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with missing minutes", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-11T14Z")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-11T14Z' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with only date", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03-10")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03-10' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with year and month", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-03")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-03' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date with only year", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("2024-")
      assert.is_nil(timestamp)
      assert.same(err, "date param: '2024-' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)

    it("returns error for date completely wrong string", function()
      local timestamp, err = date_tools.aip_date_to_timestamp("something-else")
      assert.is_nil(timestamp)
      assert.same(err, "date param: 'something-else' does not match expected format: YYYY-MM-DDTHH:MI:SSZ")
    end)
  end)
end)
