local ee_jwt = require "kong.enterprise_edition.jwt"
local pl_string     = require "pl.stringx"

describe("ee jwt", function()
  local claims, expected_header, valid_jwt, parsed_valid_jwt, err

  before_each(function()
    claims = {
      data = "data_data"
    }

    expected_header = {
      typ = "JWT",
      alg = "HS256"
    }

    valid_jwt, err = ee_jwt.generate_JWT(claims, "super_secret_squirrel", "HS256")
    assert.is_nil(err)

    parsed_valid_jwt, err = ee_jwt.parse_JWT(valid_jwt)
    assert.is_nil(err)
  end)

  describe("verify_signature", function()
    it("should return an error if alg is not supported", function()
      local bad_jwt = {
        header = {
          alg = "rando_alg",
        },
      }
      local res, err = ee_jwt.verify_signature(bad_jwt, "super_secret_squirrel")
      assert.is_nil(res)
      assert.equal("invalid alg", err)
    end)

    it("should return false if signature does not match", function()
      local res, err = ee_jwt.verify_signature(parsed_valid_jwt, "dif_secret")
      assert.is_nil(err)
      assert.is_false(res)
    end)

    it("should return true if signature matches", function()
      local res, err = ee_jwt.verify_signature(parsed_valid_jwt, "super_secret_squirrel")
      assert.is_nil(err)
      assert.is_true(res)
    end)
  end)

  describe("generate_jwt", function()
    it("should return error if alg is not supported", function()
      local jwt, err = ee_jwt.generate_JWT(claims, "super_secret_squirrel", "randoooo")
      assert.is_nil(jwt)
      assert.equal("invalid alg", err)
    end)

    it("should default to HS256 if no alg is passed", function()
      local jwt = ee_jwt.generate_JWT(claims, "super_secret_squirrel")
      local parsed_jwt = ee_jwt.parse_JWT(jwt)

      assert.equal("HS256", parsed_jwt.header.alg)
    end)
  end)

  describe("parse_jwt", function()
    it("should return an error if jwt is not a string", function()
      local jwt, err = ee_jwt.parse_JWT(9000)
      assert.is_nil(jwt)
      assert.equal(ee_jwt.INVALID_JWT, err)
    end)

    it("should return an error if jwt is nil", function()
      local jwt, err = ee_jwt.parse_JWT()
      assert.is_nil(jwt)
      assert.equal(ee_jwt.INVALID_JWT, err)
    end)

    it("should return an error if header is not valid", function()
      local invalid_header = "bad." .. parsed_valid_jwt.claims_64 .. "." .. parsed_valid_jwt.signature_64
      local jwt, err = ee_jwt.parse_JWT(invalid_header)
      assert.is_nil(jwt)
      assert.equal(ee_jwt.INVALID_JWT, err)
    end)

    it("should return an error if claims is not valid", function()
      local invalid_header = parsed_valid_jwt.header_64 .. ".bad." .. parsed_valid_jwt.signature_64
      local jwt, err = ee_jwt.parse_JWT(invalid_header)
      assert.is_nil(jwt)
      assert.equal(ee_jwt.INVALID_JWT, err)
    end)

    it("should decode the jwt", function()
      local header_64, claims_64, signature_64 = unpack(pl_string.split(valid_jwt, "."))
      local jwt, err = ee_jwt.parse_JWT(valid_jwt)
      assert.is_nil(err)

      assert.same(header_64, jwt.header_64)
      assert.same(claims_64, jwt.claims_64)
      assert.same(signature_64, jwt.signature_64)
      assert.same(expected_header, jwt.header)
      assert.same(claims, jwt.claims)
    end)
  end)
end)
