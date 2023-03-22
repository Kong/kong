local asn1 = require "kong.plugins.ldap-auth.asn1"
local asn1_decode = asn1.decode
local asn1_parse_ldap_result = asn1.parse_ldap_result
local char = string.char
local gsub = string.gsub

local function hex_to_char(c)
  return char(tonumber(c, 16))
end

local function from_hex(str)
  return gsub(str, "%x%x", hex_to_char)
end

describe("Plugin: ldap-auth (decode)", function()
  it("normal integer", function()
    local der = from_hex("020102") -- 0x02 INTEGER
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret)
    assert.equals(3, offset)
  end)

  it("normal enumerated", function()
    local der = from_hex("0a0102") -- 0x0a ENUMERATED
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret)
    assert.equals(3, offset)
  end)

  it("normal octet string", function()
    local der = from_hex("040568656c6c6f") -- 0x04 OCTET STRING
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals("hello", ret)
    assert.equals(7, offset)
  end)

  it("invalid asn1", function()
    local der = from_hex("020302") -- too long length
    local _, _, err = asn1_decode(der)
    assert.same("der with error encoding: 128", err)
  end)

  it("abnormal integer", function()
    local der = from_hex("02020001") -- invalid padding
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_INTEGER", err)
  end)

  it("abnormal enumerated", function()
    local der = from_hex("0a020001") -- invalid padding
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_ENUMERATED", err)
  end)

  it("unknown tag", function()
    local der = from_hex("130568656c6c6f") --0x13 PrintableString
    local _, _, err = asn1_decode(der)
    assert.same("unknown tag type: 19", err)
  end)

  it("normal bind response -- success", function()
    --[[
      02 01 01    -- message id (integer value 1)
      61 07       -- response protocol op (bind response)
         0a 01 00 -- success result code (enumerated value 0)
         04 00    -- No matched DN (0-byte octet string)
         04 00    -- No diagnostic message (0-byte octet string)
    --]]
    local der = from_hex("02010161070a010004000400")
    local res, err = asn1_parse_ldap_result(der)
    assert.same(nil, err)
    assert.equals(1, res.message_id)
    assert.equals(1, res.protocol_op)
    assert.equals(0, res.result_code)
  end)

  it("normal bind response -- fail", function()
    --[[
      02 01 01    -- message id (integer value 1)
      61 07       -- response protocol op (bind response)
         0a 01 31 -- fail result code (enumerated value 49)
         04 00    -- No matched DN (0-byte octet string)
         04 00    -- No diagnostic message (0-byte octet string)
    --]]
    local der = from_hex("02010161070a013104000400")
    local res, err = asn1_parse_ldap_result(der)
    assert.same(nil, err)
    assert.equals(1, res.message_id)
    assert.equals(1, res.protocol_op)
    assert.equals(49, res.result_code)
  end)

  it("abnormal bind response -- id isn't an integer", function()
    --[[
      04 01 01    -- message id (octet string)
    --]]
    local der = from_hex("04010161070a010004000400")
    local _, err = asn1_parse_ldap_result(der)
    assert.same("message id should be an integer value", err)
  end)

  it("abnormal bind response -- invalid response protocol op", function()
    --[[
      61 09       -- response protocol op (too long length)
    --]]
    local der = from_hex("02010161090a010004000400")
    local _, err = asn1_parse_ldap_result(der)
    assert.same("der with error encoding: 160", err)
  end)

  it("abnormal bind response -- result code isn't a number", function()
    --[[
         04 01 00 -- result code (octet string)
    --]]
    local der = from_hex("020101610704010004000400")
    local _, err = asn1_parse_ldap_result(der)
    assert.same("result code should be an enumerated value", err)
  end)

  it("abnormal bind response -- matched dn isn't a string", function()
    --[[
         02 01 01 -- matched DN (integer)
    --]]
    local der = from_hex("02010161080a01000201010400")
    local _, err = asn1_parse_ldap_result(der)
    assert.same("matched dn should be an octet string", err)
  end)

  it("abnormal bind response -- diagnostic message isn't a string", function()
    --[[
         02 01 01 -- diagnostic message (integer)
    --]]
    local der = from_hex("02010161080a01000400020101")
    local _, err = asn1_parse_ldap_result(der)
    assert.same("diagnostic message should be an octet string", err)
  end)

end)

