describe("resolve_entity_metadata", function()
  local utils = require "kong.vitals.utils"

  describe("when entity is service", function()
    it("uses service name", function()
      local expected = { name = "myservice" }
      local entity = { name = "myservice" }
      assert.are.same(expected, utils.resolve_entity_metadata(entity))
    end)
  end)

  describe("when entity is consumer", function()
    it("uses consumer name with empty app_id and app_name", function()
      local expected = { name = "myconsumer", app_id = "", app_name = "" }
      local entity = { username = "myconsumer" }
      assert.are.same(expected, utils.resolve_entity_metadata(entity))
    end)
    describe("with underscore", function()
      it("uses consumer name with empty app_id and app_name", function()
        local expected = { name = "my_consumer", app_id = "", app_name = "" }
        local entity = { username = "my_consumer" }
        assert.are.same(expected, utils.resolve_entity_metadata(entity))
      end)
    end)
    describe("with custom_id rather than username", function()
      it("uses consumer name with empty app_id and app_name", function()
        local expected = { name = "my_custom_id", app_id = "", app_name = "" }
        local entity = { custom_id = "my_custom_id" }
        assert.are.same(expected, utils.resolve_entity_metadata(entity))
      end)
    end)
  end)


  describe("when entity is application", function()
    it("name is blank and adds app_id and app_name", function()
      local expected = { name = "", app_id = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69", app_name = "mycoolapp" }
      local entity = { username = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69_mycoolapp", type = 3 }
      assert.are.same(expected, utils.resolve_entity_metadata(entity))
    end)
    describe("and name has an underscore", function()
      it("name is blank and adds app_id and app_name", function()
        local expected = { name = "", app_id = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69", app_name = "my_cool_app" }
        local entity = { username = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69_my_cool_app", type = 3 }
        assert.are.same(expected, utils.resolve_entity_metadata(entity))
      end)
    end)
  end)

end)


describe("append_to_stats", function()
  local utils = require "kong.vitals.utils"
  describe("given one service and no state", function()
    it("creates single vitals stats row and looks up name", function()
      local id = "exampleid"
      local status_group = "2XX"
      local request_count = 10
      local entity = { name = "example"}
      local current_state = {}
      local expected = { exampleid = { ["total"] = 10, ["2XX"] = 10, ["4XX"] = 0, ["5XX"] = 0, ["name"] = "example" }}
      assert.are.same(expected, utils.append_to_stats(current_state, id, status_group, request_count, entity))
    end)
  end)

  describe("given one service and some 200s", function()
    it("aggregates a single vitals stats row", function()
      local id = "exampleid"
      local status_group = "2XX"
      local request_count = 10
      local entity = { name = "example"}
      local current_state = { exampleid = { ["total"] = 15, ["2XX"] = 15, ["4XX"] = 0, ["5XX"] = 0 }}
      local expected = { exampleid = { ["total"] = 25, ["2XX"] = 25, ["4XX"] = 0, ["5XX"] = 0, ["name"] = "example" }}
      assert.are.same(expected, utils.append_to_stats(current_state, id, status_group, request_count, entity))
    end)
  end)

  describe("given one application and some 200s", function()
    it("aggregates a single vitals stats row", function()
      local id = "exampleid"
      local status_group = "2XX"
      local request_count = 10
      local entity = { name = "consumername", app_id = "appid", app_name = "appname"}
      local current_state = { exampleid = { ["total"] = 15, ["2XX"] = 15, ["4XX"] = 0, ["5XX"] = 0 }}
      local expected = { exampleid = { ["total"] = 25, ["2XX"] = 25, ["4XX"] = 0, ["5XX"] = 0, ["name"] = "consumername", ["app_id"] = "appid", ["app_name"] = "appname" }}
      assert.are.same(expected, utils.append_to_stats(current_state, id, status_group, request_count, entity))
    end)
  end)
end)
