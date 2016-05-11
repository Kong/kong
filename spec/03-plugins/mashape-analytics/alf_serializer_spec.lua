require "kong.tools.ngx_stub"
local fixtures = require "spec.plugins.mashape-analytics.fixtures.requests"
local ALFSerializer = require "kong.plugins.log-serializers.alf"

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
  assert.equal(#(fixture_entry.request.headers), #(entry.request.headers))
  assert.equal(#(fixture_entry.request.queryString), #(entry.request.queryString))
  assert.equal(#(fixture_entry.response.headers), #(entry.response.headers))

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
  describe("#serialize_entry()", function()
    it("should serialize an ngx GET request/response", function()
      local entry = ALFSerializer.serialize_entry(fixtures.GET.NGX_STUB)
      assert.are.sameEntry(fixtures.GET.ENTRY, entry)
    end)

    it("should handle timing calculation if multiple upstreams were called", function()
      local entry = ALFSerializer.serialize_entry(fixtures.MULTIPLE_UPSTREAMS.NGX_STUB)
      assert.are.sameEntry(fixtures.MULTIPLE_UPSTREAMS.ENTRY, entry)
      assert.equal(236, entry.timings.wait)
    end)

    it("should return the last header if two are present for mimeType", function()
      local entry = ALFSerializer.serialize_entry(fixtures.MULTIPLE_HEADERS.NGX_STUB)
      assert.are.sameEntry(fixtures.MULTIPLE_HEADERS.ENTRY, entry)
    end)
  end)

  describe("#new_alf()", function ()
    it("should require some parameters", function()
      assert.has_error(function()
        ALFSerializer.new_alf()
      end, "Missing ngx context")

      assert.has_error(function()
        ALFSerializer.new_alf({})
      end, "Mashape Analytics serviceToken required")
    end)
    it("should return an ALF with one entry", function()
      local alf = ALFSerializer.new_alf(fixtures.GET.NGX_STUB, "123456")
      assert.truthy(alf)
      assert.equal("1.0.0", alf.version)
      assert.equal("123456", alf.serviceToken)
      assert.equal("127.0.0.1", alf.clientIPAddress)
      assert.falsy(alf.environment)
      assert.truthy(alf.har)
      assert.truthy(alf.har.log)
      assert.equal("1.2", alf.har.log.version)
      assert.truthy(alf.har.log.creator)
      assert.equal("galileo-agent-kong", alf.har.log.creator.name)
      assert.equal("1.1.0", alf.har.log.creator.version)
      assert.truthy(alf.har.log.entries)
      assert.equal(1, #(alf.har.log.entries))
    end)
    it("should accept an environment parameter", function()
      local alf = ALFSerializer.new_alf(fixtures.GET.NGX_STUB, "123456", "test")
      assert.equal("test", alf.environment)
    end)
    -- https://github.com/ahmadnassri/har-validator/blob/8fd21c30edb23a1fed2d50b934d055d1be3dd7c9/lib/schemas/record.json#L12
    it("should convert all records to strings", function()
      local alf = ALFSerializer.new_alf(fixtures.GET.NGX_STUB, "123456", "test")
      for _, record in ipairs(alf.har.log.entries[1].request.queryString) do
        assert.equal("string", type(record.value))
      end
    end)
  end)
end)
