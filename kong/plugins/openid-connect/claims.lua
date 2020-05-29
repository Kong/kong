local type     = type
local ipairs   = ipairs
local concat   = table.concat
local tostring = tostring
local tonumber = tonumber


local function find_claim(token, search)
  if type(token) ~= "table" then
    return nil
  end

  local search_t = type(search)
  local t = token
  if search_t == "string" then
    if not t[search] then
      return nil
    end
    t = t[search]

  elseif search_t == "table" then
    for _, claim in ipairs(search) do
      if not t[claim] then
        return nil
      end

      t = t[claim]
    end

  else
    return nil
  end

  if type(t) == "table" then
    return concat(t, " ")
  end

  return tostring(t)
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
}
