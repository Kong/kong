local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_cast = ffi.cast

local lpack = require "lua_pack"
local bpack = lpack.pack

local setmetatable = setmetatable
local tonumber = tonumber
local reverse = string.reverse
local concat = table.concat
local pairs = pairs
local type = type
local char = string.char
local bit = bit
local band = bit.band

local cucharpp = ffi_new("const unsigned char*[1]")
local charpp = ffi_new("char*[1]")

ffi.cdef [[
  typedef struct asn1_string_st ASN1_OCTET_STRING;
  typedef struct asn1_string_st ASN1_INTEGER;
  typedef struct asn1_string_st ASN1_ENUMERATED;

  ASN1_OCTET_STRING *ASN1_OCTET_STRING_new();
  ASN1_INTEGER *ASN1_INTEGER_new();

  long ASN1_INTEGER_get(const ASN1_INTEGER *a);
  long ASN1_ENUMERATED_get(const ASN1_ENUMERATED *a);

  const unsigned char *ASN1_STRING_get0_data(const ASN1_STRING *x);
  // openssl 1.1.0
  unsigned char *ASN1_STRING_data(ASN1_STRING *x);

  ASN1_OCTET_STRING *d2i_ASN1_OCTET_STRING(ASN1_OCTET_STRING **a, const unsigned char **ppin, long length);
  ASN1_INTEGER *d2i_ASN1_INTEGER(ASN1_INTEGER **a, const unsigned char **ppin, long length);
  ASN1_ENUMERATED *d2i_ASN1_ENUMERATED(ASN1_ENUMERATED **a, const unsigned char **ppin, long length);

  int i2d_ASN1_OCTET_STRING(const ASN1_OCTET_STRING *a, unsigned char **pp);
  int i2d_ASN1_INTEGER(const ASN1_INTEGER *a, unsigned char **pp);

  int ASN1_get_object(const unsigned char **pp, long *plength, int *ptag,
                      int *pclass, long omax);
  int ASN1_object_size(int constructed, int length, int tag);
]]

local ASN1_STRING_get0_data
if not pcall(function () return C.ASN1_STRING_get0_data end) then
  ASN1_STRING_get0_data = C.ASN1_STRING_data
else
  ASN1_STRING_get0_data = C.ASN1_STRING_get0_data
end

local _M = {}


_M.BERCLASS = {
  Universal = 0,
  Application = 64,
  ContextSpecific = 128,
  Private = 192
}


function _M.BERtoInt(class, constructed, num)
  local asn1_type = class + num

  if constructed == true then
    asn1_type = asn1_type + 32
  end

  return asn1_type
end


local asn1_get_object
do
  local lenp = ffi_new("long[1]")
  local tagp = ffi_new("int[1]")
  local classp = ffi_new("int[1]")
  local strpp = ffi_new("const unsigned char*[1]")

  function asn1_get_object(der, start, stop)
    start = start or 0
    stop = stop or #der
    if stop < start or stop > #der then
      return nil, "invalid offset"
    end

    local s_der = ffi_cast("const unsigned char *", der)
    strpp[0] = s_der + start

    local ret = C.ASN1_get_object(strpp, lenp, tagp, classp, stop - start + 1)
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
      hl = strpp[0] - s_der - start,
      cons = cons,
    }

    return obj
  end
end
_M.asn1_get_object = asn1_get_object


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
  local p = ffi_cast("const unsigned char *", der)
  cucharpp[0] = p
  local obj, err = asn1_get_object(der)
  if not obj then
    return err
  end

  -- message ID (integer)
  local asn1_int = C.d2i_ASN1_INTEGER(nil, cucharpp, #der)
  local id = C.ASN1_INTEGER_get(asn1_int)

  -- response protocol op
  obj = asn1_get_object(der, obj.offset + obj.len)
  if not obj then
    return err
  end
  local op = obj.tag

  -- success result code
  cucharpp[0] = p + obj.offset
  asn1_int = C.d2i_ASN1_ENUMERATED(nil, cucharpp, obj.len)
  local code = C.ASN1_ENUMERATED_get(asn1_int)

  -- matched DN (octet string)
  local asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local matched_dn = ASN1_STRING_get0_data(asn1_str)

  -- diagnostic message (octet string)
  asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local diagnostic_msg = ASN1_STRING_get0_data(asn1_str)

  C.ASN1_STRING_free(asn1_str)
  C.ASN1_INTEGER_free(asn1_int)

  local res = {
    message_id = tonumber(id),
    protocol_op = op,
    result_code = tonumber(code),
    matched_dn = ffi_string(matched_dn),
    diagnostic_msg = ffi_string(diagnostic_msg),
  }

  return res
end
_M.parse_ldap_result = parse_ldap_result


_M.ASN1Decoder = {
  new = function(self,o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:registerBaseDecoders()
    return o
  end,

  decode = function(self, encStr, pos)
    local obj, err = asn1_get_object(encStr, pos - 1)
    if not obj then
      return nil, err
    end

    local ret
    if self.decoder[obj.tag] then
      ret = self.decoder[obj.tag](self, encStr, obj.len, pos - 1)
    end
    
    return obj.offset + 1, ret
  end,

  registerBaseDecoders = function(self)
    self.decoder = {}
  
    -- Integer
    self.decoder[2] = function(self, encStr, elen, pos)
      local p = ffi_cast("const unsigned char *", encStr) + pos
      cucharpp[0] = p
      local typ = C.d2i_ASN1_INTEGER(nil, cucharpp, elen)
      local ret = C.ASN1_INTEGER_get(typ)
      C.ASN1_INTEGER_free(typ)
      return tonumber(ret)
    end

    -- Octet String
    self.decoder[4] = function(self, encStr, elen, pos)
      local p = ffi_cast("const unsigned char *", encStr) + pos
      cucharpp[0] = p
      local typ = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, elen)
      local ret = ASN1_STRING_get0_data(typ)
      C.ASN1_STRING_free(typ)
      return ffi_string(ret)
    end
  end
}


_M.ASN1Encoder = {
  new = function(self)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:registerBaseEncoders()
    return o
  end,

  encodeSeq = function(self, seqData)
    return bpack("XAA" , "30", self.encodeLength(#seqData), seqData)
  end,

  encode = function(self, val)
    local vtype = type(val)

    if self.encoder[vtype] then
      return self.encoder[vtype](self,val)
    end
  end,

  registerTagEncoders = function(self, tagEncoders)
    self:registerBaseEncoders()

    for k, v in pairs(tagEncoders) do
      self.encoder[k] = v
    end
  end,

  registerBaseEncoders = function(self)
    self.encoder = {}

    -- TODO(mayo) replace ldapop
    self.encoder["table"] = function(self, val)
      if val._ldaptype then
        local len

        if val[1] == nil or #val[1] == 0 then
          return bpack("XC", val._ldaptype, 0)
        end

        len = self.encodeLength(#val[1])
        return bpack("XAA", val._ldaptype, len, val[1])
      end
    end

    -- Integer encoder
    self.encoder["number"] = function(self, val)
      local typ = C.ASN1_INTEGER_new()
      C.ASN1_INTEGER_set(typ, val)
      charpp[0] = nil
      local ret = C.i2d_ASN1_INTEGER(typ, charpp)
      C.ASN1_INTEGER_free(typ)
      return ffi_string(charpp[0], ret)
    end

    -- Octet String encoder
    self.encoder["string"] = function(self, val)
      local typ = C.ASN1_OCTET_STRING_new()
      C.ASN1_STRING_set(typ, val, #val)
      charpp[0] = nil
      local ret = C.i2d_ASN1_OCTET_STRING(typ, charpp)
      C.ASN1_STRING_free(typ)
      return ffi_string(charpp[0], ret)
    end

  end,

  encodeLength = function(len)
    if len < 128 then
      return char(len)

    else
      local parts = {}

      while len > 0 do
        parts[#parts + 1] = char(len % 256)
        len = bit.rshift(len, 8)
      end

      return char(#parts + 0x80) .. reverse(concat(parts))
    end
  end
}


return _M
