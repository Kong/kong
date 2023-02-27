---
-- JWK Module
--
-- Utilities to deal with JWK (JSON Web Keys)
--
-- @module kong.jwk

local JWK = {}

--- A metatable for a Lua table representing a JSON Web Key (JWK).
-- This metatable provides two special methods:
--   - __index: allows access to a JWK's attributes by indexing its table
--   - __eq: compares two JWKs for equality, based on their attributes
local jwk_mt = {
  __index = function(jwk, key)
    return jwk.attributes[key]
  end,
  __eq = function (jwk1, jwk2)
    for k, v in pairs(jwk1.attributes) do
        if jwk2.attributes[k] ~= v then return false end
    end
    for k, v in pairs(jwk2.attributes) do
        if jwk1.attributes[k] ~= v then return false end
    end
    return true
  end
}

--- Creates a new JWK instance from the provided JWK data.
-- @param jwk_data A Lua table representing the JWK data to be used to create the JWK instance.
-- @return A new JWK instance with a metatable set to jwk_mt.
function JWK.new(jwk_data)
  return setmetatable({ attributes = jwk_data }, jwk_mt)
end


return {
	new = function ()
    return JWK
  end
}
