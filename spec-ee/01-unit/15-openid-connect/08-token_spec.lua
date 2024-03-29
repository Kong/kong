-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local oic = require "kong.openid-connect"
local mtls_fixtures = require "spec-ee.fixtures.mtls"

local CLIENT_CERT                   = mtls_fixtures.CLIENT_CERT
local CERT_ACCESS_TOKEN             = mtls_fixtures.CERT_ACCESS_TOKEN
local WRONG_CERT_ACCESS_TOKEN       = mtls_fixtures.WRONG_CERT_ACCESS_TOKEN
local NO_CERT_ACCESS_TOKEN          = mtls_fixtures.NO_CERT_ACCESS_TOKEN
local CERT_INTROSPECTION_DATA       = mtls_fixtures.CERT_INTROSPECTION_DATA
local WRONG_CERT_INTROSPECTION_DATA = mtls_fixtures.WRONG_CERT_INTROSPECTION_DATA
local NO_CERT_INTROSPECTION_DATA    = mtls_fixtures.NO_CERT_INTROSPECTION_DATA


local KEYS = [[
{
  "keys": [
    {
      "kid": "n8DfUDtTTFcQU7r7ic8MDhz2QPvzj3-3-aLOIN3hF1k",
      "kty": "RSA",
      "alg": "RS256",
      "use": "sig",
      "n": "nlW-87IWOaiL3Q4anz5cnwD7nlHP3e_YTPUx659fAnyFr-fAg-AMWgDVNB3GungHJYBlHnDSAeHrV5LT4K7COrHJHm8Cy-xb_pW3EXUo6nAl_xXOcSjzYNxnESmqYhhNZcEKyaD7OSwVGrTFNzpFh4b87YEJcIl7j-ivtk7z09u7EkaL2up9VKqYLSP9-r2giN7QmdO0ras_VohmMQ2GgVPbCL-MnQth33o6ogjIE0G5X52_YAynx5ixgRSkbph9aPNkWGNtFxXxLgepcmrlbpguVb9eKVy_R3-WuzXHNriB-K6q6h56Ihe83H7CO5eABC91hm3MqP3-eOd-Bd_O7w",
      "e": "AQAB",
      "x5c": [
        "MIIClzCCAX8CBgF7NKExPTANBgkqhkiG9w0BAQsFADAPMQ0wCwYDVQQDDARkZW1vMB4XDTIxMDgxMTA5NTEyNFoXDTMxMDgxMTA5NTMwNFowDzENMAsGA1UEAwwEZGVtbzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ5VvvOyFjmoi90OGp8+XJ8A+55Rz93v2Ez1MeufXwJ8ha/nwIPgDFoA1TQdxrp4ByWAZR5w0gHh61eS0+CuwjqxyR5vAsvsW/6VtxF1KOpwJf8VznEo82DcZxEpqmIYTWXBCsmg+zksFRq0xTc6RYeG/O2BCXCJe4/or7ZO89PbuxJGi9rqfVSqmC0j/fq9oIje0JnTtK2rP1aIZjENhoFT2wi/jJ0LYd96OqIIyBNBuV+dv2AMp8eYsYEUpG6YfWjzZFhjbRcV8S4HqXJq5W6YLlW/Xilcv0d/lrs1xza4gfiuquoeeiIXvNx+wjuXgAQvdYZtzKj9/njnfgXfzu8CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAaU6BbHHjp3t9/SJaGeHWFv1jWNOU+valCBvwbjmNhRJehqbyLMRb4cD0hDXGTfRT2Pw3TEG5ZMVNxb6Eawx2b+4GUIdPFjDPvfmowCFThUeFW+kD7ctPHtIbW+b2fZVNVcvjXfHhYo59uX65OvShZq4nyoZCZanchksL3x693mTSYjCgATZCGq0GbqIMpQ2Fyttnl/RKvB/x2iMtnvI841UhCAPk9Srlf4hMeaFOYW7NodVKTY+YHGaFo7Ev1eFjOQsO+kS38GW6TS8OCbeO35ZG3+ulPkPV/qz5+O4VFh4PLbqKAE6g3EfDX48M5K7SBfrwHe8gNfZ8LOx3Nd+QnA=="
      ],
      "x5t": "tKxAIGUN0j4ectWnHCcRnR80P7U",
      "x5t#S256": "87gQByUhXXevecXW2Bh1PZxD3rJjkqmIkwkEHPjzQVA"
    }
  ]
}
]]


local TOKENS_ENCODED = { id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJrb25nLWNsaWVudC1wYXIiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiam9obiIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJEb2UiLCJlbWFpbCI6ImpvaG4uZG9lQGtvbmdocS5jb20ifQ.Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }
local TOKENS_DECODED = {
  id_token = {
    decoded = true,
    header = {
      alg = "RS256",
      kid = "n8DfUDtTTFcQU7r7ic8MDhz2QPvzj3-3-aLOIN3hF1k",
      typ = "JWT"
    },
    jwk = {
      alg = "RS256",
      e = "AQAB",
      kid = "n8DfUDtTTFcQU7r7ic8MDhz2QPvzj3-3-aLOIN3hF1k",
      kty = "RSA",
      n = "nlW-87IWOaiL3Q4anz5cnwD7nlHP3e_YTPUx659fAnyFr-fAg-AMWgDVNB3GungHJYBlHnDSAeHrV5LT4K7COrHJHm8Cy-xb_pW3EXUo6nAl_xXOcSjzYNxnESmqYhhNZcEKyaD7OSwVGrTFNzpFh4b87YEJcIl7j-ivtk7z09u7EkaL2up9VKqYLSP9-r2giN7QmdO0ras_VohmMQ2GgVPbCL-MnQth33o6ogjIE0G5X52_YAynx5ixgRSkbph9aPNkWGNtFxXxLgepcmrlbpguVb9eKVy_R3-WuzXHNriB-K6q6h56Ihe83H7CO5eABC91hm3MqP3-eOd-Bd_O7w",
      use = "sig",
      x5c = { "MIIClzCCAX8CBgF7NKExPTANBgkqhkiG9w0BAQsFADAPMQ0wCwYDVQQDDARkZW1vMB4XDTIxMDgxMTA5NTEyNFoXDTMxMDgxMTA5NTMwNFowDzENMAsGA1UEAwwEZGVtbzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ5VvvOyFjmoi90OGp8+XJ8A+55Rz93v2Ez1MeufXwJ8ha/nwIPgDFoA1TQdxrp4ByWAZR5w0gHh61eS0+CuwjqxyR5vAsvsW/6VtxF1KOpwJf8VznEo82DcZxEpqmIYTWXBCsmg+zksFRq0xTc6RYeG/O2BCXCJe4/or7ZO89PbuxJGi9rqfVSqmC0j/fq9oIje0JnTtK2rP1aIZjENhoFT2wi/jJ0LYd96OqIIyBNBuV+dv2AMp8eYsYEUpG6YfWjzZFhjbRcV8S4HqXJq5W6YLlW/Xilcv0d/lrs1xza4gfiuquoeeiIXvNx+wjuXgAQvdYZtzKj9/njnfgXfzu8CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAaU6BbHHjp3t9/SJaGeHWFv1jWNOU+valCBvwbjmNhRJehqbyLMRb4cD0hDXGTfRT2Pw3TEG5ZMVNxb6Eawx2b+4GUIdPFjDPvfmowCFThUeFW+kD7ctPHtIbW+b2fZVNVcvjXfHhYo59uX65OvShZq4nyoZCZanchksL3x693mTSYjCgATZCGq0GbqIMpQ2Fyttnl/RKvB/x2iMtnvI841UhCAPk9Srlf4hMeaFOYW7NodVKTY+YHGaFo7Ev1eFjOQsO+kS38GW6TS8OCbeO35ZG3+ulPkPV/qz5+O4VFh4PLbqKAE6g3EfDX48M5K7SBfrwHe8gNfZ8LOx3Nd+QnA==" },
      x5t = "tKxAIGUN0j4ectWnHCcRnR80P7U",
      ["x5t#S256"] = "87gQByUhXXevecXW2Bh1PZxD3rJjkqmIkwkEHPjzQVA"
    },
    payload = {
      acr = "1",
      at_hash = "NrRgB98p4iH-e--mDSSUFw",
      aud = "kong-client-par",
      auth_time = 1704716795,
      azp = "kong-client-par",
      email = "john.doe@konghq.com",
      email_verified = true,
      exp = 1704717395,
      family_name = "Doe",
      given_name = "John",
      iat = 1704716795,
      iss = "http://keycloak.test:8080/realms/demo",
      jti = "94ea1899-e8c5-41db-8439-68a115943d50",
      name = "John Doe",
      nonce = "MhhByfx_4rxnz-CR2BooIqrx",
      preferred_username = "john",
      session_state = "cf44996d-6ad1-4dcd-80a7-6805b7089a1f",
      sid = "cf44996d-6ad1-4dcd-80a7-6805b7089a1f",
      sub = "23e1af17-b1be-43c9-be4e-082ea31ab553",
      typ = "ID"
    },
    signature = "Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ",
    type = "JWS",
  }
}


local function initialize_oic_and_token(options)
  local _oic = oic.new(options, {}, KEYS)
  return _oic.token
end

describe("Token tests", function ()
  local t

  describe("Signature verification - decode()", function()
    it("is enabled by default", function()
      t = initialize_oic_and_token({})
      local res, err = t:decode(TOKENS_ENCODED, { verify_claims = false })
      assert.is_nil(err)
      assert.same(TOKENS_DECODED, res)
    end)

    it("fails with invalid header", function()
      local tokens = { id_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im44RGZVRHRUVEZjUVU3cjdpYzhNRGh6MlFQdnpqMy0zLWFMT0lOM2hGMWsiLCJleHRyYSI6ImhhY2tlZCJ9.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJrb25nLWNsaWVudC1wYXIiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiam9obiIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJEb2UiLCJlbWFpbCI6ImpvaG4uZG9lQGtvbmdocS5jb20ifQ.Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }
      local res, err = t:decode(tokens, { verify_claims = false })
      assert.is_nil(res)
      assert.is_string(err)
    end)


    it("fails with invalid payload", function()
      local tokens = { id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJrb25nLWNsaWVudC1wYXIiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiaGFja2VyIiwiZ2l2ZW5fbmFtZSI6IkpvaG4iLCJmYW1pbHlfbmFtZSI6IkRvZSIsImVtYWlsIjoiam9obi5kb2VAa29uZ2hxLmNvbSJ9.NHVaYe26MbtOYhSKkoKYdFVomg4i8ZJd8_-RU8VNbftc4TSMb4bXP3l3YlNWACwyXPGffz5aXHc6lty1Y2t4SWRqGteragsVdZufDn5BlnJl9pdR_kdVFUsra2rWKEofkZeIC4yWytE58sMIihvo9H1ScmmVwBcQP6XETqYd0aSHp1gOa9RdUPDvoXQ5oqygTqVtxaDr6wUFKrKItgBMzWIdNZ6y7O9E0DhEPTbE9rfBo6KTFsHAZnMg4k68CDp2woYIaXbmYTWcvbzIuHO7_37GT79XdIwkm95QJ7hYC9RiwrV7mesbY4PAahERJawntho0my942XheVLmGwLMBkQ" }
      local res, err = t:decode(tokens, { verify_claims = false })
      assert.is_nil(res)
      assert.is_string(err)
    end)

    it("fails with invalid signature", function()
      local tokens = { id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJrb25nLWNsaWVudC1wYXIiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiam9obiIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJEb2UiLCJlbWFpbCI6ImpvaG4uZG9lQGtvbmdocS5jb20ifQ.Kl8uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }
      local res, err = t:decode(tokens, { verify_claims = false })
      assert.is_nil(res)
      assert.is_string(err)
    end)
  end)

  describe("Standard claims verification - verify()", function()
    it("verifies claims and succeeds", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify(TOKENS_ENCODED, { leeway = 90000000000 })
      assert.is_nil(err)
      assert.same(TOKENS_DECODED, res)
    end)

    it("verifies claims and fails", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify(TOKENS_ENCODED)
      assert.equal("invalid exp claim (1704717395) was specified for id token", err)
      assert.is_nil(res)
    end)

    it("verifies aud claim and succeeds", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify(TOKENS_ENCODED, { leeway = 90000000000, clients = "kong-client-par" })
      assert.is_nil(err)
      assert.same(TOKENS_DECODED, res)
    end)

    it("verifies aud claim and fails", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify(TOKENS_ENCODED, { leeway = 90000000000, clients = "hacked-client" })
      assert.equal("invalid aud claim (kong-client-par) was specified for id token, hacked-client was expected", err)
      assert.is_nil(res)
    end)

    it("verifies existence of aud claim", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify({ id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJrb25nLWNsaWVudC1wYXIiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiam9obiIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJEb2UiLCJlbWFpbCI6ImpvaG4uZG9lQGtvbmdocS5jb20ifQ.Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }, {
        leeway = 90000000000,
        clients = "kong-client-par",
        verify_signature = false,
      })
      assert.equal("aud claim was not specified for id token", err)
      assert.is_nil(res)
    end)

    it("verifies azp claim when specified", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify({ id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJhenAiOiJoYWNrZWQtY2xpZW50Iiwibm9uY2UiOiJNaGhCeWZ4XzRyeG56LUNSMkJvb0lxcngiLCJzZXNzaW9uX3N0YXRlIjoiY2Y0NDk5NmQtNmFkMS00ZGNkLTgwYTctNjgwNWI3MDg5YTFmIiwiYXRfaGFzaCI6Ik5yUmdCOThwNGlILWUtLW1EU1NVRnciLCJhY3IiOiIxIiwic2lkIjoiY2Y0NDk5NmQtNmFkMS00ZGNkLTgwYTctNjgwNWI3MDg5YTFmIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiJKb2huIERvZSIsInByZWZlcnJlZF91c2VybmFtZSI6ImpvaG4iLCJnaXZlbl9uYW1lIjoiSm9obiIsImZhbWlseV9uYW1lIjoiRG9lIiwiZW1haWwiOiJqb2huLmRvZUBrb25naHEuY29tIn0.Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }, {
        leeway = 90000000000,
        clients = "kong-client-par",
        verify_signature = false,
      })
      assert.equal("invalid azp claim (hacked-client) was specified for id token", err)
      assert.is_nil(res)
    end)

    it("skips verifying azp claim when not specified", function()
      t = initialize_oic_and_token({})
      local res, err = t:verify({ id_token = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJuOERmVUR0VFRGY1FVN3I3aWM4TURoejJRUHZ6ajMtMy1hTE9JTjNoRjFrIn0.eyJleHAiOjE3MDQ3MTczOTUsImlhdCI6MTcwNDcxNjc5NSwiYXV0aF90aW1lIjoxNzA0NzE2Nzk1LCJqdGkiOiI5NGVhMTg5OS1lOGM1LTQxZGItODQzOS02OGExMTU5NDNkNTAiLCJpc3MiOiJodHRwOi8va2V5Y2xvYWsudGVzdDo4MDgwL3JlYWxtcy9kZW1vIiwiYXVkIjoia29uZy1jbGllbnQtcGFyIiwic3ViIjoiMjNlMWFmMTctYjFiZS00M2M5LWJlNGUtMDgyZWEzMWFiNTUzIiwidHlwIjoiSUQiLCJub25jZSI6Ik1oaEJ5ZnhfNHJ4bnotQ1IyQm9vSXFyeCIsInNlc3Npb25fc3RhdGUiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJhdF9oYXNoIjoiTnJSZ0I5OHA0aUgtZS0tbURTU1VGdyIsImFjciI6IjEiLCJzaWQiOiJjZjQ0OTk2ZC02YWQxLTRkY2QtODBhNy02ODA1YjcwODlhMWYiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6IkpvaG4gRG9lIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiam9obiIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJEb2UiLCJlbWFpbCI6ImpvaG4uZG9lQGtvbmdocS5jb20ifQ.Kl7uMD5Ojzqq5lCqSPToCdK2y_gZOAGeGFLFKDtWX-AELSmARfHCOsAHbK4QBkSNld6wj7zCYhmFIDmh5Dd7PtB_XMAHQQlrrLRu_xV5cH-n-tOo5OZZmACJCeG4AZqGAaiecMz3S85OH00Li7j0w8coyDfmwzfddJWvXgUbjOC1_Xxwa5Owu7P1qfVmokus6x_Q_oa0O5rSuPMAH2HgwDkfVp88oW32ZwHFcD0c3xZ75jGk664CvSCy9hfGLNA8RcRB8WygMvha7MSaUlPSv4LyCCorzlp3FfBybj2fD_K0rIMYGPzlG6Wbq5_xThuafM-1u8bSAiMHspD0AHwMcQ" }, {
        leeway = 90000000000,
        clients = "kong-client-par",
        verify_signature = false,
      })
      assert.is_nil(err)
      assert.is_table(res)
    end)
  end)

  describe("Proof of Possession #mtls mode - verify_client()", function()
    local options

    before_each(function()
      options = {
        proof_of_possession_mtls = "strict",
        client_cert_pem = CLIENT_CERT,
        verify_signature = false,
      }
    end)

    it("should return true when token is bound to the right certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(CERT_ACCESS_TOKEN)
      assert.is_true(res)
      assert.is_nil(err)
    end)

    it("should return err when token is not bound to any certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(NO_CERT_ACCESS_TOKEN)
      assert.is_nil(res)
      assert.equals(err, "x5t#S256 claim required but not found")
    end)

    it("should return err when token is bound to the wrong certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(WRONG_CERT_ACCESS_TOKEN)
      assert.is_nil(res)
      assert.equals(err, "the client certificate thumbprint does not match the x5t#S256 claim")
    end)

    it("does not enforce PoP with proof_of_possession_mtls = optional", function()
      options.proof_of_possession_mtls = "optional"
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(NO_CERT_ACCESS_TOKEN)
      assert.is_true(res)
      assert.is_nil(err)
    end)

    it("does not validate PoP with proof_of_possession_mtls = off", function()
      options.proof_of_possession_mtls = "off"
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(WRONG_CERT_ACCESS_TOKEN)
      assert.is_true(res)
      assert.is_nil(err)
    end)

    it("should return true when introspection data is bound to the right certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(CERT_INTROSPECTION_DATA)
      assert.is_true(res)
      assert.is_nil(err)
    end)

    it("should return err when introspection data is not bound to any certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(NO_CERT_INTROSPECTION_DATA)
      assert.is_nil(res)
      assert.equals(err, "x5t#S256 claim required but not found")
    end)

    it("should return err when introspection data is bound to the wrong certificate", function()
      t = initialize_oic_and_token(options)

      local res, err = t:verify_client(WRONG_CERT_INTROSPECTION_DATA)
      assert.is_nil(res)
      assert.equals(err, "the client certificate thumbprint does not match the x5t#S256 claim")
    end)
  end)
end)
