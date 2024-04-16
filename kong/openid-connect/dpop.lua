-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uri = require("kong.openid-connect.uri")
local jwa = require("kong.openid-connect.jwa")
local jwks = require("kong.openid-connect.jwks")
local codec = require("kong.openid-connect.codec")
local rand = require("kong.tools.rand")
local buffer = require("string.buffer")


local normalize_uri_path = require("kong.tools.uri").normalize
local contain_private_key = jwks.contain_private_key
local compute_thumbprint = jwks.compute_thumbprint


local char, byte = string.char, string.byte
local floor = math.floor
local type = type
local error = error
local assert = assert
local pcall = pcall
local ipairs = ipairs
local time = ngx.time
local decode_base64url = codec.base64url.decode
local encode_base64url = codec.base64url.encode


local IAT_TOLERANCE = 5 -- seconds. The time skew allowed between the client and the server


local NONCE_LEEWAY = 60 -- seconds
local NONCE_IAT_BYTES = 5 -- the generation time of the nonce, 5 bytes is fair enough for the timestamp
local NONCE_RANDOM_BYTES = 16
-- with specific choice of RANDOM_LEN and TIMESTAMP_BYTES, the size is a multiple of 3
-- thus no padding is needed for base64url encoding and we can concat the signature directly
-- equal to #codec.base64url.encode(string.rep(".", TIMESTAMP_BYTES + RANDOM_LEN))
local NONCE_PAYLOAD_ENCODED_BYTES = math.ceil(4 * (NONCE_RANDOM_BYTES + NONCE_IAT_BYTES) / 3)


local DEFAULT_PORTS = {
  ["http"] = 80,
  ["https"] = 443,
  ["ws"] = 80,
  ["wss"] = 443,
}


-- TODO: add unit test for this
-- https://www.rfc-editor.org/rfc/rfc3986#section-6.1
-- those are considered equivalent:
-- http://example.com
-- http://example.com/
-- http://example.com:/
-- http://example.com:80/
-- also strip the fragments and queries and normalize the path
local function normalize_dpop_url(url)
  local url_parts, err = uri.parse(url)
  if not url_parts then
    return nil, err
  end

  local scheme = url_parts.scheme
  if not scheme then
    return nil, "missing scheme"
  end

  local host = url_parts.host
  if host == nil then
    return nil, "missing host"
  end

  local path = url_parts.path
  if path then
    path = normalize_uri_path(path, true)
  else
    path = "/"
  end

  local port = url_parts.port
  if not port or port == DEFAULT_PORTS[scheme] then
    return scheme .. "://" .. host .. path
  end

  return scheme .. "://" .. host .. ":" .. port .. path
end


local timestamp_buf = buffer.new(NONCE_IAT_BYTES)


-- TODO: add unit test for this
local function encode_timestamp(iat)
  timestamp_buf:reset()

  for i = 1, NONCE_IAT_BYTES do
    timestamp_buf:put(char(iat % 256))
    if i == NONCE_IAT_BYTES then
      return timestamp_buf:get()
    end
    iat = floor(iat / 256)
  end
end


local function decode_timestamp(encoded_iat)
  assert(#encoded_iat == NONCE_IAT_BYTES, "invalid iat length")
  timestamp_buf:set(encoded_iat)
  local iat = 0
  for i = 1, NONCE_IAT_BYTES do
    iat = iat + byte(timestamp_buf:get(1)) * (2 ^ ((i - 1) * 8))
  end
  return iat
end


local function validate_nonce_unsafe(nonce, nonce_gen_jwk)
  assert(type(nonce) == "string", "nonce must be a string")
  local random_and_iat = nonce:sub(1, NONCE_PAYLOAD_ENCODED_BYTES)
  assert(#random_and_iat == NONCE_PAYLOAD_ENCODED_BYTES, "invalid nonce length")
  local signature = nonce:sub(NONCE_PAYLOAD_ENCODED_BYTES + 1)
  local random_and_iat_decoded = assert(decode_base64url(random_and_iat))
  local iat_encoded = random_and_iat_decoded:sub(NONCE_RANDOM_BYTES + 1)
  local iat = assert(decode_timestamp(iat_encoded))
  assert(jwa.verify(nonce_gen_jwk.alg, nonce_gen_jwk, random_and_iat_decoded, signature))
  return iat
end


local function validate_nonce(nonce, nonce_gen_jwk)
  local ok, iat_or_err = pcall(validate_nonce_unsafe, nonce, nonce_gen_jwk)
  if not ok then
    return nil, iat_or_err or "invalid nonce"
  end
  return iat_or_err
end


local function generate_nonce_unsafe(nonce_gen_jwk)
  local random = rand.get_rand_bytes(NONCE_RANDOM_BYTES)
  local iat = time()
  local iat_encoded = encode_timestamp(iat)
  local random_and_iat = random .. iat_encoded
  local signature = assert(jwa.sign(nonce_gen_jwk.alg, nonce_gen_jwk, random_and_iat))
  return encode_base64url(random_and_iat) .. signature
end


-- we ask for new nonce value when a request fails, but accept the old one if it's still valid
local function generate_nonce(nonce_gen_jwk)
  local ok, nonce = pcall(generate_nonce_unsafe, nonce_gen_jwk)
  if not ok then
    return nil, nonce
  end
  return nonce
end


local function real_handle_err(err_desc, err_code, nonce)
  if err_desc then
    kong.log.debug(err_desc)
  end

  return nil, err_code or "invalid_dpop_proof", "Unable to validate the DPoP proof", nonce
end


local function generate_handle_err_func(nonce_gen_jwk)
  if nonce_gen_jwk then
    return function(err_desc, err_code)
      local nonce, nonce_err = generate_nonce(nonce_gen_jwk)
      if not nonce then
        kong.log.err("failed to generate nonce (", nonce_err, ")")
      end
      return real_handle_err(err_desc, err_code, nonce)
    end
  end
  return real_handle_err
end


local function verify_client_dpop(oic, jwt, claims, is_dpop_token, dpop_req_info, options)
  local nonce_gen_jwk
  local dpop_use_nonce = options.dpop_use_nonce
  if dpop_use_nonce then
    nonce_gen_jwk = options.client_jwk or oic.options.client_jwk
    if not nonce_gen_jwk then
      -- intentionally fail with 500
      -- needs to be configured correctly
      error("unable to generate nonce (need to provide a client jwk)")
    end
  end
  local handle_err = generate_handle_err_func(nonce_gen_jwk)

  if not is_dpop_token then
    return handle_err("not a DPoP token")
  end

  if dpop_req_info.truncated then
    kong.log.notice("too many request headers - unable to verify that the DPoP header is present only once")
    return handle_err("there should be one and only one DPoP header")
  end

  -- if the PoP header is present and only once [[
  local dpop_header = dpop_req_info.dpop_header
  if type(dpop_header) ~= "string" then
    return handle_err("there should be one and only one DPoP header")
  end
  -- ]]

  -- if the PoP header is a valid JWT and correctly signed [[
  local pop_jwt, err = oic.jwt:decode_dpop_proof(dpop_header, options) -- the signature is verified here
  if not pop_jwt then
    return handle_err("invalid DPoP header: " .. err)
  end

  local jwt_typ = pop_jwt.header.typ
  jwt_typ = type(jwt_typ) == "string" and jwt_typ:lower()
  if jwt_typ ~= "dpop+jwt" then -- if the PoP header is a DPoP JWT
    return handle_err("invalid DPoP header type")
  end

  local pop_jwk = pop_jwt.header.jwk
  if type(pop_jwk) ~= "table" then -- if the PoP header contains the necessary claims
    return handle_err("missing JWK in DPoP header")
  end
  -- ]]

  -- code does not ensure that [[
  local pop_payload = pop_jwt.payload
  local jti, htm, htu, iat = pop_payload.jti, pop_payload.htm, pop_payload.htu, pop_payload.iat
  if type(jti) ~= "string" or type(htm) ~= "string" or type(htu) ~= "string" or type(iat) ~= "number" then
    return handle_err("missing required claims in DPoP payload")
  end
  -- ]]

  -- keys must not contain private keys [[
  for _, key in ipairs(pop_jwk) do
    if contain_private_key(key) then
      return handle_err("private keys are not allowed in DPoP jwk")
    end
  end
  -- ]]

  local now = time()
  local nonce_header
  local dpop_proof_lifetime = options.dpop_proof_lifetime or 300
  if dpop_use_nonce then
    local nonce = pop_jwt.payload.nonce
    if type(nonce) ~= "string" then
      return handle_err("Resource server requires nonce in DPoP proof", "use_dpop_nonce")
    end

    local nonce_iat, err = validate_nonce(nonce, nonce_gen_jwk)
    if not nonce_iat then
      kong.log.debug("invalid nonce (", err, ")")
      return handle_err("invalid nonce")
    end

    local nonce_remaing_ttl = nonce_iat + dpop_proof_lifetime - now
    -- we are using dpop_proof_lifetime as a default value for nonce lifetime
    if nonce_remaing_ttl < 0 then
      kong.log.debug("nonce has expired")
      return handle_err("invalid nonce") -- do not reveal the detail of nonce generation to the client
    end

    -- update the nonce before it expires so the client does not have to get new one with 401 response
    if nonce_remaing_ttl < NONCE_LEEWAY then
      nonce_header, err = generate_nonce(nonce_gen_jwk)
      if not nonce_header then
        kong.log.err("failed to generate nonce (", err, ")")
      end
    end
  end

  -- if the proof is not expired [[
  if iat > now + IAT_TOLERANCE then
    return handle_err("DPoP token is not yet valid")
  end

  if iat + dpop_proof_lifetime < now then
    return handle_err("DPoP token has expired")
  end
  -- ]]

  -- if the proof matches the request [[
  if htm ~= dpop_req_info.method or normalize_dpop_url(htu) ~= normalize_dpop_url(dpop_req_info.uri) then
    return handle_err("DPoP proof does not match the request")
  end
  -- ]]

  -- if the proof matches the access token [[
  if type(jwt) ~= "string" then
    return handle_err("access token is not a string")
  end

  local ath_compare, err = jwa.S256(jwt)
  if not ath_compare then
    kong.log.err("failed to hash the access token (", err, ")")
    return handle_err()
  end

  ath_compare = encode_base64url(ath_compare)
  local ath = pop_jwt.payload.ath
  if ath ~= ath_compare then
    return handle_err("DPoP proof does not match the access token")
  end
  -- ]]

  -- match the proof's public key with that bound with the access token [[
  local cnf = claims and claims.cnf

  local jkt_tumbprint = cnf and cnf.jkt
  if not jkt_tumbprint then
    return handle_err("DPoP key bound to the access token is missing")
  end

  local key_hash, err = compute_thumbprint(pop_jwk)
  if not key_hash then
    kong.log.debug("failed to hash the DPoP proof's jwk (", err, ")")
    return handle_err()
  end

  if jkt_tumbprint ~= key_hash then
    return handle_err("The JWK in the DPoP proof does not match the token")
  end
  -- ]]

  return true, nil, nil, nonce_header
end


return {
  verify_client_dpop = verify_client_dpop,
}
