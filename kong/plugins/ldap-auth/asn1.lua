local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_cast = ffi.cast
local assert = assert
local fmt = string.format

local lpack = require "lua_pack"
local bpack = lpack.pack
local bunpack = lpack.unpack

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
  ASN1_STRING *ASN1_OCTET_STRING_new();

  long ASN1_ENUMERATED_get(const ASN1_ENUMERATED *a);

  ASN1_TYPE *d2i_ASN1_TYPE(ASN1_TYPE **a, const unsigned char **ppin, long length);
  ASN1_STRING *d2i_ASN1_OCTET_STRING(ASN1_STRING **a, const unsigned char **ppin, long length);
  ASN1_INTEGER *d2i_ASN1_INTEGER(ASN1_INTEGER **a, const unsigned char **ppin, long length);
  ASN1_ENUMERATED *d2i_ASN1_ENUMERATED(ASN1_ENUMERATED **a, const unsigned char **ppin, long length);

  int i2d_ASN1_OCTET_STRING(const ASN1_STRING *a, unsigned char **pp);
  int i2d_ASN1_INTEGER(const ASN1_INTEGER *a, unsigned char **pp);

  int ASN1_get_object(const unsigned char **pp, long *plength, int *ptag,
                      int *pclass, long omax);
  int ASN1_object_size(int constructed, int length, int tag);
]]


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


function _M.intToBER(i)
  local ber = {}

  if band(i, _M.BERCLASS.Application) == _M.BERCLASS.Application then
    ber.class = _M.BERCLASS.Application
  elseif band(i, _M.BERCLASS.ContextSpecific) == _M.BERCLASS.ContextSpecific then
    ber.class = _M.BERCLASS.ContextSpecific
  elseif band(i, _M.BERCLASS.Private) == _M.BERCLASS.Private then
    ber.class = _M.BERCLASS.Private
  else
    ber.class = _M.BERCLASS.Universal
  end

  -- constructed  0x20
  if band(i, 0x20) == 0x20 then
    ber.constructed = true
    ber.number = i - ber.class - 32

  else
    ber.primitive = true
    ber.number = i - ber.class
  end

  return ber
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
    assert(stop >= start, fmt("invalid offset '%s', start: %s", stop, start))
    assert(stop <= #der, "stop offset must less than length")

    local s_der = ffi_cast("const unsigned char *", der)
    strpp[0] = s_der + start

    local ret = C.ASN1_get_object(strpp, lenp, tagp, classp, stop - start + 1)
    if band(ret, 0x80) == 0x80 then
        error("der with error encoding", ret)
    end

    local constructed = false
    if band(ret, 0x20) == 0x20 then
        constructed = true
    end

    return tagp[0], classp[0], tonumber(lenp[0]), strpp[0] - s_der, constructed
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
  local _, _, len, offset = asn1_get_object(der)

  -- message ID (integer)
  local asn1_int = C.d2i_ASN1_INTEGER(nil, cucharpp, #der)
  local id = C.ASN1_INTEGER_get(asn1_int)

  _, _, len, offset = asn1_get_object(der, offset + len)
  local _, op_int = bunpack(der, "C", offset - 1)

  local op = _M.intToBER(op_int)

  -- success result code
  cucharpp[0] = p + offset
  asn1_int = C.d2i_ASN1_ENUMERATED(nil, cucharpp, len)
  local res = C.ASN1_ENUMERATED_get(asn1_int)

  -- No matched DN (octet string)
  local asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local err1 = C.ASN1_STRING_get0_data(asn1_str)

  -- No diagnostic message (octet string)
  asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, #der)
  local err2 = C.ASN1_STRING_get0_data(asn1_str)

  -- free
  ffi.gc(asn1_str, C.ASN1_STRING_free)
  ffi.gc(asn1_int, C.ASN1_INTEGER_free)

  return tonumber(id), op, tonumber(res), err1, err2
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
    local tag, _, len, offset, _ = asn1_get_object(encStr, pos - 1)
    local newpos = offset + 1

    if self.decoder[tag] then
      return self.decoder[tag](self, encStr, len, pos - 1)
    end
    
    return newpos, nil
  end,

  registerBaseDecoders = function(self)
    self.decoder = {}
  
    -- Integer
    self.decoder[2] = function(self, encStr, elen, pos)
      local p = ffi_cast("const unsigned char *", encStr) + pos
      cucharpp[0] = p
      local asn1_int = C.d2i_ASN1_INTEGER(nil, cucharpp, elen)
      local ret = C.ASN1_INTEGER_get(asn1_int)
      ffi.gc(asn1_int, C.ASN1_INTEGER_free)
      return tonumber(ret)
    end

    -- Octet String
    self.decoder[4] = function(self, encStr, elen, pos)
      local p = ffi_cast("const unsigned char *", encStr) + pos
      cucharpp[0] = p
      local asn1_str = C.d2i_ASN1_OCTET_STRING(nil, cucharpp, elen)
      local ret = C.ASN1_STRING_get0_data(asn1_str)
      ffi.gc(asn1_str, C.ASN1_STRING_free)
      return ret
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
      ffi.gc(typ, C.ASN1_INTEGER_free)
      return ffi_string(charpp[0], ret)
    end

    -- Octet String encoder
    self.encoder["string"] = function(self, val)
      local typ = C.ASN1_OCTET_STRING_new()
      C.ASN1_STRING_set(typ, val, #val)
      charpp[0] = nil
      local ret = C.i2d_ASN1_OCTET_STRING(typ, charpp)
      ffi.gc(typ, C.ASN1_STRING_free)
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
