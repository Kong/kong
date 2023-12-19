-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local asn1 = require "kong.plugins.ldap-auth-advanced.asn1"
local asn1_decode = asn1.decode
local asn1_parse_ldap_op = asn1.parse_ldap_op
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

  it("normal set", function()
    local der = from_hex("110a020102040568656c6c6f") -- 0x11 SET
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret[1])
    assert.equals("hello", ret[2])
    assert.equals(12, offset)
  end)

  it("normal sequence", function()
    local der = from_hex("100a020102040568656c6c6f") -- 0x10 SEQUENCE
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret[1])
    assert.equals("hello", ret[2])
    assert.equals(12, offset)
  end)

  it("positive integer/enumerated with redundant leading padding -- short form", function()
    for _, tag in ipairs({"02", "0a"}) do
      local der = from_hex(tag .. "020001")
      local offset, ret, err = asn1_decode(der)
      assert.same(nil, err)
      assert.equals(1, ret)
      assert.equals(4, offset)
    end
  end)

  it("doesn't support integer/enumerated with long form", function()
    for name, tag in pairs({ ASN1_INTEGER = "02", ASN1_ENUMERATED = "0a" }) do
      local der = from_hex(tag .. "81020001")  -- value length 2
      local _, _, err = asn1_decode(der)
      assert.same("don't support long form for " .. name, err)
    end
  end)

  it("negative integer/enumerated should report error", function()
    for name, tag in pairs({ ASN1_INTEGER = "02", ASN1_ENUMERATED = "0a" }) do
      local der = from_hex(tag .. "01ff")
      local _, _, err = asn1_decode(der)
      assert.same(name .. " is negative", err)
    end
  end)

  it("invalid asn1", function()
    local der = from_hex("020302") -- too long length
    local _, _, err = asn1_decode(der)
    assert.same("der with error encoding: 128", err)
  end)

  it("unknown tag", function()
    local der = from_hex("130568656c6c6f") --0x13 PrintableString
    local _, _, err = asn1_decode(der)
    assert.same("unknown tag type: 19", err)
  end)

  it("abnormal set -- external error", function()
    local der = from_hex("110f020102040568656c6c6f") -- too long length
    local _, _, err = asn1_decode(der)
    assert.same("der with error encoding: 128", err)
  end)

  it("abnormal set -- internal element error", function()
    local der = from_hex("110a0201ff040568656c6c6f") -- internal integer is negative
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_SET: ASN1_INTEGER is negative", err)
  end)

  it("abnormal sequence -- external error", function()
    local der = from_hex("100f020102040568656c6c6f") -- too long length
    local _, _, err = asn1_decode(der)
    assert.same("der with error encoding: 128", err)
  end)

  it("abnormal sequence -- internal element error", function()
    local der = from_hex("100b02810101040568656c6c6f") -- internal integer is long form
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_SEQUENCE: don't support long form for ASN1_INTEGER", err)
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
    local res, err = asn1_parse_ldap_op(der)
    assert.same(nil, err)
    assert.equals(1, res.message_id)
    assert.equals(1, res.protocol_op)
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
    local res, err = asn1_parse_ldap_op(der)
    assert.same(nil, err)
    assert.equals(1, res.message_id)
    assert.equals(1, res.protocol_op)
  end)

  it("normal bind response -- success result code", function()
    --[[
      02 01 01    -- message id (integer value 1)
      61 07       -- response protocol op (bind response)
         0a 01 00 -- success result code (enumerated value 0)
         04 00    -- No matched DN (0-byte octet string)
         04 00    -- No diagnostic message (0-byte octet string)
    --]]
    local der = from_hex("02010161070a010004000400")
    local res, err = asn1_parse_ldap_result(der, 5)
    assert.same(nil, err)
    assert.equals(0, res.result_code)
    assert.equals("", res.matched_dn)
    assert.equals("", res.diagnostic_msg)
  end)

  it("normal bind response -- fail result code", function()
    --[[
      02 01 01    -- message id (integer value 1)
      61 0b       -- response protocol op (bind response)
         0a 01 31 -- success result code (enumerated value 0)
         04 02 6f 6b -- No matched DN (2-byte octet string: "ok")
         04 02 6f 6b -- No diagnostic message (2-byte octet string: "ok")
    --]]
    local der = from_hex("020101610b0a013104026f6b04026f6b")
    local res, err = asn1_parse_ldap_result(der, 5)
    assert.same(nil, err)
    assert.equals(49, res.result_code)
    assert.equals("ok", res.matched_dn)
    assert.equals("ok", res.diagnostic_msg)
  end)

  it("abnormal bind response -- id isn't an integer", function()
    --[[
      04 01 01    -- message id (octet string)
    --]]
    local der = from_hex("04010161070a010004000400")
    local _, err = asn1_parse_ldap_op(der)
    assert.same("message id should be an integer value", err)
  end)

  it("abnormal bind response -- invalid response protocol op", function()
    --[[
      61 09       -- response protocol op (too long length)
    --]]
    local der = from_hex("02010161090a010004000400")
    local _, err = asn1_parse_ldap_op(der)
    assert.same("der with error encoding: 160", err)
  end)

  it("abnormal bind response -- result code isn't a number", function()
    --[[
         04 01 00 -- result code (octet string)
    --]]
    local der = from_hex("020101610704010004000400")
    local _, err = asn1_parse_ldap_result(der, 5)
    assert.same("result code should be an enumerated value", err)
  end)

  it("abnormal bind response -- matched dn isn't a string", function()
    --[[
         02 01 01 -- matched DN (integer)
    --]]
    local der = from_hex("02010161080a01000201010400")
    local _, err = asn1_parse_ldap_result(der, 5)
    assert.same("matched dn should be an octet string", err)
  end)

  it("abnormal bind response -- diagnostic message isn't a string", function()
    --[[
         02 01 01 -- diagnostic message (integer)
    --]]
    local der = from_hex("02010161080a01000400020101")
    local _, err = asn1_parse_ldap_result(der, 5)
    assert.same("diagnostic message should be an octet string", err)
  end)

end)

