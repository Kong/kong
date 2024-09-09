-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils   = require "kong.tools.utils"
local saml_schema = require "kong.plugins.saml.schema"
local validate = require("spec.helpers").validate_plugin_config_schema

local PLUGIN_NAME = "saml"

local idp_cert =
  "MIIC8DCCAdigAwIBAgIQLc/POHQrTIVD4/5aCN/6gzANBgkqhkiG9w0BAQsFADA0MTIwMAYDVQQD " ..
  "EylNaWNyb3NvZnQgQXp1cmUgRmVkZXJhdGVkIFNTTyBDZXJ0aWZpY2F0ZTAeFw0yMjA5MjcyMDE1 " ..
  "MzRaFw0yNTA5MjcyMDE1MzRaMDQxMjAwBgNVBAMTKU1pY3Jvc29mdCBBenVyZSBGZWRlcmF0ZWQg U" ..
  "1NPIENlcnRpZmljYXRlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv/P9hU7mjKFH " ..
  "9IxVGQt52p40Vj9lwMLBfrVc9uViCyCLILhGWz0kYbodpBtPkaYMrpJKSvaDD/Pop2Har+3gY1xB " ..
  "x3UAfLEZpb/ng+fM3AKQYRVH8rdfhtRMVx+mAus5oO/+7ca1ZhKeQpZtrSNBMSooBUFt6LygaotX " ..
  "7oJOFKBjL8vRjf0EeI0ismXuATtwE+wUDAe7qdsehjeZAD4Y1SLXulzS4ug3xRHPl8J9ZQL2D5Fp " ..
  "zRXgxX9SUpJ/iwxAj+q3igLmXMUeusCe6ugGrZ4Iz0QNq3v+VhGEhiX6DZByMhBnb1IIhpDBTUTq " ..
  "fxUno8GI1vh/w8liRldEkISZdQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAiw8VNBh5s2EVbDpJe " ..
  "kqEFT4oZdoDu3J4t1cHzst5Q3+XHWS0dndQh+R2xxVe072TKO/hn5ORlnw8Kp0Eq2g2YLpYvzt+k " ..
  "hbr/xQqMFhwZnaCCnoNLdoW6A9d7E3yDCnIK/7byfZ3484B4KrnzZdGF9eTFPcMBzyCU223S4R4z " ..
  "VYnNVfyqmlCaYUcYd9OnAbYZrbD9SPNqPSK/vPhn8aLzpn9huvcxpVYUMQ0+Mq680bse9tRu6Kbg " ..
  "SkaDNSe+xoE31OeWtR1Ko9Uhy6+Y7T1OQOi+BaNcIB1lXGivaudAVDh3mnKwSRw9vQ5y8m6kzFwE " ..
  "bkcl288gQ86BzUFaE36V"

local request_signing_key =
  "MIIJQgIBADANBgkqhkiG9w0BAQEFAASCCSwwggkoAgEAAoICAQDPKVS5dg9mFANa" ..
  "wbYIl8QmTV5vwZLZxGcg5FDNLRoDq+bsya9NMBsD8IxqJVpMxYHSpIylXI+T10j/" ..
  "+izCzCvaoRk17Bf5VYU9AXHAQ0BKOGSAlLmDRp4OpkLMsHzRuPbD/9AWXn+49B0z" ..
  "Ou6L8j8z0PuCT3VYECX6P/Bex9BTad31BWvWOeEkY23zq6VVzlZ9aetxurOVrUsA" ..
  "XQItOpet4ombNt6GBYe72+Ufh7KLaKGMxJfGDxN74T5cC77fii5WyzR+SHa+pWS7" ..
  "WEzoOpkZ/RJqiEcX8PfgJ3vS4mhBoCi3wjRyity6Bbexo5IdszsiT7YW8L/Dk+kB" ..
  "GFwVUZU5S+Jmv5cvisOmI2Ydr846BuckjLXiRe2ZZNcsZx/vt6eOld3JgmwPBvP8" ..
  "99pWbjBwzNBeactW0rdzNKsBNvU8G4+9LrxItHnTe98b8giHFiF0nq7nl9sRBdlW" ..
  "gSaJj8potHZn7LmdHr1EpL0qTcYXe/kTZlRdAaczn5SCZnxrYqqe2l+Z05DYjQZI" ..
  "5GEnzgepn/zbliUNp8gMrVHtEEc/x6nJX4LFbDebt51kJI1Scj5zyBsWmIhYV54V" ..
  "xCUwdoy2zlQwIoqAzvftrlx3fGS8q9rz8F54DJ/PWwSMaUH7kOHV22CFvhBKVq/k" ..
  "xLEwN0BeIyTriRwp3DQd4ucD6sI3vwIDAQABAoICAAp3OGA9B/UfvYJxw9w2Rc+r" ..
  "jyhOzrgkTuBGBWEANM6+E5oF0s6vx5JqevJUqPW08RfIfiro4xk628v2zxkX27Id" ..
  "YZrF4flgnS0VhbIkk6EyrSOKOYvZkijQtHignlJ+di6bt18FIidTydl2a9CNI5Or" ..
  "rKRXyeiLh4E97RfuUoBMTZoDaDNeVDLHuFyb+mvV00YqhwPSK1PV+X9VgF0mY/BO" ..
  "2aXXEhhFbw1W3bUhYJJ51D0g13J6Y4EZwlIMukIsoHLirDTvCafpaI5G0G491TgP" ..
  "ZXh7u9Lu6du2RiN2xbT/Ct+RttJmLbvsh9KFHkYhPmamDhLY0c9NiYyng7HROWkg" ..
  "cAs8hSkIuNbNwMG1K8apycFfT8IT96/rydMpTpY3DU7Izt5o8XMi61WwMY7jApxj" ..
  "CibDVO4QIU6xPhH0x3o4uylpOmIPBv3iPbbc8yb9STKH5EpE8HFM755qoO4A1Lkn" ..
  "ZcVuFhmUujEj8G+hHZZdUVfwicMlk/vQDJcflq7vu/j0u+5OuAXHhNI+u/GnDP16" ..
  "S3uRFZWAoEtTLGHnNdNEKeqR7A2YZX32PAvKE2ETy/XCvT/JcA14kYsv4Y5Ra5/o" ..
  "jh5UXKXo+496B5hLcXh+xofK7DHLivmAsdUoED9gixR7QY4lGh/3sCCnbDTD/6IT" ..
  "Eh+cUbs7gSR9uxm58S0hAoIBAQDf2yM769RynqNEQeOXaAa4qgcSLO/g1lghNfgB" ..
  "Fq4C3/FzSqqL3MMvR/7Z8k1HtxsIKLD47D4Tk6Z4vD2LtkV59PScZm/hV4h6Mlk7" ..
  "mOf7Vjc/ZLrRreoRmOX5x5rRK7oc27M5f5luCY5nwUpIzuWwe1osN/KL2mrn9Ufm" ..
  "Bc/ySTh3zra0ktk5XhCu3JTo5Se0amplc3Scgw+WVxeAuzPctsMLOHMICn1jafk4" ..
  "iUmRGIG8FrmtM3sLuQH9jh9vS2RtsOMLNYsUUK9IN7oYe3A/MjdypbZpAcx3rnEL" ..
  "90OLRFqZ7DfDutjNVdzK29dZRNnl/2QZGW3GJfkQ5uYptVafAoIBAQDs6IH4AX6I" ..
  "F1DXlSgH+EtquNyaCGz9+Kr6fSN8dJFhvl8HtaCswrVJYaQLTK1tdkQA+DrKpBYP" ..
  "GWAOdahVFdQzKVfwmNiZhsEmR0j3fgAD2p4R5e6bNWI6xDJ3wZs74nBi6JaqF7+h" ..
  "eNPBuLmKcUT6SObNEOF94qKwRrzLxdfZGEFw2xSiGCG9JyjBk6rzKEvttYp0DSNw" ..
  "X7Tj+JQKPpqyyvpXdWs7AwlFw7gEMj62N5HyDVZ8urnCJcBeTAzkvmiP8L8UDiL3" ..
  "haykpM27nFqj3Sd7oJeotQ6UzKCYbxRX2UN/Rt7+2gL5ov7BZIG3ETb46Vof32M4" ..
  "FfwFOdDk9SrhAoIBAF+gYSDL0WlVUzFpZCvdiGGCYJrnD2Hgrq0hPNxaL+OSfrZd" ..
  "gxVULR0ZiEjaNSEZmzaVC2SKpsn+HPMelrwEFRHQDl5xdAGzPt3UfEH1Q8QeRGOU" ..
  "SCoiPQdfZX6aQgxwvYRuZdV+KLDU7DxuWalYmM4XI6IYFEih+WE1ao1clkRN+w1T" ..
  "BMGGqbzT7hSErif/HEL54pGMDJh/dD0o3yVi0vjKKe+1IY6hzIaXUptQKlkNOv56" ..
  "Rr8yarHLSopiGBOXBUPGeHblXJBFF1umUpz6viyA6ybSm2WoGwxVPH18FyJ7BKkU" ..
  "O44lV1AACd2upAPCYcLaoowGTNqEhi0uNcxDZskCggEAL/6mnfTHipCWqyYnlv3B" ..
  "YZyT7Iy6b/VZxidl8ge3kEK+A9TS+Uz05ynlzvg4xk1IV53yYy083tA4OpWxhZNH" ..
  "ixncG/0LHIdFSBj2+lTHcgBvN5cKcN0uylMHGmXZqhckx5TxOQJYq0DMPZnL1PU/" ..
  "kSkFwROjaxpn9ShPhUTOhse4MkHf+zrCUwzE3/qnjl1ijITTyNEElfZ9shWhADZQ" ..
  "ptoiP2elUq45ya1t8UOwmr/FTHFRTTGTAncdcr0be5frnQWb4FdA1D57jFtq5pA1" ..
  "eK8MGaqeLuqHSrPt8RPH3khAuV9FPAI0yhgwXkObV9gf9+tme8CI3Erv5Ksi28+j" ..
  "YQKCAQEAxQ8fY7MeK5qik+B5y+6TDPDoz0cTQALPdbbVEm1H5Ossq5JsiFseI6H4" ..
  "ZWwfZkXiELE/nV0gPr/SsdYsS4MuPhcTGhgRa4Lrk9JE4Kptqq5Lwd8KGJFEvPix" ..
  "CwCmR6HpNDtbLIIwy2n98gdXL3gJNKoyj7GAPZz8ro14VpkP2RoPkD6a82pmyYy2" ..
  "mmLZMZOg4D8ZsUzOGm7TMSUIMil6SMI5vwsTbvJgl3yKaMTicHLmSB+/KRI4KnpU" ..
  "Bn3JEPXZPtbYzbh5FhHI4CFI9LPYVeNFRaxlwW3cEERG13GgoOVgpWMglGvE9Ipx" ..
  "qqIM9Se/5SlYo8yOUQAdJkK6OEgInA=="

local request_signing_certificate =
  "MIIFazCCA1OgAwIBAgIUMhWrXHebS8PZx1s+1olcdAaqTqgwDQYJKoZIhvcNAQEL" ..
  "BQAwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoM" ..
  "GEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDAeFw0yMjExMzAwNzIyMzFaFw0yMzEx" ..
  "MzAwNzIyMzFaMEUxCzAJBgNVBAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEw" ..
  "HwYDVQQKDBhJbnRlcm5ldCBXaWRnaXRzIFB0eSBMdGQwggIiMA0GCSqGSIb3DQEB" ..
  "AQUAA4ICDwAwggIKAoICAQDPKVS5dg9mFANawbYIl8QmTV5vwZLZxGcg5FDNLRoD" ..
  "q+bsya9NMBsD8IxqJVpMxYHSpIylXI+T10j/+izCzCvaoRk17Bf5VYU9AXHAQ0BK" ..
  "OGSAlLmDRp4OpkLMsHzRuPbD/9AWXn+49B0zOu6L8j8z0PuCT3VYECX6P/Bex9BT" ..
  "ad31BWvWOeEkY23zq6VVzlZ9aetxurOVrUsAXQItOpet4ombNt6GBYe72+Ufh7KL" ..
  "aKGMxJfGDxN74T5cC77fii5WyzR+SHa+pWS7WEzoOpkZ/RJqiEcX8PfgJ3vS4mhB" ..
  "oCi3wjRyity6Bbexo5IdszsiT7YW8L/Dk+kBGFwVUZU5S+Jmv5cvisOmI2Ydr846" ..
  "BuckjLXiRe2ZZNcsZx/vt6eOld3JgmwPBvP899pWbjBwzNBeactW0rdzNKsBNvU8" ..
  "G4+9LrxItHnTe98b8giHFiF0nq7nl9sRBdlWgSaJj8potHZn7LmdHr1EpL0qTcYX" ..
  "e/kTZlRdAaczn5SCZnxrYqqe2l+Z05DYjQZI5GEnzgepn/zbliUNp8gMrVHtEEc/" ..
  "x6nJX4LFbDebt51kJI1Scj5zyBsWmIhYV54VxCUwdoy2zlQwIoqAzvftrlx3fGS8" ..
  "q9rz8F54DJ/PWwSMaUH7kOHV22CFvhBKVq/kxLEwN0BeIyTriRwp3DQd4ucD6sI3" ..
  "vwIDAQABo1MwUTAdBgNVHQ4EFgQU2b6058hP/Qdgy+tcyizxWLoWeowwHwYDVR0j" ..
  "BBgwFoAU2b6058hP/Qdgy+tcyizxWLoWeowwDwYDVR0TAQH/BAUwAwEB/zANBgkq" ..
  "hkiG9w0BAQsFAAOCAgEAg0zoibbCZW1o13WMVbxIeXRTg5Cbff6XEqE/x27S3Xwu" ..
  "+Wi8rEJpYIO/VpcAdOZ4hapr1B6UTXG7Tq1H6Lk0AKLjiueU0WOiAwjX2/XNt510" ..
  "/3nLQcTcNr5sote4muvyH6EljAcu0c9Wj8E/CqyFvDBU7KnTOcrMPhrvUVb1nIM3" ..
  "BIwZlZUT/GXpByCnAb+gTZ+XijgPWk/V9OMOWniS+Wo7kMbtE+1dwlk8vkbXqg3f" ..
  "NSfyDqa+g9L14winIGobfARd8rn0fS3jrZbKAOLTp9vN7WZqQ54DnRDdc6XLGfn8" ..
  "4uob/fI4eyWff3Mkkmg4RcyZcT9B8TFGUHu/iVOGJLHlZT0X9kuyyXxTj07dRy3c" ..
  "lLxpbhMRENBomtNm3Fq28YEaBZ0AJyDJCAFTqPULy+pxtwdYKq3Gdpzvz1F+LwY8" ..
  "LydKYiDSJdPSut03KS6Eua+1jOb4cVyJzEsTlGqYIZOpWiqxXe10yIkhmA6B1oxx" ..
  "UtaNcPxJEkR42KUab34TlOze3z15A6OScwswSANbo1FVA4xX+cDPNTM76GR5X9QX" ..
  "v+V2bnVebLyY6MjmyXXfB5ReAzMZSat1KXRFYE6R3E698pwX5s9mgJTfymjuCux+" ..
  "n50TETWeeo61Dmt3mBzWZe0LtK4lvr+Rhoc0l/Iew9TYrs0UIeNcnqnoeVb725w="

local session_secret = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

describe(PLUGIN_NAME .. ": (schema)", function()

  setup(function()
    -- placeholder
  end)

  teardown(function()
    -- placeholder
  end)

  it("allows to configure plugin with required params", function()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = session_secret,
      }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not allow configure plugin without issuer url", function()
    local ok, err = validate({
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = session_secret,
      }, saml_schema)

      assert.is_falsy(ok)
      assert.same("required field missing" , err.config.issuer)
  end)

  it("redis cluster nodes accepts ips or hostnames", function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_redis_cluster_nodes = {
        {
          ip = "redis-node-1",
          port = 6379,
        },
        {
          ip = "redis-node-2",
          port = 6380,
        },
        {
          ip = "127.0.0.1",
          port = 6381,
        },
      },
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it('accepts old redis configuration', function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
      session_redis_host = "localhost",
      session_redis_port = 1234,
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it('accepts new redis configuration', function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
      redis = {
        connect_timeout = 100,
        send_timeout = 101,
        read_timeout = 102,
        cluster_nodes = {
          {
            ip = "redis-node-1",
            port = 6379,
          },
          {
            ip = "redis-node-2",
            port = 6380,
          },
          {
            ip = "127.0.0.1",
            port = 6381,
          },
        }
      },
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
      redis = {
        socket = "some_socket",
        prefix = "some_prefix_",
      },
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
      redis = {
        host = "localhost",
        port = 6379,
      },
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("redis cluster nodes rejects bad ports", function()
    local ok, err = validate({
      session_storage = 'redis',
      session_redis_cluster_nodes = {
        {
          ip = "redis-node-1",
          port = "6379",
        },
        {
          ip = "redis-node-2",
          port = 6380,
        },
      },
    }, saml_schema)

    assert.is_same({ port = "expected an integer" }, err.session_redis_cluster_nodes[1])
    assert.is_falsy(ok)
  end)

  it("allows empty redis config - takes defaults", function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects empty redis config - when explicit defaults set", function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
      session_secret = session_secret,
      session_storage = 'redis',
      redis = {
        host = ngx.null,
        port = ngx.null
      }
    }, saml_schema)

    assert.is_same("No redis config provided", err['@entity'][1])
    assert.is_falsy(ok)
  end)

  it("accepts anonymous config with required params", function()
    local uuid = utils.uuid()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = session_secret,
        anonymous = uuid,
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("idp certificate not required when validate_assertion_signature is 'false' ", function()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        session_secret = session_secret,
        validate_assertion_signature = false,
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("both request_signing_key and request_signing_certificate must be specified or neither", function()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        session_secret = session_secret,
        validate_assertion_signature = false,
        request_signing_certificate = request_signing_certificate,
    }, saml_schema)

    assert.is_falsy(ok)
    assert.same("'request_signing_key' is required when 'request_signing_certificate' is set" , err.config)

    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        session_secret = session_secret,
        validate_assertion_signature = false,
        request_signing_key = request_signing_key,
    }, saml_schema)

    assert.is_falsy(ok)
    assert.same("'request_signing_certificate' is required when 'request_signing_key' is set" , err.config)

    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        session_secret = session_secret,
        validate_assertion_signature = false,
        request_signing_key = request_signing_key,
        request_signing_certificate = request_signing_certificate,
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("session_secret must be present and conform to syntax requirements", function()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
      }, saml_schema)

    assert.is_falsy(ok)
    assert.same("required field missing" , err.config.session_secret)

    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = "tooshort",
      }, saml_schema)

    assert.is_falsy(ok)
    assert.same("length must be at least 32" , err.config.session_secret)

    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = "muchmuchmuchmuchmuchtootootootoolonglonglonglong",
      }, saml_schema)

    assert.is_falsy(ok)
    assert.same("length must be at most 32" , err.config.session_secret)

    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = "XXXXXXXXXXX*XXXXXXXXXXXXXXXXXXXX",
      }, saml_schema)

    assert.is_falsy(ok)
    assert.same("invalid value: XXXXXXXXXXX*XXXXXXXXXXXXXXXXXXXX" , err.config.session_secret)
  end)

  it("allows configuring plugin with removed fields", function()
    local entity, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
        session_secret = session_secret,

        session_cookie_renew = 900,
        session_cookie_maxsize = 1024,
        session_strategy = "foo",
        session_compressor = "none",
        session_auth_ttl = 900,
      }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.is_not_nil(entity.config)
  end)
end)
