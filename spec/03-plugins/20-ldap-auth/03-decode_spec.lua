local asn1 = require "kong.plugins.ldap-auth.asn1"
local asn1_decode = asn1.decode
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
    local der = from_hex("020102")
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret)
    assert.equals(3, offset)
  end)

  it("normal enumerated", function()
    local der = from_hex("0a0102")
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals(2, ret)
    assert.equals(3, offset)
  end)

  it("normal octet string", function()
    local der = from_hex("040568656c6c6f")
    local offset, ret, err = asn1_decode(der)
    assert.same(nil, err)
    assert.equals("hello", ret)
    assert.equals(7, offset)
  end)

  it("invalid asn1", function()
    local der = from_hex("020302")
    local _, _, err = asn1_decode(der)
    assert.same("der with error encoding: 128", err)
  end)

  it("abnormal integer", function()
    local der = from_hex("02020001")
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_INTEGER", err)
  end)

  it("abnormal enumerated", function()
    local der = from_hex("0a020001")
    local _, _, err = asn1_decode(der)
    assert.same("failed to decode ASN1_ENUMERATED", err)
  end)

  it("unknown tag", function()
    local der = from_hex("130568656c6c6f")
    local _, _, err = asn1_decode(der)
    assert.same("unknown tag type: 19", err)
  end)

end)

