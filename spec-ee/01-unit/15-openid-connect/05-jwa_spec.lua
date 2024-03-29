-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local clone = require "table.clone"
local jwa = require "kong.openid-connect.jwa"


local function replace_char(pos, str, r)
  return str:sub(1, pos - 1) .. r .. str:sub(pos + 1)
end


describe("[Test JSON Web Algorithms (JWA)]", function()
  local shared_key = ngx.encode_base64("secret")
  local generic_input = "dummy input"

  describe("Generic tests", function()
      it("sign input [unknown jwa signing algorithm]", function()
        local jwk = { k = shared_key }
        local dgt, err = jwa.sign("unknown-alg", jwk, generic_input)
        assert.is_nil(dgt)
        assert.is_same("unsupported jwa signing algorithm was specified", err)
      end)
  end)

  describe("Hash Based Authentcation Code [HMAC]:", function()
    -- Test for invalid input. The `sign` interface is sufficient to test
    -- since all known JWAs call into it.

    it("sign input [no shared secret]", function()
      local jwk = { k = nil }
      local dgt, err = jwa.sign("HS256", jwk, generic_input)
      assert.is_nil(dgt)
      assert.is_same("hs shared secret was not specified", err)
    end)

    it("sign input [base64 decoding fails]", function()
      local jwk = { k = "&gt;@?OeK]?TI" }
      local dgt, err = jwa.sign("HS256", jwk, generic_input)
      assert.is_nil(dgt)
      assert.matches("hs key value could not be base64 url decoded", err)
    end)

    pending("sign input [hashing fails]", function()
      -- this needs fixing in the library
      local jwk = { k = shared_key }
      local dgt, err = jwa.sign("HS256", jwk, nil)
      assert.is_nil(dgt)
      assert.matches("hs key value could not be base64 url decoded", err)
    end)

    it("verify input [unknown jwa signing algorithm]", function()
      local jwk = { k = shared_key }
      local dgt, err = jwa.verify("unknown-alg", jwk, generic_input)
      assert.is_nil(dgt)
      assert.is_same("unsupported jwa signature verification algorithm was specified", err)
    end)

    it("verify input [no shared secret]", function()
      local jwk = { k = nil }
      local sig = "XcS98F9tkIoSt0_TRwtKkobtHRKMpEAnwf3yApreHyM"
      local dgt, err = jwa.verify("HS256", jwk, generic_input, sig)
      assert.is_nil(dgt)
      assert.is_same("hs shared secret was not specified", err)
    end)

    it("verify input [no signature]", function()
      local jwk = { k = generic_input }
      local dgt, err = jwa.verify("HS256", jwk, generic_input, nil)
      assert.is_nil(dgt)
      assert.is_same("hs signature was not specified", err)
    end)

    it("verify input [sig base64 decoding fails]", function()
      local jwk = { k = "foo" }
      local sig = "&gt;@?OeK]?TI"
      local dgt, err = jwa.verify("HS256", jwk, generic_input, sig)
      assert.is_nil(dgt)
      assert.match("hs signature could not be base64 url decoded", err)
    end)

    it("verify input [sig base64 decoding fails]", function()
      local jwk = { k = "&gt;@?OeK]?TI" }
      local sig = "XcS98F9tkIoSt0_TRwtKkobtHRKMpEAnwf3yApreHyM"
      local dgt, err = jwa.verify("HS256", jwk, generic_input, sig)
      assert.is_nil(dgt)
      assert.match("hs key value could not be base64 url decoded", err)
    end)

    it("verify input [comparison fails]", function()
      local sig = "XcS98F9tkIoSt0_TRwtKkobtHRKMpEAnwf3yApreHyM"
      local jwk = { k = shared_key }
      -- different input will generate a different mac
      local dgt, err = jwa.verify("HS256", jwk, "non-generic-input", sig)
      assert.is_same(err, "hs signature verification failed")
      assert.is_nil(dgt)      
    end)

    for _, alg in ipairs({ "HS256", "HS384", "HS512" }) do
      -- iterate over known JWAs
      it("if signing and verification for [" .. alg .. "] works correctly", function()
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        local jwk = { k = shared_key }
        local sig, err = obj.sign(jwk, generic_input)
        assert.is_nil(err)
        assert.is_string(sig)
        local ret, err = obj.verify(jwk, generic_input, sig)
        assert.is_nil(err)
        assert.is_truthy(ret)
      end)
    end

    describe("test critical vulnerabilities:", function()
      it("must not use alg in the header field #1", function()
        -- explicitly set alg=HS256
        local jwk = { k = shared_key, alg = "HS256" }
        -- create signature with "HS256"
        local sig, _ = jwa.sign("HS256", jwk, generic_input)
        -- try to force another alg
        local dgt, err = jwa.verify("HS384", jwk, generic_input, sig)
        -- expect dgt to not get computed
        assert.is_same(err, "algorithm mismatch")
        assert.is_nil(dgt)
      end)

      it("must not use alg in the header field #2", function()
        -- explicitly set alg=none
        local jwk = { k = shared_key, alg="none" }
        -- create signature with "HS256"
        local sig, _ = jwa.sign("HS256", jwk, generic_input)
        -- try to force another alg
        local dgt, err = jwa.verify("HS384", jwk, generic_input, sig)
        -- expect dgt to not get computed
        assert.is_same(err, "algorithm mismatch")
        assert.is_nil(dgt)
      end)

      it("must not use alg in the header field #3", function()
        -- explicitly set alg=HS256
        local jwk = { k = shared_key, alg="HS384" }
        -- create signature with "HS256"
        local sig, _ = jwa.sign("HS256", jwk, generic_input)
        -- pass alg=nil
        local dgt, err = jwa.verify(nil, jwk, generic_input, sig)
        -- expect dgt to not get computed
        assert.is_same(err, "jwa signature verification algorithm was not specified")
        assert.is_nil(dgt)
      end)
    end)

  end)

  describe("RSA using SHA:", function()
    -- dummy data following https://en.wikipedia.org/wiki/RSA_(cryptosystem)
    local jwk = {
      n  = "pjdss8ZaDfEH6K6U7GeW2nxDqR4IP049fk1fK0lndimbMMVBdPv_hSpm8T8EtBDxrUdi1OHZfMhUixGaut-3nQ4GG9nM249oxhCtxqqNvEXrmQRGqczyLxuh-fKn9Fg--hS9UpazHpfVAFnB5aCfXoNhPuI8oByyFKMKaOVgHNqP5NBEqabiLftZD3W_lsFCPGuzr4Vp0YS7zS2hDYScC2oOMu4rGU1LcMZf39p3153Cq7bS2Xh6Y-vw5pwzFYZdjQxDn8x8BG3fJ6j8TGLXQsbKH1218_HcUJRvMwdpbUQG5nvA2GXVqLqdwp054Lzk9_B_f1lVrmOKuHjTNHq48w",
      e  = "AQAB",
      d  = "ksDmucdMJXkFGZxiomNHnroOZxe8AmDLDGO1vhs-POa5PZM7mtUPonxwjVmthmpbZzla-kg55OFfO7YcXhg-Hm2OWTKwm73_rLh3JavaHjvBqsVKuorX3V3RYkSro6HyYIzFJ1Ek7sLxbjDRcDOj4ievSX0oN9l-JZhaDYlPlci5uJsoqro_YrE0PRRWVhtGynd-_aWgQv1YzkfZuMD-hJtDi1Im2humOWxA4eZrFs9eG-whXcOvaSwO4sSGbS99ecQZHM2TcdXeAs1PvjVgQ_dKnZlGN3lTWoWfQP55Z7Tgt8Nf1q4ZAKd-NlMe-7iqCFfsnFwXjSiaOa2CRGZn-Q",
      p  = "4A5nU4ahEww7B65yuzmGeCUUi8ikWzv1C81pSyUKvKzu8CX41hp9J6oRaLGesKImYiuVQK47FhZ--wwfpRwHvSxtNU9qXb8ewo-BvadyO1eVrIk4tNV543QlSe7pQAoJGkxCia5rfznAE3InKF4JvIlchyqs0RQ8wx7lULqwnn0",
      q  = "ven83GM6SfrmO-TBHbjTk6JhP_3CMsIvmSdo4KrbQNvp4vHO3w1_0zJ3URkmkYGhz2tgPlfd7v1l2I6QkIh4Bumdj6FyFZEBpxjE4MpfdNVcNINvVj87cLyTRmIcaGxmfylY7QErP8GFA-k4UoH_eQmGKGK44TRzYj5hZYGWIC8",
      dp = "lmmU_AG5SGxBhJqb8wxfNXDPJjf__i92BgJT2Vp4pskBbr5PGoyV0HbfUQVMnw977RONEurkR6O6gxZUeCclGt4kQlGZ-m0_XSWx13v9t9DIbheAtgVJ2mQyVDvK4m7aRYlEceFh0PsX8vYDS5o1txgPwb3oXkPTtrmbAGMUBpE",
      dq = "mxRTU3QDyR2EnCv0Nl0TCF90oliJGAHR9HJmBe__EjuCBbwHfcT8OG3hWOv8vpzokQPRl5cQt3NckzX3fs6xlJN4Ai2Hh2zduKFVQ2p-AF2p6Yfahscjtq-GY9cB85NxLy2IXCC0PF--Sq9LOrTE9QV988SJy_yUrAjcZ5MmECk",
      qi = "ldHXIrEmMZVaNwGzDF9WG8sHj2mOZmQpw9yrjLK9hAsmsNr5LTyqWAqJIYZSwPTYWhY4nu2O0EY9G9uYiqewXfCKw_UngrJt8Xwfq1Zruz0YY869zPN4GiE9-9rzdZB33RBw8kIOquY3MK74FMwCihYx_LiU2YTHkaoJ3ncvtvg"
    }
    local optional_keys = { dq=true, dp=true, qi=true }
    local error_msg_map = {
      n = "modulus was not specified",
      e = "exponent was not specified",
      d = "secret exponent was not specified",
      p = "factor p was not specified",
      q = "factor q was not specified",
    }

    pending("Tests VUL token forging per CVE-2016-10555", function()
      -- https://nvd.nist.gov/vuln/detail/CVE-2016-10555
      -- 1. Setup server that expects tokens signed with RSA
      -- 2. Create token that is signed with HMAC where the secret is the
      --    public key of the server
      -- 3. force the server to use a verifcation algorithm of our choice.

      -- The accepted fix for this is to set a `algorithm` parameter in
      -- our verification method, which we do.
    end)

    for _, alg in ipairs({ "RS256", "RS512", "RS384" }) do
      -- iterate over known JWAs
      it("if signing and verification for [" .. alg .. "] works correctly", function()
        local jwk_copy = clone(jwk)
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        local sig, err = obj.sign(jwk_copy, generic_input)
        assert.is_nil(err)
        assert.is_string(sig)
        local ret, err = obj.verify(jwk_copy, generic_input, sig)
        assert.is_nil(err)
        assert.is_truthy(ret)
      end)

      for _, k in ipairs({ "n", "e", "d" , "p", "q", "dp" }) do
        local perhaps = it
        if k == "dp" and helpers.is_fips_build() then
          perhaps = pending
        end
        perhaps("snips <" .. k .. "> from the jwk and expect a failure", function()
          local jwk_copy = clone(jwk)
          -- snip, snip...
          jwk_copy[k] = nil
          -- either all or none of these must be in the jwk
          if k == "dp" then
            jwk_copy.dq = nil
            jwk_copy.qi = nil
          end

          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)

          if optional_keys[k] ~= nil then
            -- if this key is not present, signing will be successful anyways.
            assert.is_nil(err)
            assert.is_not_nil(dgt)
          else
            -- if this key are missing signing fails.
            assert.is_not_nil(err)
            assert.is_same(err, error_msg_map[k])
            assert.is_nil(dgt)
          end
        end)
      end

      -- All values can be modified and signature succeeds on resty.openssl
      pending("Alter values for keys", function()
        -- d (secret exponent) is allowed to be different
        local altered_values_allowed = { d = true }
        for k, v in pairs(jwk) do
          it("alters values for key <" .. k .. "> from the jwk and expect a failure", function()
            local jwk_copy = clone(jwk)
            -- replace the first char with a "x"
            -- todo: find out when this is fine and when a success is considered a bug
            jwk_copy[k] = replace_char(1, v, "x")
            -- FIXME: test errors when string is appended at the end with:
            -- nginx: rsa-sec-compute-root.c:171: _nettle_rsa_sec_compute_root: Assertion `bn <= qn" failed.
            -- this should not error out but handle the error gracefully.
            -- Q: How is this error interpreted in a real ngx env?
            -- sending in arbitrary jwks can cause crashes
            local dgt, err = jwa.sign(alg, jwk_copy, generic_input)

            if altered_values_allowed[k] ~= nil then
              assert.is_nil(err)
              assert.is_not_nil(dgt)
            else
              assert.is_not_nil(err)
              assert.is_nil(dgt)
            end
          end)
        end
      end)
    end
  end)

  describe("RSA with Probabilistic Signature Scheme using SHA:", function()
    pending("Tests VUL token forging per CVE-2016-10555", function()
      -- https://nvd.nist.gov/vuln/detail/CVE-2016-10555
      -- 1. Setup server that expects tokens signed with RSA
      -- 2. Create token that is signed with HMAC where the secret is the
      --    public key of the server
      -- 3. force the server to use a verifcation algorithm of our choice.

      -- The accepted fix for this is to set a `algorithm` parameter in
      -- our verification method, which we do.
    end)

    -- not n=true, e=true as with RS*
    local optional_keys = { dq=true, dp=true, qi=true }
    local error_msg_map = { d = "secret exponent was not specified",
                           p = "factor p was not specified",
                           q = "factor q was not specified",
                           n = "modulus was not specified",
                           e = "exponent was not specified"
                           }
    -- dummy data following https://en.wikipedia.org/wiki/RSA_(cryptosystem)
    local jwk = {
      n  = "pjdss8ZaDfEH6K6U7GeW2nxDqR4IP049fk1fK0lndimbMMVBdPv_hSpm8T8EtBDxrUdi1OHZfMhUixGaut-3nQ4GG9nM249oxhCtxqqNvEXrmQRGqczyLxuh-fKn9Fg--hS9UpazHpfVAFnB5aCfXoNhPuI8oByyFKMKaOVgHNqP5NBEqabiLftZD3W_lsFCPGuzr4Vp0YS7zS2hDYScC2oOMu4rGU1LcMZf39p3153Cq7bS2Xh6Y-vw5pwzFYZdjQxDn8x8BG3fJ6j8TGLXQsbKH1218_HcUJRvMwdpbUQG5nvA2GXVqLqdwp054Lzk9_B_f1lVrmOKuHjTNHq48w",
      e  = "AQAB",
      d  = "ksDmucdMJXkFGZxiomNHnroOZxe8AmDLDGO1vhs-POa5PZM7mtUPonxwjVmthmpbZzla-kg55OFfO7YcXhg-Hm2OWTKwm73_rLh3JavaHjvBqsVKuorX3V3RYkSro6HyYIzFJ1Ek7sLxbjDRcDOj4ievSX0oN9l-JZhaDYlPlci5uJsoqro_YrE0PRRWVhtGynd-_aWgQv1YzkfZuMD-hJtDi1Im2humOWxA4eZrFs9eG-whXcOvaSwO4sSGbS99ecQZHM2TcdXeAs1PvjVgQ_dKnZlGN3lTWoWfQP55Z7Tgt8Nf1q4ZAKd-NlMe-7iqCFfsnFwXjSiaOa2CRGZn-Q",
      p  = "4A5nU4ahEww7B65yuzmGeCUUi8ikWzv1C81pSyUKvKzu8CX41hp9J6oRaLGesKImYiuVQK47FhZ--wwfpRwHvSxtNU9qXb8ewo-BvadyO1eVrIk4tNV543QlSe7pQAoJGkxCia5rfznAE3InKF4JvIlchyqs0RQ8wx7lULqwnn0",
      q  = "ven83GM6SfrmO-TBHbjTk6JhP_3CMsIvmSdo4KrbQNvp4vHO3w1_0zJ3URkmkYGhz2tgPlfd7v1l2I6QkIh4Bumdj6FyFZEBpxjE4MpfdNVcNINvVj87cLyTRmIcaGxmfylY7QErP8GFA-k4UoH_eQmGKGK44TRzYj5hZYGWIC8",
      dp = "lmmU_AG5SGxBhJqb8wxfNXDPJjf__i92BgJT2Vp4pskBbr5PGoyV0HbfUQVMnw977RONEurkR6O6gxZUeCclGt4kQlGZ-m0_XSWx13v9t9DIbheAtgVJ2mQyVDvK4m7aRYlEceFh0PsX8vYDS5o1txgPwb3oXkPTtrmbAGMUBpE",
      dq = "mxRTU3QDyR2EnCv0Nl0TCF90oliJGAHR9HJmBe__EjuCBbwHfcT8OG3hWOv8vpzokQPRl5cQt3NckzX3fs6xlJN4Ai2Hh2zduKFVQ2p-AF2p6Yfahscjtq-GY9cB85NxLy2IXCC0PF--Sq9LOrTE9QV988SJy_yUrAjcZ5MmECk",
      qi = "ldHXIrEmMZVaNwGzDF9WG8sHj2mOZmQpw9yrjLK9hAsmsNr5LTyqWAqJIYZSwPTYWhY4nu2O0EY9G9uYiqewXfCKw_UngrJt8Xwfq1Zruz0YY869zPN4GiE9-9rzdZB33RBw8kIOquY3MK74FMwCihYx_LiU2YTHkaoJ3ncvtvg"
    }
    for _, alg in ipairs({ "PS256", "PS384", "PS512" }) do
      -- iterate over known JWAs
      it("if signing and verification for [" .. alg .. "] works correctly", function()
        local jwk_copy = clone(jwk)
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        local sig, err = obj.sign(jwk_copy, generic_input)
        assert.is_nil(err)
        assert.is_string(sig)
        local ret, err = obj.verify(jwk_copy, generic_input, sig)
        assert.is_nil(err)
        assert.is_truthy(ret)
      end)
      
      for _, k in ipairs({ "n", "e", "d", "p", "q", "dp" }) do
        local perhaps = it
        if k == "dp" and helpers.is_fips_build() then
          perhaps = pending
        end
        perhaps("snips <" .. k .. "> from the jwk and expect a failure", function()
          local jwk_copy = clone(jwk)
          
          -- snip, snip...
          jwk_copy[k] = nil
          if k == "dp" then
            jwk_copy.dq = nil
            jwk_copy.qi = nil
          end
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
          if optional_keys[k] ~= nil then
            -- if this key is not present, signing will be successful anyways.
            assert.is_nil(err)
            assert.is_not_nil(dgt)
          else
            -- if this key are missing signing fails.
            assert.is_not_nil(err)
            assert.is_same(err, error_msg_map[k])
            assert.is_nil(dgt)
          end
        end)
      end

      local keys_needed_for_verify = { n = true, e = true }
      for k, v in pairs(jwk) do
        it("verification behaves as expected when <" .. k .. "> is altered", function()
          local jwk_copy = clone(jwk)
          -- signs and subsequently verifies signature
          jwk_copy[k] = replace_char(1, v, "x")
          local obj = jwa[alg]
          local sig, err = obj.sign(jwk_copy, generic_input)
          assert.is_nil(err)
          assert.is_string(sig)
          local ret, err = obj.verify(jwk_copy, generic_input, sig)
          if keys_needed_for_verify[k] then
            assert.is_falsy(ret)
          else
            assert.is_nil(err)
            assert.is_truthy(ret)
          end
        end)
      end

      -- All values can be modified and signature succeeds on resty.openssl
      pending("Alter values for keys", function()
        -- d (secret exponent) is allowed to be different
        local altered_values_allowed = { d=true }
        for k, v in pairs(jwk) do
          it("alters values for key <" .. k .. "> from the jwk and expect a failure", function()
            local jwk_copy = clone(jwk)
            -- replace the first char with a "x"
            -- todo: find out when this is fine and when a success is considered a bug
            jwk_copy[k] = replace_char(1, v, "x")
            local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
            if altered_values_allowed[k] ~= nil then
              assert.is_nil(err)
              assert.is_not_nil(dgt)
            else
              assert.is_not_nil(err)
              assert.is_nil(dgt)
            end
          end)
        end
      end)
    end
  end)

  describe("Elliptic Curve Digital Signature Algorithm using SHA:", function()
    local jwk_p256 = {
      crv = "P-256",
      d = "0g5vAEKzugrXaRbgKG0Tj2qJ5lMP4Bezds1_sTybkfk",
      y = "lf0u0pMj4lGAzZix5u4Cm5CMQIgMNpkwy163wtKYVKI",
      x = "SVqB4JcUD6lsfvqMr-OKUNUphdNn64Eay60978ZlL74",
    }
    local jwk_p384 = {
      crv = "P-384",
      d = "iuuX3Z0DjRILhOMVGyS4R83f1ZS00ieTfhA0HcVfy9XR0iybAfEK_nYOpuhYjO9I",
      x = "7Da8aVXwE5qH59GnyCSsXQSW6xIFyCGSLs9SebRcESNsxQwQebeVQtnEf0eW9oR0",
      y = "QCr5a7ZQq2BoMKItZldwE2wTjwthYdEClJTIEtydIeHpgj-jCU_-KVCKYOlT3YAe"
    }
    local jwk_512 = {
      crv = "P-521",
      d = "AZRqDLEnqVjXqR_dkO7mgjuLw9uVFbDwx5y-qdrTId59XX1O2OrIIZv-8Q4ooGaBq0RItt3EWMPRq3VzEuudVcI3",
      x = "ASn_xNmYprggNhBepoYjl7qLpuksMAyxiskcSra_T4Pq-mEBpznUEpYLCmM5_tB2TaiKDdz-Ygw_Dc72OM2ooDxr",
      y = "AWwo9t7Vum7PhJone5E3zVPXx0GrVghKUBh9P8y6gZtazbIv4BagPPsU4jxaEeiUlnQIbZ7hO_cccWWU8VnGVs46"
    }

    for alg, jwk in pairs({ES384 = jwk_p384, ES256 = jwk_p256, ES512 = jwk_512}) do
      -- iterate over known JWAs
      it("test if signing and verification for [" .. alg .. "] with curve [" .. jwk.crv .. "] works correctly", function()
        local jwk_copy = clone(jwk)
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        local sig, err = obj.sign(jwk_copy, generic_input)
        assert.is_nil(err)
        assert.is_string(sig)
        local ret, err = obj.verify(jwk_copy, generic_input, sig)
        assert.is_nil(err)
        assert.is_truthy(ret)
      end)

      it("creating ASN.1/DER signature and check if it correctly rejects the verification for [" .. alg .. "] with curve [" .. jwk.crv .. "] works correctly", function()
        local jwk_copy = clone(jwk)
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        -- create ASN.1/DER signature
        local sig, err = obj.sign(jwk_copy, generic_input, false)
        assert.is_nil(err)
        assert.is_string(sig)
        -- expect to fail validation as it expects a raw signature but received a asn.1/der formatted sig
        local ret = obj.verify(jwk_copy, generic_input, sig)
        assert.is_falsy(ret)
      end)

      it("signing fails when unknown curve is used", function()
        local jwk_copy = clone(jwk)
        jwk_copy.crv = "unknown"
        local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
        assert.is_nil(dgt)
        assert.matches("curve \"unknown\" is not supported by this library", err)
      end)

      it("signing fails when x or y are altered", function()
        local jwk_copy = clone(jwk)
        jwk_copy.x = replace_char(1, jwk_copy.x, "x")
        local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
        assert.is_nil(dgt)
        assert.matches("point is not on curve", err)
        jwk_copy = clone(jwk)
        jwk_copy.y = replace_char(1, jwk_copy.y, "x")
        dgt, err = jwa.sign(alg, jwk_copy, generic_input)
        assert.is_nil(dgt)
        assert.matches("point is not on curve", err)
      end)

      it("verification fails when x or y are altered", function()
        local jwk_copy = clone(jwk)
        local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
        assert.is_nil(err)
        assert.is_not_nil(dgt)
        jwk_copy.x = replace_char(1, jwk_copy.x, "x")
        local ret, err = jwa.verify(alg, jwk_copy, generic_input, dgt)
        assert.match("failed instantiating key", err)
        assert.is_not_truthy(ret)
        jwk_copy = clone(jwk)
        jwk_copy.y = replace_char(1, jwk_copy.y, "x")
        local ret, err = jwa.verify(alg, jwk_copy, generic_input, dgt)
        assert.match("failed instantiating key", err)
        assert.is_not_truthy(ret)
      end)

      it("verification fails when unknown curve is used", function()
        local jwk_copy = clone(jwk)
        local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
        assert.is_nil(err)
        assert.is_not_nil(dgt)
        jwk_copy.crv = "unknown"
        local ret, err = jwa.verify(alg, jwk_copy, generic_input, dgt)
        assert.matches("curve \"unknown\" is not supported by this library", err)
        assert.is_not_truthy(ret)
      end)
    end
  end)

  describe("Edwards Curve Digital Signature Algorithm using SHA:", function()
    local optional_keys_for_signing = { x = true }
    local optional_keys_for_verification = { d = true }
    local error_msg_map = {
      crv = "eddsa curve was not specified",
      d = "eddsa ecc private key was not specified"
    }
    local error_msg_verfy_map = {
      crv = "eddsa curve was not specified",
      x = "eddsa x coordinate was not specified",
    }
    local jwk_512 = {
      d = "Lou-gsjFGAnb9S6KZ4MPu8z81Ov9PfZvdCgF5BVBrBs",
      crv = "Ed25519",
      x = "To0Ykjw6SGHtcslcOFoo8yq6LogvFb5cMuuXJD7LMzQ"
    }

    for alg, jwk in pairs({EdDSA=jwk_512}) do
      -- iterate over known JWAs
      it("test if signing and verification for [" .. alg .. "] with curve [" .. jwk.crv .. "] works correctly", function()
        -- signs and subsequently verifies signature
        local obj = jwa[alg]
        local sig, err = obj.sign(jwk, generic_input)
        assert.is_nil(err)
        assert.is_string(sig)
        local ret, err = obj.verify(jwk, generic_input, sig)
        assert.is_nil(err)
        assert.is_truthy(ret)
      end)

      for k, _ in pairs(jwk) do
        it("snips <" .. k .. "> from the jwk and expect a failure when signing", function()
          local jwk_copy = clone(jwk)
          -- snip, snip...
          jwk_copy[k] = nil
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)

          if optional_keys_for_signing[k] ~= nil then
            -- if this key is not present, signing will be successful anyways.
            assert.is_nil(err)
            assert.is_not_nil(dgt)
          else
            -- if this key are missing signing fails.
            assert.is_not_nil(err)
            assert.match(error_msg_map[k], err)
            assert.is_nil(dgt)            
          end
        end)
      end

      for k, _ in pairs(jwk) do
        it("snips <" .. k .. "> from the jwk and expect a failure when verifying", function()
          local jwk_copy = clone(jwk)
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
          assert.is_nil(err)
          assert.is_not_nil(dgt)

          -- snip, snip...
          jwk_copy[k] = nil
          local ret, err = jwa.verify(alg, jwk_copy, generic_input, dgt)
          if optional_keys_for_verification[k] ~= nil then
            -- if this key is not present, signing will be successful anyways.
            assert.is_nil(err)
            assert.is_not_nil(ret)
          else
            -- if this key are missing verifying fails.
            assert.is_not_nil(err)
            assert.match(error_msg_verfy_map[k], err)
            assert.is_nil(ret)
          end
        end)
      end

      it("signing fails when unknown curve is used", function()
          local jwk_copy = clone(jwk)
          jwk_copy.crv = "unknown"
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
          assert.is_nil(dgt)
          assert.match("unknown curve \"unknown", err)
      end)

      it("verification fails when x was altered", function()
          local jwk_copy = clone(jwk)
          jwk_copy.x = replace_char(1, jwk_copy.x, "x")
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
          assert.is_nil(err)
          assert.is_not_nil(dgt)
          local ret = jwa.verify(alg, jwk_copy, generic_input, dgt)
          assert.is_not_truthy(ret)
      end)

      it("verification fails when unknown curve is used", function()
          local jwk_copy = clone(jwk)
          local dgt, err = jwa.sign(alg, jwk_copy, generic_input)
          assert.is_nil(err)
          assert.is_not_nil(dgt)
          jwk_copy.crv = "unknown"
          local ret, err = jwa.verify(alg, jwk_copy, generic_input, dgt)
          assert.match("unknown curve \"unknown", err)
          assert.is_not_truthy(ret)
      end)
    end
  end)
  
  describe("jwa.hash produces expected outputs", function()
    local t = {
      RS256 = {
        gruce = "YUxNp3z8X5yHznhV4mvBvLP8KBE78siR/vGwKhZsoUI="
      },
      RS384 = {
        gruce = "YRwaSP/d4rElnimlrD103SCC5nOCr3mmNZtL7cNL6kSGiDXSUu4xZBR9LE" ..
                "efQkdD"
      },
      RS512 = {
        gruce = "tMDcdXATRsDbzl+ohpny5nxcQHBXpQIE4FaW/oOu8sb9bqGyIEl1qllWue" ..
                "dmtgJrXUN4unC+AH/1k1fy6tL2Fw=="
      }
    }
    for alg, val in pairs(t) do
      it("correctly performs hashing with " .. alg, function()
        for input, expected in pairs(val) do
          local hsh, err = ngx.encode_base64(jwa.hash(alg, input))
          assert.is_nil(err)
          assert.equals(expected, hsh)
        end
      end)
      it("correctly handles unknown algorithm", function()
        local hsh, err = jwa.hash("unknown", "gruce")
        assert.equals(err, "unsupported jwa hashing algorithm")
        assert.is_nil(hsh)
      end)
    end
  end)
end)
