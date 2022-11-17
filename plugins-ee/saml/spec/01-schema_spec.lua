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

local idp_cert = "MIIC8DCCAdigAwIBAgIQLc/POHQrTIVD4/5aCN/6gzANBgkqhkiG9w0BAQsFADA0MTIwMAYDVQQD " ..
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
      }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not allow configure plugin without issuer url", function()
    local ok, err = validate({
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
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

  it("redis cluster nodes rejects bad ports", function()
    local ok, err = validate({
      issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
      assertion_consumer_path = "/consumer",
      idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
      idp_certificate = idp_cert,
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

    assert.is_same({ port = "expected an integer" }, err.config.session_redis_cluster_nodes[1])
    assert.is_falsy(ok)
  end)

  it("accepts anonymous config with required params", function()
    local uuid = utils.uuid()
    local ok, err = validate({
        issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
        assertion_consumer_path = "/consumer",
        idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
        idp_certificate = idp_cert,
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
        validate_assertion_signature = false,
    }, saml_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
end)
