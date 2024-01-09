-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local xmlua     = require "xmlua"

local utils      = require "kong.tools.utils"
local xslt       = require "kong.plugins.saml.utils.xslt"
local xpath      = require "kong.plugins.saml.utils.xpath"
local xmlschema  = require "kong.plugins.saml.utils.xmlschema"
local timestamp  = require "kong.plugins.saml.utils.timestamp"
local saml       = require "kong.plugins.saml.saml"

local helpers    = require "spec.helpers"


local PLUGIN_NAME = "saml"


describe(PLUGIN_NAME .. " -> AuthnRequest creation", function()
    local REQUEST_ID = utils.uuid()
    local ISSUE_INSTANT = os.date("%Y-%m-%dT%H:%M:%S.000Z", ngx.time())
    local ISSUER = "https://example.com"
    local NAMEID_FORMAT = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"

    local DIGEST_ALGORITHM = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    local DIGEST_VALUE = "abc123"
    local SIGNATURE_ALGORITHM = "http://www.w3.org/2000/09/xmldsig#sha1"

    local SIGNATURE_VALUE = "def456"
    local SIGNATURE_CERTIFICATE = "ghi789"

    local make_authn_request = assert(xslt.new("make-authn-request"))
    local transform_parameters

    before_each(function()
        transform_parameters = xslt.make_parameter_table()
        transform_parameters["authn-request-id"] = REQUEST_ID
        transform_parameters["issue-instant"] = ISSUE_INSTANT
        transform_parameters["issuer"] = ISSUER
        transform_parameters["nameid-format"] = NAMEID_FORMAT
    end)

    it("creates correct response XML with no signing", function()

        local unsigned_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

        assert.equal(REQUEST_ID,    xpath.evaluate(unsigned_authn_request, "/samlp:AuthnRequest/@ID"))
        assert.equal(ISSUE_INSTANT, xpath.evaluate(unsigned_authn_request, "/samlp:AuthnRequest/@IssueInstant"))
        assert.equal(ISSUER,        xpath.evaluate(unsigned_authn_request, "/samlp:AuthnRequest/saml:Issuer/text()"))
        assert.equal(NAMEID_FORMAT, xpath.evaluate(unsigned_authn_request, "/samlp:AuthnRequest/samlp:NameIDPolicy/@Format"))

        assert.is_nil(xpath.evaluate(unsigned_authn_request, "/samlp:AuthnRequest/dsig:Signature"))
    end)

    it("creates correct intermediate response XML with digest", function()

        transform_parameters["digest-algorithm"] = DIGEST_ALGORITHM
        transform_parameters["digest-value"] = DIGEST_VALUE
        transform_parameters["signature-algorithm"] = SIGNATURE_ALGORITHM

        local digested_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

        assert.equal(DIGEST_ALGORITHM,    xpath.evaluate(digested_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:Reference/dsig:DigestMethod/@Algorithm"))
        assert.equal(DIGEST_VALUE,        xpath.evaluate(digested_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:Reference/dsig:DigestValue/text()"))
        assert.equal(SIGNATURE_ALGORITHM, xpath.evaluate(digested_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:SignatureMethod/@Algorithm"))

        assert.is_nil(xpath.evaluate(digested_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignatureValue"))
    end)

    it("creates correct response XML with digest and signature", function()

        transform_parameters["digest-algorithm"] = DIGEST_ALGORITHM
        transform_parameters["digest-value"] = DIGEST_VALUE
        transform_parameters["signature-algorithm"] = SIGNATURE_ALGORITHM

        transform_parameters["signature-value"] = SIGNATURE_VALUE
        transform_parameters["signature-certificate"] = SIGNATURE_CERTIFICATE

        local signed_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

        assert.equal(DIGEST_ALGORITHM,      xpath.evaluate(signed_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:Reference/dsig:DigestMethod/@Algorithm"))
        assert.equal(DIGEST_VALUE,          xpath.evaluate(signed_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:Reference/dsig:DigestValue/text()"))
        assert.equal(SIGNATURE_ALGORITHM,   xpath.evaluate(signed_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo/dsig:SignatureMethod/@Algorithm"))

        assert.equal(SIGNATURE_VALUE,       xpath.evaluate(signed_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignatureValue/text()"))
        assert.equal(SIGNATURE_CERTIFICATE, xpath.evaluate(signed_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:KeyInfo/dsig:X509Data/dsig:X509Certificate/text()"))
    end)
end)


local function slurp(filename)
  local f = assert(io.open(filename, "r"))
  local contents = f:read("*a")
  f:close()
  return contents
end


local function make_fixture_xml_path(name)
  return helpers.get_fixtures_path() .. "/saml/" .. name .. ".xml"
end


local function read_fixture_xml(name)
  return slurp(make_fixture_xml_path(name))
end


local function get_response_issue_timestamp(xml)
  local doc = xmlua.XML.parse(xml)
  return timestamp.parse(xpath.evaluate(doc, "/samlp:Response/@IssueInstant")):timestamp()
end


local function fake_time(timestamp, handler)
  local old_time = ngx.time
  ngx.time = function() -- luacheck: ignore
    return timestamp
  end
  local success, result = pcall(handler)
  ngx.time = old_time -- luacheck: ignore
  if not success then
    error(result)
  end
  return result
end


describe(PLUGIN_NAME .. " -> Assertion parsing", function()
    local IDP_CERTIFICATE = "MIIC8DCCAdigAwIBAgIQLc/POHQrTIVD4/5aCN/6gzANBgkqhkiG9w0BAQsFADA0MTIwMAYDVQQDEylNaWNyb3NvZnQgQXp1cmUgRmVkZXJhdGVkIFNTTyBDZXJ0aWZpY2F0ZTAeFw0yMjA5MjcyMDE1MzRaFw0yNTA5MjcyMDE1MzRaMDQxMjAwBgNVBAMTKU1pY3Jvc29mdCBBenVyZSBGZWRlcmF0ZWQgU1NPIENlcnRpZmljYXRlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv/P9hU7mjKFH9IxVGQt52p40Vj9lwMLBfrVc9uViCyCLILhGWz0kYbodpBtPkaYMrpJKSvaDD/Pop2Har+3gY1xBx3UAfLEZpb/ng+fM3AKQYRVH8rdfhtRMVx+mAus5oO/+7ca1ZhKeQpZtrSNBMSooBUFt6LygaotX7oJOFKBjL8vRjf0EeI0ismXuATtwE+wUDAe7qdsehjeZAD4Y1SLXulzS4ug3xRHPl8J9ZQL2D5FpzRXgxX9SUpJ/iwxAj+q3igLmXMUeusCe6ugGrZ4Iz0QNq3v+VhGEhiX6DZByMhBnb1IIhpDBTUTqfxUno8GI1vh/w8liRldEkISZdQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAiw8VNBh5s2EVbDpJekqEFT4oZdoDu3J4t1cHzst5Q3+XHWS0dndQh+R2xxVe072TKO/hn5ORlnw8Kp0Eq2g2YLpYvzt+khbr/xQqMFhwZnaCCnoNLdoW6A9d7E3yDCnIK/7byfZ3484B4KrnzZdGF9eTFPcMBzyCU223S4R4zVYnNVfyqmlCaYUcYd9OnAbYZrbD9SPNqPSK/vPhn8aLzpn9huvcxpVYUMQ0+Mq680bse9tRu6KbgSkaDNSe+xoE31OeWtR1Ko9Uhy6+Y7T1OQOi+BaNcIB1lXGivaudAVDh3mnKwSRw9vQ5y8m6kzFwEbkcl288gQ86BzUFaE36V"
    local ENCRYPTED_ASSERTION_KEY = "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"
    local NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO = "_a739b726-0f3a-46fc-b96e-b1cdcdd44c76"
    local ENCRYPTED_ASSERTION_IN_RESPONSE_TO = "_1e1bf2e5-a773-4b29-a0e7-4398610f56ad"
    local CONSUME_URL = "http://localhost:8000/saml/consume"

    it("correctly parses non-encrypted assertion", function()
        local xml = read_fixture_xml("aad-non-encrypted-assertion-success")
        local conf = {
          validate_assertion_signature = true,
          response_signature_algorithm = "SHA256",
          idp_certificate = IDP_CERTIFICATE,
        }
        fake_time(get_response_issue_timestamp(xml), function()
            local response, err = saml.parse_and_validate_login_response(xml, CONSUME_URL, NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert(response, err)
            assert.equal("hans.huebner@konghq.com", response.username)
            assert.equal("https://sts.windows.net/f177c1d6-50cf-49e0-818a-a0585cbafd8d/", response.issuer)
            assert.equal("_a12a7599-00db-447d-b931-a49e4bfc0100", response.session_idx)
        end)
    end)

    it("correctly parses encrypted assertion", function()
        local xml = read_fixture_xml("aad-encrypted-assertion-success")
        local conf = {
          validate_assertion_signature = true,
          response_signature_algorithm = "SHA256",
          idp_certificate = IDP_CERTIFICATE,
          response_encryption_key = ENCRYPTED_ASSERTION_KEY,
        }
        fake_time(get_response_issue_timestamp(xml), function()
            local response, err = saml.parse_and_validate_login_response(xml, CONSUME_URL, ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert(response, err)
            assert.equal("hans.huebner@konghq.com", response.username)
            assert.equal("https://sts.windows.net/f177c1d6-50cf-49e0-818a-a0585cbafd8d/", response.issuer)
            assert.equal("_5cdf9726-3f18-4412-aa7e-10bcf2f21900", response.session_idx)
        end)
    end)

    it("subject confirmation and conditions are correctly observed", function()
        local xml = read_fixture_xml("aad-non-encrypted-assertion-success")
        local conf = {
          validate_assertion_signature = true,
          response_signature_algorithm = "SHA256",
          idp_certificate = IDP_CERTIFICATE,
        }
        local issue_timestamp = get_response_issue_timestamp(xml)
        -- AAD makes the assertion valid 5 minutes before the issue
        -- time, supposedly to help clients who don't have their
        -- clocks synchronized well
        fake_time(issue_timestamp - 600, function()
            local response, err = saml.parse_and_validate_login_response(xml, CONSUME_URL, NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert.is_false(response)
            assert.match("not yet", err)
        end)
        fake_time(issue_timestamp + 3600, function()
            local response, err = saml.parse_and_validate_login_response(xml, CONSUME_URL, NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert.is_false(response)
            assert.match("expired", err)
        end)

        fake_time(get_response_issue_timestamp(xml), function()
            local response, err = saml.parse_and_validate_login_response(xml, "invalid", NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert.is_false(response)
            assert.match("subject recipient does not match", err)

            local response, err = saml.parse_and_validate_login_response(xml, CONSUME_URL, "invalid", conf)
            assert.is_false(response)
            assert.match("subject request ID does not match", err)

            local response, err = saml.parse_and_validate_login_response(xml, nil, NON_ENCRYPTED_ASSERTION_IN_RESPONSE_TO, conf)
            assert.is_truthy(response, err)
        end)
    end)
end)


describe(PLUGIN_NAME .. " -> XML schema validation", function()
    local schema = xmlschema.new("xml/xsd/saml-schema-protocol-2.0.xsd")

    it("validates the test SAML protocol files", function()

        for _, fixture_file in ipairs({ "aad-non-encrypted-assertion-success", "aad-encrypted-assertion-success" }) do
          local doc = xmlua.XML.parse(read_fixture_xml(fixture_file))
          assert.is_true(xmlschema.validate(schema, doc))
        end
    end)

    it("fails validation for non-conformant XML", function()
        local doc = xmlua.XML.parse("<invalid-document/>")
        local success, err = xmlschema.validate(schema, doc)
        assert.is_false(success)
        assert.is_equal("Element 'invalid-document': No matching global declaration available for the validation root.\n", err)
    end)
end)
