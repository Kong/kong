local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local fixtures   = require "spec.03-plugins.16-jwt.fixtures"
local helpers    = require "spec.helpers"


local u          = helpers.unindent


describe("Plugin: jwt (parser)", function()
  describe("Encoding", function()
    it("should properly encode using HS256", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true
      }, "secret")

      if helpers.openresty_ver_num < 11123 then
        assert.equal(u([[
          eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6d
          HJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg
          5MCJ9.eNK_fimsCW3Q-meOXyc_dnZHubl2D4eZkIcn6llniCk
        ]], true), token)
      else
        assert.equal(u([[
          eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm
          9obiBEb2UiLCJhZG1pbiI6dHJ1ZSwic3ViIjoiMTIzNDU2Nzg5M
          CJ9.Nu43HyL_byXrv-QEc96OCNF0KogddZPLsxYBuDnX1rU
        ]], true), token)
      end
    end)
    it("should properly encode using HS384", function()
      local token = jwt_parser.encode({
        name  = "John Doe",
        admin = true,
        sub   = "1234567890"
      }, "secret", "HS384")

      assert.equal(u([[
        eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiS
        m9obiBEb2UiLCJhZG1pbiI6dHJ1ZSwic3ViIjoiMTIzNDU2Nzg
        5MCJ9.4Ok0xhf2eh04vVDC4tPG0vmRwmVYVqUueU8R9sRdQ4_Z
        r2duC69lo0EtSUE6iO7c
      ]], true), token)
    end)
    it("should properly encode using HS512", function()
      local token = jwt_parser.encode({
        name  = "John Doe",
        admin = true,
        sub   = "1234567890"
      }, "secret", "HS512")

      assert.equal(u([[
        eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm
        9obiBEb2UiLCJhZG1pbiI6dHJ1ZSwic3ViIjoiMTIzNDU2Nzg5M
        CJ9.3xG0Dl5rEokSV9iehelulvP0FhURRt4HlTNUorEPl7gkOR0
        LEAjuRqn7mTncXSSq8qR64JMjnOc1M7ez0iejeA
      ]], true), token)
    end)
    it("should properly encode using RS256", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true
      }, fixtures.rs256_private_key, "RS256")

      assert.equal(u([[
        eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCJhZG1p
        biI6dHJ1ZSwic3ViIjoiMTIzNDU2Nzg5MCJ9.m6E0DvUJrnw5oLYrvIwJ6n_xFFrAsXSL
        zHtDAukzCv6yoDkJkMi37DhHB3EZr_shJFA-41UhdkSXSKg8xvnZ4VpeJcXx7UU4sdOQa
        VGfJyRcZqdfYyXq3yz_oZjnoi74b1N2Eogas2Jw3wC8ee7_gMEyixQFQu88k8Mi9hm819
        Hd-UJauLpAc60kMCpLXpl0i8zACbG7h1iO9--j16HMzyF3R8dysiNivScwVTHHNkM2VrF
        BqyGv84CMqdr42bk0z4WiNnVOzSqReub9DXSDx4gNd9hK41UChFv6k2iDELXP0nwllnyu
        qbGbjm0HM7GOAptzViFqULEBvGb-J-s99Q
      ]], true), token)
    end)
    it("should encode using RS512", function()
      local token = jwt_parser.encode({
        sub   = "1234567890",
        name  = "John Doe",
        admin = true,
      }, fixtures.rs512_private_key, "RS512")

      if helpers.openresty_ver_num < 11123 then
        assert.equal(u([[
          eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJhZG1pbiI6dHJ1ZSwibmFtZSI6Ikpv
          aG4gRG9lIiwic3ViIjoiMTIzNDU2Nzg5MCJ9.VhoFYud-lrxtkbkfMl0Wkr4fERsDNjGf
          vHc2hFEecjLqSJ65_cydJiU011QqAmlMM8oIRCnoGKvA63XeE7M6qPsNkJ_vHMoqO-Hg3
          ajx1RaWmVaHyeTCkkyStNvh88phVSH5EB5wIYjukHErRXLCTL9UhE0Z60fNzLeEZ5yJZS
          -rhOK3fa0QSVoTD2QKVITYBcX_xt6NzHzTTx_3kQ1KlcuueNlOLmCYx_6tissUvMY91Kj
          cZfs3z9tYREu5paFx0pSiPvgNBvrWQfbm3irr-1YcBH7wJuIinPDrERVohK1v37t8fDnS
          qhi1tWUati7Mynkb3JrpCeF3IyReSvkhQA
        ]], true), token)

      else
        assert.equal(u([[
          eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCJhZG1p
          biI6dHJ1ZSwic3ViIjoiMTIzNDU2Nzg5MCJ9.YgYhC6E8_4V--36yWGSCIvPfL77zibNk
          m6lnM-8u2J39nP3QlQtiEkuY0lWZku_mWggYiL0PycTLHChLqeiL0ElP6IYaL39XrlYES
          kH4iwJ_F9_x6JUvlPYZmgerD6oxmpyA-FNNdej_DCgztuzzaJBSsXLE8zn_HNnc0WsRBA
          TV85hXzhp5_YvGgayTzAYr9fiS0NeuIl7s6CPhuH1UZp5PDx6v2TmfaHlia16ZbaAoUtM
          KXI18ZRTBOmh4hV66fzbzTxh_kO7Z-h0hOfdVbtqEJRLlQkgq3c_JUB5Sky2WLkK3rFWm
          UecxqNnQXKYkOgq_DuXU8KIv7GGzpTELww
        ]], true), token)
      end
    end)

    it("should encode using ES256", function()
      local token = jwt_parser.encode({
        sub   = "5656565656",
        name  = "Jane Doe",
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
      assert.False(jwt:verify_signature(fixtures.rs256_public_key:gsub('QAB', 'zzz')))
    end)
    it("using RS512", function()
      local token = jwt_parser.encode({sub = "foo"}, fixtures.rs512_private_key, 'RS512')
      local jwt = assert(jwt_parser:new(token))
      assert.True(jwt:verify_signature(fixtures.rs512_public_key))
      assert.False(jwt:verify_signature(fixtures.rs512_public_key:gsub('AE=', 'zzz')))
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
