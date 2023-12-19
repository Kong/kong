-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_cast = ffi.cast
local band = bit.band
local base = require "resty.core.base"
local new_tab = base.new_tab
local lpack = require "lua_pack"
local bpack = lpack.pack
local insert = table.insert
local byte = string.byte

local cucharpp = ffi_new("const unsigned char*[1]")
local ucharpp = ffi_new("unsigned char*[1]")
local charpp = ffi_new("char*[1]")


local BN_ULONG
if ffi.abi('64bit') then
  BN_ULONG = 'unsigned long long'
else -- 32bit
  BN_ULONG = 'unsigned int'
end

ffi.cdef( [[
  typedef struct asn1_string_st ASN1_OCTET_STRING;
  typedef struct asn1_string_st ASN1_INTEGER;
  typedef struct asn1_string_st ASN1_ENUMERATED;
  typedef struct asn1_string_st ASN1_STRING;
  typedef struct bignum_st BIGNUM;

  ASN1_OCTET_STRING *ASN1_OCTET_STRING_new();
  ASN1_INTEGER *ASN1_INTEGER_new();
  ASN1_ENUMERATED *ASN1_ENUMERATED_new();

  void ASN1_INTEGER_free(ASN1_INTEGER *a);
  void ASN1_STRING_free(ASN1_STRING *a);

  long ASN1_INTEGER_get(const ASN1_INTEGER *a);
  long ASN1_ENUMERATED_get(const ASN1_ENUMERATED *a);

  int ASN1_INTEGER_set(ASN1_INTEGER *a, long v);
  int ASN1_ENUMERATED_set(ASN1_ENUMERATED *a, long v);
  int ASN1_STRING_set(ASN1_STRING *str, const void *data, int len);

  const unsigned char *ASN1_STRING_get0_data(const ASN1_STRING *x);
  // openssl 1.1.0
  unsigned char *ASN1_STRING_data(ASN1_STRING *x);

  ASN1_OCTET_STRING *d2i_ASN1_OCTET_STRING(ASN1_OCTET_STRING **a, const unsigned char **ppin, long length);
  ASN1_INTEGER *d2i_ASN1_INTEGER(ASN1_INTEGER **a, const unsigned char **ppin, long length);
  ASN1_ENUMERATED *d2i_ASN1_ENUMERATED(ASN1_ENUMERATED **a, const unsigned char **ppin, long length);

  int i2d_ASN1_OCTET_STRING(const ASN1_OCTET_STRING *a, unsigned char **pp);
  int i2d_ASN1_INTEGER(const ASN1_INTEGER *a, unsigned char **pp);
  int i2d_ASN1_ENUMERATED(const ASN1_ENUMERATED *a, unsigned char **pp);

  int ASN1_get_object(const unsigned char **pp, long *plength, int *ptag,
                      int *pclass, long omax);
  int ASN1_object_size(int constructed, int length, int tag);

  void ASN1_put_object(unsigned char **pp, int constructed, int length,
                      int tag, int xclass);
  BIGNUM *BN_bin2bn(const unsigned char *s, int len, BIGNUM *ret);
  unsigned ]] .. BN_ULONG .. [[ BN_get_word(BIGNUM *a);
  void BN_free(BIGNUM *a);
]])


local ASN1_STRING_get0_data
if not pcall(function() return C.ASN1_STRING_get0_data end) then
  ASN1_STRING_get0_data = C.ASN1_STRING_data
else
  ASN1_STRING_get0_data = C.ASN1_STRING_get0_data
end


local _M = new_tab(0, 7)


local CLASS = {
  UNIVERSAL = 0x00,
  APPLICATION = 0x40,
  CONTEXT_SPECIFIC = 0x80,
  PRIVATE = 0xc0
}
_M.CLASS = CLASS


local TAG = {
  -- ASN.1 tag values
  EOC = 0,
  BOOLEAN = 1,
  INTEGER = 2,
  OCTET_STRING = 4,
  NULL = 5,
  ENUMERATED = 10,
  SEQUENCE = 16,
  SET = 17,
}
_M.TAG = TAG


local asn1_get_object
do
  local lenp = ffi_new("long[1]")
  local tagp = ffi_new("int[1]")
  local classp = ffi_new("int[1]")
  local strpp = ffi_new("const unsigned char*[1]")

  function asn1_get_object(der, start, stop)
    start = start or 0
    stop = stop or #der
    if stop <= start or stop > #der then
      return nil, "invalid offset"
    end

    local s_der = ffi_cast("const unsigned char *", der)
    strpp[0] = s_der + start

    local ret = C.ASN1_get_object(strpp, lenp, tagp, classp, stop - start)
    if band(ret, 0x80) == 0x80 then
      return nil, "der with error encoding: " .. ret
    end

    local cons = false
    if band(ret, 0x20) == 0x20 then
      cons = true
    end

    local obj = {
      tag = tagp[0],
      class = classp[0],
      len = tonumber(lenp[0]),
      offset = strpp[0] - s_der,
      hl = strpp[0] - s_der - start, -- header length
      cons = cons,
    }

    return obj
  end
end
_M.get_object = asn1_get_object


local function asn1_put_object(tag, class, constructed, data, len)
  len = type(data) == "string" and #data or len or 0
  if len <= 0 then
    return nil, "invalid object length"
  end

  local outbuf = ffi_new("unsigned char[?]", len)
  ucharpp[0] = outbuf

  C.ASN1_put_object(ucharpp, constructed, len, tag, class)
  if not data then
    return ffi_string(outbuf)
  end
  return ffi_string(outbuf) .. data
end
_M.put_object = asn1_put_object


local encode
do
  local encoder = new_tab(0, 3)

  -- Integer
  encoder[TAG.INTEGER] = function(val)
    local typ = C.ASN1_INTEGER_new()
    C.ASN1_INTEGER_set(typ, val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_INTEGER(typ, charpp)
    C.ASN1_INTEGER_free(typ)
    return ffi_string(charpp[0], ret)
  end

  -- Octet String
  encoder[TAG.OCTET_STRING] = function(val)
    local typ = C.ASN1_OCTET_STRING_new()
    C.ASN1_STRING_set(typ, val, #val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_OCTET_STRING(typ, charpp)
    C.ASN1_STRING_free(typ)
    return ffi_string(charpp[0], ret)
  end

  encoder[TAG.ENUMERATED] = function(val)
    local typ = C.ASN1_ENUMERATED_new()
    C.ASN1_ENUMERATED_set(typ, val)
    charpp[0] = nil
    local ret = C.i2d_ASN1_ENUMERATED(typ, charpp)
    C.ASN1_INTEGER_free(typ)
    return ffi_string(charpp[0], ret)
  end

  encoder[TAG.SEQUENCE] = function(val)
    if val == "" then
      return bpack("X", "30 00")
    end
    return asn1_put_object(TAG.SEQUENCE, CLASS.UNIVERSAL, 1, val)
  end

  encoder[TAG.BOOLEAN] = function(val)
    if val then
      return bpack('X','01 01 FF')
    else
      return bpack('X', '01 01 00')
    end
  end

  function encode(val, tag)
    if tag == nil then
      local typ = type(val)
      if typ == "string" then
        tag = TAG.OCTET_STRING
      elseif typ == "number" then
        tag = TAG.INTEGER
      elseif typ == "boolean" then
        tag = TAG.BOOLEAN
      end
    end

    if encoder[tag] then
      return encoder[tag](val)
    end
  end
end
_M.encode = encode


local decode
do
  local decoder = new_tab(0, 3)

  -- some implemetations like VDS are not strictly comply to
  -- the smallest length integer encoding of BER. That is,
  -- there may be redundant leading padding.
  -- https://konghq.atlassian.net/browse/FTI-5605
  -- So that we don't use d2i_ASN1_INTEGER here.
  local function decode_integer(der, offset, name)
    assert(offset < #der)

    local len_byte1 = byte(der, offset + 2)
    if len_byte1 == 0x80 then
      return nil, name .. " can't use indefinite form"
    elseif band(len_byte1, 0x80) == 0x80 then
      return nil, "don't support long form for " .. name
    end

    if band(byte(der, offset + 3), 0x80) == 0x80 then
      return nil, name .. " is negative"
    end

    cucharpp[0] = ffi_cast("const unsigned char *", der:sub(offset + 3))
    local bn = C.BN_bin2bn(cucharpp[0], len_byte1, nil)
    if bn == nil then
      return nil, "failed to decode " .. name
    end

    local ret = tonumber(C.BN_get_word(bn))
    C.BN_free(bn)
    return ret
  end

  decoder[TAG.OCTET_STRING] = function(der, offset, len)
    assert(offset < #der)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, len)
    if typ == nil then
      return nil, "failed to decode ASN1_OCTET_STRING"
    end
    local ret = ffi_string(ASN1_STRING_get0_data(typ))
    C.ASN1_STRING_free(typ)
    return ret
  end

  decoder[TAG.INTEGER] = function(der, offset, len)
    return decode_integer(der, offset, "ASN1_INTEGER")
  end

  decoder[TAG.ENUMERATED] = function(der, offset, len)
    return decode_integer(der, offset, "ASN1_ENUMERATED")
  end

  decoder[TAG.SET] = function(der, offset, len)
    local obj, err = asn1_get_object(der, offset)
    if err then
      return nil, "failed to decode ASN1_SET: " .. err
    end

    offset = obj.offset
    local last = offset + obj.len

    local set = {}
    while (offset < last) do
      local ret
      offset, ret, err = decode(der, offset)
      if err then
        return nil, "failed to decode ASN1_SET: " .. err
      end
      insert(set, ret)
    end

    return set
  end

  decoder[TAG.SEQUENCE] = function(der, offset, len)
    local obj, err = asn1_get_object(der, offset)
    if not obj then
      return nil, "failed to decode ASN1_SEQUENCE: " .. err
    end

    offset = obj.offset
    local last = offset + obj.len

    local seq = {}
    while (offset < last) do
      local ret
      offset, ret, err = decode(der, offset)
      if err then
        return nil, "failed to decode ASN1_SEQUENCE: " .. err
      end
      insert(seq, ret)
    end
    return seq
  end

  -- offset starts from 0
  function decode(der, offset)
    offset = offset or 0
    local obj, err = asn1_get_object(der, offset)
    if not obj then
      return nil, nil, err
    end

    local ret
    if decoder[obj.tag] then
      ret, err = decoder[obj.tag](der, offset, obj.hl + obj.len)
    else
      return nil, nil, "unknown tag type: " .. obj.tag
    end
    return obj.offset + obj.len, ret, err
  end
end
_M.decode = decode


--[[
Encoded LDAP Result: https://ldap.com/ldapv3-wire-protocol-reference-ldap-result/

   02 01 03 -- The message ID (integer value 3)
   69 07 -- Begin the add response protocol op
      0a 01 00 -- success result code (enumerated value 0)
--]]
local function parse_ldap_op(der)
  local offset, err
  -- message ID (integer)
  local id
  offset, id, err = decode(der)
  if err then
    return nil, err
  end

  if type(id) ~= "number" then
    return nil, "message id should be an integer value"
  end

  -- response protocol op
  local obj
  obj, err = asn1_get_object(der, offset)
  if err then
    return nil, err
  end
  local op = obj.tag

  local res = {
    message_id = id,
    protocol_op = op,
    offset = obj.offset,
  }

  return res
end
_M.parse_ldap_op = parse_ldap_op


--[[
Encoded LDAP Result: https://ldap.com/ldapv3-wire-protocol-reference-ldap-result/

      0a 01 00 -- success result code (enumerated value 0)
      04 00 -- No matched DN (0-byte octet string)
      04 00 -- No diagnostic message (0-byte octet string)
--]]
local function parse_ldap_result(der, offset)
  -- result code
  local code, err
  offset, code, err = decode(der, offset)
  if err then
    return nil, err
  end

  if type(code) ~= "number" then
    return nil, "result code should be an enumerated value"
  end

  -- matched DN (octet string)
  local matched_dn
  offset, matched_dn, err = decode(der, offset)
  if err then
    return nil, err
  end

  if type(matched_dn) ~= "string" then
    return nil, "matched dn should be an octet string"
  end

  -- diagnostic message (octet string)
  local _, diagnostic_msg
  _, diagnostic_msg, err = decode(der, offset)
  if err then
    return nil, err
  end

  if type(diagnostic_msg) ~= "string" then
    return nil, "diagnostic message should be an octet string"
  end

  local res = {
    result_code = code,
    matched_dn = matched_dn,
    diagnostic_msg = diagnostic_msg,
  }

  return res
end
_M.parse_ldap_result = parse_ldap_result

return _M
