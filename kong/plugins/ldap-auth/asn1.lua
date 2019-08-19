local bpack, bunpack
do
  local string_pack = string.pack
  local string_unpack = string.unpack
  require "lua_pack"
  bpack = string.pack
  bunpack = string.unpack
  -- luacheck: globals string.unpack
  string.unpack = string_unpack
  -- luacheck: globals string.pack
  string.pack = string_pack
end


local setmetatable = setmetatable
local tonumber = tonumber
local reverse = string.reverse
local ipairs = ipairs
local concat = table.concat
local insert = table.insert
local pairs = pairs
local math = math
local type = type
local char = string.char
local bit = bit


local _M = { bpack = bpack, bunpack = bunpack }


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

    self.encoder["table"] = function(self, val)
      if val._ldap == "0A" then
        local ival = self.encodeInt(val[1])
        local len = self.encodeLength(#ival)

        return bpack("XAA", "0A", len, ival)
      end

      if val._ldaptype then
        local len

        if val[1] == nil or #val[1] == 0 then
          return bpack("XC", val._ldaptype, 0)
        end

        len = self.encodeLength(#val[1])
        return bpack("XAA", val._ldaptype, len, val[1])
      end

      local encVal = ""
      for _, v in ipairs(val) do
        encVal = encVal .. self.encode(v) -- todo: buffer?
      end

      local tableType = "\x30"
      if val["_snmp"] then
        tableType = bpack("X", val["_snmp"])
      end

      return bpack("AAA", tableType, self.encodeLength(#encVal), encVal)
    end

    -- Boolean encoder
    self.encoder["boolean"] = function(self, val)
      if val then
        return bpack("X", "01 01 FF")
      else
        return bpack("X", "01 01 00")
      end
    end

    -- Integer encoder
    self.encoder["number"] = function(self, val)
      local ival = self.encodeInt(val)
      local len = self.encodeLength(#ival)

      return bpack("XAA", "02", len, ival)
    end

    -- Octet String encoder
    self.encoder["string"] = function(self, val)
      local len = self.encodeLength(#val)
      return bpack("XAA", "04", len, val)
    end

    -- Null encoder
    self.encoder["nil"] = function(self, val)
      return bpack("X", "05 00")
    end
  end,

  encode_oid_component = function(n)
    local parts = {}

    parts[1] = char(n % 128)
    while n >= 128 do
      n = bit.rshift(n, 7)
      parts[#parts + 1] = char(n % 128 + 0x80)
    end

    return reverse(concat(parts))
  end,

  encodeInt = function(val)
    local lsb = 0

    if val > 0 then
      local valStr = ""

      while (val > 0) do
        lsb = math.fmod(val, 256)
        valStr = valStr .. bpack("C", lsb)
        val = math.floor(val/256)
      end

      if lsb > 127 then
        valStr = valStr .. "\0"
      end

      return reverse(valStr)

    elseif val < 0 then
      local i = 1
      local tcval = val + 256

      while tcval <= 127 do
        tcval = tcval + (math.pow(256, i) * 255)
        i = i+1
      end

      local valStr = ""

      while (tcval > 0) do
        lsb = math.fmod(tcval, 256)
        valStr = valStr .. bpack("C", lsb)
        tcval = math.floor(tcval/256)
      end

      return reverse(valStr)

    else -- val == 0
      return bpack("x")
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
