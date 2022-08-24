-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G._TEST = true
describe("timestamp generated", function()
  local strategy = require "kong.vitals.influxdb.strategy"
  local socket = require "socket"
  it("generates a full microsecond precision unix timestamp", function()
    -- Roll the time dice a bunch of times generate a bunch of timestamps.
    -- the origin of the was leading 0s in tv_usec causing us timestamps to
    -- drop a digit due to string concatination instead of arithmetic
    for i = 0, 10, 1
      do
        local timestring = strategy.gettimeofday()
        assert.are.same(#timestring, 16)
        socket.sleep(0.1)
      end
  end)
end)

describe("authorization_headers", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("given user and password nil", function()
    it("creates empty table", function()
      assert.are.same({}, strategy.authorization_headers(nil, nil))
    end)
  end)

  describe("given user and password", function()
    it("creates table with Authorization header", function()
      local expected = { ["Authorization"] = "Basic a29uZzprb25n" }
      assert.are.same(expected, strategy.authorization_headers("kong", "kong"))
    end)
  end)
end)

describe("get_flush_params", function()
  local helpers = require "spec.helpers"
  local strategy = require "kong.vitals.influxdb.strategy"
  local vitals = require "kong.vitals"

  describe("given user and password", function()
    it("auth will be added to flush request parameters", function()
      local db = select(2, helpers.get_db_utils())
      kong.configuration = {
        vitals = true,
        vitals_strategy = "influxdb",
        vitals_tsdb_address = "1.2.3.4",
        vitals_tsdb_user = "kong_user",
        vitals_tsdb_password = "kong_password"
      }
      vitals.new({db = db})
      local expected = {
        body="test message",
        method="POST",
        headers={
          Authorization = "Basic a29uZ191c2VyOmtvbmdfcGFzc3dvcmQ="
        }
      }
      assert.are.same(expected, strategy.get_flush_params("test message"))
    end)
  end)

  describe("given no user and password", function()
    it("no auth will be added to flush request parameters", function()
      local db = select(2, helpers.get_db_utils())
      kong.configuration = {
        vitals = true,
        vitals_strategy = "influxdb",
        vitals_tsdb_address = "1.2.3.4"
      }
      vitals.new({db = db})
      local expected = {
        body="test message",
        method="POST",
        headers={}
      }
      assert.are.same(expected, strategy.get_flush_params("test message"))
    end)
  end)
end)

describe("prepend_protocol", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("when tsdb_address doesn't have protocol", function()
    it("prepends http", function()
      assert.are.same("http://teddy.bear", strategy.prepend_protocol("teddy.bear"))
    end)
  end)

  describe("when tsdb_address has protocol", function()
    it("keeps the original address", function()
      assert.are.same("https://safe.bear", strategy.prepend_protocol("https://safe.bear"))
    end)
  end)
end)
