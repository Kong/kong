local pl_stringx = require "pl.stringx"

local str_find = string.find
local str_sub = string.sub
local endswith = pl_stringx.endswith

local _M = {}


function _M.mime_type_match(this_type, this_subtype, other_type, other_subtype)
  if this_type == other_type or this_type == "*" then
    if this_subtype == other_subtype or this_subtype == "*" then
      return true
    end

    -- suffix comparation
    -- e.g. this_subtype(*+json) should match to other_subtype(jwk-set+json)
    local idx = str_find(this_subtype, "+", 1, true)
    if idx then
      local suffix = str_sub(this_subtype, idx + 1)
      if endswith(other_subtype, suffix) then
        return true
      end
    end
  end

  return false
end


return _M
