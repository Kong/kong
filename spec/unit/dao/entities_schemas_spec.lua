local validate = require("kong.dao.schemas_validation").validate
local api_schema = require "kong.dao.schemas.apis"

require "kong.tools.ngx_stub"

describe("Entities Schemas", function()
  describe("APIs", function()

    it("should return error with wrong target_url", function()
      local valid, errors = validate({
        public_dns = "hello.com",
        target_url = "asdasd"
      }, api_schema)
      assert.False(valid)
      assert.same("Invalid target URL", errors.target_url)
    end)

    it("should return error with wrong target_url protocol", function()
      local valid, errors = validate({
        public_dns = "hello.com",
        target_url = "wot://hello.com/"
      }, api_schema)
      assert.False(valid)
      assert.same("Supported protocols are HTTP and HTTPS", errors.target_url)
    end)

    it("should work without a path", function()
      local valid, errors = validate({
        public_dns = "hello.com",
        target_url = "http://hello.com"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)
    end)

    it("should work without upper case protocol", function()
      local valid, errors = validate({
        public_dns = "hello2.com",
        target_url = "HTTP://hello.com/world"
      }, api_schema)
      assert.True(valid)
      assert.falsy(errors)
    end)

  end)
end)
