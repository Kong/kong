local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_cast = ffi.cast
local band = bit.band
local new_tab = require("table.new")

local cucharpp = ffi_new("const unsigned char*[1]")
local ucharpp = ffi_new("unsigned char*[1]")
local charpp = ffi_new("char*[1]")


ffi.cdef [[
  typedef struct asn1_string_st ASN1_OCTET_STRING;
  typedef struct asn1_string_st ASN1_INTEGER;
  typedef struct asn1_string_st ASN1_ENUMERATED;
  typedef struct asn1_string_st ASN1_STRING;

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
]]


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
    return asn1_put_object(TAG.SEQUENCE, CLASS.UNIVERSAL, 1, val)
  end

  function encode(val, tag)
    if tag == nil then
      local typ = type(val)
      if typ == "string" then
        tag = TAG.OCTET_STRING
      elseif typ == "number" then
        tag = TAG.INTEGER
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
    assert(offset < #der)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_INTEGER(nil, cucharpp, len)
    if typ == nil then
      return nil, "failed to decode ASN1_INTEGER"
    end
    local ret = C.ASN1_INTEGER_get(typ)
    C.ASN1_INTEGER_free(typ)
    return tonumber(ret)
  end

  decoder[TAG.ENUMERATED] = function(der, offset, len)
    assert(offset < #der)
    cucharpp[0] = ffi_cast("const unsigned char *", der) + offset
    local typ = C.d2i_ASN1_ENUMERATED(nil, cucharpp, len)
    if typ == nil then
      return nil, "failed to decode ASN1_ENUMERATED"
    end
    local ret = C.ASN1_ENUMERATED_get(typ)
    C.ASN1_INTEGER_free(typ)
    return tonumber(ret)
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

30 0c -- Begin the LDAPMessage sequence
   02 01 03 -- The message ID (integer value 3)
   69 07 -- Begin the add response protocol op
      0a 01 00 -- success result code (enumerated value 0)
      04 00 -- No matched DN (0-byte octet string)
      04 00 -- No diagnostic message (0-byte octet string)
--]]
local function parse_ldap_result(der)
  local offset, err, _
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

  -- success result code
  local code
  offset, code, err = decode(der, obj.offset)
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
  local diagnostic_msg
  _, diagnostic_msg, err = decode(der, offset)
  if err then
    return nil, err
  end

  if type(diagnostic_msg) ~= "string" then
    return nil, "diagnostic message should be an octet string"
  end

  local res = {
    message_id = id,
    protocol_op = op,
    result_code = code,
    matched_dn = matched_dn,
    diagnostic_msg = diagnostic_msg,
  }

  return res
end

_M.parse_ldap_result = parse_ldap_result


return _M
