local ee_jwt = require "kong.enterprise_edition.jwt"
local ee_utils = require "kong.enterprise_edition.utils"


describe("validate_reset_jwt", function()
  it("should return an error if fails to parse jwt", function()
    stub(ee_jwt, "parse_JWT").returns(nil, "error!")
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if header is missing", function()
    local jwt = {}

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error type is not 'JWT'", function()
    local jwt = {
      header = {
        typ = "not_JWT",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if alg is not 'HS256'", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "not_HS256",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if claims is missing", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if expiration is missing from claims", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {},
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if expired", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() - 1000000,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.EXPIRED_JWT, err)
  end)

  it("should return an error if id is missing from claims", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() + 1000000,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return jwt if valid", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() + 1000000,
        id = 1,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local res, err = ee_utils.validate_reset_jwt()
    assert.is_nil(err)
    assert.equal(jwt, res)
  end)
end)
