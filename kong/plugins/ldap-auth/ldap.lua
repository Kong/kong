local asn1 = require "kong.plugins.ldap-auth.asn1"
local bunpack = require "lua_pack".unpack
local fmt = string.format
local asn1_parse_ldap_result = asn1.parse_ldap_result
local asn1_put_object = asn1.put_object
local asn1_encode = asn1.encode


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
  local ldapAuth = asn1_put_object(0, asn1.CLASS.CONTEXT_SPECIFIC, 0, password)
  local bindReq = asn1_encode(3) ..asn1_encode(username) .. ldapAuth
  local ldapMsg = asn1_encode(ldapMessageId) ..
                    asn1_put_object(APPNO.BindRequest, asn1.CLASS.APPLICATION, 1, bindReq)

  local packet, packet_len, _

  packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)

  ldapMessageId = ldapMessageId + 1

  socket:send(packet)

  packet = socket:receive(2)

  _, packet_len = calculate_payload_length(packet, 2, socket)

  packet = socket:receive(packet_len)

  local res, err = asn1_parse_ldap_result(packet)
  if err then
    return false, "Invalid LDAP message encoding: " .. err
  end

  if res.protocol_op ~= APPNO.BindResponse then
    return false, fmt("Received incorrect Op in packet: %d, expected %d",
                      res.protocol_op, APPNO.BindResponse)
  end

  if res.result_code ~= 0 then
    local error_msg = ERROR_MSG[res.result_code]

    return false, fmt("\n  Error: %s\n  Details: %s",
                      error_msg or "Unknown error occurred (code: " .. 
                      res.result_code .. ")", res.diagnostic_msg or "")

  else
    return true
  end
end


function _M.unbind_request(socket)
  local ldapMsg, packet

  ldapMessageId = ldapMessageId + 1

  ldapMsg = asn1_encode(ldapMessageId) ..
              asn1_put_object(APPNO.UnbindRequest, asn1.CLASS.APPLICATION, 0)
  packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)

  socket:send(packet)

  return true, ""
end


function _M.start_tls(socket)
  local ldapMsg, packet, packet_len, _

  local method_name = asn1_put_object(0, asn1.CLASS.CONTEXT_SPECIFIC, 0, "1.3.6.1.4.1.1466.20037")

  ldapMessageId = ldapMessageId + 1

  ldapMsg = asn1_encode(ldapMessageId) ..
              asn1_put_object(APPNO.ExtendedRequest, asn1.CLASS.APPLICATION, 1, method_name)

  packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)
  socket:send(packet)
  packet = socket:receive(2)

  _, packet_len = calculate_payload_length(packet, 2, socket)

  packet = socket:receive(packet_len)

  local res, err = asn1_parse_ldap_result(packet)
  if err then
    return false, "Invalid LDAP message encoding: " .. err
  end

  if res.protocol_op ~= APPNO.ExtendedResponse then
    return false, fmt("Received incorrect Op in packet: %d, expected %d",
                      res.protocol_op, APPNO.ExtendedResponse)
  end

  if res.result_code ~= 0 then
    local error_msg = ERROR_MSG[res.result_code]

    return false, fmt("\n  Error: %s\n  Details: %s",
                      error_msg or "Unknown error occurred (code: " ..
                      res.result_code .. ")", res.diagnostic_msg or "")

  else
    return true
  end
end


return _M;
