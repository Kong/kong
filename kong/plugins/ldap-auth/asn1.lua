require "resty.openssl.include.ossl_typ"
local asn1_macro = require "resty.openssl.include.asn1"
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
local math = math
local type = type
local char = string.char
local bit = bit


asn1_macro.declare_asn1_functions("ASN1_TYPE")
asn1_macro.declare_asn1_functions("ASN1_ENUMERATED")


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

  if bit.band(i, _M.BERCLASS.Application) == _M.BERCLASS.Application then
    ber.class = _M.BERCLASS.Application
  elseif bit.band(i, _M.BERCLASS.ContextSpecific) == _M.BERCLASS.ContextSpecific then
    ber.class = _M.BERCLASS.ContextSpecific
  elseif bit.band(i, _M.BERCLASS.Private) == _M.BERCLASS.Private then
    ber.class = _M.BERCLASS.Private
  else
    ber.class = _M.BERCLASS.Universal
  end

  -- constructed  0x20
  if bit.band(i, 0x20) == 0x20 then
    ber.constructed = true
    ber.number = i - ber.class - 32

  else
    ber.primitive = true
    ber.number = i - ber.class
  end

  return ber
end


local function asn1_get_object(der, start, stop)
  start = start or 0
  stop = stop or #der
  assert(stop >= start, fmt("invalid offset '%s', start: %s", stop, start))
  assert(stop <= #der, "stop offset must less than length")

  local len = ffi_new("long[1]")
  local tag = ffi_new("int[1]")
  local class = ffi_new("int[1]")
  local s_der = ffi_cast("const unsigned char *", der)
  local p = s_der + start
  local c_str = ffi_new("const unsigned char*[1]", p)

  local ret = C.ASN1_get_object(c_str, len, tag, class, stop - start + 1)
  if bit.band(ret, 0x80) == 0x80 then
      error("der with error encoding", ret)
  end

  local constructed = false
  if bit.band(ret, 0x20) == 0x20 then
      constructed = true
  end

  return tag[0], class[0], tonumber(len[0]), c_str[0] - s_der, constructed
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
  local pp = ffi_new("const unsigned char *[1]", p)
  local _, _, len, offset = asn1_get_object(der)

  -- message ID (integer)
  local asn1_int = C.d2i_ASN1_INTEGER(nil, pp, #der)
  local id = C.ASN1_INTEGER_get(asn1_int)

  _, _, len, offset = asn1_get_object(der, offset + len)
  local _, op_int = bunpack(der, "C", offset - 1)

  local op = _M.intToBER(op_int)

  -- success result code
  pp[0] = p + offset
  asn1_int = C.d2i_ASN1_ENUMERATED(nil, pp, len)
  local res = C.ASN1_ENUMERATED_get(asn1_int)

  -- No matched DN (octet string)
  local asn1_str = C.d2i_ASN1_OCTET_STRING(nil, pp, #der)
  local err1 = C.ASN1_STRING_get0_data(asn1_str)

  -- No diagnostic message (octet string)
  asn1_str = C.d2i_ASN1_OCTET_STRING(nil, pp, #der)
  local err2 = C.ASN1_STRING_get0_data(asn1_str)

  -- free
  C.ASN1_STRING_free(asn1_str)
  C.ASN1_INTEGER_free(asn1_int)

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

    local etype = "02"
    if tag == 4 then
      etype = "04"
    end

    if self.decoder[etype] then
      return self.decoder[etype](self, encStr, len, newpos)
    else
      return newpos, nil
    end
  end,

  registerBaseDecoders = function(self)
    self.decoder = {}

    self.decoder["0A"] = function(self, encStr, elen, pos)
      return self.decodeInt(encStr, elen, pos)
    end
  
    -- Integer
    self.decoder["02"] = function(self, encStr, elen, pos)
      return self.decodeInt(encStr, elen, pos)
    end

    -- Octet String
    self.decoder["04"] = function(self, encStr, elen, pos)
      return bunpack(encStr, "A" .. elen, pos)
    end
  end,

  decodeLength = function(encStr, pos)
    local elen

    pos, elen = bunpack(encStr, "C", pos)
    if elen > 128 then
      elen = elen - 128
      local elenCalc = 0
      local elenNext

      for i = 1, elen do
        elenCalc = elenCalc * 256
        pos, elenNext = bunpack(encStr, "C", pos)
        elenCalc = elenCalc + elenNext
      end

      elen = elenCalc
    end

    return pos, elen
  end,

  decodeInt = function(encStr, len, pos)
    local hexStr

    pos, hexStr = bunpack(encStr, "X" .. len, pos)

    local value = tonumber(hexStr, 16)
    if value >= math.pow(256, len)/2 then
      value = value - math.pow(256, len)
    end

    return pos, value
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
      local pp = ffi_new("char*[1]")
      local ret = C.i2d_ASN1_INTEGER(typ, pp)
      C.ASN1_INTEGER_free(typ)
      if ret <= 0 then
        return nil, "failed to call i2d_ASN1_UTF8STRING"
      end
      return ffi_string(pp[0], ret)
    end

    -- Octet String encoder
    self.encoder["string"] = function(self, val)
      local typ = C.ASN1_OCTET_STRING_new()
      C.ASN1_STRING_set(typ, val, #val)
      local pp = ffi_new("char*[1]")
      local ret = C.i2d_ASN1_OCTET_STRING(typ, pp)
      C.ASN1_STRING_free(typ)
      if ret <= 0 then
        return nil, "failed to call i2d_ASN1_UTF8STRING"
      end
      return ffi_string(pp[0], ret)
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
