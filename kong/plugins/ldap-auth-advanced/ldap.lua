local asn1 = require "kong.plugins.ldap-auth-advanced.asn1"
local bunpack = asn1.bunpack

local string_format = string.format

local _M = {}

local ldapMessageId = 1

local ERROR_MSG = {
  [1]  = "Initialization of LDAP library failed.",
  [4]  = "Size limit exceeded.",
  [13] = "Confidentiality required",
  [32] = "No such object",
  [34] = "Invalid DN",
  [49] = "The supplied credential is invalid."
}

local APPNO = {
  BindRequest = 0,
  BindResponse = 1,
  SearchRequest = 3,
  SearchResult = 4,
  SearchResultDone = 5;
  UnbindRequest = 2,
  ExtendedRequest = 23,
  ExtendedResponse = 24
}

local encoder = asn1.ASN1Encoder:new()
local decoder = asn1.ASN1Decoder:new()

local function encodeLDAPOp(encoder, appno, isConstructed, data)
  local asn1_type = asn1.BERtoInt(asn1.BERCLASS.Application, isConstructed, appno)
  return encoder:encode({ _ldaptype = string_format("%X", asn1_type), data })
end

local function calculate_payload_length(encStr, pos, socket)
  local elen
  pos, elen = bunpack(encStr, 'C', pos)
  if elen > 128 then
    elen = elen - 128
    local elenCalc = 0
    local elenNext
    for i = 1, elen do
      elenCalc = elenCalc * 256
      encStr = encStr .. socket:receive(1)
      pos, elenNext = bunpack(encStr, 'C', pos)
      elenCalc = elenCalc + elenNext
    end
    elen = elenCalc
  end
  return pos, elen
end

local function receive_packet(socket)
  local data = socket:receive(2)
  local _, packet_len = calculate_payload_length(data, 2, socket)
  return socket:receive(packet_len)
end

local function receive_ldap_message(socket)
  local packet = receive_packet(socket)
  local pos, messageID = decoder:decode(packet, 1)
  local protocolOp
  pos, protocolOp = bunpack(packet, "C", pos)
  pos = decoder.decodeLength(packet, pos)
  protocolOp = asn1.intToBER(protocolOp)
  return messageID, protocolOp, packet, pos
end

function _M.bind_request(socket, username, password)
  local ldapAuth = encoder:encode({ _ldaptype = 80, password })
  local bindReq = encoder:encode(3) .. encoder:encode(username) .. ldapAuth
  local ldapMsg = encoder:encode(ldapMessageId) ..
    encodeLDAPOp(encoder, APPNO.BindRequest, true, bindReq)

  local send_packet = encoder:encodeSeq(ldapMsg)
  ldapMessageId = ldapMessageId +1
  socket:send(send_packet)

  local _, protocolOp, packet, pos = receive_ldap_message(socket)

  if protocolOp.number ~= APPNO.BindResponse then
    return false, string_format("Received incorrect Op in packet: %d, expected %d",
                                protocolOp.number, APPNO.BindResponse)
  end

  local resultCode
  pos, resultCode = decoder:decode(packet, pos)

  if resultCode ~= 0 then
    local _, errorMessage
    pos, _ = decoder:decode(packet, pos)
    _, errorMessage = decoder:decode(packet, pos)
    local error_msg = ERROR_MSG[resultCode]
    return false, string_format("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. resultCode ..
      ")", errorMessage or "")
  else
    return true
  end
end

function _M.unbind_request(socket)
  local ldapMsg, packet
  local encoder = asn1.ASN1Encoder:new()

  ldapMessageId = ldapMessageId +1
  ldapMsg = encoder:encode(ldapMessageId) ..
            encodeLDAPOp(encoder, APPNO.UnbindRequest,
                         false, nil)
  packet = encoder:encodeSeq(ldapMsg)
  socket:send(packet)
  return true, ""
end

local scopes = {
  -- alias in RFC 4511
  baseObject = 0;
  singleLevel = 1;
  wholeSubtree = 2;
  -- aliases used by ldapsearch command
  base = 0;
  one = 1;
  sub = 2;
}

function _M.search_request(socket, query)
  local base = assert(query.base, "missing base")
  local scope = assert(query.scope, "missing scope")
  if type(scope) == "string" then
    scope = assert(scopes[scope], "unknown scope")
  elseif type(scope) ~= "number" then
    error "invalid scope field"
  end
  local filter = query.filter
  if filter == nil then
    filter = encoder:encodeTag("context", false, 7, "objectclass")
  else
    local field, value = filter:match("(%g+)=([%s%g]+)")
    if field then
      filter = encoder:encodeTag("context", true, 3, encoder:encode(field)..encoder:encode(value))
    else
      error "NYI"
    end
  end
  local attributes = query.attrs
  if attributes == nil then
    attributes = encoder:encodeSeq("")
  elseif type(attributes) == "string" then
    attributes = encoder:encodeSeq(encoder:encode(attributes))
  elseif type(attributes) == "table" then
    local a = {}
    for i, v in ipairs(attributes) do
      assert(type(v) == "string")
      a[i] = encoder:encode(v)
    end
    attributes = encoder:encodeSeq(table.concat(a))
  else
    error "invalid attrs field"
  end

  local data = encoder:encode(base)
    .. encoder:encodeEnum(scope) -- scope
    .. encoder:encodeEnum(0) -- derefAliases
    .. encoder:encode(0) -- sizeLimit
    .. encoder:encode(0) -- timeLimit
    .. encoder:encode(false) -- typesOnly
    .. filter -- filter
    .. attributes -- attributes
  ldapMessageId = ldapMessageId +1
  local ldapMsg = encoder:encode(ldapMessageId) .. encodeLDAPOp(encoder, 3, true, data)
  local packet = encoder:encodeSeq(ldapMsg)
  socket:send(packet)

  local response = {}

  local _, protocolOp, packet, pos = receive_ldap_message(socket)

  while protocolOp.number == APPNO.SearchResult do
    local key
    pos, key = decoder:decode(packet, pos)
    local _, seq = decoder:decode(packet, pos)
    local val = {}
    for i,v in ipairs(seq) do
      if v[3] ~= nil then
        local k = table.remove(v, 1)
        val[k] = v
      else
        val[v[1]] = v[2]
      end
    end
    response[key] = val

    -- Read next packet
    _, protocolOp, packet, pos = receive_ldap_message(socket)
  end

  if protocolOp.number ~= APPNO.SearchResultDone then
    if protocolOp.number == APPNO.ExtendedResponse then
      local resultCode
      pos, resultCode = decoder:decode(packet, pos)
      local error_msg, _
      pos, response.matchedDN = decoder:decode(packet, pos)
      _, response.errorMessage = decoder:decode(packet, pos)
      error_msg = ERROR_MSG[resultCode]
      return false, string_format("\n  Error: %s\n  Details: %s",
        error_msg or "Unknown error occurred (code: " .. resultCode ..
        ")", response.errorMessage or "")
    end
    return false, string_format("Received incorrect Op in packet: %d, expected %d", protocolOp.number, APPNO.SearchResultDone)
  end

  local resultCode
  pos, resultCode = decoder:decode(packet, pos)

  if resultCode ~= 0 then
    local _, errorMessage
    pos, _ = decoder:decode(packet, pos)
    _, errorMessage = decoder:decode(packet, pos)
    local error_msg = ERROR_MSG[resultCode]

    return false, string_format("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. resultCode ..
      ")", errorMessage or "")
  else
    return response
  end
end

function _M.start_tls(socket)
  local method_name = encoder:encode({_ldaptype = 80, "1.3.6.1.4.1.1466.20037"})
  ldapMessageId = ldapMessageId +1
  local ldapMsg = encoder:encode(ldapMessageId) ..
    encodeLDAPOp(encoder, APPNO.ExtendedRequest, true, method_name)
  local send_packet = encoder:encodeSeq(ldapMsg)
  socket:send(send_packet)

  local _, protocolOp, packet, pos = receive_ldap_message(socket)

  if protocolOp.number ~= APPNO.ExtendedResponse then
    return false, string_format("Received incorrect Op in packet: %d, expected %d",
                                protocolOp.number, APPNO.ExtendedResponse)
  end

  local resultCode
  pos, resultCode = decoder:decode(packet, pos)

  if resultCode ~= 0 then
    local _, errorMessage
    pos, _ = decoder:decode(packet, pos)
    _, errorMessage = decoder:decode(packet, pos)
    local error_msg = ERROR_MSG[resultCode]
    return false, string_format("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. resultCode ..
      ")", errorMessage or "")
  else
    return true
  end
end

return _M;
