local sub = string.sub
local lower = string.lower
return function(location, pattern, insensitive)
    local prefix = sub(location, 1, #pattern)
    if insensitive then
        prefix  = lower(prefix)
        pattern = lower(pattern)
    end
    return prefix == pattern
end