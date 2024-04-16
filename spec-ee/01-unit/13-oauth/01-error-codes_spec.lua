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

describe("#Oauth Error Object ->", function ()
  it("build_www_auth_header processes `host` parameter correctly", function ()
    local forbidden_error = ForbiddenError:new {
      expose_error_code = true,
      fields = {
        realm = "foo"
      }
    }
    local www_header = forbidden_error:build_www_auth_header()
    assert.is_same('Bearer realm="foo", error="insufficient_scope"', www_header)
  end)

  describe("ForbiddenError", function ()
    local error = ForbiddenError:new{}
    it("has sane defaults", function ()
      assert.same(403, error.status_code)
      assert.same(oauth_error_codes.INSUFFICIENT_SCOPE, error.error_code)
      assert.same(nil, error.error_description)
      assert.same("Forbidden", error.log)
      assert.same(false, error.expose_error_code)
      assert.same("Forbidden", error.message)
    end)

    it("builds base headers correctly", function ()
      local www_header = error:build_www_auth_header()
      assert.same("Bearer realm=\"kong\"", www_header)
    end)

    it("builds `error_description` headers correctly", function ()
      error.error_description = "something forbidden"
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="insufficient_scope", error_description="something forbidden"]], www_header)
    end)

    it("builds headers without `error_description` correctly", function ()
      error.error_description = nil
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="insufficient_scope"]], www_header)
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

    it("builds base headers correctly", function ()
      local www_header = error:build_www_auth_header()
      assert.is_same("Bearer realm=\"kong\"", www_header)
    end)

    it("builds `error_description` headers correctly", function ()
      error.error_description = "something unauthorized"
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="invalid_token", error_description="something unauthorized"]], www_header)
    end)

    it("builds headers without `error_description` correctly", function ()
      error.error_description = "something unauthorized"
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="invalid_token", error_description="something unauthorized"]], www_header)
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

    it("builds base headers correctly", function ()
      local www_header = error:build_www_auth_header()
      assert.is_same("Bearer realm=\"kong\"", www_header)
    end)

    it("builds `error_description` headers correctly", function ()
      error.error_description = "something bad"
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="invalid_request", error_description="something bad"]], www_header)
    end)

    it("builds headers without `error_description` correctly", function ()
      error.error_description = nil
      error.expose_error_code = true
      local www_header = error:build_www_auth_header()
      assert.is_same(
[[Bearer realm="kong", error="invalid_request"]], www_header)
    end)
  end)

end)
