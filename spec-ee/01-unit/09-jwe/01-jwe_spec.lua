-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local base64 = require "ngx.base64"


local decode_base64url = base64.decode_base64url
local encode_base64url = base64.encode_base64url
local concat = table.concat


local PUBLIC_RSA_JWK = {
  kty = "RSA",
  n = "oahUIoWw0K0usKNuOR6H4wkf4oBUXHTxRvgb48E-BVvxkeDNjbC4he8rUWcJoZmds2h7M70imEVhRU5djINXtqllXI4DFqcI1DgjT9LewND8MW2Krf3Spsk_ZkoFnilakGygTwpZ3uesH-PFABNIUYpOiN15dsQRkgr0vEhxN92i2asbOenSZeyaxziK72UwxrrKoExv6kc5twXTq4h-QChLOln0_mtUZwfsRaMStPs6mS6XrgxnxbWhojf663tuEQueGC-FCMfra36C9knDFGzKsNa7LZK2djYgyD3JR_MB_4NUJW_TqOQtwHYbxevoJArm-L5StowjzGy-_bq6Gw",
  e = "AQAB",
}


local PRIVATE_RSA_JWK = {
  kty = "RSA",
  n = "oahUIoWw0K0usKNuOR6H4wkf4oBUXHTxRvgb48E-BVvxkeDNjbC4he8rUWcJoZmds2h7M70imEVhRU5djINXtqllXI4DFqcI1DgjT9LewND8MW2Krf3Spsk_ZkoFnilakGygTwpZ3uesH-PFABNIUYpOiN15dsQRkgr0vEhxN92i2asbOenSZeyaxziK72UwxrrKoExv6kc5twXTq4h-QChLOln0_mtUZwfsRaMStPs6mS6XrgxnxbWhojf663tuEQueGC-FCMfra36C9knDFGzKsNa7LZK2djYgyD3JR_MB_4NUJW_TqOQtwHYbxevoJArm-L5StowjzGy-_bq6Gw",
  e = "AQAB",
  d = "kLdtIj6GbDks_ApCSTYQtelcNttlKiOyPzMrXHeI-yk1F7-kpDxY4-WY5NWV5KntaEeXS1j82E375xxhWMHXyvjYecPT9fpwR_M9gV8n9Hrh2anTpTD93Dt62ypW3yDsJzBnTnrYu1iwWRgBKrEYY46qAZIrA2xAwnm2X7uGR1hghkqDp0Vqj3kbSCz1XyfCs6_LehBwtxHIyh8Ripy40p24moOAbgxVw3rxT_vlt3UVe4WO3JkJOzlpUf-KTVI2Ptgm-dARxTEtE-id-4OJr0h-K-VFs3VSndVTIznSxfyrj8ILL6MG_Uv8YAu7VILSB3lOW085-4qE3DzgrTjgyQ",
  p = "1r52Xk46c-LsfB5P442p7atdPUrxQSy4mti_tZI3Mgf2EuFVbUoDBvaRQ-SWxkbkmoEzL7JXroSBjSrK3YIQgYdMgyAEPTPjXv_hI2_1eTSPVZfzL0lffNn03IXqWF5MDFuoUYE0hzb2vhrlN_rKrbfDIwUbTrjjgieRbwC6Cl0",
  q = "wLb35x7hmQWZsWJmB_vle87ihgZ19S8lBEROLIsZG4ayZVe9Hi9gDVCOBmUDdaDYVTSNx_8Fyw1YYa9XGrGnDew00J28cRUoeBB_jKI1oma0Orv1T9aXIWxKwd4gvxFImOWr3QRL9KEBRzk2RatUBnmDZJTIAfwTs0g68UZHvtc",
  dp = "ZK-YwE7diUh0qR1tR7w8WHtolDx3MZ_OTowiFvgfeQ3SiresXjm9gZ5KLhMXvo-uz-KUJWDxS5pFQ_M0evdo1dKiRTjVw_x4NyqyXPM5nULPkcpU827rnpZzAJKpdhWAgqrXGKAECQH0Xt4taznjnd_zVpAmZZq60WPMBMfKcuE",
  dq = "Dq0gfgJ1DdFGXiLvQEZnuKEN0UUmsJBxkjydc3j4ZYdBiMRAy86x0vHCjywcMlYYg4yoC4YZa9hNVcsjqA3FeiL19rk8g6Qn29Tt0cj8qqyFpz9vNDBUfCAiJVeESOjJDZPYHdHY8v1b-o-Z2X5tvLx-TCekf7oxyeKDUqKWjis",
  qi = "VIMpMYbPf47dT1w_zDUXfPimsSegnMOA1zTaX7aGk_8urY6R8-ZW1FxU7AlWAyLWybqq6t16VFd7hQd0y6flUK4SlOydB61gwanOsXGOAOv82cHq0E3eL4HrtZkUuKvnPrMnsUUFlfUdybVzxyjz9JF_XyaY14ardLSjf4L_FNY",
}


local PUBLIC_EC_JWK = {
  kty = "EC",
  crv = "P-256",
  x   = "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
  y   = "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
  use = "enc"
}


local PRIVATE_EC_JWK = {
  kty = "EC",
  crv = "P-256",
  x   = "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
  y   = "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
  d   = "870MB6gfuTJ4HtUnUvYMyJpr5eUZNP4Bk43bVdj3eAE",
  use = "enc"
}

local JWT_HEADER = "eyJhbGciOiJFQ0RILUVTIiwiZW5jIjoiQTI1NkdDTSIsImFwdSI6Ik1lUFhUS2" ..
                   "oyWFR1NUktYldUSFI2bXciLCJhcHYiOiJmUHFoa2hfNkdjVFd1SG5YWFZBclVn" ..
                   "IiwiZXBrIjp7Imt0eSI6IkVDIiwiY3J2IjoiUC0yNTYiLCJ4IjoiWWd3eF9NVX" ..
                   "RLTW9NYUpNZXFhSjZjUFV1Z29oYkVVc0I1NndrRlpYRjVMNCIsInkiOiIxaEYz" ..
                   "YzlRVEhELVozam1vYUp2THZwTGJqcVNaSW9KNmd4X2YtUzAtZ21RIn19"
local JWT_KEY = ""
local JWT_IV = "4ZrIopIhLi3LeXyE"
local JWT_PAYLOAD = "-Ke4ofA"
local JWT_TAG = "MI5lTkML5NIa-Twm-92F6Q"
local JWT_TOKEN = concat({
  JWT_HEADER,
  JWT_KEY,
  JWT_IV,
  JWT_PAYLOAD,
  JWT_TAG
}, ".")


local Z = decode_base64url("hRrTfl52zmlGgRC-x8KLcYdBA9Bsq6U_5ryShtcatv")
local APU = decode_base64url("jPIzGZAOkauI2STQq1SmvA")
local APV = decode_base64url("Ft69yO8k1EbjZc52XNeV5g")


describe("ee jwe", function()
  local jwe = require "kong.enterprise_edition.jwe"

  describe("jwe.deflate", function()
    it("deflates data", function()
      local data = ("a"):rep(10000)
      local deflated, err = jwe.deflate(data)
      assert.equal(nil, err)
      assert.equal(28, #deflated)
    end)

    it("deflate raises error with invalid input", function()
      assert.error(function() jwe.deflate() end, "invalid data argument")
      assert.error(function() jwe.deflate(true) end, "invalid data argument")
      assert.error(function() jwe.deflate(false) end, "invalid data argument")
      assert.error(function() jwe.deflate(1) end, "invalid data argument")
      assert.error(function() jwe.deflate({}) end, "invalid data argument")
      assert.error(function() jwe.deflate(function() end) end, "invalid data argument")
      assert.error(function() jwe.deflate("", "") end, "invalid chunk_size argument")
      assert.error(function() jwe.deflate("", true) end, "invalid chunk_size argument")
      assert.error(function() jwe.deflate("", false) end, "invalid chunk_size argument")
      assert.error(function() jwe.deflate("", {}) end, "invalid chunk_size argument")
      assert.error(function() jwe.deflate("", function() end) end, "invalid chunk_size argument")
    end)
  end)

  describe("jwe.inflate", function()
    it("inflates data", function()
      local data = ("a"):rep(10000)
      local deflated = jwe.deflate(data)
      local inflated, err = jwe.inflate(deflated)
      assert.equal(nil, err)
      assert.equal(data, inflated)
    end)

    it("raises error with invalid input", function()
      assert.error(function() jwe.inflate() end, "invalid data argument")
      assert.error(function() jwe.inflate(true) end, "invalid data argument")
      assert.error(function() jwe.inflate(false) end, "invalid data argument")
      assert.error(function() jwe.inflate(1) end, "invalid data argument")
      assert.error(function() jwe.inflate({}) end, "invalid data argument")
      assert.error(function() jwe.inflate(function() end) end, "invalid data argument")
      assert.error(function() jwe.inflate("", "") end, "invalid chunk_size argument")
      assert.error(function() jwe.inflate("", true) end, "invalid chunk_size argument")
      assert.error(function() jwe.inflate("", false) end, "invalid chunk_size argument")
      assert.error(function() jwe.inflate("", {}) end, "invalid chunk_size argument")
      assert.error(function() jwe.inflate("", function() end) end, "invalid chunk_size argument")
    end)
  end)

  describe("jwe.key", function()
    local pkey = require "resty.openssl.pkey"

    it("loads private RSA pkey", function()
      local key, err = pkey.new()
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))

      local keytype
      key, err, keytype = jwe.key(key, "RSA-OAEP")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(true, key:is_private())
      assert.equal("RSA", keytype)
    end)

    it("loads private EC pkey", function()
      local key, err = pkey.new({ type = "EC"})
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))

      local keytype
      key, err, keytype = jwe.key(key, "ECDH-ES")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(true, key:is_private())
      assert.equal("EC", keytype)
    end)

    it("loads private JWK key", function()
      local key, err, keytype = jwe.key(PRIVATE_RSA_JWK, "RSA-OAEP")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(true, key:is_private())
      assert.equal("RSA", keytype)

      key, err, keytype = jwe.key(PRIVATE_EC_JWK, "ECDH-ES")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(true, key:is_private())
      assert.equal("EC", keytype)
    end)

    it("loads public JWK key", function()
      local key, err, keytype = jwe.key(PUBLIC_RSA_JWK, "RSA-OAEP")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(false, key:is_private())
      assert.equal("RSA", keytype)

      key, err, keytype = jwe.key(PUBLIC_EC_JWK, "ECDH-ES")
      assert.equal(nil, err)
      assert.equal(true, pkey.istype(key))
      assert.equal(false, key:is_private())
      assert.equal("EC", keytype)
    end)

    it("returns error with invalid input", function()
      local ok, err = jwe.key({})
      assert.equal(nil, ok)
      assert.matches("unable to load encryption key", err)

      ok, err = jwe.key("")
      assert.equal(nil, ok)
      assert.matches("unable to load encryption key", err)
    end)

    it("raises error with invalid input", function()
      assert.error(function() jwe.key() end, "invalid key argument")
      assert.error(function() jwe.key(true) end, "invalid key argument")
      assert.error(function() jwe.key(false) end, "invalid key argument")
      assert.error(function() jwe.key(1) end, "invalid key argument")
      assert.error(function() jwe.key("", true) end, "invalid alg argument")
      assert.error(function() jwe.key("", false) end, "invalid alg argument")
      assert.error(function() jwe.key("", 1) end, "invalid alg argument")
      assert.error(function() jwe.key("", {}) end, "invalid alg argument")
      assert.error(function() jwe.key("", function() end) end, "invalid alg argument")
    end)
  end)

  describe("jwe.keytype", function()
    it("returns key type", function()
      local keytype, err = jwe.keytype(PUBLIC_RSA_JWK)
      assert.equal(nil, err)
      assert.equal("RSA", keytype)

      keytype, err = jwe.keytype(PUBLIC_EC_JWK)
      assert.equal(nil, err)
      assert.equal("EC", keytype)
    end)
  end)

  describe("jwe.key2alg", function()
    it("returns default algorithm for key", function()
      local alg, err, keytype = jwe.key2alg(PUBLIC_RSA_JWK)
      assert.equal(nil, err)
      assert.equal("RSA-OAEP", alg)
      assert.equal("RSA", keytype)

      alg, err, keytype = jwe.key2alg(PUBLIC_EC_JWK)
      assert.equal(nil, err)
      assert.equal("ECDH-ES", alg)
      assert.equal("EC", keytype)
    end)
  end)

  describe("jwe.curve", function()
    it("returns curve for EC key", function()
      local curve, err, keytype = jwe.curve(PUBLIC_EC_JWK)
      assert.equal(nil, err)
      assert.equal("P-256", curve)
      assert.equal("EC", keytype)
    end)
  end)

  describe("jwe.concatkdf", function()
    it("calculates key", function()
      local k, err = jwe.concatkdf(Z, "A256GCM", APU, APV)
      assert.equal(nil, err)
      assert.equal(32, #k)
      assert.equal("mIW1uHx8iKhvbo0V74f8SC-VuxHZp57Ry6FzUBlONy8", encode_base64url(k))
    end)
  end)

  describe("jwe.split", function()
    it("splits the JWE encrypted JWT token", function()
      local parts, err = jwe.split(JWT_TOKEN)
      assert.equal(nil, err)
      assert.equal(5, #parts)
      assert.equal(JWT_TOKEN, concat(parts, "."))
      assert.equal(JWT_HEADER, parts[1])
      assert.equal(JWT_KEY, parts[2])
      assert.equal(JWT_IV, parts[3])
      assert.equal(JWT_PAYLOAD, parts[4])
      assert.equal(JWT_TAG, parts[5])
    end)
  end)

  describe("jwe.decode", function()
    it("decodes the JWE encrypted JWT token", function()
      local parts, err = jwe.decode(JWT_TOKEN)
      assert.equal(nil, err)
      assert.equal(5, #parts)
      assert.equal(JWT_TOKEN, concat(parts, "."))
      assert.equal(JWT_HEADER, parts[1])
      assert.equal(JWT_KEY, parts[2])
      assert.equal(JWT_IV, parts[3])
      assert.equal(JWT_PAYLOAD, parts[4])
      assert.equal(JWT_TAG, parts[5])
      assert.same({
        alg = "ECDH-ES",
        enc = "A256GCM",
        apu = "MePXTKj2XTu5I-bWTHR6mw",
        apv = "fPqhkh_6GcTWuHnXXVArUg",
        epk = {
          kty = "EC",
          crv = "P-256",
          x = "Ygwx_MUtKMoMaJMeqaJ6cPUugohbEUsB56wkFZXF5L4",
          y = "1hF3c9QTHD-Z3jmoaJvLvpLbjqSZIoJ6gx_f-S0-gmQ",
        }
      }, parts.protected)
      assert.equal(decode_base64url(JWT_KEY), parts.encrypted_key)
      assert.equal(decode_base64url(JWT_IV), parts.iv)
      assert.equal(decode_base64url(JWT_PAYLOAD), parts.ciphertext)
      assert.equal(decode_base64url(JWT_TAG), parts.tag)
      assert.equal(JWT_HEADER, parts.aad)
    end)

    describe("jwe.decrypt", function()
      it("decrypts the JWE encrypted JWT token", function()
        local plaintext, err = jwe.decrypt("ECDH-ES", "A256GCM", PRIVATE_EC_JWK, JWT_TOKEN)
        assert.equal(nil, err)
        assert.equal("hello", plaintext)
      end)
    end)

    describe("jwe.encrypt", function()
      it("encrypts the plaintext and returns a JWT token", function()
        local secret = "secret stuff"

        local token, err = jwe.encrypt("ECDH-ES", "A256GCM", PUBLIC_EC_JWK, secret)
        assert.equal("string", type(token))
        assert.equal(nil, err)

        local parts
        parts, err = jwe.decode(token)
        assert.equal(nil, err)
        assert.equal(#secret, #parts.ciphertext)

        local plaintext
        plaintext, err = jwe.decrypt("ECDH-ES", "A256GCM", PRIVATE_EC_JWK, token)
        assert.equal(nil, err)
        assert.equal(secret, plaintext)
      end)
    end)
  end)
end)
