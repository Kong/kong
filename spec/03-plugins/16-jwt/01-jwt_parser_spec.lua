local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local fixtures   = require "spec.03-plugins.16-jwt.fixtures"


describe("Plugin: jwt (parser)", function()
  describe("Encoding", function()
    it("should properly encode using HS256", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true
      }, "secret")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
    end)
    it("should properly encode using HS384", function()
      local token = jwt_parser.encode({
        name  = "John Doe",
        admin = true,
        sub   = "1234567890"
      }, "secret", "HS384")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
    end)
    it("should properly encode using HS512", function()
      local token = jwt_parser.encode({
        name  = "John Doe",
        admin = true,
        sub   = "1234567890"
      }, "secret", "HS512")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
    end)
    it("should properly encode using RS256", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true
      }, fixtures.rs256_private_key, "RS256")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs256_public_key))
    end)
    it("should properly encode using RS384", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true
      }, fixtures.rs384_private_key, "RS384")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs384_public_key))
    end)
    it("should encode using RS512", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true,
      }, fixtures.rs512_private_key, "RS512")

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs512_public_key))
    end)

    it("should encode using ES256", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.es256_private_key, 'ES256')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.es256_public_key))
    end)

    it("should encode using ES384", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.es384_private_key, 'ES384')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.es384_public_key))
    end)

    it("should encode using ES512", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.es512_private_key, 'ES512')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.es512_public_key))
    end)
    it("should encode using PS256", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.ps256_private_key, 'PS256')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.ps256_public_key))
    end)

    it("should encode using PS384", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.ps384_private_key, 'PS384')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.ps384_public_key))
    end)

    it("should encode using PS512", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.ps512_private_key, 'PS512')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.ps512_public_key))
    end)

    it("should encode using EdDSA with Ed25519 key", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.ed25519_private_key, 'EdDSA')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.ed25519_public_key))
    end)

    it("should encode using EdDSA with Ed448 key", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
        admin = true
      }, fixtures.ed448_private_key, 'EdDSA')

      assert.truthy(token)
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.ed448_public_key))
    end)

  end)
  describe("Decoding", function()
    it("throws an error if not given a string", function()
      assert.has_error(function()
        jwt_parser:new()
      end, "Token must be a string, got nil")
    end)
    it("refuses invalid alg", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {
        typ = "JWT",
        alg = "foo"
      })
      local _, err = jwt_parser:new(token)
      assert.equal("invalid alg", err)
    end)
    it("accepts a valid encoding request", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {
        typ = "JWT",
        alg = "RS256"
      })
      assert(jwt_parser:new(token))
    end)
    it("accepts a valid encoding request with lowercase TYP", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {
        typ = "jwt",
        alg = "RS256"
      })
      assert(jwt_parser:new(token))
    end)
    it("accepts a valid encoding request with missing TYP", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {alg = "RS256"})
      assert(jwt_parser:new(token))
    end)
  end)
  describe("verify signature", function()
    it("using HS256", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret")
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
      assert.False(jwt:verify_signature("invalid"))
    end)
    it("using HS384", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret", "HS384")
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
      assert.False(jwt:verify_signature("invalid"))
    end)
    it("using HS512", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret", "HS512")
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature("secret"))
      assert.False(jwt:verify_signature("invalid"))
    end)
    it("using RS256", function()
      local token = jwt_parser.encode({sub = "foo"}, fixtures.rs256_private_key, 'RS256')
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs256_public_key))
      assert.False(jwt:verify_signature(fixtures.rs384_public_key))
    end)
    it("using RS384", function()
      local token = jwt_parser.encode({sub = "foo"}, fixtures.rs384_private_key, "RS384")
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs384_public_key))
      assert.False(jwt:verify_signature(fixtures.rs512_public_key))
    end)
    it("using RS512", function()
      local token = jwt_parser.encode({sub = "foo"}, fixtures.rs512_private_key, 'RS512')
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs512_public_key))
      assert.False(jwt:verify_signature(fixtures.rs256_public_key))
    end)
    it("using ES256", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.es256_private_key, 'ES256')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.es256_public_key))
        assert.False(jwt:verify_signature(fixtures.rs256_public_key))
      end
    end)
    it("using ES384", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.es384_private_key, 'ES384')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.es384_public_key))
        assert.False(jwt:verify_signature(fixtures.rs256_public_key))
      end
    end)
    it("using ES512", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.es512_private_key, 'ES512')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.es512_public_key))
        assert.False(jwt:verify_signature(fixtures.rs256_public_key))
      end
    end)
    it("using PS256", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.ps256_private_key, 'PS256')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.ps256_public_key))
        assert.False(jwt:verify_signature(fixtures.es256_public_key))
      end
    end)
    it("using PS384", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.ps384_private_key, 'PS384')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.ps384_public_key))
        assert.False(jwt:verify_signature(fixtures.es256_public_key))
      end
    end)
    it("using PS512", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.ps512_private_key, 'PS512')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.ps512_public_key))
        assert.False(jwt:verify_signature(fixtures.es256_public_key))
      end
    end)
  end)
  describe("verify registered claims", function()
    it("requires claims passed as arguments", function()
      local token = jwt_parser.encode({sub = "foo"}, "secret")
      local jwt = assert(jwt_parser:new(token))

      local ok, errors = jwt:verify_registered_claims({"exp", "nbf"})
      assert.False(ok)
      assert.same({exp = "must be a number", nbf = "must be a number"}, errors)

      ok, errors = jwt:verify_registered_claims({"nbf"})
      assert.False(ok)
      assert.same({nbf = "must be a number"}, errors)
    end)
    it("checks the type of given registered claims", function()
      local token = jwt_parser.encode({exp = "bar", nbf = "foo"}, "secret")
      local jwt = assert(jwt_parser:new(token))

      local ok, errors = jwt:verify_registered_claims({"exp", "nbf"})
      assert.False(ok)
      assert.same({exp = "must be a number", nbf = "must be a number"}, errors)
    end)
    it("checks the exp claim", function()
      local token = jwt_parser.encode({exp = os.time() - 10}, "secret")
      local jwt = assert(jwt_parser:new(token))

      ngx.update_time()
      local ok, errors = jwt:verify_registered_claims({"exp"})
      assert.False(ok)
      assert.same({exp = "token expired"}, errors)
    end)
    it("checks the nbf claim", function()
      local token = jwt_parser.encode({nbf = os.time() + 10}, "secret")
      local jwt = assert(jwt_parser:new(token))

      local ok, errors = jwt:verify_registered_claims({"nbf"})
      assert.False(ok)
      assert.same({nbf = "token not valid yet"}, errors)
    end)
  end)
end)
