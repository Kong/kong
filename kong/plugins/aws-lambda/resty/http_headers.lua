local   rawget, rawset, setmetatable =
        rawget, rawset, setmetatable

local str_gsub = string.gsub
local str_lower = string.lower


local _M = {
    _VERSION = '0.01',
}


-- Returns an empty headers table with internalised case normalisation.
-- Supports the same cases as in ngx_lua:
--
-- headers.content_length
-- headers["content-length"]
-- headers["Content-Length"]
function _M.new(self)
    local mt = { 
        normalised = {},
    }


    mt.__index = function(t, k)
        local k_hyphened = str_gsub(k, "_", "-")
        local matched = rawget(t, k)
        if matched then
            return matched
        else
            local k_normalised = str_lower(k_hyphened)
            return rawget(t, mt.normalised[k_normalised])
        end
    end


    -- First check the normalised table. If there's no match (first time) add an entry for
    -- our current case in the normalised table. This is to preserve the human (prettier) case
    -- instead of outputting lowercased header names.
    --
    -- If there's a match, we're being updated, just with a different case for the key. We use
    -- the normalised table to give us the original key, and perorm a rawset().
    mt.__newindex = function(t, k, v)
        -- we support underscore syntax, so always hyphenate.
        local k_hyphened = str_gsub(k, "_", "-")

        -- lowercase hyphenated is "normalised"
        local k_normalised = str_lower(k_hyphened)

        if not mt.normalised[k_normalised] then
            mt.normalised[k_normalised] = k_hyphened
            rawset(t, k_hyphened, v)
        else
            rawset(t, mt.normalised[k_normalised], v)
        end
    end

    return setmetatable({}, mt)
end


return _M
