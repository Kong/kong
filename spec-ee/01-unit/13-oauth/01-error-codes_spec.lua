-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local oauth_error_codes = require("kong.enterprise_edition.oauth.error_codes")
local ForbiddenError = oauth_error_codes.ForbiddenError
local UnauhorizedError = oauth_error_codes.UnauthorizedError
local BadRequestError = oauth_error_codes.BadRequestError


describe("Error:expose_error", function()
  it("should return true when expose_error_code is true and error_code and error_description are present", function()
    local err = ForbiddenError:new({
      expose_error_code = true,
      error_code = "invalid_scope",
      error_description = "The requested scope is invalid or unknown."
    })
    assert.is_true(err:expose_error())
  end)

  it("should return false when expose_error_code is false", function()
    local err = ForbiddenError:new({
      expose_error_code = false,
      error_code = "invalid_request",
      error_description = "The request is missing a required parameter."
    })
    assert.is_false(err:expose_error())
  end)

  it("should return true when error_description is missing as the RFC does not enforce a error_description", function()
    local err = ForbiddenError:new({
      expose_error_code = true,
      error_code = "invalid_request"
    })
    assert.is_true(err:expose_error())
  end)
end)

describe("Oauth Error Object ->", function ()
  it("build_auth_header processes `host` parameter correctly", function ()
    local forbidden_error = ForbiddenError:new {
      expose_error_code = true
    }
    local header = forbidden_error:build_auth_header("foo")
    assert.is_table(header)
    assert.is_not_nil(header["WWW-Authenticate"])
    local header_value = header["WWW-Authenticate"]
    assert.is_same('Bearer realm="foo", error="insufficient_scope"', header_value)
  end)

  describe("ForbiddenError", function ()
    local error = ForbiddenError:new{}
    it("has sane defaults", function ()
      assert(error.status_code == 403)
      assert(error.error_code == oauth_error_codes.INSUFFICIENT_SCOPE)
      assert(error.error_description == nil)
      assert(error.log == "Forbidden")
      assert(error.expose_error_code == false)
      assert(error.message == "Forbidden")
    end)

    it("builds base header correctly", function ()
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same("Bearer realm=\"kong\"", header_value)
    end)

    it("builds `error_description` header correctly", function ()
      error.error_description = "something forbidden"
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="insufficient_scope", error_description="something forbidden"]], header_value)
    end)

    it("builds header without `error_description` correctly", function ()
      error.error_description = nil
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="insufficient_scope"]], header_value)
    end)
  end)

  describe("UnauthorizedError", function ()
    local error = UnauhorizedError:new{}
    it("has sane defaults", function ()
      assert(error.status_code == 401)
      assert(error.error_code == oauth_error_codes.INVALID_TOKEN)
      assert(error.error_description == nil)
      assert(error.expose_error_code == false)
      assert(error.log == "Unauthorized")
      assert(error.message == "Unauthorized")
    end)

    it("builds base header correctly", function ()
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same("Bearer realm=\"kong\"", header_value)
    end)

    it("builds `error_description` header correctly", function ()
      error.error_description = "something unauthorized"
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="invalid_token", error_description="something unauthorized"]], header_value)
    end)

    it("builds header without `error_description` correctly", function ()
      error.error_description = "something unauthorized"
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="invalid_token", error_description="something unauthorized"]], header_value)
    end)
  end)

  describe("BadRequestError", function ()
    local error = BadRequestError:new{}
    it("has sane defaults", function ()
      assert(error.status_code == 400)
      assert(error.error_code == oauth_error_codes.INVALID_REQUEST)
      assert(error.error_description == nil)
      assert(error.expose_error_code == false)
      assert(error.log == "Bad Request")
      assert(error.message == "Bad Request")
    end)

    it("builds base header correctly", function ()
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same("Bearer realm=\"kong\"", header_value)
    end)

    it("builds `error_description` header correctly", function ()
      error.error_description = "something bad"
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="invalid_request", error_description="something bad"]], header_value)
    end)

    it("builds header without `error_description` correctly", function ()
      error.error_description = nil
      error.expose_error_code = true
      local header = error:build_auth_header()
      assert.is_table(header)
      assert.is_not_nil(header["WWW-Authenticate"])
      local header_value = header["WWW-Authenticate"]
      assert.is_same(
[[Bearer realm="kong", error="invalid_request"]], header_value)
    end)
  end)

end)