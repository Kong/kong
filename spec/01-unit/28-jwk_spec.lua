local jwk = require("kong.pdk.jwk").new()

describe("JWK", function()
  -- Tests for the new function
    it(".new should create a new JWK with the provided data", function()
      local jwk_data = { kty = "RSA", kid = "1" }
      local jwk_o = jwk.new(jwk_data)
      assert.are.same(jwk_o.attributes, jwk_data)
    end)

    it("__eq should correctly detect differences", function()
      local jwk_data1 = { kty = "RSA", kid = "1", n = "public exponent" }
      local jwk_data2 = { kty = "RSA", kid = "1", n = "public exponent XXX" }
      local jwk_o_1 = jwk.new(jwk_data1)
      local jwk_o_2 = jwk.new(jwk_data2)
      assert.is_false(jwk_o_1 == jwk_o_2)
    end)

    it("__eq should correctly detect differences", function()
      local jwk_data1 = { kty = "RSA", kid = "1", n = "public exponent" }
      local jwk_data2 = { kty = "RSA", kid = "1", n = "public exponent" }
      local jwk_o_1 = jwk.new(jwk_data1)
      local jwk_o_2 = jwk.new(jwk_data2)
      assert.is_true(jwk_o_1 == jwk_o_2)
    end)
end)
