local asn1 = require "kong.plugins.ldap-auth.asn1"


local bunpack = asn1.bunpack
local fmt = string.format


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
  UnbindRequest = 2,
  ExtendedRequest = 23,
  ExtendedResponse = 24
}


local function encodeLDAPOp(encoder, appno, isConstructed, data)
  local asn1_type = asn1.BERtoInt(asn1.BERCLASS.Application, isConstructed, appno)
  return encoder:encode({ _ldaptype = fmt("%X", asn1_type), data })
end


local function calculate_payload_length(encStr, pos, socket)
  local elen

  pos, elen = bunpack(encStr, "C", pos)

  if elen > 128 then
    elen = elen - 128
    local elenCalc = 0
    local elenNext

    for i = 1, elen do
      elenCalc = elenCalc * 256
      encStr = encStr .. socket:receive(1)
      pos, elenNext = bunpack(encStr, "C", pos)
      elenCalc = elenCalc + elenNext
    end

    elen = elenCalc
  end

  return pos, elen
end


function _M.bind_request(socket, username, password)
  local encoder = asn1.ASN1Encoder:new()
  local decoder = asn1.ASN1Decoder:new()

  local ldapAuth = encoder:encode({ _ldaptype = 80, password })
  local bindReq = encoder:encode(3) .. encoder:encode(username) .. ldapAuth
  local ldapMsg = encoder:encode(ldapMessageId) ..
                    encodeLDAPOp(encoder, APPNO.BindRequest, true, bindReq)

  local packet
  local pos
  local packet_len
  local tmp
  local _

  local response = {}

  packet = encoder:encodeSeq(ldapMsg)

  ldapMessageId = ldapMessageId + 1

  socket:send(packet)

  packet = socket:receive(2)

  _, packet_len = calculate_payload_length(packet, 2, socket)

  packet = socket:receive(packet_len)
  pos, response.messageID = decoder:decode(packet, 1)
  pos, tmp = bunpack(packet, "C", pos)
  pos = decoder.decodeLength(packet, pos)
  response.protocolOp = asn1.intToBER(tmp)

  if response.protocolOp.number ~= APPNO.BindResponse then
    return false, fmt("Received incorrect Op in packet: %d, expected %d",
                      response.protocolOp.number, APPNO.BindResponse)
  end

  pos, response.resultCode = decoder:decode(packet, pos)

  if response.resultCode ~= 0 then
    local error_msg
    pos, response.matchedDN = decoder:decode(packet, pos)
    _, response.errorMessage = decoder:decode(packet, pos)
    error_msg = ERROR_MSG[response.resultCode]

    return false, fmt("\n  Error: %s\n  Details: %s",
                      error_msg or "Unknown error occurred (code: " ..
                      response.resultCode .. ")", response.errorMessage or "")

  else
    return true
  end
end


function _M.unbind_request(socket)
  local ldapMsg, packet
  local encoder = asn1.ASN1Encoder:new()

  ldapMessageId = ldapMessageId + 1

  ldapMsg = encoder:encode(ldapMessageId) ..
                           encodeLDAPOp(encoder, APPNO.UnbindRequest,
                                        false, nil)
  packet = encoder:encodeSeq(ldapMsg)

  socket:send(packet)

  return true, ""
end


function _M.start_tls(socket)
  local ldapMsg, pos, packet, packet_len, tmp, _
  local response = {}
  local encoder = asn1.ASN1Encoder:new()
  local decoder = asn1.ASN1Decoder:new()

  local method_name = encoder:encode({ _ldaptype = 80, "1.3.6.1.4.1.1466.20037" })

  ldapMessageId = ldapMessageId + 1

  ldapMsg = encoder:encode(ldapMessageId) ..
                           encodeLDAPOp(encoder, APPNO.ExtendedRequest, true, method_name)

  packet = encoder:encodeSeq(ldapMsg)
  socket:send(packet)
  packet = socket:receive(2)

  _, packet_len = calculate_payload_length(packet, 2, socket)

  packet = socket:receive(packet_len)
  pos, response.messageID = decoder:decode(packet, 1)
  pos, tmp = bunpack(packet, "C", pos)
  pos = decoder.decodeLength(packet, pos)
  response.protocolOp = asn1.intToBER(tmp)

  if response.protocolOp.number ~= APPNO.ExtendedResponse then
    return false, fmt("Received incorrect Op in packet: %d, expected %d",
                      response.protocolOp.number, APPNO.ExtendedResponse)
  end

  pos, response.resultCode = decoder:decode(packet, pos)

  if response.resultCode ~= 0 then
    local error_msg

    pos, response.matchedDN = decoder:decode(packet, pos)
    _, response.errorMessage = decoder:decode(packet, pos)
    error_msg = ERROR_MSG[response.resultCode]

    return false, fmt("\n  Error: %s\n  Details: %s",
                      error_msg or "Unknown error occurred (code: " ..
                      response.resultCode .. ")", response.errorMessage or "")

  else
    return true
  end
end


return _M;
