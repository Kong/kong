-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local type     = type
local ipairs   = ipairs
local concat   = table.concat
local tostring = tostring
local tonumber = tonumber
local floor    = math.floor


local function find_claim(token, search, no_transform)
  if type(token) ~= "table" then
    return nil
  end

  local search_t = type(search)
  local t = token
  if search_t == "string" then
    if t[search] then
      t = t[search]
    else
      local search_n = tonumber(search, 10)
      if search_n and floor(search_n) == search_n and t[search_n] then
        t = t[search_n]
      else
        return nil
      end
    end
  elseif search_t == "table" then
    for _, claim in ipairs(search) do
      if t[claim] then
        t = t[claim]
      else
        local claim_n = tonumber(claim, 10)
        if claim_n and floor(claim_n) == claim_n and t[claim_n] then
          t = t[claim_n]
        else
          return nil
        end
      end
    end

  else
    return nil
  end

  if no_transform then
    return t
  end

  if type(t) == "table" then
    return concat(t, " ")
  end

  return tostring(t)
end


-- @tparam table token The token to check for forbidden claims.
-- @tparam table forbidden_claim A list of forbidden claims.
-- @treturn boolean false if the token doesn't have a forbidden claim.
-- @treturn string the name of the first forbidden claim found.
local function has_forbidden_claim(token, forbidden_claims)
  for _, claim in ipairs(forbidden_claims) do
    if find_claim(token, claim) then
      return claim
    end
  end

  return false
end


---compares two timestamps and returns a boolean
---indicating token expiration.
---
-- According to the RFC https://www.rfc-editor.org/rfc/rfc7519#section-4.1.4
---The "exp" (expiration time) claim identifies the expiration time on or
---after which the JWT MUST NOT be accepted for processing. The processing
---of the "exp" claim requires that the current date/time MUST be before the
---expiration date/time listed in the "exp" claim.
---
---`true` when expired
--- `false+err` when still valid
--- Be very defensive here and indicate token expiration
--- when unexpected values are passed
---@param exp number
---@param now number
---@return boolean, string
local function token_is_expired(exp, now)
  -- expecting numbers to avoid incorrect comparisons
  if type(now) ~= "number" then return true, "now must be a number" end
  if type(exp) ~= "number" then return true, "exp must be a number" end
  -- not before epoch (meaning greater than zero)
  if exp < 0 then return true, "exp must be greater than 0" end
  if now < 0 then return true, "now must be greater than 0" end
  -- still valid when an expiry timestamp is larger (more distant in the future)
  -- than the `now` (the current unix timestamp)
  if exp > now then
    return false
  end
  return true, "token has expired"
end

local function get_exp(access_token, tokens_encoded, now, exp_default)
  if access_token and type(access_token) == "table" then
    local exp

    if type(access_token.payload) == "table" then
      if access_token.payload.exp then
        exp = tonumber(access_token.payload.exp, 10)
        if exp then
          return exp
        end
      end
    end

    exp = tonumber(access_token.exp)
    if exp then
      return exp
    end
  end

  if tokens_encoded and type(tokens_encoded) == "table" then
    if tokens_encoded.expires_in then
      local expires_in = tonumber(tokens_encoded.expires_in, 10)
      if expires_in then
        if expires_in == 0 then
          return 0
        end

        return now + expires_in
      end
    end
  end

  return exp_default
end


return {
  find = find_claim,
  exp  = get_exp,
  token_is_expired = token_is_expired,
  has_forbidden_claim = has_forbidden_claim,
}
