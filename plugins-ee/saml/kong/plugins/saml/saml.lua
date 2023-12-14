-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pkey                = require "resty.openssl.pkey"
local cipher              = require "resty.openssl.cipher"
local digest              = require "resty.openssl.digest"
local xmlua               = require "xmlua"

local utils               = require "kong.tools.utils"
local log                 = require "kong.plugins.saml.log"
local helpers             = require "kong.plugins.saml.utils.helpers"
local timestamp           = require "kong.plugins.saml.utils.timestamp"
local evp                 = require "kong.plugins.saml.utils.evp"
local canon               = require "kong.plugins.saml.utils.canon"
local xslt                = require "kong.plugins.saml.utils.xslt"
local xpath               = require "kong.plugins.saml.utils.xpath"
local xmlcatalog          = require "kong.plugins.saml.utils.xmlcatalog"
local xmlschema           = require "kong.plugins.saml.utils.xmlschema"

local base64_decode       = ngx.decode_base64


xmlcatalog.load("xml/xsd/saml-metadata.xml")


local saml_schema = xmlschema.new("xml/xsd/saml-schema-protocol-2.0.xsd")


local ENCRYPTION_ALGORITHM_FROM_XML = {
  ["http://www.w3.org/2001/04/xmlenc#aes128-cbc"] = "aes-128-cbc",
  ["http://www.w3.org/2001/04/xmlenc#aes256-cbc"] = "aes-256-cbc",
}


local DIGEST_ALGORITHM_TO_XML = {
  SHA256 = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
  SHA1 = "http://www.w3.org/2000/09/xmldsig#sha1",
}


local NAMEID_FORMAT_TO_XML = {
  EmailAddress = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
  Transient = "urn:oasis:names:tc:SAML:2.0:nameid-format:transient",
  Persistent = "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
}


local SUCCESS_STATUS_CODE = "urn:oasis:names:tc:SAML:2.0:status:Success"


local _M = {}


local function dump_document(doc) -- luacheck: ignore
  local f = assert(io.open("/tmp/document.xml", "w"))
  f:write(doc:to_xml())
  f:close()
end


local function evaluate_xpath_base64(element, path)
  local encoded = xpath.evaluate(element, path)
  if encoded == nil then
    local err = "could not find " .. path .. " in document"
    log.err(err)
    return nil, err
  end
  local decoded = ngx.decode_base64(encoded)
  if not decoded then
    local err = "could not base64 decode data at " .. path .. " (" .. encoded .. ")"
    log.err(err)
    return nil, err
  end

  return decoded
end


local function make_decrypter(xenc_algorithm)
  local openssl_algorithm = ENCRYPTION_ALGORITHM_FROM_XML[xenc_algorithm]
  if not openssl_algorithm then
    return nil, "unknown encryption algorithm " .. xenc_algorithm
  end

  return cipher.new(openssl_algorithm)
end


-- decrypt the SAML assertion
local function decrypt_assertion(encrypted_assertion, response_encryption_key)
  log("assertion is encrypted")

  local encrypted_session_key = evaluate_xpath_base64(encrypted_assertion, "xenc:EncryptedData/dsig:KeyInfo/xenc:EncryptedKey/xenc:CipherData/xenc:CipherValue/text()")

  local private_key, err = pkey.new(helpers.format_key(response_encryption_key))
  log("created key")
  if not private_key then
    return nil, "unable to create private key: " .. err
  end
  local session_key, err = private_key:decrypt(encrypted_session_key, pkey.PADDINGS.RSA_PKCS1_OAEP_PADDING)
  log("decrypted private key")
  if not session_key then
    return nil, "unable to decrypt cipher value: " .. err
  end

  local encrypted_data = evaluate_xpath_base64(encrypted_assertion, "xenc:EncryptedData/xenc:CipherData/xenc:CipherValue/text()")
  local encryption_algorithm = xpath.evaluate(encrypted_assertion, "xenc:EncryptedData/xenc:EncryptionMethod/@Algorithm")
  log("encryption_algorithm: " .. encryption_algorithm)

  local decrypter = make_decrypter(encryption_algorithm)
  local decrypted_data, err = decrypter:decrypt(
    session_key,
    string.sub(encrypted_data, 1, 16),
    string.sub(encrypted_data, 17)
  )
  if not decrypted_data then
    return nil, "unable to decrypt assertion: " .. err
  end

  log("decrypted assertion")

  return xmlua.XML.parse(decrypted_data)
end


-- verifies the reference data's digest value.
-- this is step one of core validation as defined by the XML Signature
-- spec: https://www.w3.org/TR/xmldsig-core/#sec-CoreValidation
local function verify_reference(element, signature_algorithm)
  log("verifying reference")
  local sig = xpath.evaluate(element, "dsig:Signature")
  local digest_value = xpath.evaluate(sig, "dsig:SignedInfo/dsig:Reference/dsig:DigestValue/text()")
  if not digest_value then
    return false, "no digest value found"
  end
  -- fixme: do we need to make a copy of the document before we unlink the signature?
  sig:unlink()
  local canon_xml = canon:c14n(element)
  local mdi, err = digest.new(signature_algorithm)
  if err then
    return false, "unsupported digest algorithm: " .. (signature_algorithm or "nil")
  end
  local md, err = mdi:final(canon_xml)
  if err then
    return false, "failed to generate digest: " .. err
  end
  local valid = md == base64_decode(digest_value)
  log("reference validation is ", valid)
  if not valid then
    return false, "digest does not match"
  end
  return true
end


-- retrieve X509 cert from XML response
local function get_cert(saml_response)
  local cert_data = xpath.evaluate(saml_response, "dsig:Signature/dsig:KeyInfo/dsig:X509Data/dsig:X509Certificate/text()")
  if not cert_data then
    return nil, nil, "no X509 Certificate supplied in authn response"
  end
  local cert, err = evp.Cert:new(helpers.format_cert(cert_data))
  if not cert then
    return nil, nil, "failed to load certificate: " .. err
  end
  return cert, cert_data
end


-- checks to see if the certificate passed in matches that specified in the configuration
local function cert_match(response_cert_data, idp_cert)
  return response_cert_data == string.gsub(idp_cert, "%s", "")
end


-- verifies the signature of the message
local function verify_signature(saml_response, signature_algorithm, idp_cert)
  log("validating signature")
  local signature_value = evaluate_xpath_base64(saml_response, "dsig:Signature/dsig:SignatureValue/text()")
  if not signature_value then
    return false, "no SignatureValue element in SAML response"
  end

  local signed_elem = xpath.evaluate(saml_response, "dsig:Signature/dsig:SignedInfo")
  local canon_signed = canon:c14n(signed_elem)
  local cert, cert_data, err = get_cert(saml_response)
  if err then
    return false, "failed to retrieve cert from authn response"
  end
  -- check that the Identity Provider's public key matches that we have stored locally
  -- this is prevent MITM attacks whereby the key has been replaced
  if not cert_match(cert_data, idp_cert) then
    log.err("expected key does not match that in the saml response")
    return false, "public key in saml response does not match"
  end

  local verifier, err = evp.RSAVerifier:new(cert)
  if err then
    return false, "failed to create RSAVerifier object: " .. err
  end

  local verified, err = verifier:verify(canon_signed, signature_value, signature_algorithm)
  if not verified then
    return false, "error verifying signature value: " .. err
  end

  return true
end


_M.parse_and_validate_login_response = function(xml_text, invoked_consume_url, request_id, config)
  local success, doc = pcall(xmlua.XML.parse, xml_text)
  if not success then
    return false, "unable to parse response XML: " .. doc
  end

  local valid, err = xmlschema.validate(saml_schema, doc)
  if not valid then
    return false, "SAML response failed schema validation: " .. err
  end

  local saml_response = xpath.evaluate(doc, "/samlp:Response")

  local status_code = xpath.evaluate(saml_response, "samlp:Status/samlp:StatusCode/@Value")
  if status_code ~= SUCCESS_STATUS_CODE then
    return false, "unsuccessful response status code return " .. status_code
  end

  local assertion
  local encrypted_assertion = xpath.evaluate(saml_response, "saml:EncryptedAssertion")
  if encrypted_assertion then
    local response_encryption_key = config.response_encryption_key
    if not response_encryption_key then
      return false, "encrypted assertion received from SAML provider, but no response_encryption_key configured"
    end

    local decrypted_assertion, err = decrypt_assertion(encrypted_assertion, response_encryption_key)
    if not decrypted_assertion then
      log.err(err)
      return false, err
    end
    log("assertion is decrypted")
    assertion = xpath.evaluate(decrypted_assertion, "/saml:Assertion")
  else
    assertion = xpath.evaluate(saml_response, "saml:Assertion")
  end

  if config.validate_assertion_signature then
    log("validating assertion element")
    local signature_algorithm = config.response_signature_algorithm
    local idp_cert = config.idp_certificate
    local sig_valid, err = verify_signature(assertion, signature_algorithm, idp_cert)
    if not sig_valid then
      log("signature invalid")
      return false, err
    end

    log("response assertion signature is valid")

    --there is a problem verifying the digest value with AzureAD when AttributeStatement exists
    --in the SAML response - ticket logged with MS Identity team #2209270030002595
    local ref_valid, err = verify_reference(assertion, signature_algorithm)
    if not ref_valid then
      log("reference invalid")
      return false, err
    end
    log("response assertion reference is valid")

    -- shouldn't need to verify both assertion and response
    -- e.g. AzureAD will sign assertion but not the response, but Keycloak signs both
    if not sig_valid and not ref_valid then
      --validate signed doc (if signed)
      log("validating signature for response root element")
      local sig_valid, err = verify_signature(saml_response, signature_algorithm, idp_cert)
      if not sig_valid then
        return false, err
      end
      log("response root element signature is valid")
      local ref_valid, err = verify_reference(saml_response, signature_algorithm)
      if not ref_valid then
        return false, err
      end
      log("response root element reference is valid")
    end
  end

  -- At this point, we know that the assertion indicated success and
  -- that its signature is valid.  Perform further checks to validate
  -- the assertion.

  -- Note that timestamps are compared only to second precision due to
  -- limitations of the luaty library.

  local now = ngx.time()

  local subject_confirmation_data = xpath.evaluate(assertion, "saml:Subject/saml:SubjectConfirmation[@Method='urn:oasis:names:tc:SAML:2.0:cm:bearer']/saml:SubjectConfirmationData")
  if subject_confirmation_data then
    local recipient = xpath.evaluate(subject_confirmation_data, "@Recipient")
    if recipient and invoked_consume_url and recipient ~= invoked_consume_url then
      -- The receipient matching is optional as we don't always know
      -- the URL with which we have been invoked, given that
      -- additional proxies may be sitting in front of us.
      log.notice("subject confirmation lists recipient URL as " .. recipient .. " but " .. invoked_consume_url .. " was invoked")
      return false, "subject recipient does not match"
    end

    local in_response_to = xpath.evaluate(subject_confirmation_data, "@InResponseTo")
    if in_response_to and in_response_to ~= request_id then
      log.notice("subject confirmation is for request " .. in_response_to .. " but was sent in response to request " .. request_id)
      return false, "subject request ID does not match"
    end

    local not_on_or_after = timestamp.parse(xpath.evaluate(subject_confirmation_data, "@NotOnOrAfter"))
    if not_on_or_after and now >= not_on_or_after:timestamp() then
      log.notice("subject confirmation has expired, possible replay attack?")
      return false, "subject confirmation has expired"
    end
  end

  local conditions = xpath.evaluate(assertion, "saml:Conditions")
  if conditions then
    local audience_restriction = xpath.evaluate(assertion, "saml:AudienceRestriction/saml:Audience/text()")
    if audience_restriction and audience_restriction ~= config.issuer then
      log.notice("received assertion for wrong audience, expected " .. (config.issuer or "<not set>") .. " got " .. audience_restriction)
      return false, "audience restriction mismatch"
    end

    local not_before = timestamp.parse(xpath.evaluate(conditions, "@NotBefore"))
    if not_before and now < not_before:timestamp() then
      log.notice("conditions not yet valid, possible replay attack?")
      return false, "conditions not yet valid " .. timestamp.format(not_before)
    end

    local not_on_or_after = timestamp.parse(xpath.evaluate(conditions, "@NotOnOrAfter"))
    if not_on_or_after and now >= not_on_or_after:timestamp() then
      log.notice("conditions have expired, possible replay attack?")
      return false, "conditions has expired at " .. timestamp.format(not_on_or_after)
    end
  end

  return {
    username = xpath.evaluate(assertion, "saml:Subject/saml:NameID/text()"),
    issuer = xpath.evaluate(assertion, "saml:Issuer/text()"),
    session_idx = xpath.evaluate(assertion, "saml:AuthnStatement/@SessionIndex") or utils.uuid(),
  }
end

local function make_signature(string, config)
  local key = config.request_signing_key
  local algorithm = config.request_signature_algorithm
  local signer, err = evp.RSASigner:new(helpers.format_key(key))
  if not signer then
    err = "failed to create a signing key object: " .. err
    log.err(err)
    return nil, err
  end

  local signature, err = signer:sign(string, algorithm)
  if not signature then
    err = "failed to sign data: " .. err
    log.err(err)
    return nil, err
  end

  return signature
end


local make_authn_request

local function ensure_stylesheet_loaded()
  if not make_authn_request then
    make_authn_request = assert(xslt.new("make-authn-request"))
  end
end


local function validate_authn_request(request)
  local valid, err = xmlschema.validate(saml_schema, request)
  if not valid then
    return nil, "could not validate SAML request that was generated: " .. err
  end
  return request
end


-- generates base64 encoded string to which can be used to send a SAML assertion to ADFS.
_M.build_login_request = function(request_id, config)
  log("build authn request")

  ensure_stylesheet_loaded()

  local transform_parameters = xslt.make_parameter_table()

  transform_parameters["authn-request-id"] = request_id
  transform_parameters["issue-instant"] = timestamp.format(timestamp.now())
  transform_parameters["issuer"] = config.issuer
  transform_parameters["nameid-format"] = NAMEID_FORMAT_TO_XML[config.nameid_format]

  log("create unsigned authn request")
  local unsigned_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

  local valid, err = validate_authn_request(unsigned_authn_request)
  if not valid then
    return nil, err
  end

  if not config.request_signing_key then
    return unsigned_authn_request:to_xml()
  end

  local digest_algorithm = config.request_digest_algorithm
  local mdi, err = digest.new(digest_algorithm)
  if err then
    return nil, "unsupported digest algorithm: " .. (digest_algorithm or "nil")
  end

  local md, err = mdi:final(canon:c14n(unsigned_authn_request:root()))
  if err then
    return nil, "failed to generate digest: " .. err
  end

  transform_parameters["digest-algorithm"] = DIGEST_ALGORITHM_TO_XML[digest_algorithm]
  transform_parameters["digest-value"] = ngx.encode_base64(md)
  transform_parameters["signature-algorithm"] = DIGEST_ALGORITHM_TO_XML[config.request_signature_algorithm]

  log("create authn request with digest")

  local digested_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

  local signed_info = canon:c14n(xpath.evaluate(digested_authn_request, "/samlp:AuthnRequest/dsig:Signature/dsig:SignedInfo"))

  transform_parameters["signature-value"] = ngx.encode_base64(make_signature(signed_info, config))
  transform_parameters["signature-certificate"] = ngx.encode_base64(config.request_signing_certificate)

  log("add signature to authn request with digest")
  local signed_authn_request = xslt.apply(make_authn_request, nil, transform_parameters)

  local valid, err = validate_authn_request(signed_authn_request)
  if not valid then
    return nil, err
  end

  return signed_authn_request:to_xml()
end


return _M
