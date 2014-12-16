local BaseModel = require "apenode.models.base_model"

local validator = {
  id = { type = "number", read_only = true },
  name = { type = "string", required = true },
  public_dns = { type = "string", required = true },
  target_url = { type = "string", required = true },
  created_at = { type = "number", read_only = true, default = 123 }
}

describe("BaseModel", function()

  describe("#init()", function()
    it("should instanciate an entity entity", function()
      local entity, err = BaseModel("", {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, validator)

      assert.falsy(err)
      assert.truthy(entity)
    end)
    it("should set default values if specified in the validator", function()
      local entity, err = BaseModel("", {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, validator)

      assert.falsy(err)
      assert.truthy(entity)
      assert.truthy(entity.created_at)
    end)
    it("should return error when unexpected values are included in the schema", function()
      local entity, err = BaseModel("", {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org",
        wot = 123
      }, validator)

      assert.truthy(err)
      assert.falsy(entity)
      assert.are.same("wot is an unknown field", err.wot)
    end)
    it("should return errors if trying to pass read_only properties", function()
      local entity, err = BaseModel("", {
        id = 1,
        created_at = 123456,
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, validator)

      assert.falsy(entity)
      assert.truthy(err)
      assert.are.same("id is read only", err.id)
      assert.are.same("created_at is read only", err.created_at)
    end)
    it("should return errors when validation fails", function()
      local model, err = BaseModel("", {
        public_dns = 123,
        target_url = "target asdads"
      }, validator)

      assert.falsy(entity)
      assert.truthy(err)
      assert.are.same("name is required", err.name)
      assert.are.same("public_dns should be a string", err.public_dns)
    end)
  end)

end)
