local fixtures = require "spec.plugins.mashape-analytics.fixtures.requests"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

-- @see http://lua-users.org/wiki/CopyTable
local function deepcopy(orig)
  local copy = {}
  if type(orig) == "table" then
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

local function sameEntry(state, arguments)
  local fixture_entry = deepcopy(arguments[1])
  local entry = deepcopy(arguments[2])

  local delta = 0.000000000000001
  -- Compare timings
  for k, fixture_timer in pairs(fixture_entry.timings) do
    assert.True(math.abs(entry.timings[k] - fixture_timer) < delta)
  end

  -- Compare time property
  assert.True(math.abs(entry.time - fixture_entry.time) < delta)

  -- Compare things that are not computed in the same order depending on the platform
  assert.are.equal(#(fixture_entry.request.headers), #(entry.request.headers))
  assert.are.equal(#(fixture_entry.request.queryString), #(entry.request.queryString))
  assert.are.equal(#(fixture_entry.response.headers), #(entry.response.headers))

  entry.time = nil
  entry.timings = nil
  fixture_entry.time = nil
  fixture_entry.timings = nil

  entry.request.headers = nil
  entry.response.headers = nil
  entry.request.queryString = nil
  fixture_entry.request.headers = nil
  fixture_entry.response.headers = nil
  fixture_entry.request.queryString = nil

  assert.are.same(fixture_entry, entry)

  return true
end

local say = require("say")
say:set("assertion.sameEntry.positive", "Not the same entries")
say:set("assertion.sameEntry.negative", "Not the same entries")
assert:register("assertion", "sameEntry", sameEntry, "assertion.sameEntry.positive", "assertion.sameEntry.negative")

describe("ALF serializer", function()

  local alf

  describe("#new_alf()", function ()

    it("should create a new ALF", function()
      alf = ALFSerializer:new_alf()
      assert.same({
        version = "1.0.0",
        serviceToken = "",
        har = {
          log = {
            version = "1.2",
            creator = {name = "mashape-analytics-agent-kong", version = "1.0.0"},
            entries = {}
          }
        }
      }, alf)
    end)

  end)

  describe("#serialize_entry()", function()

    it("should serialize an ngx GET request/response", function()
      local entry = alf:serialize_entry(fixtures.GET.NGX_STUB)
      assert.are.sameEntry(fixtures.GET.ENTRY, entry)
    end)

  end)

  describe("#add_entry()", function()

    it("should add the entry to the serializer entries property", function()
      alf:add_entry(fixtures.GET.NGX_STUB)
      assert.equal(1, table.getn(alf.har.log.entries))
      assert.are.sameEntry(fixtures.GET.ENTRY, alf.har.log.entries[1])

      alf:add_entry(fixtures.GET.NGX_STUB)
      assert.equal(2, table.getn(alf.har.log.entries))
      assert.are.sameEntry(fixtures.GET.ENTRY, alf.har.log.entries[2])
    end)

    it("#new_alf() should instanciate a new ALF that has nothing to do with the existing one", function()
      local other_alf = ALFSerializer:new_alf()
      assert.are_not_same(alf, other_alf)
    end)

    it("should handle timing calculation if multiple upstreams were called", function()
      alf:add_entry(fixtures.MULTIPLE_UPSTREAMS.NGX_STUB)
      assert.equal(3, table.getn(alf.har.log.entries))
      assert.are.sameEntry(fixtures.MULTIPLE_UPSTREAMS.ENTRY, alf.har.log.entries[3])
      assert.equal(123, alf.har.log.entries[3].timings.wait)
    end)

  end)

  describe("#to_json_string()", function()

    it("should throw an error if no token was given", function()
      assert.has_error(function() alf:to_json_string() end,
        "Mashape Analytics serviceToken required")
    end)

    it("should return a JSON string", function()
      local json_str = alf:to_json_string("stub_service_token")
      assert.equal("string", type(json_str))
    end)

    it("should add an environment property", function()
      local json = require "cjson"
      local json_str = alf:to_json_string("stub_service_token", "test")
      assert.equal("string", type(json_str))
      local json_alf = json.decode(json_str)
      assert.equal(json_alf.environment, "test")
    end)
  end)

  describe("#flush_entries()", function()

    it("should remove any existing entry", function()
      alf:flush_entries()
      assert.equal(0, table.getn(alf.har.log.entries))
    end)

  end)
end)
