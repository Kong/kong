local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local fixtures = require "spec.03-plugins.17-jwt.fixtures"

describe("Plugin: jwt (parser)", function()
  describe("Encoding", function()
    it("should properly encode using HS256", function()
      local token = jwt_parser.encode({
        sub = "1234567890",
        name = "John Doe",
        admin = true
      }, "secret")

      assert.equal([[eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6dHJ1ZSw]]
                 ..[[ibmFtZSI6IkpvaG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg5MCJ9.]]
                 ..[[eNK_fimsCW3Q-meOXyc_dnZHubl2D4eZkIcn6llniCk]], token)
    end)
    it("should properly encode using RS256", function()
      local token = jwt_parser.encode({
        sub = "1234567890",
        name = "John Doe",
        admin = true
      }, fixtures.rs256_private_key, 'RS256')

      assert.equal([[eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6dHJ1ZSwi]]
                 ..[[bmFtZSI6IkpvaG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg5MCJ9.EiOLxyMimY8vbLR8]]
                 ..[[EcGOlXAiEe-eEVn7Aewgu0gYIBPyiEhVTq0CzB_XtHoQ_0y4gBBBZVRnz1pgruOtN]]
                 ..[[mOzcaoXnyplFm1IbrCCBKYQeA4lanmu_-Wzk6Dw4p-TimRHpf8EEHBUJSEbVEyet3]]
                 ..[[cpozUo2Ep0dEfA_Nf3T-g8RjfOYXkFTr3M6FuIDq95cFZloH-DRGodUVQX508wggg]]
                 ..[[tcFKN-Pi7_rWzBtQwP2u4CrFD4ZJbn2sxobzSlFb9fn4nRh_-rPPjDSeHVKwrpsYp]]
                 ..[[FSLBJxwX-KhbeGUfalg2eu9tHLDPHC4gTCpoQKxxRIwfMjW5zlHOZhohKZV2ZtpcgA]] , token)
    end)

    it("should encode using ES256", function()
      local token = jwt_parser.encode({
        sub = "5656565656",
        name = "Jane Doe",
        admin = true
      }, fixtures.es256_private_key, 'ES256')
      assert.truthy(token)
    end)
  end)
  describe("Decoding", function()
    it("throws an error if not given a string", function()
      assert.has_error(function()
        jwt_parser:new()
      end, "Token must be a string, got nil")
    end)
    it("refuses invalid typ", function()
      local token = jwt_parser.encode({sub = "1234"}, "secret", nil, {typ = "foo"})
      local _, err = jwt_parser:new(token)
      assert.equal("invalid typ", err)
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
    it("using RS256", function()
      local token = jwt_parser.encode({sub = "foo"}, fixtures.rs256_private_key, 'RS256')
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs256_public_key))
      assert.False(jwt:verify_signature(fixtures.rs256_public_key:gsub('QAB', 'zzz')))
    end)
    it("using ES256", function()
      for _ = 1, 500 do
        local token = jwt_parser.encode({sub = "foo"}, fixtures.es256_private_key, 'ES256')
        local jwt = assert(jwt_parser:new(token))
        assert.True(jwt:verify_signature(fixtures.es256_public_key))
        assert.False(jwt:verify_signature(fixtures.rs256_public_key:gsub('1z+', 'zzz')))
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
