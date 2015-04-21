local ALFSerializer = require "kong.plugins.log_serializers.alf"
local fixtures = require "spec.plugins.apianalytics.fixtures.requests"

describe("ALF serializer", function()

  describe("#serialize_entry()", function()

    it("should serialize an ngx GET request/response", function()
      local entry = ALFSerializer:serialize_entry(fixtures.GET.NGX_STUB)
      assert.are.same(fixtures.GET.ENTRY, entry)
    end)

  end)
  
  describe("#add_entry()", function()

    it("should add the entry to the serializer entries property", function()
      ALFSerializer:add_entry(fixtures.GET.NGX_STUB)
      assert.are.same(1, table.getn(ALFSerializer.har.log.entries))
      assert.are.same(fixtures.GET.ENTRY, ALFSerializer.har.log.entries[1])

      ALFSerializer:add_entry(fixtures.GET.NGX_STUB)
      assert.are.same(2, table.getn(ALFSerializer.har.log.entries))
      assert.are.same(fixtures.GET.ENTRY, ALFSerializer.har.log.entries[2])
    end)

  end)

  describe("#to_json_string()", function()

    it("should throw an error if no token was given", function()
      assert.has_error(function() ALFSerializer:to_json_string() end,
        "API Analytics serviceToken required")
    end)

    it("should return a JSON string", function()
      local json_str = ALFSerializer:to_json_string("stub_service_token")
      assert.are.same("string", type(json_str))
    end)

  end)

  describe("#flush_entries()", function()

    it("should remove any existing entry", function()
      ALFSerializer:flush_entries()
      assert.are.same(0, table.getn(ALFSerializer.har.log.entries))
    end)

  end)

  -- TODO: tests empty queryString (empty array) both JSON + Lua formats
end)
