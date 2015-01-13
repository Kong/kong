local utils = require "apenode.utils"
local configuration = require "spec.unit.daos.sqlite.configuration"
local SQLiteFactory = require "apenode.dao.sqlite"
local BaseModel = require "apenode.models.base_model"

local configuration, dao_properties = utils.parse_configuration(configuration)
local dao_factory = SQLiteFactory(dao_properties)

local function check_number(val)
  if not val or val == 123 then
    return true
  else
    return false, "The value should be 123"
  end
end

local function get_schema(v)
  return {
    smart = { type = "boolean" }
  }
end

local collection = "apis"
local validator = {
  id = { type = "number", read_only = true },
  name = { type = "string", required = true, func = check_account_id },
  public_dns = { type = "string", required = true, unique = false, regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { type = "string", required = true, unique = false },
  created_at = { type = "number", read_only = true, default = 123 },
  random_value = { type = "number", func = check_number },
  some_schema = { type = "table", schema_from_func = get_schema}
}

describe("BaseModel", function()

  describe("#init()", function()
    it("should instantiate an entity entity", function()
      local res, err = BaseModel(collection, validator, {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, dao_factory):save()
      assert.falsy(err)
      assert.truthy(res)
      assert.are.same("test.com", res.public_dns)
    end)

    it("should set default values if specified in the validator", function()
      local res, err = BaseModel(collection, validator, {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, dao_factory):save()
      assert.truthy(res)
      assert.falsy(err)
      assert.truthy(res.created_at)
    end)
    it("should return error when unexpected values are included in the schema", function()
      local res, err = BaseModel(collection, validator, {
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org",
        wot = 123
      }, dao_factory):save()
      assert.falsy(res)
      assert.truthy(err)
      assert.are.same("wot is an unknown field", err.wot)
    end)
    it("should return errors if trying to pass read_only properties", function()
      local res, err = BaseModel(collection, validator, {
        id = 1,
        created_at = 123456,
        name = "httpbin entity",
        public_dns = "test.com",
        target_url = "http://httpbin.org"
      }, dao_factory):save()
      assert.falsy(res)
      assert.truthy(err)
      assert.are.same("id is read only", err.id)
      assert.are.same("created_at is read only", err.created_at)
    end)
    it("should return errors when validation fails", function()
      local res, err = BaseModel(collection, validator, {
        public_dns = 123,
        target_url = "target asdads"
      }, dao_factory):save()
      assert.falsy(res)
      assert.truthy(err)
      assert.are.same("name is required", err.name)
      assert.are.same("public_dns should be a string", err.public_dns[1])
      assert.are.same("public_dns has an invalid value", err.public_dns[2])
    end)
    it("should return errors when func validation fails", function()
      local res, err = BaseModel(collection, validator, {
        name = "test",
        public_dns = "test.com",
        target_url = "target asdads",
        random_value = 1234
      }, dao_factory):save()
      assert.falsy(res)
      assert.truthy(err)
      assert.are.same("The value should be 123", err.random_value)
    end)
    it("should not return errors when func validation succeeds", function()
      local res, err = BaseModel(collection, validator, {
        name = "test",
        public_dns = "test.com",
        target_url = "target asdads",
        random_value = 123
      }, dao_factory):save()
      assert.truthy(res)
      assert.falsy(err)
    end)
    it("should return errors when testing nested schemas", function()
      local res, err = BaseModel(collection, validator, {
        name = "test",
        public_dns = "test.com",
        target_url = "target asdads",
        random_value = 123,
        some_schema = {
          smart = "hello world this is wrong"
        }
      }, dao_factory):save()
      assert.falsy(res)
      assert.truthy(err)
      assert.are.same({smart = 'smart should be a boolean' }, err.some_schema)
    end)
    it("should not return errors when testing nested schemas", function()
      local res, err = BaseModel(collection, validator, {
        name = "test",
        public_dns = "test.com",
        target_url = "target asdads",
        random_value = 123,
        some_schema = {
          smart = true
        }
      }, dao_factory):save()
      assert.truthy(res)
      assert.falsy(err)
    end)
  end)

end)
