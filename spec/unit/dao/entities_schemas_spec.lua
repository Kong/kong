local api_schema = require "kong.dao.schemas.apis"
local consumer_schema = require "kong.dao.schemas.consumers"
local validate_fields = require("kong.dao.schemas_validation").validate_fields

require "kong.tools.ngx_stub"

describe("Entities Schemas", function()
  describe("APIs", function()

    it("should return error with wrong target_url", function()
      local valid, errors = validate_fields({
        public_dns = "mockbin.com",
        target_url = "asdasd"
      }, api_schema)
      assert.False(valid)
      assert.equal("Invalid target URL", errors.target_url)
    end)

    it("should return error with wrong target_url protocol", function()
      local valid, errors = validate_fields({
        public_dns = "mockbin.com",
        target_url = "wot://mockbin.com/"
      }, api_schema)
      assert.False(valid)
      assert.equal("Supported protocols are HTTP and HTTPS", errors.target_url)
    end)

    it("should validate without a path", function()
      local valid, errors = validate_fields({
        public_dns = "mockbin.com",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should validate with upper case protocol", function()
      local valid, errors = validate_fields({
        public_dns = "mockbin.com",
        target_url = "HTTP://mockbin.com/world"
      }, api_schema)
      assert.falsy(errors)
      assert.True(valid)
    end)

    it("should complain if missing `public_dns` and `path`", function()
      local valid, errors = validate_fields({
        name = "mockbin"
      }, api_schema)
      assert.False(valid)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.path)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.public_dns)

      local valid, errors = validate_fields({
        name = "mockbin",
        path = true
      }, api_schema)
      assert.False(valid)
      assert.equal("path is not a string", errors.path)
      assert.equal("At least a 'public_dns' or a 'path' must be specified", errors.public_dns)
    end)

    it("should only accept alphanumeric `path`", function()
      local valid, errors = validate_fields({
        name = "mockbin",
        path = "/[a-zA-Z]{3}",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.equal("path must only contain alphanumeric and '. -, _, ~, /' characters", errors.path)
      assert.False(valid)

      valid = validate_fields({
        name = "mockbin",
        path = "/status/",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)

      valid = validate_fields({
        name = "mockbin",
        path = "/abcd~user-2",
        target_url = "http://mockbin.com"
      }, api_schema)
      assert.True(valid)
    end)

    it("should prefix a `path` with a slash and remove trailing slash", function()
      local api_t = { name = "mockbin", path = "status", target_url = "http://mockbin.com" }
      validate_fields(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/status"
      validate_fields(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "status/"
      validate_fields(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/status/"
      validate_fields(api_t, api_schema)
      assert.equal("/status", api_t.path)

      api_t.path = "/deep/nested/status/"
      validate_fields(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      api_t.path = "deep/nested/status"
      validate_fields(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Strip all leading slashes
      api_t.path = "//deep/nested/status"
      validate_fields(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Strip all trailing slashes
      api_t.path = "/deep/nested/status//"
      validate_fields(api_t, api_schema)
      assert.equal("/deep/nested/status", api_t.path)

      -- Error if invalid path
      api_t.path = "/deep//nested/status"
      local _, errors = validate_fields(api_t, api_schema)
      assert.equal("path is invalid: /deep//nested/status", errors.path)
    end)

  end)

  describe("Consumers", function()

    it("should require a `custom_id` or `username`", function()
      local valid, errors = validate_fields({}, consumer_schema)
      assert.False(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_fields({ username = "" }, consumer_schema)
      assert.False(valid)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)

      valid, errors = validate_fields({ username = true }, consumer_schema)
      assert.False(valid)
      assert.equal("username is not a string", errors.username)
      assert.equal("At least a 'custom_id' or a 'username' must be specified", errors.custom_id)
    end)

  end)
end)
