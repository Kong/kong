-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local bunpack = require "lua_pack".unpack
local asn1 = require "kong.plugins.ldap-auth-advanced.asn1"
local asn1_put_object = asn1.put_object
local asn1_parse_ldap_op = asn1.parse_ldap_op
local asn1_parse_ldap_result = asn1.parse_ldap_result
local asn1_encode = asn1.encode
local asn1_decode = asn1.decode
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
  SearchRequest = 3,
  SearchResult = 4,
  SearchResultDone = 5,
  SearchResultReference = 19,
  UnbindRequest = 2,
  ExtendedRequest = 23,
  ExtendedResponse = 24
}

local RETURN_CODE = {
  OK = 0,     -- success
  FAIL = 1,   -- fail
  ERROR = 2,  -- unexpected error
}

_M.RETURN_CODE = RETURN_CODE

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
  if not data then
    return nil, 'socket packet is empty'
  end
  local _, packet_len = calculate_payload_length(data, 2, socket)
  return socket:receive(packet_len)
end

local function receive_ldap_message(socket)
  local packet, err = receive_packet(socket)
  if err then
    return nil, nil, nil, nil, err
  end

  local res
  res, err = asn1_parse_ldap_op(packet)
  if err then
    return nil, nil, nil, nil, err
  end

  return res.message_id, res.protocol_op, packet, res.offset
end

function _M.bind_request(socket, username, password)
  local ldapAuth = asn1_put_object(0, asn1.CLASS.CONTEXT_SPECIFIC, 0, password)
  local bindReq = asn1_encode(3) .. asn1_encode(username) .. ldapAuth
  local ldapMsg = asn1_encode(ldapMessageId) ..
    asn1_put_object(APPNO.BindRequest, asn1.CLASS.APPLICATION, 1, bindReq)

  local send_packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)
  ldapMessageId = ldapMessageId + 1
  socket:send(send_packet)

  local _, protocol_op, packet, pos, err = receive_ldap_message(socket)
  if err then
    return RETURN_CODE.ERROR, err
  end

  if protocol_op ~= APPNO.BindResponse then
    return RETURN_CODE.ERROR, fmt("Received incorrect Op in packet: %d, expected %d",
                                protocol_op, APPNO.BindResponse)
  end

  local res
  res, err = asn1_parse_ldap_result(packet, pos)
  if err then
    return RETURN_CODE.ERROR, err
  end

  if res.result_code ~= 0 then
    local error_msg = ERROR_MSG[res.result_code]
    return RETURN_CODE.FAIL, fmt("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. res.result_code ..
      ")", res.diagnostic_msg or "")
  else
    return RETURN_CODE.OK
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
    filter = asn1_put_object(7, asn1.CLASS.CONTEXT_SPECIFIC, 0, "objectclass")
  else
    local field, value = filter:match("(%g+)=([%s%g]+)")
    if field then
      filter = asn1_put_object(3, asn1.CLASS.CONTEXT_SPECIFIC, 1, asn1_encode(field)..asn1_encode(value))
    else
      error "NYI"
    end
  end
  local attributes = query.attrs
  if attributes == nil then
    attributes = asn1_encode("", asn1.TAG.SEQUENCE)
  elseif type(attributes) == "string" then
    attributes = asn1_encode(asn1_encode(attributes), asn1.TAG.SEQUENCE)
  elseif type(attributes) == "table" then
    local a = {}
    for i, v in ipairs(attributes) do
      assert(type(v) == "string")
      a[i] = asn1_encode(v)
    end
    attributes = asn1_encode(table.concat(a), asn1.TAG.SEQUENCE)
  else
    error "invalid attrs field"
  end

  local data = asn1_encode(base)
    .. asn1_encode(scope, asn1.TAG.ENUMERATED) -- scope
    .. asn1_encode(0, asn1.TAG.ENUMERATED) -- derefAliases
    .. asn1_encode(0) -- sizeLimit
    .. asn1_encode(0) -- timeLimit
    .. asn1_encode(false) -- typesOnly
    .. filter -- filter
    .. attributes -- attributes
  ldapMessageId = ldapMessageId + 1
  local ldapMsg = asn1_encode(ldapMessageId) .. asn1_put_object(3, asn1.CLASS.APPLICATION, 1, data)
  local packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)
  socket:send(packet)

  local response = {}

  local _, protocol_op, packet, pos, err = receive_ldap_message(socket)
  if err then
    return false, err
  end

  while protocol_op == APPNO.SearchResult or
        protocol_op == APPNO.SearchResultReference do

    while protocol_op == APPNO.SearchResultReference do
      _, protocol_op, packet, pos, err = receive_ldap_message(socket)
      if err then
        return false, err
      end
    end

    if protocol_op == APPNO.SearchResultDone then
      break
    end

    local key
    pos, key, err = asn1_decode(packet, pos)
    if err then
      return false, err
    end
    local _, seq, err = asn1_decode(packet, pos)
    if err then
      return false, err
    end

    local val = {}
    for _, v in ipairs(seq) do
      local k = v[1]
      local vv = v[2]
      if type(vv) == "table" and #vv == 1 then
        vv = vv[1]
      end
      val[k] = vv
    end
    response[key] = val

    -- Read next packet
    _, protocol_op, packet, pos, err = receive_ldap_message(socket)
    if err then
      return false, err
    end
  end

  if protocol_op ~= APPNO.SearchResultDone then
    if protocol_op == APPNO.ExtendedResponse then
      local res
      res, err = asn1_parse_ldap_result(packet, pos)
      if err then
        return false, err
      end

      local error_msg = ERROR_MSG[res.result_code]
      return false, fmt("\n  Error: %s\n  Details: %s",
        error_msg or "Unknown error occurred (code: " .. res.result_code ..
        ")", res.diagnostic_msg or "")
    end
    return false, fmt("Received incorrect Op in packet: %d, expected %d", protocol_op, APPNO.SearchResultDone)
  end

  local res
  res, err = asn1_parse_ldap_result(packet, pos)
  if err then
    return false, err
  end

  if res.result_code ~= 0 then
    local error_msg = ERROR_MSG[res.result_code]
    return false, fmt("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. res.result_code ..
      ")", res.diagnostic_msg or "")
  else
    return response
  end
end

function _M.start_tls(socket)
  local method_name = asn1_put_object(0, asn1.CLASS.CONTEXT_SPECIFIC, 0, "1.3.6.1.4.1.1466.20037")
  ldapMessageId = ldapMessageId + 1
  local ldapMsg = asn1_encode(ldapMessageId) ..
                  asn1_put_object(APPNO.ExtendedRequest, asn1.CLASS.APPLICATION, 1, method_name)
  local send_packet = asn1_encode(ldapMsg, asn1.TAG.SEQUENCE)
  socket:send(send_packet)

  local _, protocol_op, packet, pos, err = receive_ldap_message(socket)
  if err then
    return false, err
  end

  if protocol_op ~= APPNO.ExtendedResponse then
    return false, fmt("Received incorrect Op in packet: %d, expected %d",
                                protocol_op, APPNO.ExtendedResponse)
  end

  local res
  res, err = asn1_parse_ldap_result(packet, pos)
  if err then
    return false, err
  end

  if res.result_code ~= 0 then
    local error_msg = ERROR_MSG[res.result_code]
    return false, fmt("\n  Error: %s\n  Details: %s",
      error_msg or "Unknown error occurred (code: " .. res.result_code ..
      ")", res.diagnostic_msg or "")
  else
    return true
  end
end

return _M;
