require "resty.openssl.include.ossl_typ"
local asn1_macro = require "resty.openssl.include.asn1"
local ffi = require "ffi"
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string

local lpack = require "lua_pack"
local bpack = lpack.pack
local bunpack = lpack.unpack

local setmetatable = setmetatable
local tonumber = tonumber
local reverse = string.reverse
local concat = table.concat
local insert = table.insert
local pairs = pairs
local math = math
local type = type
local char = string.char
local bit = bit

asn1_macro.declare_asn1_functions("ASN1_TYPE")

ffi.cdef [[
	int i2d_ASN1_OCTET_STRING(const ASN1_STRING *a, unsigned char **pp);
	int i2d_ASN1_INTEGER(const ASN1_INTEGER *a, unsigned char **pp);
	ASN1_STRING *ASN1_OCTET_STRING_new();
]]

local _M = {}


_M.BERCLASS = {
  Universal = 0,
  Application = 64,
  ContextSpecific = 128,
  Private = 192
}


_M.ASN1Decoder = {
  new = function(self,o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:registerBaseDecoders()
    return o
  end,

  decode = function(self, encStr, pos)
    local etype, elen
    local newpos = pos

    newpos, etype = bunpack(encStr, "X1", newpos)
    newpos, elen = self.decodeLength(encStr, newpos)

    if self.decoder[etype] then
      return self.decoder[etype](self, encStr, elen, newpos)
    else
      return newpos, nil
    end
  end,

  setStopOnError = function(self, val)
    self.stoponerror = val
  end,

  registerBaseDecoders = function(self)
    self.decoder = {}

    self.decoder["0A"] = function(self, encStr, elen, pos)
      return self.decodeInt(encStr, elen, pos)
    end

    self.decoder["8A"] = function(self, encStr, elen, pos)
      return bunpack(encStr, "A" .. elen, pos)
    end

    self.decoder["31"] = function(self, encStr, elen, pos)
      return pos, nil
    end

    -- Boolean
    self.decoder["01"] = function(self, encStr, elen, pos)
      local val = bunpack(encStr, "X", pos)
      if val ~= "FF" then
        return pos, true
      else
        return pos, false
      end
    end

    -- Integer
    self.decoder["02"] = function(self, encStr, elen, pos)
      return self.decodeInt(encStr, elen, pos)
    end

    -- Octet String
    self.decoder["04"] = function(self, encStr, elen, pos)
      return bunpack(encStr, "A" .. elen, pos)
    end

    -- Null
    self.decoder["05"] = function(self, encStr, elen, pos)
      return pos, false
    end

    -- Object Identifier
    self.decoder["06"] = function(self, encStr, elen, pos)
      return self:decodeOID(encStr, elen, pos)
    end

    -- Context specific tags
    self.decoder["30"] = function(self, encStr, elen, pos)
      return self:decodeSeq(encStr, elen, pos)
    end
  end,

  registerTagDecoders = function(self, tagDecoders)
    self:registerBaseDecoders()

    for k, v in pairs(tagDecoders) do
      self.decoder[k] = v
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

  decodeSeq = function(self, encStr, len, pos)
    local seq = {}
    local sPos = 1
    local sStr

    pos, sStr = bunpack(encStr, "A" .. len, pos)

    while (sPos < len) do
      local newSeq

      sPos, newSeq = self:decode(sStr, sPos)
      if not newSeq and self.stoponerror then
        break
      end

      insert(seq, newSeq)
    end

    return pos, seq
  end,

  decode_oid_component = function(encStr, pos)
    local octet
    local n = 0

    repeat
      pos, octet = bunpack(encStr, "b", pos)
      n = n * 128 + bit.band(0x7F, octet)
    until octet < 128

    return pos, n
  end,

  decodeOID = function(self, encStr, len, pos)
    local last
    local oid = {}
    local octet

    last = pos + len - 1
    if pos <= last then
      oid._snmp = "06"
      pos, octet = bunpack(encStr, "C", pos)
      oid[2] = math.fmod(octet, 40)
      octet = octet - oid[2]
      oid[1] = octet/40
    end

    while pos <= last do
      local c
      pos, c = self.decode_oid_component(encStr, pos)
      oid[#oid + 1] = c
    end

    return pos, oid
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

function _M.BERtoInt(class, constructed, number)
  local asn1_type = class + number

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

  if bit.band(i, 32) == 32 then
    ber.constructed = true
    ber.number = i - ber.class - 32

  else
    ber.primitive = true
    ber.number = i - ber.class
  end

  return ber
end


return _M
